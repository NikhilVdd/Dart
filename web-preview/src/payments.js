// Stripe in the PWA: the Payment Element for card holds and embedded Connect onboarding for runners.
// Both load Stripe's scripts from Stripe's own domains on first use (required by Stripe; see the CSP).
import { loadConnectAndInitialize } from "@stripe/connect-js";
import { loadStripe } from "@stripe/stripe-js";

const variables = {
  colorPrimary: "#c6ff00",
  colorBackground: "#111411",
  colorText: "#f7f9f5",
  colorDanger: "#ff6868",
  fontFamily: "inherit",
  borderRadius: "14px"
};

let stripePromise = null;
let stripeKey = null;

function stripeFor(publishableKey) {
  if (!stripePromise || stripeKey !== publishableKey) {
    stripeKey = publishableKey;
    stripePromise = loadStripe(publishableKey);
  }
  return stripePromise;
}

export function formatCents(cents) {
  return `$${(Number(cents) / 100).toFixed(2)}`;
}

/** Mounts the Payment Element for a hold returned by startPayment(). */
export async function mountPaymentElement(container, hold) {
  const stripe = await stripeFor(hold.publishable_key);
  if (!stripe) throw new Error("Couldn’t load the payment form. Check your connection and try again.");
  const elements = stripe.elements({ clientSecret: hold.client_secret, appearance: { theme: "night", variables } });
  elements.create("payment", { layout: "tabs" }).mount(container);
  return { stripe, elements };
}

/** Confirms the hold in place (cards and wallets never redirect). */
export async function authorizeCard({ stripe, elements }) {
  const { error, paymentIntent } = await stripe.confirmPayment({ elements, redirect: "if_required" });
  if (error) throw new Error(error.message || "Your card was not accepted.");
  return paymentIntent;
}

/** Mounts Stripe's embedded onboarding for the signed-in runner. */
export function mountOnboarding(container, { publishableKey, fetchClientSecret, onExit }) {
  const connect = loadConnectAndInitialize({
    publishableKey,
    fetchClientSecret,
    appearance: { overlays: "dialog", variables: { ...variables, colorBackground: "#080a08", colorText: "#f7f9f5" } }
  });
  const banner = connect.create("notification-banner");
  const onboarding = connect.create("account-onboarding");
  onboarding.setOnExit(onExit);
  container.replaceChildren(banner, onboarding);
}
