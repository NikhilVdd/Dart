import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type PushEvent = {
  id: number;
  recipient_id: string;
  event_type: "request_status" | "request_message" | "group_message";
  request_id: string | null;
  title: string;
  body: string;
  status: string | null;
};

type WebhookPayload = { type: "INSERT"; table: "push_events"; record: PushEvent };

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const hookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  if (!hookSecret || request.headers.get("x-grab-webhook-secret") !== hookSecret) {
    return new Response("Unauthorized", { status: 401 });
  }

  const payload = await request.json() as WebhookPayload;
  const event = payload.record;
  if (!event?.recipient_id) return new Response("Invalid payload", { status: 400 });

  try {
    const [
      { data: destinations, error: destinationError },
      { data: activityTokens, error: activityError },
      { data: clipTokens, error: clipError },
    ] = await Promise.all([
      supabase.from("push_tokens").select("token,bundle_id,environment").eq("user_id", event.recipient_id),
      event.request_id
        ? supabase.from("live_activity_tokens").select("token,bundle_id,environment").eq("user_id", event.recipient_id).eq("request_id", event.request_id)
        : Promise.resolve({ data: [], error: null }),
      event.request_id
        ? supabase.from("clip_push_tokens").select("token,bundle_id,environment,token_kind").eq("request_id", event.request_id)
        : Promise.resolve({ data: [], error: null }),
    ]);
    if (destinationError) throw destinationError;
    if (activityError) throw activityError;
    if (clipError) throw clipError;

    const clipAlerts = (clipTokens ?? []).filter((destination) => destination.token_kind === "alert");
    const clipActivities = (clipTokens ?? []).filter((destination) => destination.token_kind === "liveactivity");

    const results = await Promise.allSettled([
      ...[...(destinations ?? []), ...clipAlerts].map((destination) => sendAPNs(destination, {
        aps: {
          alert: { title: event.title, body: event.body },
          sound: "default",
          "thread-id": event.request_id ? `request-${event.request_id}` : event.event_type,
        },
        request_id: event.request_id,
      }, "alert")),
      ...[...(activityTokens ?? []), ...clipActivities]
        .map((destination) => sendAPNs(destination, liveActivityPayload(event), "liveactivity")),
    ]);

    const failures = results.filter((result) => result.status === "rejected");
    await supabase.from("push_events").update({
      delivered_at: failures.length ? null : new Date().toISOString(),
      last_error: failures.length ? `${failures.length} APNs delivery attempt(s) failed` : null,
    }).eq("id", event.id);

    return Response.json({ attempted: results.length, failed: failures.length }, { status: failures.length ? 502 : 200 });
  } catch (error) {
    await supabase.from("push_events").update({ last_error: String(error) }).eq("id", event.id);
    return Response.json({ error: "Push delivery failed" }, { status: 500 });
  }
});

function liveActivityPayload(event: PushEvent) {
  const terminal = ["completed", "cancelled", "expired"].includes(event.status ?? "");
  return {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: terminal ? "end" : "update",
      "dismissal-date": terminal ? Math.floor(Date.now() / 1000) + 900 : undefined,
      "content-state": {
        status: event.status ?? "accepted",
        headline: event.title,
        progress: progress(event.status),
        updatedAt: Date.now() / 1000,
        isComplete: terminal,
      },
      alert: { title: event.title, body: event.body },
    },
  };
}

function progress(status: string | null) {
  return ({ accepted: 0.18, picking_up: 0.42, on_the_way: 0.72, delivered: 0.92, completed: 1 } as Record<string, number>)[status ?? ""] ?? 0.08;
}

async function sendAPNs(
  destination: { token: string; bundle_id: string; environment: string },
  payload: unknown,
  pushType: "alert" | "liveactivity",
) {
  const jwt = await apnsJWT();
  const host = destination.environment === "production" ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  const topic = pushType === "liveactivity" ? `${destination.bundle_id}.push-type.liveactivity` : destination.bundle_id;
  const response = await fetch(`https://${host}/3/device/${destination.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": pushType,
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!response.ok) throw new Error(`APNs ${response.status}: ${await response.text()}`);
}

let cachedJWT: { value: string; expires: number } | undefined;
async function apnsJWT() {
  if (cachedJWT && cachedJWT.expires > Date.now()) return cachedJWT.value;
  const teamID = required("APNS_TEAM_ID");
  const keyID = required("APNS_KEY_ID");
  const privateKey = required("APNS_PRIVATE_KEY");
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyID }));
  const claims = base64url(JSON.stringify({ iss: teamID, iat: now }));
  const input = `${header}.${claims}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemBytes(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(input));
  const value = `${input}.${base64url(new Uint8Array(signature))}`;
  cachedJWT = { value, expires: Date.now() + 50 * 60 * 1000 };
  return value;
}

function required(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function pemBytes(pem: string) {
  const base64 = pem.replace(/-----[^-]+-----/g, "").replace(/\s/g, "");
  return Uint8Array.from(atob(base64), (character) => character.charCodeAt(0));
}

function base64url(value: string | Uint8Array) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  bytes.forEach((byte) => binary += String.fromCharCode(byte));
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
