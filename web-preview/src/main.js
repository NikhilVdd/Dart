import "./styles.css";
import {
  acceptRequest,
  addListItem,
  advanceRequest,
  cancelRequest,
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
  releaseRequest,
  requestFromRun,
  sendGroupMessage,
  sendPasswordReset,
  sendRequestMessage,
  submitFeedback,
  setHomePlace,
  setListItem,
  signIn,
  signOut,
  signUp,
  subscribeToChanges,
  supabase,
  trackProductEvent,
  updateDisplayName,
  updatePassword,
  updateRunStatus
} from "./api.js";

const app = document.querySelector("#app");
const modalRoot = document.querySelector("#modal-root");
const toast = document.querySelector("#toast");

const initialTab = new URLSearchParams(location.search).get("tab");
const validTabs = ["home", "groups", "request", "earn", "activity", "profile"];
const state = {
  session: null,
  data: null,
  loading: true,
  refreshing: false,
  working: false,
  authMode: "signin",
  tab: validTabs.includes(initialTab) ? initialTab : "home",
  groupId: null,
  modal: null,
  requestMessages: [],
  coords: null,
  online: navigator.onLine,
  installPrompt: null,
  recovery: false,
  searchQuery: "",
  earnSort: "soonest",
  onboardingStep: 0,
  unsubscribeRealtime: null,
  loadVersion: 0
};

const icons = {
  home: '<path d="M3 11.5 12 4l9 7.5"/><path d="M5.5 10.5V20h13v-9.5"/><path d="M9.5 20v-6h5v6"/>',
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
  arrow: '<path d="M5 12h14M14 7l5 5-5 5"/>'
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

function money(cents = 0) {
  return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(Number(cents) / 100);
}

function shortDate(value) {
  if (!value) return "Not set";
  return new Intl.DateTimeFormat("en-US", { weekday: "short", hour: "numeric", minute: "2-digit" }).format(new Date(value));
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

function errorMessage(error) {
  const message = error?.message || "Something went wrong. Please try again.";
  const replacements = [
    [/invalid login credentials/i, "Check your email and password, then try again."],
    [/user already registered/i, "An account already exists for this email. Sign in instead."],
    [/email address not authorized/i, "Grab’s recovery email service is not connected for this address yet. Contact the app owner for a password reset."],
    [/email rate limit exceeded/i, "Too many recovery emails were requested. Wait a little, then try again."],
    [/password should be at least/i, "Use a password with at least 6 characters."],
    [/failed to fetch/i, "Grab couldn’t reach the backend. Check your connection and try again."],
    [/networkerror/i, "Grab couldn’t reach the backend. Check your connection and try again."]
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

function setUrlTab(tab) {
  const url = new URL(location.href);
  url.searchParams.set("tab", tab);
  history.replaceState({}, "", url);
}

function isInstalled() {
  return matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;
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
  return `<section class="empty-card"><span class="empty-icon">${iconMarkup(iconName)}</span><h3>${escapeHTML(title)}</h3><p>${escapeHTML(body)}</p>${action}</section>`;
}

function iconMarkup(name) {
  return icons[name] ? icon(name) : icon("spark");
}

function pageHeader(eyebrow, title, subtitle, action = "") {
  return `<header class="page-header"><div><p class="eyebrow">${escapeHTML(eyebrow)}</p><h1>${escapeHTML(title)}</h1><p>${escapeHTML(subtitle)}</p></div>${action}</header>`;
}

function skeleton() {
  return `<main class="skeleton-shell" aria-label="Loading Grab"><aside class="skeleton-rail"></aside><section class="skeleton-page"><div class="skeleton-line short"></div><div class="skeleton-line title"></div><div class="skeleton-line"></div><div class="skeleton-grid"><div></div><div></div></div><div class="skeleton-row"></div><div class="skeleton-row"></div></section></main>`;
}

function render() {
  document.body.classList.toggle("offline", !state.online);
  if (state.loading) {
    app.innerHTML = skeleton();
    return;
  }
  if (!state.session) {
    renderAuth();
    return;
  }
  renderShell();
}

function renderAuth() {
  const creating = state.authMode === "signup";
  const resetting = state.authMode === "reset";
  app.innerHTML = `
    <main class="auth-layout" id="main">
      <section class="auth-story" aria-label="About Grab">
        <div class="brand-lockup"><img src="./icons/icon-192.png" alt="" /><strong>Grab</strong></div>
        <div class="story-copy">
          <p class="eyebrow light">EVERYDAY ERRANDS</p>
          <h1>Already on<br />the way.</h1>
          <p>Ask trusted people nearby for what you need—or earn by helping along a route you’re already taking.</p>
        </div>
        <div class="trust-row"><span>Private groups</span><span>Live updates</span><span>Secure accounts</span></div>
      </section>
      <section class="auth-panel">
        <div class="auth-card">
          <img class="auth-mark" src="./icons/icon-192.png" alt="Grab" />
          <p class="eyebrow">${resetting ? "ACCOUNT RECOVERY" : creating ? "NEW ACCOUNT" : "WELCOME BACK"}</p>
          <h2>${resetting ? "Reset your password" : creating ? "Create your Grab account" : "Sign in to Grab"}</h2>
          <p class="auth-subtitle">${resetting ? "We’ll email you a secure recovery link." : creating ? "Use any email address—no Berkeley address or verification link is required." : "Use your email and password to continue."}</p>
          <form id="auth-form" class="form-stack">
            ${creating ? `<label><span>Your name</span><input name="displayName" autocomplete="name" minlength="2" maxlength="60" required placeholder="Nikhil V" /></label>` : ""}
            <label><span>Email</span><input name="email" type="email" inputmode="email" autocomplete="email" required placeholder="you@example.com" /></label>
            ${resetting ? "" : `<label><span>Password</span><input name="password" type="password" autocomplete="${creating ? "new-password" : "current-password"}" minlength="6" required placeholder="At least 6 characters" /></label>`}
            ${creating ? `<label><span>Confirm password</span><input name="confirmation" type="password" autocomplete="new-password" minlength="6" required placeholder="Repeat your password" /></label>` : ""}
            <button class="primary-button" type="submit" ${state.working ? "disabled" : ""}>${state.working ? '<span class="button-spinner"></span>' : resetting ? "Send recovery link" : creating ? "Create account" : "Sign in"}</button>
          </form>
          <div class="auth-actions">
            ${resetting ? `<button data-action="auth-mode" data-mode="signin">Back to sign in</button>` : `<button data-action="auth-mode" data-mode="${creating ? "signin" : "signup"}">${creating ? "Already have an account? Sign in" : "New to Grab? Create an account"}</button>`}
            ${!creating && !resetting ? `<button data-action="auth-mode" data-mode="reset">Forgot password?</button>` : ""}
          </div>
          <p class="legal-copy">By continuing, you agree to the <button data-action="legal" data-document="terms">Terms</button> and acknowledge the <button data-action="legal" data-document="privacy">Privacy Notice</button>.</p>
        </div>
      </section>
    </main>`;
}

function renderShell() {
  const profile = state.data?.profile;
  const tabs = ["home", "groups", "request", "earn", "activity", "profile"];
  app.innerHTML = `
    <div class="app-layout">
      <aside class="side-nav">
        <a class="app-brand" href="./" aria-label="Grab home"><span class="brand-mark">G</span><span>Grab</span><em>Beta</em></a>
        <nav aria-label="Main navigation">${tabs.map(tab => navButton(tab)).join("")}</nav>
        <button class="feedback-rail" data-action="feedback">${icon("spark")}<span>Share feedback</span></button>
        <button class="side-profile" data-action="nav" data-tab="profile">${avatar(profile)}<div><strong>${escapeHTML(profile?.display_name || "Grab member")}</strong><span>${escapeHTML(profile?.campus?.name || "Grab community")}</span></div>${icon("arrow")}</button>
      </aside>
      <div class="app-content">
        <div class="network-banner" ${state.online ? "hidden" : ""}>You’re offline. Changes will be available when you reconnect.</div>
        <header class="top-bar">
          <a class="mobile-brand" href="./"><span class="brand-mark">G</span><strong>Grab</strong></a>
          <div class="top-actions">
            <button class="search-trigger" data-action="search" aria-label="Search Grab">${icon("search")}<span>Search Grab</span><kbd>⌘K</kbd></button>
            ${!isInstalled() ? `<button class="install-button" data-action="install">Install app</button>` : ""}
            <button class="icon-button" data-action="updates" aria-label="View updates">${icon("bell")}</button>
            <button class="icon-button ${state.refreshing ? "is-spinning" : ""}" data-action="refresh" aria-label="Refresh live data" ${state.refreshing ? "disabled" : ""}>${icon("route")}</button>
            <button class="profile-button" data-action="nav" data-tab="profile" aria-label="Open profile">${escapeHTML(profile?.initials || "?")}</button>
          </div>
        </header>
        <main id="main" class="main-content">${renderPage()}</main>
      </div>
      <nav class="bottom-nav" aria-label="Main navigation">${tabs.map(tab => navButton(tab)).join("")}</nav>
    </div>`;
  renderModal();
}

function navButton(tab) {
  return `<button class="nav-item ${state.tab === tab ? "active" : ""}" data-action="nav" data-tab="${tab}" aria-current="${state.tab === tab ? "page" : "false"}"><span>${icon(tab)}</span><b>${titleCase(tab)}</b></button>`;
}

function renderPage() {
  if (!state.data) return skeleton();
  if (state.tab === "groups") return renderGroups();
  if (state.tab === "request") return renderRequestForm();
  if (state.tab === "earn") return renderEarn();
  if (state.tab === "activity") return renderActivity();
  if (state.tab === "profile") return renderProfile();
  return renderHome();
}

function renderHome() {
  const { profile, runs, nearby, requests } = state.data;
  const active = requests.filter(item => !["completed", "cancelled", "expired"].includes(item.status));
  const openCount = nearby.length;
  const communityCount = memberGroups().length;
  return `
    <div class="page page-wide">
      <section class="welcome-band">
        <div><p class="eyebrow">GOOD TO SEE YOU</p><h1>Hi, ${escapeHTML((profile.display_name || "there").split(" ")[0])}.</h1><p>What can your community help move today?</p></div>
        <div class="pulse-stats"><span><b>${openCount}</b> open nearby</span><span><b>${runs.length}</b> live runs</span><span><b>${communityCount}</b> communities</span></div>
        <button class="primary-button compact" data-action="nav" data-tab="request">${icon("request")} Make a request</button>
      </section>
      <section class="quick-grid">
        <button class="quick-card request-card" data-action="nav" data-tab="request"><span class="quick-icon">${icon("bag")}</span><span class="category-pill">REQUEST</span><h2>Get something<br />you need.</h2><p>Post it in under a minute. A nearby friend can pick it up.</p><b>Start a request ${icon("arrow")}</b></button>
        <button class="quick-card earn-card" data-action="nav" data-tab="earn"><span class="quick-icon">${icon("route")}</span><span class="category-pill">HELP & EARN</span><h2>Make your route<br />count.</h2><p>Help with a request that already fits where you’re going.</p><b>Browse tasks ${icon("arrow")}</b></button>
      </section>
      <div class="content-grid">
        <section>
          <div class="section-heading"><div><p class="eyebrow">LIVE NOW</p><h2>Store runs</h2></div><button data-action="open-run-form">Announce a run</button></div>
          ${runs.length ? `<div class="card-list">${runs.slice(0, 4).map(renderRunCard).join("")}</div>` : emptyState("bag", "No live runs yet", "Be the first to announce a trip you’re already taking.", `<button class="secondary-button compact" data-action="open-run-form">Announce a run</button>`)}
        </section>
        <aside>
          <div class="section-heading"><div><p class="eyebrow">YOUR DAY</p><h2>Active activity</h2></div><button data-action="nav" data-tab="activity">See all</button></div>
          ${active.length ? `<div class="mini-list">${active.slice(0, 4).map(renderMiniRequest).join("")}</div>` : emptyState("check", "You’re all clear", "Requests you post or accept will appear here.")}
        </aside>
      </div>
      <section>
        <div class="section-heading"><div><p class="eyebrow">NEARBY</p><h2>Tasks that could fit</h2></div><button data-action="locate">${state.coords ? "Using your location" : "Use my location"}</button></div>
        ${nearby.length ? `<div class="task-grid">${nearby.slice(0, 6).map(renderRequestCard).join("")}</div>` : emptyState("route", "Nothing open nearby", "New tasks will appear here as your community posts them.")}
      </section>
    </div>`;
}

function renderRunCard(run) {
  const own = run.runner_id === state.session.user.id;
  return `<button class="run-card" data-action="open-run" data-id="${run.id}">
    <div class="card-top"><span class="category-pill">${escapeHTML(titleCase(run.audience))}</span>${statusPill(run.status)}</div>
    <div class="card-person">${avatar(run.runner)}<div><strong>${escapeHTML(run.runner?.display_name || "Grab runner")}</strong><span>${own ? "Your run" : "is making a run"}</span></div></div>
    <h3>${escapeHTML(run.store_label)}</h3><p>Heading to ${escapeHTML(run.destination_label)}</p>
    <div class="card-meta"><span>Closes ${escapeHTML(relativeTime(run.closes_at))}</span><b>${run.fee_cents ? `${money(run.fee_cents)} / request` : "Free"}</b></div>
  </button>`;
}

function renderRequestCard(request) {
  return `<button class="task-card" data-action="open-request" data-id="${request.id}">
    <div class="card-top">${statusPill(request.status)}<strong class="reward">${money(request.reward_cents)}</strong></div>
    <h3>${escapeHTML(request.title)}</h3><p>${escapeHTML(request.pickup_label)} → ${escapeHTML(request.destination_label)}</p>
    <div class="card-meta"><span>Due ${escapeHTML(shortDate(request.deliver_by))}</span><span>${request.est_minutes ? `+${request.est_minutes} min` : "Open task"}</span></div>
  </button>`;
}

function renderMiniRequest(request) {
  const role = request.requester_id === state.session.user.id ? "Requested" : "Helping";
  return `<button class="mini-row" data-action="open-request" data-id="${request.id}">${avatar(role === "Requested" ? request.helper : request.requester, role[0])}<span><strong>${escapeHTML(request.title)}</strong><small>${role} · ${escapeHTML(titleCase(request.status))}</small></span><b>${money(request.reward_cents)}</b></button>`;
}

function renderGroups() {
  const { groups, members } = state.data;
  const memberIds = new Set(members.filter(item => item.user_id === state.session.user.id).map(item => item.group_id));
  const joined = groups.filter(group => memberIds.has(group.id));
  const discoverable = groups.filter(group => !memberIds.has(group.id) && group.kind === "building");
  if (state.groupId) {
    const group = groups.find(item => item.id === state.groupId);
    if (group) return renderGroupDetail(group, members.filter(item => item.group_id === group.id));
    state.groupId = null;
  }
  return `<div class="page">
    ${pageHeader("PRIVATE SPACES", "Your groups", "Coordinate lists, runs, and conversations with people you trust.", `<button class="primary-button compact" data-action="group-tools">＋ Add group</button>`)}
    ${joined.length ? `<div class="group-grid">${joined.map(group => renderGroupCard(group, members)).join("")}</div>` : emptyState("users", "No groups yet", "Create a friend group or join one with an invite code.", `<button class="secondary-button compact" data-action="group-tools">Create or join</button>`)}
    ${discoverable.length ? `<section class="subsection"><div class="section-heading"><div><p class="eyebrow">YOUR CAMPUS</p><h2>Building communities</h2></div></div><div class="group-grid">${discoverable.map(group => `<article class="group-card"><span class="group-icon">⌂</span><div><span class="category-pill">Building</span><h3>${escapeHTML(group.name)}</h3><p>Join your neighbors for shared errands.</p></div><button class="secondary-button compact" data-action="join-building" data-id="${group.id}">Join building</button></article>`).join("")}</div></section>` : ""}
  </div>`;
}

function renderGroupCard(group, members) {
  const count = members.filter(item => item.group_id === group.id).length;
  const latest = state.data.messages.find(item => item.group_id === group.id);
  return `<button class="group-card clickable" data-action="open-group" data-id="${group.id}"><span class="group-icon">${group.kind === "building" ? "⌂" : "◎"}</span><div><span class="category-pill">${escapeHTML(titleCase(group.kind))}</span><h3>${escapeHTML(group.name)}</h3><p>${latest ? `${escapeHTML(latest.sender?.display_name || "Member")}: ${escapeHTML(latest.body)}` : "No messages yet"}</p><small>${count} ${count === 1 ? "member" : "members"}</small></div><span class="chevron">›</span></button>`;
}

function renderGroupDetail(group, members) {
  const items = state.data.listItems.filter(item => item.group_id === group.id);
  const messages = state.data.messages.filter(item => item.group_id === group.id).slice().reverse();
  const run = state.data.runs.find(item => item.group_id === group.id);
  return `<div class="page">
    <button class="back-button" data-action="back-groups">← All groups</button>
    ${pageHeader(titleCase(group.kind), group.name, `${members.length} ${members.length === 1 ? "member" : "members"} · Invite code ${group.invite_code}`, `<button class="quiet-danger" data-action="leave-group" data-id="${group.id}">Leave</button>`)}
    ${run ? `<section class="run-highlight"><div><span class="category-pill">Active run</span><h2>${escapeHTML(run.store_label)}</h2><p>${escapeHTML(run.runner?.display_name || "A member")} is accepting requests until ${escapeHTML(shortDate(run.closes_at))}.</p></div><button class="primary-button compact" data-action="open-run" data-id="${run.id}">View run</button></section>` : ""}
    <div class="group-detail-grid">
      <section class="panel"><div class="section-heading"><div><p class="eyebrow">SHARED LIST</p><h2>What the group needs</h2></div></div>
        <form id="list-item-form" class="inline-form"><input type="hidden" name="groupId" value="${group.id}" /><input name="body" required maxlength="200" placeholder="Add an item" aria-label="Add a list item" /><button type="submit" aria-label="Add item">＋</button></form>
        <div class="list-rows">${items.length ? items.map(item => `<div class="list-row ${item.status === "picked" ? "done" : ""}"><button data-action="toggle-list" data-id="${item.id}" data-picked="${item.status === "picked"}" aria-label="${item.status === "picked" ? "Mark needed" : "Mark picked"}">${item.status === "picked" ? "✓" : "○"}</button><span>${escapeHTML(item.body)}${item.quantity > 1 ? `<small>Qty ${item.quantity}</small>` : ""}</span><button class="row-delete" data-action="delete-list" data-id="${item.id}" aria-label="Delete ${escapeHTML(item.body)}">×</button></div>`).join("") : `<p class="empty-copy">Nothing on the list yet.</p>`}</div>
      </section>
      <section class="panel chat-panel"><div class="section-heading"><div><p class="eyebrow">GROUP CHAT</p><h2>Conversation</h2></div></div>
        <div class="chat-feed">${messages.length ? messages.map(message => `<div class="chat-message ${message.sender_id === state.session.user.id ? "mine" : ""}"><strong>${escapeHTML(message.sender?.display_name || "Member")}</strong><p>${escapeHTML(message.body)}</p><small>${escapeHTML(shortDate(message.created_at))}</small></div>`).join("") : `<p class="empty-copy">Say hi to your group.</p>`}</div>
        <form id="group-message-form" class="inline-form"><input type="hidden" name="groupId" value="${group.id}" /><input name="body" required maxlength="2000" placeholder="Message the group" aria-label="Message the group" /><button type="submit" aria-label="Send message">↑</button></form>
      </section>
    </div>
  </div>`;
}

function renderRequestForm() {
  const stores = state.data.places.filter(place => ["store", "restaurant", "library", "other"].includes(place.kind));
  const destinations = state.data.places.filter(place => ["residence", "campus", "transit", "library", "other"].includes(place.kind));
  const groups = memberGroups();
  const minDate = new Date(Date.now() + 30 * 60 * 1000);
  minDate.setMinutes(Math.ceil(minDate.getMinutes() / 15) * 15, 0, 0);
  const localMin = new Date(minDate.getTime() - minDate.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  return `<div class="page form-page">
    ${pageHeader("ASK YOUR COMMUNITY", "Make a request", "Clear details, a realistic deadline, and a fair reward help the right person say yes.")}
    <form id="request-form" class="form-card">
      <div class="form-section"><span class="step">1</span><div><h2>What do you need?</h2><p>Keep the title short and put substitutions or quantities in the details.</p></div></div>
      <label class="wide"><span>Request title</span><input name="title" required minlength="2" maxlength="120" placeholder="Oat milk from Berkeley Bowl" /></label>
      <label class="wide"><span>Details</span><textarea name="details" maxlength="1000" rows="3" placeholder="Any brand, unsweetened, one carton"></textarea></label>
      <div class="form-section"><span class="step">2</span><div><h2>Where and when?</h2><p>Precise places improve matching while private handoff details stay between participants.</p></div></div>
      <div class="form-grid">
        <label><span>Pickup</span><select name="pickupPlaceId"><option value="">Any store</option>${placeOptions(stores)}</select></label>
        <label><span>Destination</span><select name="destinationPlaceId" required><option value="">Choose a handoff area</option>${placeOptions(destinations)}</select></label>
        <label><span>Deliver by</span><input name="deliverBy" type="datetime-local" min="${localMin}" value="${localMin}" required /></label>
        <label><span>Audience</span><select name="groupId"><option value="">Campus</option>${groups.map(group => `<option value="${group.id}">${escapeHTML(group.name)}</option>`).join("")}</select></label>
      </div>
      <div class="form-section"><span class="step">3</span><div><h2>Set the amounts</h2><p>The purchase budget and runner reward are separate. Grab is not charging payments yet.</p></div></div>
      <div class="form-grid">
        <label><span>Purchase budget</span><div class="money-input"><b>$</b><input name="budget" type="number" min="0" max="500" step="0.01" placeholder="12.00" /></div></label>
        <label><span>Runner reward</span><div class="money-input"><b>$</b><input name="reward" type="number" min="0" max="200" step="0.01" value="5.00" required /></div></label>
      </div>
      <div class="notice"><b>Payment status</b><p>Amounts are recorded for coordination only. No card is charged and no payout is sent.</p></div>
      <button class="primary-button" type="submit" ${state.working ? "disabled" : ""}>${state.working ? "Posting…" : "Post request"}</button>
    </form>
  </div>`;
}

function renderEarn() {
  const { earnings } = state.data;
  const nearby = sortedEarnRequests();
  return `<div class="page">
    ${pageHeader("HELP ON YOUR ROUTE", "Earn with Grab", "Accept only the requests that fit where you’re already going.", `<button class="secondary-button compact" data-action="open-run-form">Announce a run</button>`)}
    <section class="earnings-strip"><div><span>Recorded earnings</span><strong>${money(earnings.earned_cents)}</strong></div><div><span>Completed</span><strong>${earnings.completed_count}</strong></div><div><span>Active</span><strong>${earnings.active_count}</strong></div><p>Payments are not processed yet.</p></section>
    <div class="section-heading stacked-mobile"><div><p class="eyebrow">OPEN REQUESTS</p><h2>Available tasks</h2></div><button data-action="locate">${state.coords ? "Location on" : "Use my location"}</button></div>
    <div class="filter-row" role="group" aria-label="Sort open requests">
      ${[["soonest", "Soonest"], ["closest", "Closest"], ["reward", "Top reward"]].map(([value, label]) => `<button class="filter-chip ${state.earnSort === value ? "active" : ""}" data-action="earn-sort" data-sort="${value}">${label}</button>`).join("")}
    </div>
    ${nearby.length ? `<div class="task-grid">${nearby.map(renderRequestCard).join("")}</div>` : emptyState("route", "No tasks available", "Try again soon or announce a store run so neighbors can request items.", `<button class="secondary-button compact" data-action="open-run-form">Announce a run</button>`)}
  </div>`;
}

function sortedEarnRequests() {
  const requests = [...state.data.nearby];
  if (state.earnSort === "reward") return requests.sort((a, b) => Number(b.reward_cents) - Number(a.reward_cents));
  if (state.earnSort === "closest") return requests.sort((a, b) => Number(a.est_minutes ?? 9999) - Number(b.est_minutes ?? 9999));
  return requests.sort((a, b) => new Date(a.deliver_by) - new Date(b.deliver_by));
}

function renderActivity() {
  const mine = state.data.requests.filter(item => item.requester_id === state.session.user.id);
  const helping = state.data.requests.filter(item => item.helper_id === state.session.user.id);
  return `<div class="page">
    ${pageHeader("LIVE STATUS", "Activity", "Track every request you posted or agreed to help with.")}
    <div class="activity-columns">
      <section><div class="section-heading"><div><p class="eyebrow">REQUESTING</p><h2>Your requests</h2></div></div>${mine.length ? `<div class="activity-list">${mine.map(renderActivityCard).join("")}</div>` : emptyState("request", "No requests yet", "Post your first request and it will appear here.", `<button class="secondary-button compact" data-action="nav" data-tab="request">Make a request</button>`)}</section>
      <section><div class="section-heading"><div><p class="eyebrow">HELPING</p><h2>Your deliveries</h2></div></div>${helping.length ? `<div class="activity-list">${helping.map(renderActivityCard).join("")}</div>` : emptyState("route", "No accepted tasks", "Browse open requests and pick one that fits your route.", `<button class="secondary-button compact" data-action="nav" data-tab="earn">Browse tasks</button>`)}</section>
    </div>
  </div>`;
}

function renderActivityCard(request) {
  const person = request.requester_id === state.session.user.id ? request.helper : request.requester;
  return `<button class="activity-card" data-action="open-request" data-id="${request.id}"><div>${statusPill(request.status)}<h3>${escapeHTML(request.title)}</h3><p>${escapeHTML(request.pickup_label)} → ${escapeHTML(request.destination_label)}</p></div><div class="activity-side">${avatar(person)}<strong>${money(request.reward_cents)}</strong><span>${escapeHTML(shortDate(request.deliver_by))}</span></div></button>`;
}

function renderProfile() {
  const { profile, places } = state.data;
  const residences = places.filter(place => place.kind === "residence");
  return `<div class="page profile-page">
    ${pageHeader("YOUR ACCOUNT", "Profile & settings", "Manage your identity, home community, installation, and data.")}
    <section class="profile-hero">${avatar(profile)}<div><h2>${escapeHTML(profile.display_name)}</h2><p>${escapeHTML(state.session.user.email)}</p><span>${escapeHTML(profile.campus?.name || "Grab community")}</span></div></section>
    <div class="settings-grid">
      <section class="panel"><p class="eyebrow">IDENTITY</p><h2>Display name</h2><form id="profile-form" class="form-stack"><label><span>Name shown to members</span><input name="displayName" value="${escapeHTML(profile.display_name)}" minlength="1" maxlength="60" required /></label><button class="secondary-button" type="submit">Save name</button></form></section>
      <section class="panel"><p class="eyebrow">HOME</p><h2>Building community</h2><form id="home-form" class="form-stack"><label><span>Home building</span><select name="placeId"><option value="">No home selected</option>${placeOptions(residences, profile.home_place_id)}</select></label><button class="secondary-button" type="submit">Update home</button></form></section>
      <section class="panel"><p class="eyebrow">PHONE</p><h2>Install Grab</h2><p>Use Grab from your Home Screen in a full-screen app window.</p>${isInstalled() ? `<div class="success-note">✓ Grab is installed on this device.</div>` : `<button class="secondary-button" data-action="install">Install on this device</button>`}</section>
      <section class="panel"><p class="eyebrow">ACCOUNT</p><h2>Security & data</h2><div class="settings-actions"><button data-action="feedback">Share feedback</button><button data-action="password-reset">Email password reset</button><button data-action="signout">Sign out</button><button class="danger-link" data-action="delete-account">Delete account</button></div></section>
    </div>
    <footer class="app-footer"><button data-action="legal" data-document="privacy">Privacy</button><button data-action="legal" data-document="terms">Terms</button><span>Grab web v1.0</span></footer>
  </div>`;
}

function placeOptions(places, selected = null) {
  return places.map(place => `<option value="${place.id}" ${place.id === selected ? "selected" : ""}>${escapeHTML(place.name)}${place.detail ? ` · ${escapeHTML(place.detail)}` : ""}</option>`).join("");
}

function memberGroups() {
  const memberIds = new Set(state.data.members.filter(item => item.user_id === state.session.user.id).map(item => item.group_id));
  return state.data.groups.filter(group => memberIds.has(group.id));
}

function renderModal() {
  if (!state.modal) {
    modalRoot.innerHTML = "";
    return;
  }
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
  return "";
}

function searchModal() {
  return `<div class="search-modal"><p class="eyebrow">DISCOVER</p><h2 id="modal-title">Search Grab</h2><label class="search-field">${icon("search")}<span class="sr-only">Search requests, runs, and groups</span><input id="global-search" value="${escapeHTML(state.searchQuery)}" placeholder="Try “Target”, “oat milk”, or a group" autocomplete="off" autofocus /></label><div id="search-results">${searchResultsMarkup()}</div></div>`;
}

function searchResultsMarkup() {
  const query = state.searchQuery.trim().toLowerCase();
  const requests = [...state.data.nearby, ...state.data.requests]
    .filter((item, index, all) => all.findIndex(other => other.id === item.id) === index)
    .filter(item => !query || [item.title, item.details, item.pickup_label, item.destination_label].some(value => String(value || "").toLowerCase().includes(query)))
    .slice(0, 5);
  const runs = state.data.runs
    .filter(item => !query || [item.store_label, item.destination_label, item.runner?.display_name].some(value => String(value || "").toLowerCase().includes(query)))
    .slice(0, 4);
  const groups = state.data.groups
    .filter(item => !query || item.name.toLowerCase().includes(query))
    .slice(0, 4);
  if (query.length === 1) return `<div class="search-empty">Keep typing to search your community.</div>`;
  if (!requests.length && !runs.length && !groups.length) return `<div class="search-empty">${icon("search")}<strong>No matches yet</strong><span>Try a store, item, destination, or group name.</span></div>`;
  return `<div class="search-groups">
    ${runs.length ? `<section><span class="result-label">LIVE RUNS</span>${runs.map(run => `<button class="search-result" data-action="open-run" data-id="${run.id}"><span class="result-icon">${icon("bag")}</span><span><strong>${escapeHTML(run.store_label)}</strong><small>${escapeHTML(run.destination_label)} · ${escapeHTML(run.runner?.display_name || "Grab runner")}</small></span>${icon("arrow")}</button>`).join("")}</section>` : ""}
    ${requests.length ? `<section><span class="result-label">REQUESTS</span>${requests.map(request => `<button class="search-result" data-action="open-request" data-id="${request.id}"><span class="result-icon">${icon("route")}</span><span><strong>${escapeHTML(request.title)}</strong><small>${escapeHTML(request.pickup_label)} → ${escapeHTML(request.destination_label)}</small></span><b>${money(request.reward_cents)}</b></button>`).join("")}</section>` : ""}
    ${groups.length ? `<section><span class="result-label">GROUPS</span>${groups.map(group => `<button class="search-result" data-action="search-group" data-id="${group.id}"><span class="result-icon">${icon("users")}</span><span><strong>${escapeHTML(group.name)}</strong><small>${escapeHTML(titleCase(group.kind))} community</small></span>${icon("arrow")}</button>`).join("")}</section>` : ""}
  </div>`;
}

function updatesModal() {
  const active = state.data.requests.filter(item => !["completed", "cancelled", "expired"].includes(item.status)).slice(0, 6);
  const runs = state.data.runs.slice(0, 3);
  return `<p class="eyebrow">LIVE ACTIVITY</p><h2 id="modal-title">Your updates</h2><p>Everything that needs your attention, in one place.</p><div class="update-list">${active.map(request => `<button class="update-row" data-action="open-request" data-id="${request.id}"><span class="update-dot"></span><span><strong>${escapeHTML(request.title)}</strong><small>${escapeHTML(titleCase(request.status))} · ${escapeHTML(relativeTime(request.updated_at || request.created_at))}</small></span>${statusPill(request.status)}</button>`).join("")}${runs.map(run => `<button class="update-row" data-action="open-run" data-id="${run.id}"><span class="update-dot lime"></span><span><strong>${escapeHTML(run.store_label)}</strong><small>Run closes ${escapeHTML(relativeTime(run.closes_at))}</small></span>${icon("arrow")}</button>`).join("")}${!active.length && !runs.length ? `<div class="search-empty">${icon("check")}<strong>You’re all caught up</strong><span>New request and run activity will appear here.</span></div>` : ""}</div>`;
}

function feedbackModal() {
  return `<p class="eyebrow">FRIENDS & FAMILY</p><h2 id="modal-title">Help shape Grab</h2><p>Tell us what felt confusing, broken, or surprisingly useful.</p><form id="feedback-form" class="form-stack"><label><span>Feedback type</span><select name="category"><option value="idea">Idea</option><option value="bug">Something is broken</option><option value="confusing">Something is confusing</option><option value="love">Something I love</option></select></label><label><span>Your feedback</span><textarea name="message" minlength="3" maxlength="2000" rows="5" required placeholder="What happened, and what did you expect?"></textarea></label><label class="check-row"><input name="contactOk" type="checkbox" /><span>You may follow up with me at my account email.</span></label><button class="primary-button" type="submit" ${state.working ? "disabled" : ""}>Send feedback</button></form>`;
}

function onboardingModal() {
  const slides = [
    { icon: "bag", eyebrow: "WELCOME TO GRAB", title: "One less trip.", body: "Ask someone already heading out to bring back what you need." },
    { icon: "route", eyebrow: "HELP ON YOUR WAY", title: "Make your route count.", body: "Accept a nearby request or announce a store run—only when it fits your plans." },
    { icon: "users", eyebrow: "PEOPLE YOU TRUST", title: "Start with your circle.", body: "Create a private group, join your building, and coordinate handoffs in real time." }
  ];
  const slide = slides[state.onboardingStep] || slides[0];
  return `<div class="onboarding"><span class="onboarding-icon">${icon(slide.icon)}</span><p class="eyebrow">${slide.eyebrow}</p><h2 id="modal-title">${slide.title}</h2><p>${slide.body}</p><div class="onboarding-dots">${slides.map((_, index) => `<i class="${index === state.onboardingStep ? "active" : ""}"></i>`).join("")}</div><div class="onboarding-actions">${state.onboardingStep ? `<button class="secondary-button" data-action="onboarding-back">Back</button>` : `<button class="text-button" data-action="onboarding-skip">Skip</button>`}<button class="primary-button" data-action="${state.onboardingStep === slides.length - 1 ? "onboarding-complete" : "onboarding-next"}">${state.onboardingStep === slides.length - 1 ? "Start using Grab" : "Continue"}</button></div></div>`;
}

function installModal() {
  const ios = /iphone|ipad|ipod/i.test(navigator.userAgent);
  return `<p class="eyebrow">INSTALL GRAB</p><h2 id="modal-title">Put Grab on your Home Screen</h2>${ios ? `<ol class="install-steps"><li><b>1</b><span>Open this page in Safari.</span></li><li><b>2</b><span>Tap the Share button.</span></li><li><b>3</b><span>Choose <strong>Add to Home Screen</strong>, turn on <strong>Open as Web App</strong>, then tap Add.</span></li></ol>` : `<p>Your browser can install Grab as an app. Choose Install below or use your browser’s install menu.</p><button class="primary-button" data-action="trigger-install">Install Grab</button>`}<p class="modal-note">After installation, Grab opens in its own app window and keeps your signed-in session securely on this device.</p>`;
}

function runFormModal() {
  const stores = state.data.places.filter(place => ["store", "restaurant", "other"].includes(place.kind));
  const destinations = state.data.places.filter(place => ["residence", "campus", "transit", "other"].includes(place.kind));
  const groups = memberGroups();
  return `<p class="eyebrow">ALREADY GOING?</p><h2 id="modal-title">Announce a store run</h2><p>Let people request items only if they fit the route you’re already taking.</p><form id="run-form" class="form-stack">
    <label><span>Store</span><select name="storePlaceId" required><option value="">Choose a store</option>${placeOptions(stores)}</select></label>
    <label><span>Destination</span><select name="destinationPlaceId" required><option value="">Where are you heading?</option>${placeOptions(destinations)}</select></label>
    <div class="split-fields"><label><span>Accept for</span><select name="minutes"><option value="30">30 minutes</option><option value="45">45 minutes</option><option value="60">1 hour</option><option value="90">90 minutes</option></select></label><label><span>Capacity</span><select name="capacity"><option value="3">3 requests</option><option value="5">5 requests</option><option value="8">8 requests</option></select></label></div>
    <label><span>Audience</span><select name="audience"><option value="campus">Campus</option>${groups.map(group => `<option value="group:${group.id}">${escapeHTML(group.name)}</option>`).join("")}</select></label>
    <div class="split-fields"><label><span>Fee per request</span><div class="money-input"><b>$</b><input name="fee" type="number" min="0" max="100" step="0.01" value="0" /></div></label><label><span>Max detour</span><select name="detour"><option value="5">5 min</option><option value="10" selected>10 min</option><option value="15">15 min</option><option value="20">20 min</option></select></label></div>
    <label><span>Note</span><textarea name="note" maxlength="500" rows="2" placeholder="Optional details"></textarea></label>
    <button class="primary-button" type="submit" ${state.working ? "disabled" : ""}>Announce run</button>
  </form>`;
}

function runModal(id) {
  const run = state.data.runs.find(item => item.id === id);
  if (!run) return `<h2 id="modal-title">Run unavailable</h2><p>This run may have closed. Refresh to see current activity.</p>`;
  const own = run.runner_id === state.session.user.id;
  return `<p class="eyebrow">${escapeHTML(titleCase(run.audience))} RUN</p><div class="modal-title-row"><div><h2 id="modal-title">${escapeHTML(run.store_label)}</h2><p>Heading to ${escapeHTML(run.destination_label)}</p></div>${statusPill(run.status)}</div>
    <div class="detail-person">${avatar(run.runner)}<div><strong>${escapeHTML(run.runner?.display_name || "Grab runner")}</strong><span>${own ? "You announced this run" : `Accepting requests ${relativeTime(run.closes_at)}`}</span></div></div>
    <dl class="detail-grid"><div><dt>Closes</dt><dd>${escapeHTML(shortDate(run.closes_at))}</dd></div><div><dt>Fee</dt><dd>${run.fee_cents ? money(run.fee_cents) : "Free"}</dd></div><div><dt>Capacity</dt><dd>${run.capacity} requests</dd></div><div><dt>Max detour</dt><dd>${run.max_added_minutes} min</dd></div></dl>
    ${run.note ? `<div class="notice"><b>Runner note</b><p>${escapeHTML(run.note)}</p></div>` : ""}
    ${own ? `<div class="modal-actions">${run.status === "open" ? `<button class="primary-button" data-action="run-status" data-id="${run.id}" data-status="shopping">Start shopping</button>` : ""}${run.status === "shopping" ? `<button class="primary-button" data-action="run-status" data-id="${run.id}" data-status="returning">Head back</button>` : ""}${run.status === "returning" ? `<button class="primary-button" data-action="run-status" data-id="${run.id}" data-status="completed">Finish run</button>` : ""}<button class="quiet-danger" data-action="run-status" data-id="${run.id}" data-status="cancelled">Cancel run</button></div>` : `<form id="request-from-run-form" class="form-stack"><input type="hidden" name="runId" value="${run.id}" /><label><span>What should they grab?</span><input name="title" required maxlength="120" placeholder="One carton of oat milk" /></label><label><span>Details</span><textarea name="details" maxlength="1000" rows="2" placeholder="Brand or substitution notes"></textarea></label><label><span>Purchase budget</span><div class="money-input"><b>$</b><input name="budget" type="number" min="0" max="500" step="0.01" placeholder="10.00" /></div></label><button class="primary-button" type="submit">Request from this run</button></form>`}`;
}

function requestModal(id) {
  const request = [...state.data.requests, ...state.data.nearby].find(item => item.id === id);
  if (!request) return `<h2 id="modal-title">Request unavailable</h2><p>Someone may have accepted or cancelled it. Refresh to see current tasks.</p>`;
  const isRequester = request.requester_id === state.session.user.id;
  const isHelper = request.helper_id === state.session.user.id;
  const canChat = isRequester || isHelper;
  const transitions = { accepted: "picking_up", picking_up: "on_the_way", on_the_way: "delivered", delivered: "completed" };
  let actions = "";
  if (request.status === "open" && !isRequester) actions += `<button class="primary-button" data-action="accept-request" data-id="${request.id}">Accept request</button>`;
  if (isHelper && transitions[request.status] && request.status !== "delivered") actions += `<button class="primary-button" data-action="advance-request" data-id="${request.id}" data-status="${transitions[request.status]}">Mark ${escapeHTML(titleCase(transitions[request.status]))}</button>`;
  if (isRequester && ["on_the_way", "delivered"].includes(request.status)) actions += `<button class="primary-button" data-action="advance-request" data-id="${request.id}" data-status="completed">Confirm received</button>`;
  if (isHelper && ["accepted", "picking_up"].includes(request.status)) actions += `<button class="secondary-button" data-action="release-request" data-id="${request.id}">Release task</button>`;
  if (isRequester && ["open", "accepted"].includes(request.status)) actions += `<button class="quiet-danger" data-action="cancel-request" data-id="${request.id}">Cancel request</button>`;
  return `<div class="modal-title-row"><div><p class="eyebrow">REQUEST</p><h2 id="modal-title">${escapeHTML(request.title)}</h2></div>${statusPill(request.status)}</div>
    <p>${escapeHTML(request.details || "No additional details.")}</p>
    <dl class="detail-grid"><div><dt>Pickup</dt><dd>${escapeHTML(request.pickup_label)}</dd></div><div><dt>Handoff</dt><dd>${escapeHTML(request.destination_label)}</dd></div><div><dt>Due</dt><dd>${escapeHTML(shortDate(request.deliver_by))}</dd></div><div><dt>Reward</dt><dd>${money(request.reward_cents)}</dd></div><div><dt>Purchase cap</dt><dd>${request.merchandise_budget_cents == null ? "Not set" : money(request.merchandise_budget_cents)}</dd></div><div><dt>Posted by</dt><dd>${escapeHTML(request.requester?.display_name || "Grab member")}</dd></div></dl>
    <div class="modal-actions">${actions || `<div class="success-note">No action is needed right now.</div>`}</div>
    ${canChat && request.helper_id ? `<section class="request-chat"><div class="section-heading"><div><p class="eyebrow">PRIVATE CHAT</p><h3>Request conversation</h3></div></div><div class="chat-feed compact-chat">${state.requestMessages.length ? state.requestMessages.map(message => `<div class="chat-message ${message.sender_id === state.session.user.id ? "mine" : ""}"><strong>${escapeHTML(message.sender?.display_name || "Member")}</strong><p>${escapeHTML(message.body)}</p></div>`).join("") : `<p class="empty-copy">No messages yet.</p>`}</div>${["accepted", "picking_up", "on_the_way", "delivered"].includes(request.status) ? `<form id="request-message-form" class="inline-form"><input type="hidden" name="requestId" value="${request.id}" /><input name="body" required maxlength="2000" placeholder="Message privately" /><button type="submit" aria-label="Send">↑</button></form>` : ""}</section>` : ""}`;
}

function groupToolsModal() {
  return `<p class="eyebrow">YOUR PEOPLE</p><h2 id="modal-title">Create or join a group</h2><div class="tool-columns"><form id="create-group-form" class="form-stack"><h3>Create a friend group</h3><label><span>Group name</span><input name="name" required minlength="1" maxlength="60" placeholder="Northside Crew" /></label><button class="primary-button" type="submit">Create group</button></form><form id="join-group-form" class="form-stack"><h3>Join with an invite</h3><label><span>8-character code</span><input name="code" required minlength="8" maxlength="8" autocomplete="off" autocapitalize="characters" placeholder="ABC12345" /></label><button class="secondary-button" type="submit">Join group</button></form></div>`;
}

function confirmDeleteModal() {
  return `<p class="eyebrow danger-text">PERMANENT ACTION</p><h2 id="modal-title">Delete your Grab account?</h2><p>This deletes your profile, requests, runs, and memberships. Active deliveries are safely released or completed by the backend. This cannot be undone.</p><form id="delete-account-form" class="form-stack"><label><span>Type DELETE to confirm</span><input name="confirmation" required pattern="DELETE" autocomplete="off" /></label><button class="danger-button" type="submit">Permanently delete account</button></form>`;
}

function passwordModal() {
  return `<p class="eyebrow">SECURE YOUR ACCOUNT</p><h2 id="modal-title">Choose a new password</h2><p>Use at least 6 characters. A longer, unique password is safer.</p><form id="password-form" class="form-stack"><label><span>New password</span><input name="password" type="password" minlength="6" autocomplete="new-password" required /></label><label><span>Confirm password</span><input name="confirmation" type="password" minlength="6" autocomplete="new-password" required /></label><button class="primary-button" type="submit">Update password</button></form>`;
}

function legalModal(document) {
  if (document === "privacy") return `<p class="eyebrow">PRIVACY NOTICE</p><h2 id="modal-title">Your data in Grab</h2><div class="legal-document"><p>Grab uses your email for account access and stores your display name, campus, optional home building, groups, requests, runs, shopping-list items, and messages so the service can work.</p><h3>Who can see what</h3><p>Supabase row-level security restricts data by account, group membership, campus audience, and request participation. Contact details are not stored in public profiles.</p><h3>Location</h3><p>If you choose “Use my location,” the browser supplies coordinates to sort nearby requests. Grab does not store that browser location from this web app.</p><h3>Account control</h3><p>You can sign out, change your name and home building, or permanently delete your account from Profile. Account deletion removes associated records according to the backend’s retention rules.</p><h3>Payments</h3><p>Payment amounts are coordination records only. Grab does not currently charge cards or send payouts.</p><p class="modal-note">For a public commercial launch, replace this product notice with counsel-reviewed company contact, jurisdiction, retention, subprocessors, and consumer-rights language.</p></div>`;
  return `<p class="eyebrow">TERMS OF USE</p><h2 id="modal-title">Use Grab responsibly</h2><div class="legal-document"><p>Grab helps people coordinate errands. Users are responsible for accurate requests, lawful items, safe public handoffs, and respectful communication.</p><h3>Safety</h3><p>Do not request controlled, illegal, dangerous, age-restricted, or unsafe items. Do not share sensitive personal information in group messages or public request details.</p><h3>Payments</h3><p>Grab currently records budgets and rewards but does not process payments. Participants must not treat displayed amounts as a completed charge or guaranteed payout.</p><h3>Availability</h3><p>Requests and runs may change or be cancelled. Grab does not guarantee that another person will accept or complete a task.</p><p class="modal-note">These launch terms are product copy, not a substitute for counsel-reviewed commercial terms.</p></div>`;
}

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
      if (state.data && !state.modal && localStorage.getItem("grab:onboarded:v1") !== "true") {
        state.onboardingStep = 0;
        state.modal = { type: "onboarding" };
      }
      render();
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

document.addEventListener("click", async event => {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  const { action, id, tab, mode, status, sort, document: documentName } = button.dataset;

  if (action === "nav") {
    state.tab = tab;
    state.groupId = null;
    state.modal = null;
    setUrlTab(tab);
    track("page_viewed", { tab });
    render();
    window.scrollTo({ top: 0, behavior: "smooth" });
  } else if (action === "auth-mode") {
    state.authMode = mode;
    render();
  } else if (action === "refresh") {
    await loadData({ quiet: true });
  } else if (action === "search") {
    state.searchQuery = "";
    state.modal = { type: "search" };
    renderModal();
    document.querySelector("#global-search")?.focus();
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
    localStorage.setItem("grab:onboarded:v1", "true");
    state.modal = null;
    track(action === "onboarding-complete" ? "onboarding_completed" : "onboarding_skipped");
    renderModal();
  } else if (action === "signout") {
    await work(() => signOut(), "Signed out", { close: false });
  } else if (action === "install") {
    if (state.installPrompt) await triggerInstall();
    else { state.modal = { type: "install" }; render(); }
  } else if (action === "trigger-install") {
    await triggerInstall();
  } else if (action === "close-modal") {
    state.modal = null;
    state.requestMessages = [];
    renderModal();
  } else if (action === "open-run-form") {
    state.modal = { type: "run-form" };
    renderModal();
  } else if (action === "open-run") {
    state.modal = { type: "run", id };
    renderModal();
  } else if (action === "open-request") {
    state.requestMessages = [];
    state.modal = { type: "request", id };
    renderModal();
    const request = [...state.data.requests, ...state.data.nearby].find(item => item.id === id);
    if (request && (request.requester_id === state.session.user.id || request.helper_id === state.session.user.id) && request.helper_id) {
      try { state.requestMessages = await loadRequestMessages(id); renderModal(); } catch { /* chat remains available after refresh */ }
    }
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
    await work(() => acceptRequest(id), "Request accepted");
  } else if (action === "advance-request") {
    await work(() => advanceRequest(id, status), `Request marked ${titleCase(status)}`);
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
  if (event.target.id !== "global-search") return;
  state.searchQuery = event.target.value;
  const results = document.querySelector("#search-results");
  if (results) results.innerHTML = searchResultsMarkup();
});

document.addEventListener("submit", async event => {
  event.preventDefault();
  const form = event.target;
  const values = Object.fromEntries(new FormData(form));

  if (form.id === "auth-form") {
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
            throw new Error("That email already has a Grab account. Sign in with its original password or choose Forgot password.");
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
  } else if (form.id === "request-form") {
    const pickup = state.data.places.find(place => place.id === values.pickupPlaceId);
    const destination = state.data.places.find(place => place.id === values.destinationPlaceId);
    const payload = {
      group_id: values.groupId || null,
      title: values.title.trim(),
      details: values.details.trim(),
      pickup_place_id: pickup?.id ?? null,
      pickup_label: pickup?.name ?? "Any store",
      destination_place_id: destination.id,
      destination_label: destination.name,
      deliver_by: new Date(values.deliverBy).toISOString(),
      reward_cents: Math.round(Number(values.reward || 0) * 100),
      merchandise_budget_cents: values.budget === "" ? null : Math.round(Number(values.budget) * 100)
    };
    if (await work(() => createRequest(payload), "Request posted")) {
      state.tab = "activity";
      setUrlTab("activity");
      track("request_created", { audience: payload.group_id ? "group" : "campus" });
      render();
    }
  } else if (form.id === "run-form") {
    const store = state.data.places.find(place => place.id === values.storePlaceId);
    const destination = state.data.places.find(place => place.id === values.destinationPlaceId);
    const groupId = values.audience.startsWith("group:") ? values.audience.slice(6) : null;
    const group = state.data.groups.find(item => item.id === groupId);
    const audience = group ? group.kind === "building" ? "building" : "friends" : "campus";
    const fee = audience === "friends" ? 0 : Math.round(Number(values.fee || 0) * 100);
    await work(() => createRun({
      group_id: groupId,
      audience,
      store_place_id: store.id,
      store_label: store.name,
      destination_place_id: destination.id,
      destination_label: destination.name,
      note: values.note.trim() || null,
      closes_at: new Date(Date.now() + Number(values.minutes) * 60000).toISOString(),
      fee_cents: fee,
      max_added_minutes: Number(values.detour),
      capacity: Number(values.capacity)
    }), "Run announced");
  } else if (form.id === "request-from-run-form") {
    await work(() => requestFromRun(values.runId, values.title.trim(), values.details.trim(), values.budget === "" ? null : Math.round(Number(values.budget) * 100)), "Request sent to the runner");
  } else if (form.id === "create-group-form") {
    await work(() => createGroup(values.name.trim()), "Group created");
  } else if (form.id === "join-group-form") {
    await work(() => joinGroup(values.code.trim().toUpperCase()), "Group joined");
  } else if (form.id === "list-item-form") {
    const run = state.data.runs.find(item => item.group_id === values.groupId);
    await work(() => addListItem(values.groupId, run?.id, values.body.trim()), "Item added", { close: false });
  } else if (form.id === "group-message-form") {
    await work(() => sendGroupMessage(values.groupId, values.body.trim()), null, { close: false });
  } else if (form.id === "request-message-form") {
    await work(() => sendRequestMessage(values.requestId, values.body.trim()), null, { close: false });
    state.modal = { type: "request", id: values.requestId };
    state.requestMessages = await loadRequestMessages(values.requestId);
    renderModal();
  } else if (form.id === "profile-form") {
    await work(() => updateDisplayName(state.session.user.id, values.displayName.trim()), "Name updated", { close: false });
  } else if (form.id === "home-form") {
    await work(() => setHomePlace(values.placeId || null), "Home updated", { close: false });
  } else if (form.id === "delete-account-form") {
    if (values.confirmation !== "DELETE") return;
    await work(async () => { await deleteAccount(); await supabase.auth.signOut({ scope: "local" }); }, "Account deleted");
  } else if (form.id === "password-form") {
    if (values.password !== values.confirmation) { showToast("The passwords don’t match", "error"); return; }
    await work(() => updatePassword(values.password), "Password updated");
    state.recovery = false;
  } else if (form.id === "feedback-form") {
    const category = values.category;
    const message = values.message.trim();
    const sent = await work(() => submitFeedback({ category, message, contactOk: values.contactOk === "on", page: state.tab }), "Thanks—your feedback was sent");
    if (sent) track("feedback_submitted", { category, page: state.tab });
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
window.addEventListener("appinstalled", () => { state.installPrompt = null; render(); showToast("Grab installed"); });
window.addEventListener("online", () => { state.online = true; render(); if (state.session) loadData({ quiet: true }); });
window.addEventListener("offline", () => { state.online = false; render(); });
window.addEventListener("keydown", event => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k" && state.session) {
    event.preventDefault();
    state.searchQuery = "";
    state.modal = { type: "search" };
    renderModal();
    document.querySelector("#global-search")?.focus();
  } else if (event.key === "Escape" && state.modal) {
    state.modal = null;
    renderModal();
  }
});
modalRoot.addEventListener("click", event => { if (event.target.classList.contains("modal-backdrop")) { state.modal = null; renderModal(); } });

async function initialize() {
  if ("serviceWorker" in navigator && location.protocol === "https:") {
    navigator.serviceWorker.register("./sw.js").catch(() => {});
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
      state.unsubscribeRealtime?.();
      state.unsubscribeRealtime = subscribeToChanges(() => loadData({ quiet: true }));
      loadData();
    } else if (!session) {
      state.data = null;
      state.unsubscribeRealtime?.();
      state.unsubscribeRealtime = null;
      render();
    } else {
      render();
    }
  });

  if (state.session) {
    state.unsubscribeRealtime = subscribeToChanges(() => loadData({ quiet: true }));
    await loadData();
  } else {
    render();
  }
}

initialize().catch(error => {
  state.loading = false;
  app.innerHTML = `<main class="center-state error-state"><img src="./icons/icon-192.png" alt="" /><h1>Grab couldn’t start</h1><p>${escapeHTML(errorMessage(error))}</p><a class="primary-button retry-link" href="./">Try again</a></main>`;
});
