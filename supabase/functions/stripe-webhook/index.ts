// Stripe webhook endpoint (snapshot events). The PWA confirms holds itself through the payments
// function; this keeps payment_holds right when that call never arrives, when Stripe cancels or
// expires a hold, and when a payment is disputed.
//
// Subscribe to: payment_intent.amount_capturable_updated, payment_intent.canceled,
//               charge.dispute.created
// Secrets: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET (whsec_…).
import { createClient } from "npm:@supabase/supabase-js@2.76.1";
import Stripe from "npm:stripe@22.6.2";

const env = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing secret ${name}`);
  return value;
};

const stripe = new Stripe(env("STRIPE_SECRET_KEY"), { httpClient: Stripe.createFetchHttpClient() });
const signingSecret = env("STRIPE_WEBHOOK_SECRET");
const cryptoProvider = Stripe.createSubtleCryptoProvider();
const admin = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false, autoRefreshToken: false }
});

async function holdCanceled(intent: Stripe.PaymentIntent) {
  const { data: hold } = await admin.from("payment_holds")
    .update({ status: "canceled" })
    .eq("payment_intent_id", intent.id).in("status", ["pending", "authorized"])
    .select("request_id").maybeSingle();
  if (hold?.request_id) {
    await admin.from("requests").update({ payment_status: "canceled" })
      .eq("id", hold.request_id).eq("payment_status", "authorized");
  }
}

Deno.serve(async request => {
  if (request.method !== "POST") return new Response("method not allowed", { status: 405 });
  const signature = request.headers.get("Stripe-Signature");
  const payload = await request.text();
  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(payload, signature ?? "", signingSecret, undefined, cryptoProvider);
  } catch (err) {
    return new Response(`bad signature: ${err instanceof Error ? err.message : err}`, { status: 400 });
  }

  try {
    if (event.type === "payment_intent.amount_capturable_updated") {
      const intent = event.data.object;
      const chargeId = typeof intent.latest_charge === "string" ? intent.latest_charge : intent.latest_charge?.id;
      const charge = chargeId ? await stripe.charges.retrieve(chargeId) : null;
      const unix = charge?.payment_method_details?.card?.capture_before;
      await admin.from("payment_holds")
        .update({
          status: "authorized",
          authorized_cents: intent.amount_capturable,
          capture_before: unix ? new Date(unix * 1000).toISOString() : null
        })
        .eq("payment_intent_id", intent.id).eq("status", "pending");
    } else if (event.type === "payment_intent.canceled") {
      await holdCanceled(event.data.object);
    } else if (event.type === "charge.dispute.created") {
      // Dart is the merchant of record and answers disputes from the Stripe Dashboard.
      const dispute = event.data.object;
      console.warn(`dispute ${dispute.id} opened on ${dispute.payment_intent} for ${dispute.amount} cents: ${dispute.reason}`);
    }
  } catch (err) {
    console.error(err);
    return new Response("handler failed", { status: 500 });
  }
  return Response.json({ received: true });
});
