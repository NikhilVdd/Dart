import "./styles.css";
import {
  acceptRequest,
  addListItem,
  advanceRequest,
  cancelRequest,
  confirmPayment,
  createGroup,
  createRequest,
  createRun,
  deleteAccount,
  deleteListItem,
  joinBuilding,
  joinGroup,
  leaveGroup,
  loadAppData,
  loadRequestMessages,
  openPayoutDashboard,
  refreshPayoutStatus,
  releaseRequest,
  requestFromRun,
  sendGroupMessage,
  sendPasswordReset,
  sendRequestMessage,
  submitFeedback,
  setHomePlace,
  setItemCost,
  setListItem,
  signIn,
  signOut,
  signUp,
  startPayment,
  startPayoutOnboarding,
  subscribeToChanges,
  supabase,
  trackProductEvent,
  updateDisplayName,
  updatePassword,
  updateRunStatus
} from "./api.js";
import { authorizeCard, formatCents, mountOnboarding, mountPaymentElement } from "./payments.js";
import { disablePush, enablePush, pushEnabled, pushStatus, setBadge, syncPush } from "./push.js";

const app = document.querySelector("#app");
const modalRoot = document.querySelector("#modal-root");
const toast = document.querySelector("#toast");

const initialTab = new URLSearchParams(location.search).get("tab");
const navTabs = ["home", "activity", "groups", "earn"];
const validTabs = [...navTabs, "profile"];
const tabLabels = { home: "Ask", activity: "Activity", groups: "Groups", earn: "Help", profile: "Profile" };
const ACTIVE_STATUSES = ["open", "accepted", "picking_up", "on_the_way", "delivered"];
const PROGRESS = ["open", "accepted", "picking_up", "on_the_way", "delivered", "completed"];
const PREFS_KEY = "grab:request-prefs:v1";

const state = {
  session: null,
  data: null,
  loading: true,
  refreshing: false,
  working: false,
  authMode: "signin",
  // "request" was the old standalone form; asking now happens on Home.
  tab: validTabs.includes(initialTab) ? initialTab : "home",
  focusComposer: initialTab === "request",
  groupId: null,
  modal: null,
  requestMessages: [],
  coords: null,
  online: navigator.onLine,
  installPrompt: null,
  recovery: false,
  searchQuery: "",
  earnSort: "soonest",
  activityView: "requesting",
  draftText: "",
  draft: null,
  picker: null,
  onboardingStep: 0,
  unsubscribeRealtime: null,
  loadVersion: 0,
  pushOn: false,
  // A tapped notification to open once data has loaded.
  pendingLink: hasDeepLink(location.href) ? location.href : null
};

const icons = {
  home: '<path d="M4 5.5h16v10H9l-5 4v-14Z"/><path d="M8.5 10.5h7"/>',
  groups: '<circle cx="8" cy="8" r="3"/><circle cx="17" cy="9" r="2.5"/><path d="M2.5 20c.7-4 2.6-6 5.5-6s4.8 2 5.5 6"/><path d="M14 15c3.9-.6 6.3 1.1 7 5"/>',
  request: '<path d="M12 5v14M5 12h14"/>',
  earn: '<path d="m5 16 11-11"/><path d="M9 5h7v7"/><path d="M5 20h14"/>',
  activity: '<path d="M4 6h16M4 12h16M4 18h10"/><circle cx="18" cy="18" r="2"/>',
  profile: '<circle cx="12" cy="8" r="4"/><path d="M4 21c.8-5 3.5-7 8-7s7.2 2 8 7"/>',
  search: '<circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/>',
  bell: '<path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9"/><path d="M10 21h4"/>',
  route: '<circle cx="6" cy="18" r="2"/><circle cx="18" cy="6" r="2"/><path d="M7.5 16.5 16.5 7.5"/>',
  bag: '<path d="M5 8h14l-1 12H6L5 8Z"/><path d="M9 9V6a3 3 0 0 1 6 0v3"/>',
  check: '<path d="m5 12 4 4L19 6"/>',
  spark: '<path d="M12 2 14.2 8.8 21 11l-6.8 2.2L12 20l-2.2-6.8L3 11l6.8-2.2L12 2Z"/>',
  users: '<circle cx="9" cy="8" r="3"/><path d="M3 20c.7-4 2.7-6 6-6s5.3 2 6 6"/><path d="M16 5c2 .2 3 1.2 3 3s-1 2.8-3 3"/><path d="M17 14c2.5.5 3.8 2.5 4 6"/>',
  inbox: '<path d="M4 5h16v14H4V5Z"/><path d="M4 14h5l2 2h2l2-2h5"/>',
  clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
  tune: '<path d="M4 7h10M18 7h2M4 17h2M10 17h10"/><circle cx="16" cy="7" r="2"/><circle cx="8" cy="17" r="2"/>',
  arrow: '<path d="M5 12h14M14 7l5 5-5 5"/>',
  send: '<path d="M12 19V5M6 11l6-6 6 6"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  refresh: '<path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 5v6h-6"/>'
};

function icon(name, className = "") {
  const paths = icons[name] || icons.spark;
  return `<svg class="app-icon ${escapeHTML(className)}" viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${paths}</svg>`;
}

function escapeHTML(value = "") {
  return String(value).replace(/[&<>'"]/g, char => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;"
  })[char]);
}

function shortDate(value) {
  if (!value) return "Not set";
  return new Intl.DateTimeFormat("en-US", { weekday: "short", hour: "numeric", minute: "2-digit" }).format(new Date(value));
}

function clockTime(value) {
  return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" }).format(new Date(value));
}

function relativeTime(value) {
  const seconds = Math.round((new Date(value).getTime() - Date.now()) / 1000);
  const formatter = new Intl.RelativeTimeFormat("en", { numeric: "auto" });
  if (Math.abs(seconds) < 60) return formatter.format(seconds, "second");
  const minutes = Math.round(seconds / 60);
  if (Math.abs(minutes) < 60) return formatter.format(minutes, "minute");
  const hours = Math.round(minutes / 60);
  if (Math.abs(hours) < 24) return formatter.format(hours, "hour");
  return formatter.format(Math.round(hours / 24), "day");
}

function titleCase(value = "") {
  return String(value).replaceAll("_", " ").replace(/\b\w/g, letter => letter.toUpperCase());
}

function firstName(name = "") {
  return String(name || "").trim().split(/\s+/)[0] || "";
}

function errorMessage(error) {
  const message = error?.message || "Something went wrong. Please try again.";
  const replacements = [
    [/invalid login credentials/i, "Check your email and password, then try again."],
    [/user already registered/i, "An account already exists for this email. Sign in instead."],
    [/email address not authorized/i, "Dart’s recovery email service is not connected for this address yet. Contact the app owner for a password reset."],
    [/email rate limit exceeded/i, "Too many recovery emails were requested. Wait a little, then try again."],
    [/password should be at least/i, "Use a password with at least 6 characters."],
    [/failed to fetch/i, "Dart couldn’t reach the backend. Check your connection and try again."],
    [/networkerror/i, "Dart couldn’t reach the backend. Check your connection and try again."]
  ];
  return replacements.find(([pattern]) => pattern.test(message))?.[1] ?? message;
}

function showToast(message, tone = "default") {
  toast.textContent = message;
  toast.dataset.tone = tone;
  toast.classList.add("show");
  clearTimeout(showToast.timer);
  showToast.timer = setTimeout(() => toast.classList.remove("show"), 3200);
}

function track(eventName, context = {}) {
  if (!state.session) return;
  trackProductEvent(eventName, context).catch(() => {});
}

function readStorage(key) {
  try { return localStorage.getItem(key); } catch { return null; }
}

function writeStorage(key, value) {
  try { localStorage.setItem(key, value); } catch { /* storage can be unavailable in private windows */ }
}

function setUrlTab(tab) {
  const url = new URL(location.href);
  url.searchParams.set("tab", tab);
  history.replaceState({}, "", url);
}

function isInstalled() {
  return matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;
}

function userId() {
  return state.session.user.id;
}

async function refreshPush() {
  state.pushOn = await pushEnabled().catch(() => false);
}

function pushButton() {
  if (pushStatus() === "unsupported") return "";
  return `<button data-action="${state.pushOn ? "push-disable" : "push-enable"}">${state.pushOn ? "Turn off notifications" : "Turn on notifications"}</button>`;
}

function updateBadge() {
  if (!state.data) return;
  const me = userId();
  setBadge(state.data.requests.filter(item => isActive(item) && (item.requester_id === me || item.helper_id === me)).length);
}

function hasDeepLink(href) {
  const params = new URL(href, location.href).searchParams;
  return ["request", "run", "group"].some(key => params.has(key));
}

// Opens what a notification points at: ./?request=<id>[&chat=1], ./?run=<id>, ./?tab=groups&group=<id>.
function openLink(href) {
  const params = new URL(href, location.href).searchParams;
  const requestId = params.get("request");
  const runId = params.get("run");
  const groupId = params.get("group");
  const clean = new URL(location.href);
  for (const key of ["request", "run", "group", "chat"]) clean.searchParams.delete(key);
  history.replaceState({}, "", clean);
  if (groupId) {
    state.tab = "groups";
    state.groupId = groupId;
    state.modal = null;
    setUrlTab("groups");
    render();
  } else if (runId) {
    state.modal = { type: "run", id: runId };
    renderModal();
  } else if (requestId) {
    openRequest(requestId, { focusChat: params.get("chat") === "1" });
  }
}

async function openRequest(id, { focusChat = false } = {}) {
  state.requestMessages = [];
  state.modal = { type: "request", id };
  renderModal();
  const request = allRequests().find(item => item.id === id);
  if (request && (request.requester_id === userId() || request.helper_id === userId()) && request.helper_id) {
    try { state.requestMessages = await loadRequestMessages(id); preserving(renderModal); } catch { /* chat remains available after refresh */ }
  }
  if (focusChat) document.querySelector("#request-message-form input[name=body]")?.focus();
}

function avatar(person, fallback = "?") {
  const initials = person?.initials || fallback;
  return `<span class="avatar" aria-hidden="true">${escapeHTML(initials)}</span>`;
}

function statusPill(status) {
  const safe = escapeHTML(status || "open");
  return `<span class="status status-${safe}"><i></i>${escapeHTML(titleCase(status || "open"))}</span>`;
}

function emptyState(iconName, title, body, action = "") {
  return `<section class="empty-card"><span class="empty-icon">${icon(iconName)}</span><h3>${escapeHTML(title)}</h3><p>${escapeHTML(body)}</p>${action}</section>`;
}

function pageHeader(eyebrow, title, subtitle, action = "") {
  return `<header class="page-header"><div><p class="eyebrow">${escapeHTML(eyebrow)}</p><h1>${escapeHTML(title)}</h1><p>${escapeHTML(subtitle)}</p></div>${action}</header>`;
}

function skeleton() {
  return `<main class="skeleton-shell" aria-label="Loading Dart"><aside class="skeleton-rail"></aside><section class="skeleton-page"><div class="skeleton-line title"></div><div class="skeleton-composer"></div><div class="skeleton-row"></div><div class="skeleton-row"></div></section></main>`;
}

// Every render replaces the DOM, so realtime refreshes would otherwise wipe whatever the person is
// typing. Edited form fields and focus are carried across each render.
function captureUi() {
  const fields = [...document.querySelectorAll("form[id] input[name], form[id] textarea[name], form[id] select[name]")]
    .filter(field => field.type !== "hidden" && isDirty(field))
    .map(field => ({ key: fieldKey(field), value: field.type === "checkbox" ? field.checked : field.value }));
  const active = document.activeElement;
  let focus = null;
  if (active && active !== document.body && (active.matches("input, textarea, select"))) {
    focus = { id: active.id || null, key: active.form?.id && active.name ? fieldKey(active) : null, selection: null };
    try { focus.selection = [active.selectionStart, active.selectionEnd]; } catch { /* not a text field */ }
  }
  return { fields, focus };
}

function isDirty(field) {
  if (field.type === "checkbox") return field.checked !== field.defaultChecked;
  if (field.tagName === "SELECT") return field.value !== ([...field.options].find(option => option.defaultSelected) ?? field.options[0])?.value;
  return field.value !== field.defaultValue;
}

function fieldKey(field) {
  return `${field.form.id}\u0000${field.name}`;
}

function findField(key) {
  const [formId, name] = key.split("\u0000");
  const field = document.getElementById(formId)?.elements.namedItem(name);
  return field instanceof Element ? field : null;
}

function restoreUi({ fields, focus }) {
  for (const { key, value } of fields) {
    const field = findField(key);
    if (!field) continue;
    if (field.type === "checkbox") field.checked = value;
    else field.value = value;
  }
  if (focus) {
    const field = (focus.id && document.getElementById(focus.id)) || (focus.key && findField(focus.key));
    if (field) {
      field.focus({ preventScroll: true });
      if (focus.selection?.[0] != null) {
        try { field.setSelectionRange(...focus.selection); } catch { /* not a text field */ }
      }
    }
  }
  document.querySelectorAll(".chat-feed").forEach(feed => { feed.scrollTop = feed.scrollHeight; });
}

function preserving(paint) {
  const snapshot = captureUi();
  paint();
  restoreUi(snapshot);
}

function render() {
  document.body.classList.toggle("offline", !state.online);
  if (state.loading) {
    app.innerHTML = skeleton();
    return;
  }
  preserving(() => {
    if (!state.session) renderAuth();
    else renderShell();
  });
  if (state.focusComposer && state.data && state.tab === "home") {
    state.focusComposer = false;
    document.querySelector("#composer-input, #draft-title")?.focus();
  }
}

function renderAuth() {
  const creating = state.authMode === "signup";
  const resetting = state.authMode === "reset";
  app.innerHTML = `
    <main class="auth-layout" id="main">
      <section class="auth-story" aria-label="About Dart">
        <div class="brand-lockup"><img src="./icons/icon-192.png" alt="" /><strong>Dart</strong></div>
        <div class="story-copy">
          <p class="eyebrow light">EVERYDAY ERRANDS</p>
          <h1>Already on<br />the way.</h1>
          <p>Ask trusted people nearby for what you need—or help out along a route you’re already taking.</p>
        </div>
        <div class="trust-row"><span>Private groups</span><span>Live updates</span><span>Secure accounts</span></div>
      </section>
      <section class="auth-panel">
        <div class="auth-card">
          <img class="auth-mark" src="./icons/icon-192.png" alt="Dart" />
          <p class="eyebrow">${resetting ? "ACCOUNT RECOVERY" : creating ? "NEW ACCOUNT" : "WELCOME BACK"}</p>
          <h2>${resetting ? "Reset your password" : creating ? "Create your Dart account" : "Sign in to Dart"}</h2>
          <p class="auth-subtitle">${resetting ? "We’ll email you a secure recovery link." : creating ? "Use any email address—no Berkeley address or verification link is required." : "Use your email and password to continue."}</p>
          <form id="auth-form" class="form-stack">
            ${creating ? `<label><span>Your name</span><input name="displayName" autocomplete="name" minlength="2" maxlength="60" required placeholder="Nikhil V" /></label>` : ""}
            <label><span>Email</span><input name="email" type="email" inputmode="email" autocomplete="email" required placeholder="you@example.com" /></label>
            ${resetting ? "" : `<label><span>Password</span><input name="password" type="password" autocomplete="${creating ? "new-password" : "current-password"}" minlength="6" required placeholder="At least 6 characters" /></label>`}
            ${creating ? `<label><span>Confirm password</span><input name="confirmation" type="password" autocomplete="new-password" minlength="6" required placeholder="Repeat your password" /></label>` : ""}
            <button class="primary-button" type="submit" ${state.working ? "disabled" : ""}>${state.working ? '<span class="button-spinner"></span>' : resetting ? "Send recovery link" : creating ? "Create account" : "Sign in"}</button>
          </form>
          <div class="auth-actions">
            ${resetting ? `<button data-action="auth-mode" data-mode="signin">Back to sign in</button>` : `<button data-action="auth-mode" data-mode="${creating ? "signin" : "signup"}">${creating ? "Already have an account? Sign in" : "New to Dart? Create an account"}</button>`}
            ${!creating && !resetting ? `<button data-action="auth-mode" data-mode="reset">Forgot password?</button>` : ""}
          </div>
          <p class="legal-copy">By continuing, you agree to the <button data-action="legal" data-document="terms">Terms</button> and acknowledge the <button data-action="legal" data-document="privacy">Privacy Notice</button>.</p>
        </div>
      </section>
    </main>`;
}

function renderShell() {
  const profile = state.data?.profile;
  const attention = state.data ? attentionCount() : 0;
  app.innerHTML = `
    <div class="app-layout">
      <aside class="side-nav">
        <a class="app-brand" href="./" aria-label="Dart home"><span class="brand-mark">D</span><span>Dart</span><em>Beta</em></a>
        <nav aria-label="Main navigation">${navTabs.map(tab => navButton(tab)).join("")}</nav>
        <button class="feedback-rail" data-action="feedback">${icon("spark")}<span>Share feedback</span></button>
        <button class="side-profile" data-action="nav" data-tab="profile">${avatar(profile)}<div><strong>${escapeHTML(profile?.display_name || "Dart member")}</strong><span>${escapeHTML(profile?.campus?.name || "Dart community")}</span></div>${icon("chevron")}</button>
      </aside>
      <div class="app-content">
        <div class="network-banner" ${state.online ? "hidden" : ""}>You’re offline. Changes will be available when you reconnect.</div>
        <header class="top-bar">
          <a class="mobile-brand" href="./"><span class="brand-mark">D</span><strong>Dart</strong></a>
          <div class="top-actions">
            <button class="search-trigger" data-action="search" aria-label="Search Dart">${icon("search")}<span>Search Dart</span><kbd>⌘K</kbd></button>
            <button class="icon-button" data-action="updates" aria-label="View updates${attention ? ` (${attention} need attention)` : ""}">${icon("bell")}${attention ? `<i class="badge">${attention}</i>` : ""}</button>
            <button class="profile-button" data-action="nav" data-tab="profile" aria-label="Open profile">${escapeHTML(profile?.initials || "?")}</button>
          </div>
        </header>
        <main id="main" class="main-content">${renderPage()}</main>
      </div>
      <nav class="bottom-nav" aria-label="Main navigation">${navTabs.map(tab => navButton(tab)).join("")}</nav>
    </div>`;
  renderModal();
}

function navButton(tab) {
  const active = state.tab === tab;
  return `<button class="nav-item ${active ? "active" : ""}" data-action="nav" data-tab="${tab}" aria-current="${active ? "page" : "false"}"><span>${icon(tab)}</span><b>${tabLabels[tab]}</b></button>`;
}

function renderPage() {
  if (!state.data) return skeleton();
  if (state.tab === "groups") return renderGroups();
  if (state.tab === "earn") return renderEarn();
  if (state.tab === "activity") return renderActivity();
  if (state.tab === "profile") return renderProfile();
  return renderHome();
}

/* ---------- Requests: shared helpers ---------- */

function allRequests() {
  return [...state.data.requests, ...state.data.nearby].filter((item, index, all) => all.findIndex(other => other.id === item.id) === index);
}

function isActive(request) {
  return ACTIVE_STATUSES.includes(request.status);
}

function paymentsOn() {
  return Boolean(state.data?.payments?.required);
}

function isPaid(request) {
  return Boolean(request.payment_status) && request.payment_status !== "none";
}

// A paid request can't be confirmed until the helper has entered the receipt total.
function canConfirm(request) {
  return ["on_the_way", "delivered"].includes(request.status) && (!isPaid(request) || request.item_cost_cents !== null);
}

function parseCents(value) {
  const amount = Number(String(value ?? "").replace(/[$,\s]/g, ""));
  return Number.isFinite(amount) && String(value ?? "").trim() !== "" ? Math.round(amount * 100) : null;
}

function paymentLine(request, forHelper) {
  const fee = request.reward_cents;
  if (request.payment_status === "paid_out") return forHelper ? `${formatCents(request.item_cost_cents + fee)} · paid` : "Paid";
  if (request.payment_status === "canceled") return "Hold released";
  if (request.payment_status === "failed") return "Payment failed";
  if (request.item_cost_cents !== null) return forHelper ? formatCents(request.item_cost_cents + fee) : `${formatCents(request.item_cost_cents)} + ${formatCents(fee)} delivery`;
  return forHelper ? `Receipt + ${formatCents(fee)}` : `Up to ${formatCents(request.merchandise_budget_cents)} + ${formatCents(fee)} delivery`;
}

function attentionCount() {
  const me = userId();
  return state.data.requests.filter(request =>
    (request.requester_id === me && ["on_the_way", "delivered"].includes(request.status)) ||
    (request.helper_id === me && ["accepted", "picking_up", "on_the_way"].includes(request.status))
  ).length;
}

const helperTransitions = { accepted: "picking_up", picking_up: "on_the_way", on_the_way: "delivered" };

function statusLine(request) {
  const mine = request.requester_id === userId();
  const helper = firstName(request.helper?.display_name) || "Your helper";
  const requester = firstName(request.requester?.display_name) || "the requester";
  const lines = {
    open: mine ? "Looking for someone already headed that way" : "Waiting for a helper",
    accepted: mine ? `${helper} accepted and will head out soon` : "You accepted · pick it up next",
    picking_up: mine ? `${helper} is picking it up` : "You’re picking it up",
    on_the_way: mine ? `${helper} is on the way` : `On the way to ${requester}`,
    delivered: mine ? "Delivered — confirm you got it" : `Delivered · waiting for ${requester} to confirm`,
    completed: "Done",
    cancelled: "Cancelled",
    expired: "Expired — nobody could make it in time"
  };
  return lines[request.status] ?? titleCase(request.status);
}

function progressBar(status) {
  const index = PROGRESS.indexOf(status);
  if (index < 0) return "";
  const steps = PROGRESS.slice(1);
  return `<div class="progress" role="img" aria-label="Progress: ${escapeHTML(titleCase(status))}">${steps.map((_, step) => `<i class="${step < index ? "done" : step === index ? "now" : ""}"></i>`).join("")}</div>`;
}

function progressSteps(status) {
  const index = PROGRESS.indexOf(status);
  if (index < 0) return "";
  const labels = ["Posted", "Accepted", "Picking up", "On the way", "Delivered"];
  return `<ol class="stepper">${labels.map((label, step) => `<li class="${step <= index ? "done" : ""} ${step === index ? "now" : ""}"><i>${step <= index ? icon("check") : ""}</i><span>${label}</span></li>`).join("")}</ol>`;
}

function quickAction(request) {
  const me = userId();
  if (request.requester_id === me && canConfirm(request)) {
    return `<button class="primary-button compact" data-action="advance-request" data-id="${request.id}" data-status="completed">Confirm received</button>`;
  }
  const next = helperTransitions[request.status];
  // Delivering a paid request needs the receipt total, which is entered in the request sheet.
  if (request.helper_id === me && next === "delivered" && isPaid(request)) {
    return `<button class="secondary-button compact" data-action="open-request" data-id="${request.id}">Mark Delivered</button>`;
  }
  if (request.helper_id === me && next) {
    return `<button class="secondary-button compact" data-action="advance-request" data-id="${request.id}" data-status="${next}">Mark ${escapeHTML(titleCase(next))}</button>`;
  }
  return "";
}

function renderTrackRow(request) {
  const action = quickAction(request);
  const live = isActive(request);
  return `<article class="track-row ${live ? "" : "is-past"} ${action ? "has-action" : ""}">
    <button class="track-main" data-action="open-request" data-id="${request.id}">
      <span class="track-head"><strong>${escapeHTML(request.title)}</strong></span>
      <span class="track-status status-text-${escapeHTML(request.status)}">${escapeHTML(statusLine(request))}</span>
      ${live ? progressBar(request.status) : ""}
      <small>${escapeHTML(request.pickup_label)} → ${escapeHTML(request.destination_label)} · ${live ? `by ${escapeHTML(clockTime(request.deliver_by))}` : escapeHTML(shortDate(request.updated_at || request.created_at))}</small>
    </button>
    ${action ? `<div class="track-action">${action}</div>` : ""}
  </article>`;
}

/* ---------- Home: ask ---------- */

function storePlaces() {
  return state.data.places.filter(place => ["store", "restaurant", "library", "other"].includes(place.kind));
}

function dropoffPlaces() {
  const home = state.data.profile.home_place_id;
  return state.data.places
    .filter(place => ["residence", "campus", "transit", "library", "other"].includes(place.kind))
    .sort((a, b) => (b.id === home) - (a.id === home));
}

function placeName(id, fallback) {
  return state.data.places.find(place => place.id === id)?.name ?? fallback;
}

function loadPrefs() {
  try { return JSON.parse(readStorage(PREFS_KEY)) || {}; } catch { return {}; }
}

function inferPickup(title) {
  const text = title.toLowerCase();
  return storePlaces()
    .filter(place => text.includes(place.name.toLowerCase()))
    .sort((a, b) => b.name.length - a.name.length)[0]?.id ?? null;
}

function startDraft(title, overrides = {}) {
  const prefs = loadPrefs();
  const dropoffs = dropoffPlaces();
  const known = id => id && dropoffs.some(place => place.id === id);
  const home = state.data.profile.home_place_id;
  const draft = {
    title,
    details: "",
    pickupId: inferPickup(title),
    destinationId: known(prefs.destinationId) ? prefs.destinationId : known(home) ? home : null,
    when: "60",
    customWhen: "",
    groupId: memberGroups().some(group => group.id === prefs.groupId) ? prefs.groupId : null,
    budget: "",
    ...overrides
  };
  if (draft.pickupId && !storePlaces().some(place => place.id === draft.pickupId)) draft.pickupId = null;
  if (!known(draft.destinationId)) draft.destinationId = null;
  if (draft.groupId && !memberGroups().some(group => group.id === draft.groupId)) draft.groupId = null;
  const store = draft.pickupId ? placeName(draft.pickupId) : null;
  if (!draft.destinationId) draft.intro = `Got it${store ? ` — from ${store}` : ""}. Where should it be dropped off?`;
  else if (overrides.title) draft.intro = "Same as last time? Change anything below, then post.";
  else draft.intro = `Got it${store ? ` — from ${store}` : ""}. Here’s your request. Tap anything to change it.`;
  state.draft = draft;
  state.draftText = "";
  state.picker = draft.destinationId ? null : "destinationId";
}

function whenOptions() {
  const now = new Date();
  const options = [["45", "In 45 min"], ["60", "In 1 hour"], ["120", "In 2 hours"]];
  if (now.getHours() < 20 || (now.getHours() === 20 && now.getMinutes() < 30)) options.push(["tonight", "Tonight"]);
  options.push(["tomorrow", "Tomorrow morning"], ["custom", "Pick a time"]);
  return options;
}

function resolveWhen(draft) {
  const now = new Date();
  if (draft.when === "custom") return draft.customWhen ? new Date(draft.customWhen) : null;
  if (draft.when === "tonight") {
    const date = new Date(now);
    date.setHours(21, 0, 0, 0);
    return date;
  }
  if (draft.when === "tomorrow") {
    const date = new Date(now);
    date.setDate(date.getDate() + 1);
    date.setHours(10, 0, 0, 0);
    return date;
  }
  const date = new Date(now.getTime() + Number(draft.when) * 60000);
  date.setMinutes(Math.ceil(date.getMinutes() / 5) * 5, 0, 0);
  return date;
}

function whenLabel(draft) {
  const date = resolveWhen(draft);
  if (!date || Number.isNaN(date.getTime())) return "Pick a time";
  const option = whenOptions().find(([value]) => value === draft.when);
  if (draft.when === "custom") return shortDate(date);
  return `${option?.[1] ?? "Soon"} · ${clockTime(date)}`;
}

function localInputValue(date) {
  return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
}

function draftRows(draft) {
  const group = memberGroups().find(item => item.id === draft.groupId);
  return [
    { field: "pickupId", label: "From", value: draft.pickupId ? placeName(draft.pickupId, "Any store") : "Any store" },
    { field: "destinationId", label: "Drop-off", value: draft.destinationId ? placeName(draft.destinationId, "Choose a spot") : "Choose a spot", missing: !draft.destinationId },
    { field: "when", label: "By", value: whenLabel(draft) },
    ...(paymentsOn() ? [{ field: "budget", label: "Item budget", value: parseCents(draft.budget) ? `Up to ${formatCents(parseCents(draft.budget))}` : "Set a budget", missing: !parseCents(draft.budget) }] : []),
    { field: "groupId", label: "Who sees it", value: group ? group.name : "Everyone on campus" },
    { field: "details", label: "Note", value: draft.details.trim() || "Brand, size, substitutions…", placeholder: !draft.details.trim() }
  ];
}

function choice(field, value, label, active) {
  return `<button class="choice ${active ? "active" : ""}" data-action="draft-set" data-field="${field}" data-value="${escapeHTML(value ?? "")}" aria-pressed="${active}">${escapeHTML(label)}</button>`;
}

function placeChoices(field, places, selected, extra = "") {
  const home = state.data.profile.home_place_id;
  const filter = places.length > 8 ? `<label class="picker-filter">${icon("search")}<span class="sr-only">Filter places</span><input id="picker-filter" placeholder="Search places" autocomplete="off" /></label>` : "";
  return `${filter}<div class="choices">${extra}${places.map(place => choice(field, place.id, place.id === home ? `${place.name} · Home` : place.name, place.id === selected)).join("")}</div>`;
}

function pickerBody(field) {
  const draft = state.draft;
  if (field === "pickupId") return placeChoices(field, storePlaces(), draft.pickupId, choice(field, "", "Any store", !draft.pickupId));
  if (field === "destinationId") {
    const places = dropoffPlaces();
    return places.length ? placeChoices(field, places, draft.destinationId) : `<p class="picker-note">No drop-off spots are set up for your campus yet.</p>`;
  }
  if (field === "when") {
    const min = localInputValue(new Date(Date.now() + 30 * 60000));
    return `<div class="choices">${whenOptions().map(([value, label]) => choice(field, value, label, draft.when === value)).join("")}</div>
      ${draft.when === "custom" ? `<label class="picker-input"><span>Deliver by</span><input id="draft-when-custom" type="datetime-local" min="${min}" value="${escapeHTML(draft.customWhen || min)}" /></label>` : ""}`;
  }
  if (field === "groupId") {
    return `<div class="choices">${choice(field, "", "Everyone on campus", !draft.groupId)}${memberGroups().map(group => choice(field, group.id, group.name, draft.groupId === group.id)).join("")}</div>`;
  }
  if (field === "budget") {
    const { delivery_fee_cents: fee, max_budget_cents: max } = state.data.payments;
    return `<label class="picker-input"><span>Most the items should cost</span><input id="draft-budget" type="number" inputmode="decimal" min="1" max="${max / 100}" step="0.01" placeholder="20.00" value="${escapeHTML(draft.budget)}" /></label>
      <p class="picker-note">Your card is held for this plus ${formatCents(fee)} delivery and card processing. You’re only charged the receipt total.</p><button class="text-button picker-done" data-action="draft-picker" data-field="budget">Done</button>`;
  }
  if (field === "details") {
    return `<textarea id="draft-details" maxlength="1000" rows="3" placeholder="Any brand, unsweetened, one carton" aria-label="Note for your helper">${escapeHTML(draft.details)}</textarea><button class="text-button picker-done" data-action="draft-picker" data-field="details">Done</button>`;
  }
  return "";
}

function renderComposer() {
  const name = firstName(state.data.profile.display_name) || "there";
  const example = storePlaces()[0]?.name;
  const recent = recentRequests();
  const starters = ["Groceries from ", "Coffee from ", "Snacks from ", "Something from the pharmacy"];
  return `<section class="ask">
    <h1 class="ask-title">Hi ${escapeHTML(name)}. <span>What do you need?</span></h1>
    <form id="composer-form" class="composer" autocomplete="off">
      <label class="sr-only" for="composer-input">What do you need?</label>
      <input id="composer-input" name="title" required minlength="2" maxlength="120" enterkeyhint="send" value="${escapeHTML(state.draftText)}" placeholder="${escapeHTML(example ? `Oat milk from ${example}` : "Oat milk and a baguette")}" />
      <button class="composer-send" type="submit" aria-label="Continue">${icon("send")}</button>
    </form>
    <div class="suggest-row">
      ${recent.length
        ? `<span class="suggest-label">Again?</span>${recent.map(request => `<button class="suggest-chip" data-action="draft-again" data-id="${request.id}">${icon("clock")}<span>${escapeHTML(request.title)}</span></button>`).join("")}`
        : starters.map(text => `<button class="suggest-chip" data-action="composer-prefill" data-value="${escapeHTML(text)}">${escapeHTML(text.trim())}</button>`).join("")}
    </div>
  </section>`;
}

function renderDraft() {
  const draft = state.draft;
  return `<section class="ask thread" aria-label="New request">
    <div class="msg msg-user">${state.picker === "title"
      ? `<div class="bubble bubble-user editing"><input id="draft-title" maxlength="120" value="${escapeHTML(draft.title)}" aria-label="What you need" /><button class="text-button picker-done" data-action="draft-picker" data-field="title">Done</button></div>`
      : `<button class="bubble bubble-user" data-action="draft-picker" data-field="title" aria-label="Edit what you need: ${escapeHTML(draft.title)}">${escapeHTML(draft.title)}<small>Edit</small></button>`}</div>
    <div class="msg msg-bot">
      <span class="bot-mark" aria-hidden="true">D</span>
      <div class="bubble bubble-bot">
        <p>${escapeHTML(draft.intro)}</p>
        <div class="draft-card">
          ${draftRows(draft).map(row => {
            const open = state.picker === row.field;
            return `<div class="draft-row ${open ? "open" : ""} ${row.missing ? "missing" : ""}">
              <button class="draft-row-head" data-action="draft-picker" data-field="${row.field}" aria-expanded="${open}"><span>${row.label}</span><b class="${row.placeholder ? "placeholder" : ""}" data-draft-value="${row.field}">${escapeHTML(row.value)}</b>${icon("chevron")}</button>
              ${open ? `<div class="picker">${pickerBody(row.field)}</div>` : ""}
            </div>`;
          }).join("")}
        </div>
        <button class="primary-button post-button" data-action="draft-post" ${state.working ? "disabled" : ""}>${state.working ? '<span class="button-spinner"></span>' : "Post request"}</button>
      </div>
    </div>
    <button class="text-button start-over" data-action="draft-reset">Start over</button>
  </section>`;
}

function refreshDraftLabels() {
  const draft = state.draft;
  if (!draft) return;
  const labels = { when: whenLabel(draft) };
  for (const [field, text] of Object.entries(labels)) {
    document.querySelectorAll(`[data-draft-value="${field}"]`).forEach(element => { element.textContent = text; });
  }
}

function recentRequests() {
  const seen = new Set();
  return state.data.requests
    .filter(request => request.requester_id === userId())
    .filter(request => {
      const key = request.title.trim().toLowerCase();
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    })
    .slice(0, 3);
}

function renderHome() {
  const me = userId();
  const { runs } = state.data;
  const mine = state.data.requests.filter(request => request.requester_id === me && isActive(request));
  const helping = state.data.requests.filter(request => request.helper_id === me && isActive(request));
  const showInstall = !isInstalled() && readStorage("grab:install-tip:dismissed") !== "true";
  return `<div class="page page-ask">
    ${state.draft ? renderDraft() : renderComposer()}
    ${mine.length ? `<section class="home-section"><div class="section-heading"><h2>On its way to you</h2><button data-action="nav" data-tab="activity">All activity</button></div><div class="track-list">${mine.map(renderTrackRow).join("")}</div></section>` : ""}
    ${helping.length ? `<button class="helping-strip" data-action="activity-view" data-view="helping">${icon("route")}<span>You’re helping with <b>${helping.length}</b> ${helping.length === 1 ? "request" : "requests"}</span>${icon("chevron")}</button>` : ""}
    <section class="home-section">
      <div class="section-heading"><div><h2>Heading out now</h2><p>Add an item to a trip someone’s already making.</p></div></div>
      ${runs.length ? `<div class="run-list">${runs.map(renderRunRow).join("")}</div>` : `<p class="quiet-empty">No one’s announced a run right now. Ask above and anyone nearby can pick it up.</p>`}
    </section>
    ${showInstall ? `<section class="install-tip"><span class="brand-mark">D</span><div><strong>Put Dart on your Home Screen</strong><p>One tap to ask, and it opens like an app.</p></div><button class="secondary-button compact" data-action="install">Install</button><button class="text-button compact" data-action="dismiss-install" aria-label="Dismiss install tip">Not now</button></section>` : ""}
  </div>`;
}

function renderRunRow(run) {
  const own = run.runner_id === userId();
  return `<button class="run-row" data-action="open-run" data-id="${run.id}">
    ${avatar(run.runner)}
    <span><strong>${own ? "You" : escapeHTML(firstName(run.runner?.display_name) || "Someone")} → ${escapeHTML(run.store_label)}</strong><small>Back to ${escapeHTML(run.destination_label)} · closes ${escapeHTML(relativeTime(run.closes_at))}</small></span>
    ${own ? "<b>Your run</b>" : ""}
    ${own ? icon("chevron") : `<em>Add item</em>`}
  </button>`;
}

/* ---------- Groups ---------- */

function renderGroups() {
  const { groups, members } = state.data;
  const memberIds = new Set(members.filter(item => item.user_id === userId()).map(item => item.group_id));
  const joined = groups.filter(group => memberIds.has(group.id));
  const discoverable = groups.filter(group => !memberIds.has(group.id) && group.kind === "building");
  if (state.groupId) {
    const group = groups.find(item => item.id === state.groupId);
    if (group) return renderGroupDetail(group, members.filter(item => item.group_id === group.id));
    state.groupId = null;
  }
  return `<div class="page page-narrow">
    ${pageHeader("YOUR PEOPLE", "Groups", "Shared lists, runs, and chat with people you trust.", `<button class="primary-button compact" data-action="group-tools">${icon("request")} New or join</button>`)}
    ${joined.length ? `<div class="group-list">${joined.map(group => renderGroupCard(group, members)).join("")}</div>` : emptyState("users", "No groups yet", "Create a friend group or join one with an invite code.", `<button class="secondary-button compact" data-action="group-tools">Create or join</button>`)}
    ${discoverable.length ? `<section class="subsection"><div class="section-heading"><h2>Buildings near you</h2></div><div class="group-list">${discoverable.map(group => `<article class="group-card"><span class="group-icon">⌂</span><div><h3>${escapeHTML(group.name)}</h3><p>Join your neighbors for shared errands.</p></div><button class="secondary-button compact" data-action="join-building" data-id="${group.id}">Join</button></article>`).join("")}</div></section>` : ""}
  </div>`;
}

function renderGroupCard(group, members) {
  const count = members.filter(item => item.group_id === group.id).length;
  const latest = state.data.messages.find(item => item.group_id === group.id);
  return `<button class="group-card clickable" data-action="open-group" data-id="${group.id}"><span class="group-icon">${group.kind === "building" ? "⌂" : "◎"}</span><div><h3>${escapeHTML(group.name)}</h3><p>${latest ? `${escapeHTML(latest.sender?.display_name || "Member")}: ${escapeHTML(latest.body)}` : "No messages yet"}</p><small>${escapeHTML(titleCase(group.kind))} · ${count} ${count === 1 ? "member" : "members"}</small></div>${icon("chevron", "chevron")}</button>`;
}

function renderGroupDetail(group, members) {
  const items = state.data.listItems.filter(item => item.group_id === group.id);
  const messages = state.data.messages.filter(item => item.group_id === group.id).slice().reverse();
  const run = state.data.runs.find(item => item.group_id === group.id);
  return `<div class="page">
    <button class="back-button" data-action="back-groups">← All groups</button>
    ${pageHeader(titleCase(group.kind), group.name, `${members.length} ${members.length === 1 ? "member" : "members"} · Invite code ${group.invite_code}`, `<button class="quiet-danger compact" data-action="leave-group" data-id="${group.id}">Leave</button>`)}
    ${run ? `<section class="run-highlight"><div><span class="category-pill">Active run</span><h2>${escapeHTML(run.store_label)}</h2><p>${escapeHTML(run.runner?.display_name || "A member")} is accepting requests until ${escapeHTML(shortDate(run.closes_at))}.</p></div><button class="primary-button compact" data-action="open-run" data-id="${run.id}">View run</button></section>` : `<button class="helping-strip" data-action="open-run-form">${icon("bag")}<span>Heading to a store? <b>Announce a run</b> to this group</span>${icon("chevron")}</button>`}
    <div class="group-detail-grid">
      <section class="panel chat-panel"><div class="section-heading"><h2>Chat</h2></div>
        <div class="chat-feed">${messages.length ? messages.map(message => `<div class="chat-message ${message.sender_id === userId() ? "mine" : ""}"><strong>${escapeHTML(message.sender?.display_name || "Member")}</strong><p>${escapeHTML(message.body)}</p><small>${escapeHTML(shortDate(message.created_at))}</small></div>`).join("") : `<p class="empty-copy">Say hi to your group.</p>`}</div>
        <form id="group-message-form" class="inline-form"><input type="hidden" name="groupId" value="${group.id}" /><input name="body" required maxlength="2000" placeholder="Message the group" aria-label="Message the group" autocomplete="off" /><button type="submit" aria-label="Send message">${icon("send")}</button></form>
      </section>
      <section class="panel"><div class="section-heading"><h2>Shared list</h2></div>
        <form id="list-item-form" class="inline-form"><input type="hidden" name="groupId" value="${group.id}" /><input name="body" required maxlength="200" placeholder="Add an item" aria-label="Add a list item" autocomplete="off" /><button type="submit" aria-label="Add item">${icon("request")}</button></form>
        <div class="list-rows">${items.length ? items.map(item => `<div class="list-row ${item.status === "picked" ? "done" : ""}"><button data-action="toggle-list" data-id="${item.id}" data-picked="${item.status === "picked"}" aria-label="${item.status === "picked" ? "Mark needed" : "Mark picked"}">${item.status === "picked" ? "✓" : "○"}</button><span>${escapeHTML(item.body)}${item.quantity > 1 ? `<small>Qty ${item.quantity}</small>` : ""}</span><button class="row-delete" data-action="delete-list" data-id="${item.id}" aria-label="Delete ${escapeHTML(item.body)}">×</button></div>`).join("") : `<p class="empty-copy">Nothing on the list yet.</p>`}</div>
      </section>
    </div>
  </div>`;
}

/* ---------- Earn ---------- */

function renderEarn() {
  const { earnings } = state.data;
  const nearby = sortedEarnRequests();
  return `<div class="page">
    ${pageHeader("HELP ON YOUR ROUTE", "Help a friend", "Pick up requests that fit where you’re already going.", `<button class="primary-button compact" data-action="open-run-form">${icon("bag")} Announce a run</button>`)}
    <section class="earnings-strip"><div><span>Helped</span><strong>${earnings.completed_count}</strong></div><div><span>In progress</span><strong>${earnings.active_count}</strong></div></section>
    <div class="toolbar">
      <div class="filter-row" role="group" aria-label="Sort open requests">
        ${[["soonest", "Soonest"], ["closest", "Closest"]].map(([value, label]) => `<button class="filter-chip ${state.earnSort === value ? "active" : ""}" data-action="earn-sort" data-sort="${value}" aria-pressed="${state.earnSort === value}">${label}</button>`).join("")}
      </div>
      <button class="link-button" data-action="locate">${state.coords ? "Location on" : "Use my location"}</button>
    </div>
    ${nearby.length ? `<div class="task-grid">${nearby.map(renderRequestCard).join("")}</div>` : emptyState("route", "No tasks available", "Try again soon or announce a store run so neighbors can request items.", `<button class="secondary-button compact" data-action="open-run-form">Announce a run</button>`)}
  </div>`;
}

function renderRequestCard(request) {
  return `<button class="task-card" data-action="open-request" data-id="${request.id}">
    <div class="card-top">${statusPill(request.status)}</div>
    <h3>${escapeHTML(request.title)}</h3><p>${escapeHTML(request.pickup_label)} → ${escapeHTML(request.destination_label)}</p>
    <div class="card-meta"><span>Due ${escapeHTML(shortDate(request.deliver_by))}</span><span>${request.est_minutes ? `+${request.est_minutes} min` : "Open task"}</span></div>
  </button>`;
}

function sortedEarnRequests() {
  const requests = [...state.data.nearby];
  if (state.earnSort === "closest") return requests.sort((a, b) => Number(a.est_minutes ?? 9999) - Number(b.est_minutes ?? 9999));
  return requests.sort((a, b) => new Date(a.deliver_by) - new Date(b.deliver_by));
}

/* ---------- Activity ---------- */

function renderActivity() {
  const me = userId();
  const mine = state.data.requests.filter(item => item.requester_id === me);
  const helping = state.data.requests.filter(item => item.helper_id === me);
  const showingHelping = state.activityView === "helping";
  const list = showingHelping ? helping : mine;
  const live = list.filter(isActive);
  const past = list.filter(request => !isActive(request));
  const segment = (view, label, count) => `<button class="${state.activityView === view ? "active" : ""}" data-action="activity-view" data-view="${view}" aria-pressed="${state.activityView === view}">${label}<b>${count}</b></button>`;
  return `<div class="page page-narrow">
    ${pageHeader("LIVE STATUS", "Activity", "Everything you’ve asked for or agreed to help with.")}
    <div class="segmented" role="group" aria-label="Activity view">${segment("requesting", "Requesting", mine.filter(isActive).length)}${segment("helping", "Helping", helping.filter(isActive).length)}</div>
    ${live.length ? `<div class="track-list">${live.map(renderTrackRow).join("")}</div>` : showingHelping
      ? emptyState("route", "Nothing in progress", "Browse open requests and pick one that fits your route.", `<button class="secondary-button compact" data-action="nav" data-tab="earn">Browse tasks</button>`)
      : emptyState("home", "Nothing in progress", "Ask for something and you can follow it here.", `<button class="secondary-button compact" data-action="ask">Ask for something</button>`)}
    ${past.length ? `<section class="subsection"><div class="section-heading"><h2>Earlier</h2></div><div class="track-list">${past.map(renderTrackRow).join("")}</div></section>` : ""}
  </div>`;
}

/* ---------- Profile ---------- */

function renderProfile() {
  const { profile, places } = state.data;
  const residences = places.filter(place => place.kind === "residence");
  return `<div class="page page-narrow profile-page">
    <section class="profile-hero">${avatar(profile)}<div><h2>${escapeHTML(profile.display_name)}</h2><p>${escapeHTML(state.session.user.email)}</p><span>${escapeHTML(profile.campus?.name || "Dart community")}</span></div></section>
    <div class="settings-grid">
      <section class="panel"><h2>Display name</h2><form id="profile-form" class="form-stack"><label><span>Name shown to members</span><input name="displayName" value="${escapeHTML(profile.display_name)}" minlength="1" maxlength="60" required /></label><button class="secondary-button" type="submit">Save name</button></form></section>
      <section class="panel"><h2>Home building</h2><form id="home-form" class="form-stack"><label><span>Used as your default drop-off</span><select name="placeId"><option value="">No home selected</option>${placeOptions(residences, profile.home_place_id)}</select></label><button class="secondary-button" type="submit">Update home</button></form></section>
      ${paymentsOn() ? `<section class="panel"><h2>Payouts</h2><p>${state.data.payout?.transfers_active ? "Payouts are on. What you earn from deliveries goes to your bank." : "Set up payouts to help with paid requests. Stripe verifies your identity and bank account."}</p>${state.data.payout?.transfers_active ? `<button class="secondary-button" data-action="payout-dashboard">View earnings and payouts</button>` : `<button class="secondary-button" data-action="payouts">Set up payouts</button>`}</section>` : ""}
      <section class="panel"><h2>Install Dart</h2><p>Use Dart from your Home Screen in a full-screen app window.</p>${isInstalled() ? `<div class="success-note">✓ Dart is installed on this device.</div>` : `<button class="secondary-button" data-action="install">Install on this device</button>`}</section>
      <section class="panel"><h2>Account</h2><div class="settings-actions"><button data-action="feedback">Share feedback</button><button data-action="replay-intro">Replay the intro</button>${pushButton()}<button data-action="password-reset">Email password reset</button><button data-action="signout">Sign out</button><button class="danger-link" data-action="delete-account">Delete account</button></div></section>
    </div>
    <footer class="app-footer"><button data-action="legal" data-document="privacy">Privacy</button><button data-action="legal" data-document="terms">Terms</button><span>Dart web v1.1</span></footer>
  </div>`;
}

function placeOptions(places, selected = null) {
  return places.map(place => `<option value="${place.id}" ${place.id === selected ? "selected" : ""}>${escapeHTML(place.name)}${place.detail ? ` · ${escapeHTML(place.detail)}` : ""}</option>`).join("");
}

function memberGroups() {
  const memberIds = new Set(state.data.members.filter(item => item.user_id === userId()).map(item => item.group_id));
  return state.data.groups.filter(group => memberIds.has(group.id));
}

/* ---------- Modals ---------- */

function renderModal() {
  if (!state.modal) {
    modalRoot.innerHTML = "";
    modalRoot.dataset.key = "";
    return;
  }
  // Payment sheets hold Stripe iframes; re-rendering would wipe what the user has typed.
  if (state.modal.key && modalRoot.dataset.key === state.modal.key) return;
  modalRoot.dataset.key = state.modal.key ?? "";
  const body = modalBody();
  modalRoot.innerHTML = `<div class="modal-backdrop"><section class="modal" role="dialog" aria-modal="true" aria-labelledby="modal-title"><button class="modal-close" data-action="close-modal" aria-label="Close">×</button>${body}</section></div>`;
}

function modalBody() {
  const modal = state.modal;
  if (modal.type === "search") return searchModal();
  if (modal.type === "updates") return updatesModal();
  if (modal.type === "feedback") return feedbackModal();
  if (modal.type === "onboarding") return onboardingModal();
  if (modal.type === "install") return installModal();
  if (modal.type === "run-form") return runFormModal();
  if (modal.type === "run") return runModal(modal.id);
  if (modal.type === "request") return requestModal(modal.id);
  if (modal.type === "group-tools") return groupToolsModal();
  if (modal.type === "delete-account") return confirmDeleteModal();
  if (modal.type === "legal") return legalModal(modal.document);
  if (modal.type === "password") return passwordModal();
  if (modal.type === "pay") return payModal();
  if (modal.type === "payouts") return payoutsModal();
  return "";
}

function searchModal() {
  return `<div class="search-modal"><h2 id="modal-title">Search Dart</h2><label class="search-field">${icon("search")}<span class="sr-only">Search requests, runs, and groups</span><input id="global-search" value="${escapeHTML(state.searchQuery)}" placeholder="Try “Target”, “oat milk”, or a group" autocomplete="off" autofocus /></label><div id="search-results">${searchResultsMarkup()}</div></div>`;
}

function searchResultsMarkup() {
  const query = state.searchQuery.trim().toLowerCase();
  const requests = allRequests()
    .filter(item => !query || [item.title, item.details, item.pickup_label, item.destination_label].some(value => String(value || "").toLowerCase().includes(query)))
    .slice(0, 5);
  const runs = state.data.runs
    .filter(item => !query || [item.store_label, item.destination_label, item.runner?.display_name].some(value => String(value || "").toLowerCase().includes(query)))
    .slice(0, 4);
  const groups = state.data.groups
    .filter(item => !query || item.name.toLowerCase().includes(query))
    .slice(0, 4);
  if (query.length === 1) return `<div class="search-empty">Keep typing to search your community.</div>`;
  if (!requests.length && !runs.length && !groups.length) return `<div class="search-empty">${icon("search")}<strong>No matches yet</strong><span>Try a store, item, destination, or group name.</span>${query ? `<button class="secondary-button compact" data-action="ask-from-search">Ask for “${escapeHTML(state.searchQuery.trim())}”</button>` : ""}</div>`;
  return `<div class="search-groups">
    ${runs.length ? `<section><span class="result-label">LIVE RUNS</span>${runs.map(run => `<button class="search-result" data-action="open-run" data-id="${run.id}"><span class="result-icon">${icon("bag")}</span><span><strong>${escapeHTML(run.store_label)}</strong><small>${escapeHTML(run.destination_label)} · ${escapeHTML(run.runner?.display_name || "Dart runner")}</small></span>${icon("arrow")}</button>`).join("")}</section>` : ""}
    ${requests.length ? `<section><span class="result-label">REQUESTS</span>${requests.map(request => `<button class="search-result" data-action="open-request" data-id="${request.id}"><span class="result-icon">${icon("route")}</span><span><strong>${escapeHTML(request.title)}</strong><small>${escapeHTML(request.pickup_label)} → ${escapeHTML(request.destination_label)}</small></span>${icon("arrow")}</button>`).join("")}</section>` : ""}
    ${groups.length ? `<section><span class="result-label">GROUPS</span>${groups.map(group => `<button class="search-result" data-action="search-group" data-id="${group.id}"><span class="result-icon">${icon("users")}</span><span><strong>${escapeHTML(group.name)}</strong><small>${escapeHTML(titleCase(group.kind))} community</small></span>${icon("arrow")}</button>`).join("")}</section>` : ""}
  </div>`;
}

function updatesModal() {
  const active = state.data.requests.filter(isActive).slice(0, 6);
  const runs = state.data.runs.slice(0, 3);
  return `<div class="modal-title-row"><div><h2 id="modal-title">Updates</h2><p>Everything that needs your attention, in one place.</p></div><button class="icon-button ${state.refreshing ? "is-spinning" : ""}" data-action="refresh" aria-label="Refresh live data" ${state.refreshing ? "disabled" : ""}>${icon("refresh")}</button></div><div class="update-list">${active.map(request => `<button class="update-row" data-action="open-request" data-id="${request.id}"><span class="update-dot ${quickAction(request) ? "" : "quiet"}"></span><span><strong>${escapeHTML(request.title)}</strong><small>${escapeHTML(statusLine(request))} · ${escapeHTML(relativeTime(request.updated_at || request.created_at))}</small></span>${icon("chevron")}</button>`).join("")}${runs.map(run => `<button class="update-row" data-action="open-run" data-id="${run.id}"><span class="update-dot lime"></span><span><strong>${escapeHTML(run.store_label)}</strong><small>Run closes ${escapeHTML(relativeTime(run.closes_at))}</small></span>${icon("chevron")}</button>`).join("")}${!active.length && !runs.length ? `<div class="search-empty">${icon("check")}<strong>You’re all caught up</strong><span>New request and run activity will appear here.</span></div>` : ""}</div>`;
}

function feedbackModal() {
  return `<p class="eyebrow">FRIENDS & FAMILY</p><h2 id="modal-title">Help shape Dart</h2><p>Tell us what felt confusing, broken, or surprisingly useful.</p><form id="feedback-form" class="form-stack"><label><span>Feedback type</span><select name="category"><option value="idea">Idea</option><option value="bug">Something is broken</option><option value="confusing">Something is confusing</option><option value="love">Something I love</option></select></label><label><span>Your feedback</span><textarea name="message" minlength="3" maxlength="2000" rows="5" required placeholder="What happened, and what did you expect?"></textarea></label><label class="check-row"><input name="contactOk" type="checkbox" /><span>You may follow up with me at my account email.</span></label><button class="primary-button" type="submit" ${state.working ? "disabled" : ""}>Send feedback</button></form>`;
}

function onboardingModal() {
  const slides = [
    { icon: "home", eyebrow: "WELCOME TO DART", title: "Just ask.", body: "Type what you need—“oat milk from Berkeley Bowl”—and someone already heading out can bring it back." },
    { icon: "activity", eyebrow: "STAY IN THE LOOP", title: "Watch it arrive.", body: "Follow every step live, chat privately with your helper, and confirm when it’s in your hands." },
    { icon: "users", eyebrow: "WHEN YOU’RE OUT", title: "Help on your way.", body: "Pick up a nearby request, announce a store run, or coordinate with your groups—only when it fits." }
  ];
  const slide = slides[state.onboardingStep] || slides[0];
  return `<div class="onboarding"><span class="onboarding-icon">${icon(slide.icon)}</span><p class="eyebrow">${slide.eyebrow}</p><h2 id="modal-title">${slide.title}</h2><p>${slide.body}</p><div class="onboarding-dots">${slides.map((_, index) => `<i class="${index === state.onboardingStep ? "active" : ""}"></i>`).join("")}</div><div class="onboarding-actions">${state.onboardingStep ? `<button class="secondary-button" data-action="onboarding-back">Back</button>` : `<button class="text-button" data-action="onboarding-skip">Skip</button>`}<button class="primary-button" data-action="${state.onboardingStep === slides.length - 1 ? "onboarding-complete" : "onboarding-next"}">${state.onboardingStep === slides.length - 1 ? "Start using Dart" : "Continue"}</button></div></div>`;
}

function installModal() {
  const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
  return `<p class="eyebrow">INSTALL DART</p><h2 id="modal-title">Put Dart on your Home Screen</h2>${ios ? `<ol class="install-steps"><li><b>1</b><span>Open this page in Safari.</span></li><li><b>2</b><span>Tap the Share button.</span></li><li><b>3</b><span>Choose <strong>Add to Home Screen</strong>, turn on <strong>Open as Web App</strong>, then tap Add.</span></li></ol>` : `<p>Your browser can install Dart as an app. Choose Install below or use your browser’s install menu.</p><button class="primary-button" data-action="trigger-install">Install Dart</button>`}<p class="modal-note">After installation, Dart opens in its own app window and keeps your signed-in session securely on this device.</p>`;
}

function runFormModal() {
  const stores = state.data.places.filter(place => ["store", "restaurant", "other"].includes(place.kind));
  const destinations = state.data.places.filter(place => ["residence", "campus", "transit", "other"].includes(place.kind));
  const groups = memberGroups();
  const currentGroup = state.tab === "groups" ? state.groupId : null;
  return `<p class="eyebrow">ALREADY GOING?</p><h2 id="modal-title">Announce a store run</h2><p>Let people request items only if they fit the route you’re already taking.</p><form id="run-form" class="form-stack">
    <label><span>Store</span><select name="storePlaceId" required><option value="">Choose a store</option>${placeOptions(stores)}</select></label>
    <label><span>Destination</span><select name="destinationPlaceId" required><option value="">Where are you heading?</option>${placeOptions(destinations, state.data.profile.home_place_id)}</select></label>
    <div class="split-fields"><label><span>Accept for</span><select name="minutes"><option value="30">30 minutes</option><option value="45">45 minutes</option><option value="60">1 hour</option><option value="90">90 minutes</option></select></label><label><span>Capacity</span><select name="capacity"><option value="3">3 requests</option><option value="5">5 requests</option><option value="8">8 requests</option></select></label></div>
    <label><span>Audience</span><select name="audience"><option value="campus">Campus</option>${groups.map(group => `<option value="group:${group.id}" ${group.id === currentGroup ? "selected" : ""}>${escapeHTML(group.name)}</option>`).join("")}</select></label>
    <label><span>Max detour</span><select name="detour"><option value="5">5 min</option><option value="10" selected>10 min</option><option value="15">15 min</option><option value="20">20 min</option></select></label>
    <label><span>Note</span><textarea name="note" maxlength="500" rows="2" placeholder="Optional details"></textarea></label>
    <button class="primary-button" type="submit" ${state.working ? "disabled" : ""}>Announce run</button>
  </form>`;
}

function runModal(id) {
  const run = state.data.runs.find(item => item.id === id);
  if (!run) return `<h2 id="modal-title">Run unavailable</h2><p>This run may have closed. Refresh to see current activity.</p>`;
  const own = run.runner_id === userId();
  return `<p class="eyebrow">${escapeHTML(titleCase(run.audience))} RUN</p><div class="modal-title-row"><div><h2 id="modal-title">${escapeHTML(run.store_label)}</h2><p>Heading to ${escapeHTML(run.destination_label)}</p></div>${statusPill(run.status)}</div>
    <div class="detail-person">${avatar(run.runner)}<div><strong>${escapeHTML(run.runner?.display_name || "Dart runner")}</strong><span>${own ? "You announced this run" : `Accepting requests · closes ${relativeTime(run.closes_at)}`}</span></div></div>
    ${run.note ? `<div class="notice"><b>Runner note</b><p>${escapeHTML(run.note)}</p></div>` : ""}
    ${own ? `<dl class="detail-grid"><div><dt>Closes</dt><dd>${escapeHTML(shortDate(run.closes_at))}</dd></div><div><dt>Capacity</dt><dd>${run.capacity} requests</dd></div><div><dt>Max detour</dt><dd>${run.max_added_minutes} min</dd></div></dl><div class="modal-actions">${run.status === "open" ? `<button class="primary-button" data-action="run-status" data-id="${run.id}" data-status="shopping">Start shopping</button>` : ""}${run.status === "shopping" ? `<button class="primary-button" data-action="run-status" data-id="${run.id}" data-status="returning">Head back</button>` : ""}${run.status === "returning" ? `<button class="primary-button" data-action="run-status" data-id="${run.id}" data-status="completed">Finish run</button>` : ""}<button class="quiet-danger" data-action="run-status" data-id="${run.id}" data-status="cancelled">Cancel run</button></div>` : `<form id="request-from-run-form" class="form-stack"><input type="hidden" name="runId" value="${run.id}" /><label><span>What should they grab?</span><input name="title" required maxlength="120" placeholder="One carton of oat milk" /></label><label><span>Details (optional)</span><textarea name="details" maxlength="1000" rows="2" placeholder="Brand or substitution notes"></textarea></label>${paymentsOn() ? `<label><span>Item budget (plus ${formatCents(state.data.payments.delivery_fee_cents)} delivery)</span><input name="budget" type="number" inputmode="decimal" min="1" max="${state.data.payments.max_budget_cents / 100}" step="0.01" required placeholder="20.00" /></label>` : ""}<button class="primary-button" type="submit">Add to ${escapeHTML(firstName(run.runner?.display_name) || "this")}’s run</button></form><p class="modal-note">Capacity ${run.capacity} requests · up to ${run.max_added_minutes} min detour · closes ${escapeHTML(shortDate(run.closes_at))}</p>`}`;
}

function requestModal(id) {
  const request = allRequests().find(item => item.id === id);
  if (!request) return `<h2 id="modal-title">Request unavailable</h2><p>Someone may have accepted or cancelled it. Refresh to see current tasks.</p>`;
  const isRequester = request.requester_id === userId();
  const isHelper = request.helper_id === userId();
  const canChat = isRequester || isHelper;
  const next = helperTransitions[request.status];
  let actions = "";
  if (request.status === "open" && !isRequester) actions += `<button class="primary-button" data-action="accept-request" data-id="${request.id}">Accept request</button>`;
  const needsReceipt = isHelper && next === "delivered" && isPaid(request);
  if (isHelper && next && !needsReceipt) actions += `<button class="primary-button" data-action="advance-request" data-id="${request.id}" data-status="${next}">Mark ${escapeHTML(titleCase(next))}</button>`;
  if (isRequester && canConfirm(request)) actions += `<button class="primary-button" data-action="advance-request" data-id="${request.id}" data-status="completed">Confirm received</button>`;
  if (isHelper && ["accepted", "picking_up"].includes(request.status)) actions += `<button class="secondary-button" data-action="release-request" data-id="${request.id}">Release task</button>`;
  if (isRequester && !isActive(request)) actions += `<button class="secondary-button" data-action="draft-again" data-id="${request.id}">Ask for this again</button>`;
  if (isRequester && ["open", "accepted"].includes(request.status)) actions += `<button class="quiet-danger" data-action="cancel-request" data-id="${request.id}">Cancel request</button>`;
  const helperName = request.helper?.display_name;
  return `<p class="eyebrow">${isRequester ? "YOUR REQUEST" : isHelper ? "YOU’RE HELPING" : "OPEN REQUEST"}</p>
    <h2 id="modal-title">${escapeHTML(request.title)}</h2>
    <p class="status-headline status-text-${escapeHTML(request.status)}">${escapeHTML(statusLine(request))}</p>
    ${progressSteps(request.status)}
    ${request.details ? `<div class="notice"><b>Note</b><p>${escapeHTML(request.details)}</p></div>` : ""}
    <dl class="detail-grid"><div><dt>From</dt><dd>${escapeHTML(request.pickup_label)}</dd></div><div><dt>Drop-off</dt><dd>${escapeHTML(request.destination_label)}</dd></div><div><dt>By</dt><dd>${escapeHTML(shortDate(request.deliver_by))}</dd></div><div><dt>${isRequester ? "Helper" : "Posted by"}</dt><dd>${escapeHTML(isRequester ? helperName || "Not yet" : request.requester?.display_name || "Dart member")}</dd></div>${isPaid(request) ? `<div class="wide"><dt>${isRequester ? "Payment" : "You get"}</dt><dd>${escapeHTML(paymentLine(request, !isRequester))}</dd></div>` : ""}</dl>
    ${needsReceipt ? `<form id="deliver-form" class="inline-form"><input type="hidden" name="requestId" value="${request.id}" /><input name="receipt" type="number" inputmode="decimal" min="0" max="${request.merchandise_budget_cents / 100}" step="0.01" required placeholder="Receipt total (up to ${escapeHTML(formatCents(request.merchandise_budget_cents))})" aria-label="Receipt total" /><button type="submit" aria-label="Mark delivered">${icon("check")}</button></form>` : ""}
    ${actions ? `<div class="modal-actions">${actions}</div>` : ""}
    ${canChat && request.helper_id ? `<section class="request-chat"><div class="section-heading"><h3>Chat with ${escapeHTML(firstName(isRequester ? helperName : request.requester?.display_name) || "them")}</h3></div><div class="chat-feed compact-chat">${state.requestMessages.length ? state.requestMessages.map(message => `<div class="chat-message ${message.sender_id === userId() ? "mine" : ""}"><strong>${escapeHTML(message.sender?.display_name || "Member")}</strong><p>${escapeHTML(message.body)}</p></div>`).join("") : `<p class="empty-copy">No messages yet. Say hi or share handoff details.</p>`}</div>${isActive(request) ? `<form id="request-message-form" class="inline-form"><input type="hidden" name="requestId" value="${request.id}" /><input name="body" required maxlength="2000" placeholder="Message privately" aria-label="Message privately" autocomplete="off" /><button type="submit" aria-label="Send">${icon("send")}</button></form>` : ""}</section>` : ""}`;
}

function payModal() {
  return `<p class="eyebrow">SECURE PAYMENT</p><h2 id="modal-title">Hold your payment</h2><p>You’re only charged the receipt total plus delivery, after you confirm you got it. If nobody picks it up, the hold is released.</p>
    <dl id="pay-summary" class="detail-grid"><div class="wide"><dt>Hold up to</dt><dd>Loading…</dd></div></dl>
    <form id="pay-form" class="form-stack"><div id="payment-element" class="stripe-embed"></div><button class="primary-button" type="submit" disabled>Hold payment</button></form>`;
}

function paySummary(hold) {
  return `<div><dt>Items, up to</dt><dd>${formatCents(hold.budget_cents)}</dd></div><div><dt>Delivery</dt><dd>${formatCents(hold.fee_cents)}</dd></div><div><dt>Card processing</dt><dd>${formatCents(hold.processing_cents)}</dd></div><div><dt>Hold up to</dt><dd>${formatCents(hold.total_cents)}</dd></div>`;
}

function payoutsModal() {
  return `<p class="eyebrow">GET PAID</p><h2 id="modal-title">Set up payouts</h2><p>Stripe verifies who you are and where to send your earnings. Dart never sees your bank details.</p><div id="connect-onboarding" class="stripe-embed"><p class="empty-copy">Loading…</p></div>`;
}

// Holds the requester's card, then runs finish(paymentIntentId) to post the request.
async function openPayment(budgetCents, finish, success) {
  const modal = { type: "pay", key: `pay-${Date.now()}`, finish, success, hold: null, stripe: null, authorized: false };
  state.modal = modal;
  renderModal();
  try {
    modal.hold = await startPayment(budgetCents);
    if (state.modal !== modal) return;
    document.querySelector("#pay-summary").innerHTML = paySummary(modal.hold);
    modal.stripe = await mountPaymentElement(document.querySelector("#payment-element"), modal.hold);
    const button = document.querySelector("#pay-form button[type=submit]");
    button.textContent = `Hold ${formatCents(modal.hold.total_cents)}`;
    button.disabled = false;
  } catch (error) {
    showToast(errorMessage(error), "error");
    if (state.modal === modal) closeModal();
  }
}

async function openPayouts() {
  const modal = { type: "payouts", key: `payouts-${Date.now()}` };
  state.modal = modal;
  renderModal();
  try {
    const first = await startPayoutOnboarding();
    if (state.modal !== modal) return;
    let reused = false;
    mountOnboarding(document.querySelector("#connect-onboarding"), {
      publishableKey: first.publishable_key,
      fetchClientSecret: async () => {
        if (!reused) { reused = true; return first.client_secret; }
        return (await startPayoutOnboarding()).client_secret;
      },
      onExit: async () => {
        const status = await refreshPayoutStatus().catch(() => null);
        if (state.modal === modal) closeModal();
        await loadData({ quiet: true });
        showToast(status?.transfers_active ? "Payouts are on. You can help with paid requests." : "Thanks! Stripe is reviewing your details.");
      }
    });
  } catch (error) {
    showToast(errorMessage(error), "error");
    if (state.modal === modal) closeModal();
  }
}

function groupToolsModal() {
  return `<p class="eyebrow">YOUR PEOPLE</p><h2 id="modal-title">Create or join a group</h2><div class="tool-columns"><form id="create-group-form" class="form-stack"><h3>Create a friend group</h3><label><span>Group name</span><input name="name" required minlength="1" maxlength="60" placeholder="Northside Crew" /></label><button class="primary-button" type="submit">Create group</button></form><form id="join-group-form" class="form-stack"><h3>Join with an invite</h3><label><span>8-character code</span><input name="code" required minlength="8" maxlength="8" autocomplete="off" autocapitalize="characters" placeholder="ABC12345" /></label><button class="secondary-button" type="submit">Join group</button></form></div>`;
}

function confirmDeleteModal() {
  return `<p class="eyebrow danger-text">PERMANENT ACTION</p><h2 id="modal-title">Delete your Dart account?</h2><p>This deletes your profile, requests, runs, and memberships. Active deliveries are safely released or completed by the backend. This cannot be undone.</p><form id="delete-account-form" class="form-stack"><label><span>Type DELETE to confirm</span><input name="confirmation" required pattern="DELETE" autocomplete="off" /></label><button class="danger-button" type="submit">Permanently delete account</button></form>`;
}

function passwordModal() {
  return `<p class="eyebrow">SECURE YOUR ACCOUNT</p><h2 id="modal-title">Choose a new password</h2><p>Use at least 6 characters. A longer, unique password is safer.</p><form id="password-form" class="form-stack"><label><span>New password</span><input name="password" type="password" minlength="6" autocomplete="new-password" required /></label><label><span>Confirm password</span><input name="confirmation" type="password" minlength="6" autocomplete="new-password" required /></label><button class="primary-button" type="submit">Update password</button></form>`;
}

function legalModal(document) {
  if (document === "privacy") return `<p class="eyebrow">PRIVACY NOTICE</p><h2 id="modal-title">Your data in Dart</h2><div class="legal-document"><p>Dart uses your email for account access and stores your display name, campus, optional home building, groups, requests, runs, shopping-list items, and messages so the service can work.</p><h3>Who can see what</h3><p>Supabase row-level security restricts data by account, group membership, campus audience, and request participation. Contact details are not stored in public profiles.</p><h3>Location</h3><p>If you choose “Use my location,” the browser supplies coordinates to sort nearby requests. Dart does not store that browser location from this web app.</p><h3>Account control</h3><p>You can sign out, change your name and home building, or permanently delete your account from Profile. Account deletion removes associated records according to the backend’s retention rules.</p><p class="modal-note">For a public commercial launch, replace this product notice with counsel-reviewed company contact, jurisdiction, retention, subprocessors, and consumer-rights language.</p></div>`;
  return `<p class="eyebrow">TERMS OF USE</p><h2 id="modal-title">Use Dart responsibly</h2><div class="legal-document"><p>Dart helps people coordinate errands. Users are responsible for accurate requests, lawful items, safe public handoffs, and respectful communication.</p><h3>Safety</h3><p>Do not request controlled, illegal, dangerous, age-restricted, or unsafe items. Do not share sensitive personal information in group messages or public request details.</p><h3>Availability</h3><p>Requests and runs may change or be cancelled. Dart does not guarantee that another person will accept or complete a task.</p><p class="modal-note">These launch terms are product copy, not a substitute for counsel-reviewed commercial terms.</p></div>`;
}

/* ---------- Data and actions ---------- */

async function loadData({ quiet = false } = {}) {
  if (!state.session?.user) return;
  const version = ++state.loadVersion;
  if (quiet) state.refreshing = true;
  else state.loading = true;
  render();
  try {
    const data = await loadAppData(state.session.user.id, state.coords);
    if (version !== state.loadVersion) return;
    state.data = data;
  } catch (error) {
    showToast(errorMessage(error), "error");
  } finally {
    if (version === state.loadVersion) {
      state.loading = false;
      state.refreshing = false;
      if (state.data && !state.modal && readStorage("grab:onboarded:v1") !== "true") {
        state.onboardingStep = 0;
        state.modal = { type: "onboarding" };
      }
      render();
      updateBadge();
      if (state.data && state.pendingLink) {
        const link = state.pendingLink;
        state.pendingLink = null;
        openLink(link);
      }
    }
  }
}

async function work(action, success, options = {}) {
  if (state.working) return false;
  state.working = true;
  render();
  try {
    await action();
    if (options.close !== false) state.modal = null;
    await loadData({ quiet: true });
    if (success) showToast(success);
  } catch (error) {
    showToast(errorMessage(error), "error");
    state.working = false;
    render();
    return false;
  }
  state.working = false;
  render();
  return true;
}

function goTo(tab) {
  state.tab = tab;
  state.groupId = null;
  state.modal = null;
  setUrlTab(tab);
  track("page_viewed", { tab });
  render();
  window.scrollTo({ top: 0, behavior: "smooth" });
}

function openSearch() {
  state.searchQuery = "";
  state.modal = { type: "search" };
  renderModal();
  document.querySelector("#global-search")?.focus();
}

function closeModal() {
  state.modal = null;
  state.requestMessages = [];
  renderModal();
}

function setDraftField(field, raw) {
  const draft = state.draft;
  if (field === "when") {
    draft.when = raw;
    if (raw === "custom" && !draft.customWhen) draft.customWhen = localInputValue(new Date(Date.now() + 60 * 60000));
  }
  else draft[field] = raw || null;
  // Picking a time keeps the picker open so the custom field can be filled in.
  state.picker = field === "when" && raw === "custom" ? "when" : null;
  if (field === "destinationId" && draft.intro.includes("Where should")) draft.intro = "Perfect. Here’s your request. Tap anything to change it.";
}

async function postDraft() {
  const draft = state.draft;
  const title = draft.title.trim();
  if (title.length < 2) {
    state.picker = "title";
    render();
    showToast("Say what you need in a couple of words", "error");
    return;
  }
  if (!draft.destinationId) {
    state.picker = "destinationId";
    render();
    showToast("Choose where it should be dropped off", "error");
    return;
  }
  const deliverBy = resolveWhen(draft);
  if (!deliverBy || Number.isNaN(deliverBy.getTime()) || deliverBy.getTime() < Date.now() + 29 * 60000) {
    state.picker = "when";
    render();
    showToast("Pick a time at least 30 minutes from now", "error");
    return;
  }
  const budgetCents = parseCents(draft.budget);
  if (paymentsOn() && (!budgetCents || budgetCents < 100 || budgetCents > state.data.payments.max_budget_cents)) {
    state.picker = "budget";
    render();
    showToast(`Set an item budget between $1 and ${formatCents(state.data.payments.max_budget_cents)}`, "error");
    return;
  }
  const pickup = state.data.places.find(place => place.id === draft.pickupId);
  const destination = state.data.places.find(place => place.id === draft.destinationId);
  const payload = {
    group_id: draft.groupId || null,
    title,
    details: draft.details.trim(),
    pickup_place_id: pickup?.id ?? null,
    pickup_label: pickup?.name ?? "Any store",
    destination_place_id: destination.id,
    destination_label: destination.name,
    deliver_by: deliverBy.toISOString(),
    reward_cents: 0,
    merchandise_budget_cents: null
  };
  const submit = async paymentIntentId => {
    await createRequest(paymentIntentId ? { ...payload, merchandise_budget_cents: budgetCents, payment_intent_id: paymentIntentId } : payload);
    writeStorage(PREFS_KEY, JSON.stringify({ destinationId: draft.destinationId, groupId: payload.group_id }));
    state.draft = null;
    state.picker = null;
    track("request_created", { audience: payload.group_id ? "group" : "campus", flow: "ask", paid: Boolean(paymentIntentId) });
  };
  const success = "Posted! We’ll let you know when someone’s on it.";
  if (paymentsOn()) await openPayment(budgetCents, submit, success);
  else await work(() => submit(null), success);
}

document.addEventListener("click", async event => {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const { action, id, tab, mode, status, sort, view, field, value, document: documentName } = button.dataset;

  if (action === "nav") {
    goTo(tab);
  } else if (action === "ask" || action === "ask-from-search") {
    if (action === "ask-from-search" && state.searchQuery.trim()) startDraft(state.searchQuery.trim());
    state.focusComposer = true;
    goTo("home");
  } else if (action === "composer-prefill") {
    state.draftText = value;
    render();
    const input = document.querySelector("#composer-input");
    input?.focus();
    input?.setSelectionRange(value.length, value.length);
  } else if (action === "draft-again") {
    const source = state.data.requests.find(item => item.id === id);
    if (!source) return;
    startDraft(source.title, {
      title: source.title,
      details: source.details || "",
      pickupId: source.pickup_place_id,
      destinationId: source.destination_place_id,
      groupId: source.group_id,
      budget: source.merchandise_budget_cents ? (source.merchandise_budget_cents / 100).toFixed(2) : ""
    });
    track("request_repeated");
    if (state.tab !== "home" || state.modal) goTo("home");
    else render();
  } else if (action === "draft-picker") {
    state.picker = state.picker === field ? null : field;
    render();
    if (state.picker === "title") document.querySelector("#draft-title")?.focus();
    if (state.picker === "details") document.querySelector("#draft-details")?.focus();
  } else if (action === "draft-set") {
    setDraftField(field, value);
    render();
  } else if (action === "draft-reset") {
    state.draft = null;
    state.picker = null;
    state.focusComposer = true;
    render();
  } else if (action === "draft-post") {
    await postDraft();
  } else if (action === "activity-view") {
    state.activityView = view;
    if (state.tab !== "activity") goTo("activity");
    else render();
  } else if (action === "auth-mode") {
    state.authMode = mode;
    render();
  } else if (action === "refresh") {
    await loadData({ quiet: true });
  } else if (action === "search") {
    openSearch();
  } else if (action === "updates") {
    state.modal = { type: "updates" };
    renderModal();
  } else if (action === "feedback") {
    state.modal = { type: "feedback" };
    renderModal();
  } else if (action === "earn-sort") {
    state.earnSort = sort;
    track("earn_sorted", { sort });
    render();
  } else if (action === "search-group") {
    state.tab = "groups";
    state.groupId = id;
    state.modal = null;
    setUrlTab("groups");
    track("search_result_opened", { type: "group" });
    render();
  } else if (action === "onboarding-next") {
    state.onboardingStep = Math.min(2, state.onboardingStep + 1);
    renderModal();
  } else if (action === "onboarding-back") {
    state.onboardingStep = Math.max(0, state.onboardingStep - 1);
    renderModal();
  } else if (action === "onboarding-skip" || action === "onboarding-complete") {
    writeStorage("grab:onboarded:v1", "true");
    state.modal = null;
    track(action === "onboarding-complete" ? "onboarding_completed" : "onboarding_skipped");
    renderModal();
    if (state.tab === "home" && !state.draft) document.querySelector("#composer-input")?.focus();
  } else if (action === "replay-intro") {
    state.onboardingStep = 0;
    state.modal = { type: "onboarding" };
    renderModal();
  } else if (action === "push-enable") {
    // enablePush() must run before any other await so Safari still treats this as the tap.
    if (pushStatus() === "needs-install") { state.modal = { type: "install" }; renderModal(); return; }
    let result;
    try { result = await enablePush(); } catch (error) { showToast(errorMessage(error), "error"); }
    await refreshPush();
    render();
    if (result === "granted") showToast("Notifications are on for this device");
    else if (result === "denied") showToast("Notifications are blocked. Allow them for Dart in Settings, then try again.", "error");
  } else if (action === "push-disable") {
    await disablePush();
    await refreshPush();
    render();
    showToast("Notifications are off for this device");
  } else if (action === "signout") {
    await work(async () => { await disablePush({ remember: false }); await signOut(); }, "Signed out", { close: false });
  } else if (action === "install") {
    if (state.installPrompt) await triggerInstall();
    else { state.modal = { type: "install" }; render(); }
  } else if (action === "dismiss-install") {
    writeStorage("grab:install-tip:dismissed", "true");
    render();
  } else if (action === "trigger-install") {
    await triggerInstall();
  } else if (action === "close-modal") {
    closeModal();
  } else if (action === "open-run-form") {
    state.modal = { type: "run-form" };
    renderModal();
  } else if (action === "open-run") {
    state.modal = { type: "run", id };
    renderModal();
  } else if (action === "open-request") {
    await openRequest(id);
  } else if (action === "group-tools") {
    state.modal = { type: "group-tools" };
    renderModal();
  } else if (action === "open-group") {
    state.groupId = id;
    render();
  } else if (action === "back-groups") {
    state.groupId = null;
    render();
  } else if (action === "join-building") {
    await work(() => joinBuilding(id), "Building joined");
  } else if (action === "leave-group") {
    if (confirm("Leave this group?")) {
      state.groupId = null;
      await work(() => leaveGroup(id), "You left the group");
    }
  } else if (action === "toggle-list") {
    await work(() => setListItem(id, button.dataset.picked !== "true"), null, { close: false });
  } else if (action === "delete-list") {
    await work(() => deleteListItem(id), "Item removed", { close: false });
  } else if (action === "accept-request") {
    const request = allRequests().find(item => item.id === id);
    if (request && isPaid(request) && !state.data.payout?.transfers_active) {
      const status = await refreshPayoutStatus().catch(() => null);
      if (!status?.transfers_active) {
        showToast("Set up payouts to help with paid requests");
        await openPayouts();
        return;
      }
    }
    await work(() => acceptRequest(id), "Request accepted");
  } else if (action === "payouts") {
    await openPayouts();
  } else if (action === "payout-dashboard") {
    // Open the window during the tap so it isn't treated as a popup.
    const tab = window.open("", "_blank");
    try {
      const { url } = await openPayoutDashboard();
      if (tab) tab.location = url;
      else location.href = url;
    } catch (error) {
      tab?.close();
      showToast(errorMessage(error), "error");
    }
  } else if (action === "advance-request") {
    await work(() => advanceRequest(id, status), status === "completed" ? "Marked as received. Thanks!" : `Request marked ${titleCase(status)}`);
  } else if (action === "release-request") {
    await work(() => releaseRequest(id), "Request released");
  } else if (action === "cancel-request") {
    if (confirm("Cancel this request?")) await work(() => cancelRequest(id), "Request cancelled");
  } else if (action === "run-status") {
    if (status !== "cancelled" || confirm("Cancel this run?")) await work(() => updateRunStatus(id, status), `Run marked ${titleCase(status)}`);
  } else if (action === "locate") {
    locateUser();
  } else if (action === "delete-account") {
    state.modal = { type: "delete-account" };
    renderModal();
  } else if (action === "password-reset") {
    await work(() => sendPasswordReset(state.session.user.email), "Password reset email sent", { close: false });
  } else if (action === "legal") {
    state.modal = { type: "legal", document: documentName };
    renderModal();
  }
});

document.addEventListener("input", event => {
  const target = event.target;
  if (target.id === "global-search") {
    state.searchQuery = target.value;
    const results = document.querySelector("#search-results");
    if (results) results.innerHTML = searchResultsMarkup();
  } else if (target.id === "composer-input") {
    state.draftText = target.value;
  } else if (!state.draft) {
    return;
  } else if (target.id === "draft-title") {
    state.draft.title = target.value;
  } else if (target.id === "draft-details") {
    state.draft.details = target.value;
  } else if (target.id === "draft-budget") {
    state.draft.budget = target.value;
  } else if (target.id === "draft-when-custom") {
    state.draft.customWhen = target.value;
    refreshDraftLabels();
  } else if (target.id === "picker-filter") {
    const query = target.value.trim().toLowerCase();
    target.closest(".picker").querySelectorAll(".choice").forEach(chip => {
      chip.hidden = Boolean(query) && !chip.classList.contains("active") && !chip.textContent.toLowerCase().includes(query);
    });
  }
});

document.addEventListener("keydown", event => {
  if (event.key !== "Enter" || event.shiftKey) return;
  if (event.target.id === "draft-title" || event.target.id === "draft-budget") {
    event.preventDefault();
    state.picker = null;
    render();
  } else if (event.target.id === "picker-filter") {
    event.preventDefault();
    event.target.closest(".picker").querySelector(".choice:not([hidden])")?.click();
  }
});

document.addEventListener("submit", async event => {
  event.preventDefault();
  const form = event.target;
  const values = Object.fromEntries(new FormData(form));
  let ok = false;

  if (form.id === "composer-form") {
    const title = values.title.trim();
    if (title.length < 2) return;
    startDraft(title);
    track("request_started", { flow: "ask" });
    render();
    return;
  } else if (form.id === "auth-form") {
    state.working = true;
    render();
    try {
      if (state.authMode === "reset") {
        await sendPasswordReset(values.email.trim().toLowerCase());
        state.authMode = "signin";
        showToast("Check your email for the recovery link");
      } else if (state.authMode === "signup") {
        if (values.password !== values.confirmation) throw new Error("The passwords don’t match.");
        const email = values.email.trim().toLowerCase();
        const password = values.password;
        const signup = await signUp(email, password, values.displayName.trim());
        if (signup.session) {
          showToast("Account created");
        } else if (signup.user?.identities?.length === 0) {
          try {
            await signIn(email, password);
            showToast("Signed in to your existing account");
          } catch {
            state.authMode = "signin";
            throw new Error("That email already has a Dart account. Sign in with its original password or choose Forgot password.");
          }
        } else {
          state.authMode = "signin";
          showToast("Check your email to confirm your account, then sign in");
        }
      } else {
        await signIn(values.email.trim().toLowerCase(), values.password);
      }
    } catch (error) {
      showToast(errorMessage(error), "error");
    } finally {
      state.working = false;
      render();
    }
    return;
  } else if (form.id === "run-form") {
    const store = state.data.places.find(place => place.id === values.storePlaceId);
    const destination = state.data.places.find(place => place.id === values.destinationPlaceId);
    const groupId = values.audience.startsWith("group:") ? values.audience.slice(6) : null;
    const group = state.data.groups.find(item => item.id === groupId);
    const audience = group ? group.kind === "building" ? "building" : "friends" : "campus";
    ok = await work(() => createRun({
      group_id: groupId,
      audience,
      store_place_id: store.id,
      store_label: store.name,
      destination_place_id: destination.id,
      destination_label: destination.name,
      note: values.note.trim() || null,
      closes_at: new Date(Date.now() + Number(values.minutes) * 60000).toISOString(),
      fee_cents: 0,
      max_added_minutes: Number(values.detour),
      capacity: Number(values.capacity)
    }), "Run announced");
  } else if (form.id === "request-from-run-form") {
    const success = "Added to the run. We’ll keep you posted.";
    if (paymentsOn()) {
      const budgetCents = parseCents(values.budget);
      if (!budgetCents || budgetCents < 100 || budgetCents > state.data.payments.max_budget_cents) {
        showToast(`Set an item budget between $1 and ${formatCents(state.data.payments.max_budget_cents)}`, "error");
        return;
      }
      await openPayment(budgetCents, paymentIntentId => requestFromRun(values.runId, values.title.trim(), values.details.trim(), budgetCents, paymentIntentId), success);
      return;
    }
    ok = await work(() => requestFromRun(values.runId, values.title.trim(), values.details.trim(), null), success);
  } else if (form.id === "pay-form") {
    const modal = state.modal;
    if (modal?.type !== "pay" || !modal.stripe) return;
    const button = form.querySelector("button[type=submit]");
    button.disabled = true;
    ok = await work(async () => {
      // If posting failed after the card was held, retrying reuses the same hold.
      if (!modal.authorized) {
        await authorizeCard(modal.stripe);
        const { status } = await confirmPayment(modal.hold.payment_intent_id);
        if (status !== "authorized") throw new Error("Your card wasn’t approved. Try another payment method.");
        modal.authorized = true;
      }
      await modal.finish(modal.hold.payment_intent_id);
    }, modal.success);
    if (!ok && state.modal === modal) button.disabled = false;
    return;
  } else if (form.id === "deliver-form") {
    const cents = parseCents(values.receipt);
    if (cents === null) return;
    ok = await work(async () => {
      await setItemCost(values.requestId, cents);
      await advanceRequest(values.requestId, "delivered");
    }, "Marked delivered. You’ll be paid once they confirm.");
  } else if (form.id === "create-group-form") {
    ok = await work(() => createGroup(values.name.trim()), "Group created");
  } else if (form.id === "join-group-form") {
    ok = await work(() => joinGroup(values.code.trim().toUpperCase()), "Group joined");
  } else if (form.id === "list-item-form") {
    const run = state.data.runs.find(item => item.group_id === values.groupId);
    ok = await work(() => addListItem(values.groupId, run?.id, values.body.trim()), "Item added", { close: false });
  } else if (form.id === "group-message-form") {
    ok = await work(() => sendGroupMessage(values.groupId, values.body.trim()), null, { close: false });
  } else if (form.id === "request-message-form") {
    ok = await work(() => sendRequestMessage(values.requestId, values.body.trim()), null, { close: false });
    if (ok) {
      state.modal = { type: "request", id: values.requestId };
      state.requestMessages = await loadRequestMessages(values.requestId);
      preserving(renderModal);
    }
  } else if (form.id === "profile-form") {
    ok = await work(() => updateDisplayName(state.session.user.id, values.displayName.trim()), "Name updated", { close: false });
  } else if (form.id === "home-form") {
    ok = await work(() => setHomePlace(values.placeId || null), "Home updated", { close: false });
  } else if (form.id === "delete-account-form") {
    if (values.confirmation !== "DELETE") return;
    ok = await work(async () => { await deleteAccount(); await disablePush({ remember: false }); await supabase.auth.signOut({ scope: "local" }); }, "Account deleted");
  } else if (form.id === "password-form") {
    if (values.password !== values.confirmation) { showToast("The passwords don’t match", "error"); return; }
    ok = await work(() => updatePassword(values.password), "Password updated");
    state.recovery = false;
  } else if (form.id === "feedback-form") {
    const category = values.category;
    const message = values.message.trim();
    ok = await work(() => submitFeedback({ category, message, contactOk: values.contactOk === "on", page: state.tab }), "Thanks—your feedback was sent");
    if (ok) track("feedback_submitted", { category, page: state.tab });
  }

  // Sent text was carried across re-renders; clear it now that it's saved.
  if (ok) {
    const sent = document.getElementById(form.id);
    sent?.reset();
    if (sent?.classList.contains("inline-form")) sent.querySelector("input:not([type=hidden])")?.focus();
  }
});

async function triggerInstall() {
  if (!state.installPrompt) {
    state.modal = { type: "install" };
    renderModal();
    return;
  }
  state.installPrompt.prompt();
  await state.installPrompt.userChoice;
  state.installPrompt = null;
  state.modal = null;
  render();
}

function locateUser() {
  if (!navigator.geolocation) {
    showToast("Location isn’t available in this browser", "error");
    return;
  }
  navigator.geolocation.getCurrentPosition(async position => {
    state.coords = position.coords;
    await loadData({ quiet: true });
    showToast("Nearby tasks are sorted using your location");
  }, () => showToast("Location permission wasn’t granted", "error"), { enableHighAccuracy: false, timeout: 10000, maximumAge: 300000 });
}

window.addEventListener("beforeinstallprompt", event => {
  event.preventDefault();
  state.installPrompt = event;
  render();
});
window.addEventListener("appinstalled", () => { state.installPrompt = null; render(); showToast("Dart installed"); });
window.addEventListener("online", () => { state.online = true; render(); if (state.session) loadData({ quiet: true }); });
window.addEventListener("offline", () => { state.online = false; render(); });
window.addEventListener("keydown", event => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k" && state.session) {
    event.preventDefault();
    openSearch();
  } else if (event.key === "Escape" && state.modal) {
    closeModal();
  } else if (event.key === "Escape" && state.picker) {
    state.picker = null;
    render();
  }
});
modalRoot.addEventListener("click", event => { if (event.target.classList.contains("modal-backdrop")) closeModal(); });

async function initialize() {
  if ("serviceWorker" in navigator && location.protocol === "https:") {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
    // A notification was tapped while Grab was already open.
    navigator.serviceWorker.addEventListener("message", event => {
      if (event.data?.type !== "open" || !event.data.url) return;
      if (state.data) openLink(event.data.url);
      else state.pendingLink = event.data.url;
    });
  }
  const { data } = await supabase.auth.getSession();
  state.session = data.session;
  state.loading = false;

  supabase.auth.onAuthStateChange((event, session) => {
    const wasSignedIn = Boolean(state.session);
    state.session = session;
    if (event === "PASSWORD_RECOVERY") {
      state.recovery = true;
      state.modal = { type: "password" };
    }
    if (session && !wasSignedIn) {
      syncPush().then(refreshPush).then(render).catch(() => {});
      state.unsubscribeRealtime?.();
      state.unsubscribeRealtime = subscribeToChanges(() => loadData({ quiet: true }));
      loadData();
    } else if (!session) {
      state.data = null;
      state.draft = null;
      state.picker = null;
      state.unsubscribeRealtime?.();
      state.unsubscribeRealtime = null;
      render();
    } else {
      render();
    }
  });

  if (state.session) {
    syncPush().then(refreshPush).then(render).catch(() => {});
    state.unsubscribeRealtime = subscribeToChanges(() => loadData({ quiet: true }));
    await loadData();
  } else {
    render();
  }
}

initialize().catch(error => {
  state.loading = false;
  app.innerHTML = `<main class="center-state error-state"><img src="./icons/icon-192.png" alt="" /><h1>Dart couldn’t start</h1><p>${escapeHTML(errorMessage(error))}</p><a class="primary-button retry-link" href="./">Try again</a></main>`;
});
