// Stripe payments for Dart (Connect marketplace, separate charges and transfers).
//
// Called by the PWA with the user's JWT:
//   start          { budget_cents }       → card hold (manual-capture PaymentIntent) + price breakdown
//   confirm        { payment_intent_id }  → marks the hold authorized once Stripe.js confirmed it
//   onboard        {}                     → creates the runner's connected account + Account Session
//   payout_status  {}                     → refreshes whether the runner can receive transfers
//   dashboard      {}                     → Express Dashboard login link
// Called by Postgres (pg_net) with the shared secret:
//   settle         {}                     → captures / releases holds queued in payment_jobs
//
// Secrets (supabase secrets set …): STRIPE_SECRET_KEY, STRIPE_PUBLISHABLE_KEY, PAYMENTS_WEBHOOK_SECRET.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the Edge runtime.
import { createClient } from "npm:@supabase/supabase-js@2.76.1";
import Stripe from "npm:stripe@22.6.2";

const env = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing secret ${name}`);
  return value;
};

// Catch swapped or wrong keys (e.g. a Supabase key in STRIPE_PUBLISHABLE_KEY) at startup, not as a blank form.
const stripeKey = (name: string, prefixes: string[]) => {
  const value = env(name);
  if (!prefixes.some(prefix => value.startsWith(prefix))) throw new Error(`${name} must start with ${prefixes.join(" or ")}`);
  return value;
};

// Restricted keys (rk_) work too, given the permissions listed in supabase/README.md.
const stripe = new Stripe(stripeKey("STRIPE_SECRET_KEY", ["sk_test_", "sk_live_", "rk_test_", "rk_live_"]), { httpClient: Stripe.createFetchHttpClient() });
const publishableKey = stripeKey("STRIPE_PUBLISHABLE_KEY", ["pk_test_", "pk_live_"]);
const jobSecret = env("PAYMENTS_WEBHOOK_SECRET");
const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false, autoRefreshToken: false }
});

// Stripe's standard card pricing (US cards; international cards add 1.5%). The requester covers it
// so Dart nets zero on each order: the hold assumes the international rate, the capture uses the
// card's actual rate.
const DOMESTIC_PERCENT = 0.029;
const INTERNATIONAL_PERCENT = 0.044;
const STRIPE_FIXED_CENTS = 30;
const grossUp = (cents: number, percent: number) => Math.ceil((cents + STRIPE_FIXED_CENTS) / (1 - percent));

// Card testing guard: how many holds one person may start.
const HOLDS_PER_HOUR = 5;
const HOLDS_PER_DAY = 15;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
const reply = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });

class UserError extends Error {}

function sameSecret(given: string | null) {
  if (!given || given.length !== jobSecret.length) return false;
  let diff = 0;
  for (let i = 0; i < given.length; i++) diff |= given.charCodeAt(i) ^ jobSecret.charCodeAt(i);
  return diff === 0;
}

async function settings() {
  const { data, error } = await admin.from("payment_settings").select("*").single();
  if (error) throw error;
  return data as { required: boolean; delivery_fee_cents: number; max_budget_cents: number };
}

function transfersStatus(account: Stripe.V2.Core.Account) {
  return account.configuration?.recipient?.capabilities?.stripe_balance?.stripe_transfers?.status ?? "pending";
}

async function refreshPayoutAccount(userId: string, accountId: string) {
  const account = await stripe.v2.core.accounts.retrieve(accountId, { include: ["configuration.recipient"] });
  const status = transfersStatus(account);
  await admin.from("payout_accounts").update({ transfers_active: status === "active" }).eq("user_id", userId);
  return status;
}

// ---------------------------------------------------------------------------
// Requester: card holds
// ---------------------------------------------------------------------------

async function holdsSince(userId: string, ms: number) {
  const { count, error } = await admin.from("payment_holds").select("payment_intent_id", { count: "exact", head: true })
    .eq("user_id", userId).gte("created_at", new Date(Date.now() - ms).toISOString());
  if (error) throw error;
  return count ?? 0;
}

// When the card on a confirmed hold must be captured by (from the charge).
async function captureBefore(intent: Stripe.PaymentIntent) {
  const chargeId = typeof intent.latest_charge === "string" ? intent.latest_charge : intent.latest_charge?.id;
  if (!chargeId) return null;
  const charge = await stripe.charges.retrieve(chargeId);
  const unix = charge.payment_method_details?.card?.capture_before;
  return unix ? new Date(unix * 1000).toISOString() : null;
}

async function start(user: { id: string }, body: { budget_cents?: unknown }) {
  const config = await settings();
  if (!config.required) throw new UserError("Payments aren’t turned on yet.");
  if (await holdsSince(user.id, 3_600_000) >= HOLDS_PER_HOUR || await holdsSince(user.id, 86_400_000) >= HOLDS_PER_DAY) {
    throw new UserError("Too many payment attempts. Try again later.");
  }
  const budget = Number(body.budget_cents);
  if (!Number.isInteger(budget) || budget < 100 || budget > config.max_budget_cents) {
    throw new UserError(`Set an item budget between $1 and $${config.max_budget_cents / 100}.`);
  }
  const fee = config.delivery_fee_cents;
  const total = grossUp(budget + fee, INTERNATIONAL_PERCENT);
  const intent = await stripe.paymentIntents.create({
    amount: total,
    currency: "usd",
    capture_method: "manual",
    // Cards and wallets only, so paying never leaves the installed PWA.
    automatic_payment_methods: { enabled: true, allow_redirects: "never" },
    description: "Dart delivery",
    metadata: { dart_user_id: user.id, budget_cents: String(budget), fee_cents: String(fee) }
  });
  const { error } = await admin.from("payment_holds").insert({
    payment_intent_id: intent.id,
    user_id: user.id,
    budget_cents: budget,
    fee_cents: fee,
    authorized_cents: total
  });
  if (error) throw error;
  return {
    payment_intent_id: intent.id,
    client_secret: intent.client_secret,
    publishable_key: publishableKey,
    budget_cents: budget,
    fee_cents: fee,
    processing_cents: total - budget - fee,
    total_cents: total
  };
}

async function confirm(user: { id: string }, body: { payment_intent_id?: unknown }) {
  const id = String(body.payment_intent_id ?? "");
  const intent = await stripe.paymentIntents.retrieve(id);
  if (intent.metadata.dart_user_id !== user.id) throw new UserError("Payment not found.");
  if (intent.status !== "requires_capture") return { status: intent.status };
  await admin.from("payment_holds")
    .update({ status: "authorized", authorized_cents: intent.amount_capturable, capture_before: await captureBefore(intent) })
    .eq("payment_intent_id", id).eq("status", "pending");
  return { status: "authorized" };
}

// ---------------------------------------------------------------------------
// Runner: connected account
// ---------------------------------------------------------------------------

async function onboard(user: { id: string; email?: string }) {
  let { data: payout } = await admin.from("payout_accounts").select("*").eq("user_id", user.id).maybeSingle();
  if (!payout) {
    const { data: profile } = await admin.from("profiles").select("display_name").eq("id", user.id).single();
    const account = await stripe.v2.core.accounts.create({
      contact_email: user.email,
      display_name: profile?.display_name,
      dashboard: "express",
      identity: { country: "us", entity_type: "individual" },
      configuration: { recipient: { capabilities: { stripe_balance: { stripe_transfers: { requested: true } } } } },
      defaults: { responsibilities: { fees_collector: "application", losses_collector: "application" } },
      metadata: { dart_user_id: user.id },
      include: ["configuration.recipient"]
    }, { idempotencyKey: `dart-account-${user.id}` });
    const { data, error } = await admin.from("payout_accounts")
      .upsert({ user_id: user.id, stripe_account_id: account.id, transfers_active: transfersStatus(account) === "active" })
      .select().single();
    if (error) throw error;
    payout = data;
  }
  const session = await stripe.accountSessions.create({
    account: payout.stripe_account_id,
    components: {
      account_onboarding: { enabled: true, features: { external_account_collection: true } },
      notification_banner: { enabled: true, features: { external_account_collection: true } }
    }
  });
  return { client_secret: session.client_secret, publishable_key: publishableKey };
}

async function payoutStatus(user: { id: string }) {
  const { data: payout } = await admin.from("payout_accounts").select("*").eq("user_id", user.id).maybeSingle();
  if (!payout) return { has_account: false, transfers_active: false, status: "none" };
  const status = await refreshPayoutAccount(user.id, payout.stripe_account_id);
  return { has_account: true, transfers_active: status === "active", status };
}

async function dashboard(user: { id: string }) {
  const { data: payout } = await admin.from("payout_accounts").select("*").eq("user_id", user.id).maybeSingle();
  if (!payout) throw new UserError("Set up payouts first.");
  const link = await stripe.accounts.createLoginLink(payout.stripe_account_id);
  return { url: link.url };
}

// ---------------------------------------------------------------------------
// Settlement (from Postgres)
// ---------------------------------------------------------------------------

type Hold = {
  payment_intent_id: string;
  request_id: string | null;
  fee_cents: number;
  status: string;
  item_cost_cents: number | null;
  destination_account: string | null;
};

async function markHold(hold: Hold, fields: Record<string, unknown>, requestStatus: string) {
  await admin.from("payment_holds").update(fields).eq("payment_intent_id", hold.payment_intent_id);
  if (hold.request_id) await admin.from("requests").update({ payment_status: requestStatus }).eq("id", hold.request_id);
}

async function capture(hold: Hold) {
  if (hold.status === "paid_out") return;
  if (hold.item_cost_cents === null) throw new Error("no receipt total");
  if (!hold.destination_account) throw new Error("no runner account");
  const payout = hold.item_cost_cents + hold.fee_cents;

  let intent = await stripe.paymentIntents.retrieve(hold.payment_intent_id, { expand: ["latest_charge"] });
  if (intent.status === "requires_capture") {
    const charge = intent.latest_charge as Stripe.Charge | null;
    const country = charge?.payment_method_details?.card?.country;
    const percent = country && country !== "US" ? INTERNATIONAL_PERCENT : DOMESTIC_PERCENT;
    intent = await stripe.paymentIntents.capture(hold.payment_intent_id, {
      amount_to_capture: Math.min(grossUp(payout, percent), intent.amount_capturable)
    }, { idempotencyKey: `capture-${hold.payment_intent_id}` });
  }
  if (intent.status !== "succeeded") {
    // The hold lapsed or was cancelled before capture; nothing to collect.
    await markHold(hold, { status: "failed" }, "failed");
    return;
  }
  await markHold(hold, { status: "captured", charged_cents: intent.amount_received }, "captured");

  const account = await stripe.v2.core.accounts.retrieve(hold.destination_account, { include: ["configuration.recipient"] });
  if (transfersStatus(account) !== "active") throw new Error("runner account cannot receive transfers yet");
  const transfer = await stripe.transfers.create({
    amount: payout,
    currency: "usd",
    destination: hold.destination_account,
    source_transaction: typeof intent.latest_charge === "string" ? intent.latest_charge : intent.latest_charge!.id,
    transfer_group: hold.request_id ? `request_${hold.request_id}` : undefined,
    metadata: { payment_intent_id: hold.payment_intent_id, request_id: hold.request_id ?? "" }
  }, { idempotencyKey: `transfer-${hold.payment_intent_id}` });
  await markHold(hold, { status: "paid_out", transfer_id: transfer.id }, "paid_out");
}

async function release(hold: Hold) {
  if (["captured", "paid_out", "canceled"].includes(hold.status)) return;
  const intent = await stripe.paymentIntents.retrieve(hold.payment_intent_id);
  if (intent.status !== "canceled" && intent.status !== "succeeded") {
    await stripe.paymentIntents.cancel(hold.payment_intent_id, {}, { idempotencyKey: `cancel-${hold.payment_intent_id}` });
  }
  await markHold(hold, { status: "canceled" }, "canceled");
}

async function settle() {
  const { data: jobs, error } = await admin.rpc("claim_payment_jobs", { p_limit: 20 });
  if (error) throw error;
  let done = 0;
  for (const job of jobs ?? []) {
    try {
      const { data: hold, error: holdError } = await admin.from("payment_holds").select("*")
        .eq("payment_intent_id", job.payment_intent_id).single();
      if (holdError) throw holdError;
      if (job.kind === "capture") await capture(hold);
      else await release(hold);
      await admin.rpc("finish_payment_job", { p_id: job.id, p_error: null });
      done++;
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      console.error(`payment job ${job.id} (${job.kind}) failed: ${message}`);
      await admin.rpc("finish_payment_job", { p_id: job.id, p_error: message.slice(0, 500) });
    }
  }
  return { claimed: jobs?.length ?? 0, done };
}

// ---------------------------------------------------------------------------

Deno.serve(async request => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (request.method !== "POST") return reply({ error: "method not allowed" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return reply({ error: "invalid JSON" }, 400);
  }

  try {
    if (body.action === "settle") {
      if (!sameSecret(request.headers.get("x-dart-payments-secret"))) return reply({ error: "unauthorized" }, 401);
      return reply(await settle());
    }

    const token = request.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
    const { data: auth } = token ? await admin.auth.getUser(token) : { data: { user: null } };
    const user = auth.user;
    if (!user) return reply({ error: "sign in required" }, 401);

    switch (body.action) {
      case "start": return reply(await start(user, body));
      case "confirm": return reply(await confirm(user, body));
      case "onboard": return reply(await onboard(user));
      case "payout_status": return reply(await payoutStatus(user));
      case "dashboard": return reply(await dashboard(user));
      default: return reply({ error: "unknown action" }, 400);
    }
  } catch (err) {
    if (err instanceof UserError) return reply({ error: err.message }, 400);
    console.error(err);
    const message = err instanceof Stripe.errors.StripeError ? err.message : "Payment service error. Please try again.";
    return reply({ error: message }, 500);
  }
});
