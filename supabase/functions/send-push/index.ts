// Drains public.notification_outbox and delivers each row as a Web Push to every device the person
// has registered. Called by Postgres (pg_net) right after rows are queued, and by the minute-ly
// retry job. Not callable from the browser: it requires the shared secret stored in Vault.
//
// Secrets (supabase secrets set …): VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT, PUSH_WEBHOOK_SECRET.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the Edge runtime.
import { createClient } from "npm:@supabase/supabase-js@2.76.1";
import webpush from "npm:web-push@3.6.7";

type OutboxRow = {
  id: number;
  user_id: string;
  category: string;
  title: string;
  body: string;
  tag: string | null;
  url: string;
  badge: number | null;
};

type Subscription = { id: string; user_id: string; endpoint: string; p256dh: string; auth: string };

const env = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing secret ${name}`);
  return value;
};

webpush.setVapidDetails(env("VAPID_SUBJECT"), env("VAPID_PUBLIC_KEY"), env("VAPID_PRIVATE_KEY"));
const webhookSecret = env("PUSH_WEBHOOK_SECRET");
const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false, autoRefreshToken: false }
});

function sameSecret(given: string | null) {
  if (!given || given.length !== webhookSecret.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ webhookSecret.charCodeAt(i);
  return diff === 0;
}

// The push service keeps only the newest undelivered message per topic (e.g. a phone that was off
// gets the latest order step, not all of them). Topics are at most 32 URL-safe characters.
async function topicFor(tag: string) {
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(tag)));
  return [...digest].map(byte => byte.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

async function deliver(row: OutboxRow, devices: Subscription[]) {
  const payload = JSON.stringify({
    title: row.title,
    body: row.body,
    tag: row.tag,
    url: row.url,
    badge: row.badge,
    category: row.category
  });
  const options = {
    TTL: row.category === "request_updates" || row.category === "chat" ? 60 * 60 : 6 * 60 * 60,
    urgency: "high" as const,
    ...(row.tag ? { topic: await topicFor(row.tag) } : {})
  };

  const delivered: string[] = [];
  const gone: string[] = [];
  const failed: string[] = [];
  const errors: string[] = [];
  await Promise.all(devices.map(async device => {
    try {
      await webpush.sendNotification(
        { endpoint: device.endpoint, keys: { p256dh: device.p256dh, auth: device.auth } },
        payload,
        options
      );
      delivered.push(device.id);
    } catch (error) {
      const status = (error as { statusCode?: number }).statusCode;
      // 404/410: the browser unsubscribed or the app was removed. Anything else (including 403,
      // which a misconfigured VAPID key also causes) is retried rather than forgetting the device.
      if (status === 404 || status === 410) gone.push(device.id);
      else failed.push(device.id);
      errors.push(`${status ?? "error"}: ${(error as Error).message}`.slice(0, 200));
    }
  }));
  return { delivered, gone, failed, errors };
}

Deno.serve(async request => {
  if (request.method !== "POST") return new Response("method not allowed", { status: 405 });
  if (!sameSecret(request.headers.get("x-dart-push-secret"))) return new Response("unauthorized", { status: 401 });

  const totals = { notifications: 0, delivered: 0, removed: 0, failed: 0 };
  // Five rounds of 100 keeps one call well inside the Edge Function CPU and memory limits; anything
  // left over is picked up by the next dispatch or the minute-ly retry.
  for (let round = 0; round < 5; round++) {
    const { data: rows, error } = await admin.rpc("claim_push_batch", { p_limit: 100 });
    if (error) return Response.json({ error: error.message }, { status: 500 });
    const batch = (rows ?? []) as OutboxRow[];
    if (!batch.length) break;

    const userIds = [...new Set(batch.map(row => row.user_id))];
    const { data: subs, error: subsError } = await admin
      .from("push_subscriptions")
      .select("id, user_id, endpoint, p256dh, auth")
      .in("user_id", userIds);
    if (subsError) return Response.json({ error: subsError.message }, { status: 500 });

    const results = await Promise.all(batch.map(async row => {
      const devices = (subs as Subscription[]).filter(sub => sub.user_id === row.user_id);
      return { row, ...(await deliver(row, devices)) };
    }));

    const sentIds: number[] = [];
    const delivered = new Set<string>();
    const gone = new Set<string>();
    const failed = new Set<string>();
    for (const result of results) {
      result.delivered.forEach(id => delivered.add(id));
      result.gone.forEach(id => gone.add(id));
      result.failed.forEach(id => failed.add(id));
      // Done when something reached a device or nothing is left to retry; otherwise the row stays
      // unsent and is claimed again after a minute (up to five attempts).
      if (result.delivered.length || !result.failed.length) sentIds.push(result.row.id);
      if (result.errors.length) {
        await admin.from("notification_outbox").update({ last_error: result.errors.join("; ") }).eq("id", result.row.id);
      }
    }

    if (sentIds.length) await admin.from("notification_outbox").update({ sent_at: new Date().toISOString() }).in("id", sentIds);
    if (delivered.size) {
      await admin.from("push_subscriptions")
        .update({ last_success_at: new Date().toISOString(), failure_count: 0 })
        .in("id", [...delivered]);
    }
    if (gone.size) await admin.from("push_subscriptions").delete().in("id", [...gone]);
    for (const id of failed) await admin.rpc("note_push_failure", { p_subscription_id: id });

    totals.notifications += batch.length;
    totals.delivered += delivered.size;
    totals.removed += gone.size;
    totals.failed += failed.size;
    if (batch.length < 100) break;
  }
  return Response.json(totals);
});
