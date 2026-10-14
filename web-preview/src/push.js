import { deletePushSubscription, savePushSubscription } from "./api.js";
import { VAPID_PUBLIC_KEY } from "./config.js";

// Web Push for the installed app. iPhone and iPad (16.4+) only offer it once Grab is opened from
// the Home Screen, and only ask for permission from a tap.
const OFF_KEY = "grab:push:off";
const isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);

function standalone() {
  return matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;
}

function readOff() {
  try { return localStorage.getItem(OFF_KEY) === "true"; } catch { return false; }
}

function writeOff(off) {
  try { off ? localStorage.setItem(OFF_KEY, "true") : localStorage.removeItem(OFF_KEY); } catch { /* storage can be unavailable */ }
}

// "unsupported" | "needs-install" | "default" | "granted" | "denied"
export function pushStatus() {
  if (location.protocol !== "https:" || !("serviceWorker" in navigator)) return "unsupported";
  if (!("PushManager" in window) || !("Notification" in window)) return isIOS && !standalone() ? "needs-install" : "unsupported";
  return Notification.permission;
}

function keyBytes(base64url) {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(base64url.length / 4) * 4, "=");
  return Uint8Array.from(atob(base64), char => char.charCodeAt(0));
}

function usesCurrentKey(subscription) {
  const key = subscription.options?.applicationServerKey;
  if (!key) return true;
  const current = keyBytes(VAPID_PUBLIC_KEY);
  const existing = new Uint8Array(key);
  return existing.length === current.length && existing.every((byte, index) => byte === current[index]);
}

async function registration() {
  const timeout = new Promise((_, reject) => setTimeout(() => reject(new Error("Grab’s background service isn’t ready yet. Reload and try again.")), 8000));
  return Promise.race([navigator.serviceWorker.ready, timeout]);
}

async function subscribe() {
  const reg = await registration();
  let subscription = await reg.pushManager.getSubscription();
  if (subscription && !usesCurrentKey(subscription)) {
    await subscription.unsubscribe();
    subscription = null;
  }
  subscription ??= await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(VAPID_PUBLIC_KEY) });
  const { endpoint, keys } = subscription.toJSON();
  await savePushSubscription(endpoint, keys.p256dh, keys.auth, navigator.userAgent);
  return subscription;
}

// Must be called straight from a tap: Safari refuses the permission prompt otherwise.
export async function enablePush() {
  const permission = await Notification.requestPermission();
  if (permission !== "granted") return permission;
  writeOff(false);
  await subscribe();
  return "granted";
}

// On every launch: re-register the device for whoever is signed in, unless they switched it off.
export async function syncPush() {
  if (pushStatus() !== "granted" || readOff()) return false;
  try {
    await subscribe();
    return true;
  } catch {
    return false;
  }
}

// `remember` keeps it off across launches (Profile toggle); signing out doesn't.
export async function disablePush({ remember = true } = {}) {
  if (remember) writeOff(true);
  if (pushStatus() === "unsupported" || pushStatus() === "needs-install") return;
  const reg = await registration().catch(() => null);
  const subscription = await reg?.pushManager.getSubscription();
  if (!subscription) return;
  await deletePushSubscription(subscription.endpoint).catch(() => {});
  await subscription.unsubscribe().catch(() => {});
}

export async function pushEnabled() {
  if (pushStatus() !== "granted" || readOff()) return false;
  const reg = await registration().catch(() => null);
  return Boolean(await reg?.pushManager.getSubscription());
}

export function setBadge(count) {
  if (!("setAppBadge" in navigator)) return;
  (count > 0 ? navigator.setAppBadge(count) : navigator.clearAppBadge()).catch(() => {});
}
