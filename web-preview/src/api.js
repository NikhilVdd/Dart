import { createClient } from "@supabase/supabase-js";
import {
  PROFILE_SELECT,
  REQUEST_SELECT,
  RUN_SELECT,
  SUPABASE_PUBLISHABLE_KEY,
  SUPABASE_URL
} from "./config.js";

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true
  }
});

const one = result => {
  if (result.error) throw result.error;
  return result.data;
};

export async function signIn(email, password) {
  return one(await supabase.auth.signInWithPassword({ email, password }));
}

export async function signUp(email, password, displayName) {
  return one(await supabase.auth.signUp({
    email,
    password,
    options: {
      data: { display_name: displayName },
      emailRedirectTo: `${window.location.origin}${window.location.pathname}`
    }
  }));
}

export async function sendPasswordReset(email) {
  return one(await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}${window.location.pathname}`
  }));
}

export async function updatePassword(password) {
  return one(await supabase.auth.updateUser({ password }));
}

export async function signOut() {
  return one(await supabase.auth.signOut());
}

export async function loadAppData(userId, coords = null) {
  const nearbyParams = {
    p_lat: coords?.latitude ?? null,
    p_lng: coords?.longitude ?? null
  };
  const [profile, places, groups, members, runs, requests, nearby, listItems, messages, earnings] = await Promise.all([
    supabase.from("profiles").select(PROFILE_SELECT).eq("id", userId).single(),
    supabase.from("places").select("*").order("name"),
    supabase.from("groups").select("id, name, kind, invite_code, place_id").order("name"),
    supabase.from("group_members").select("group_id, user_id, role, profile:profiles(initials)") ,
    supabase.from("runs").select(RUN_SELECT).in("status", ["open", "shopping", "returning"]).gt("closes_at", new Date().toISOString()).order("closes_at"),
    supabase.from("requests").select(REQUEST_SELECT).or(`requester_id.eq.${userId},helper_id.eq.${userId}`).order("created_at", { ascending: false }).limit(100),
    supabase.rpc("open_requests_nearby", nearbyParams).select(REQUEST_SELECT).limit(50),
    supabase.from("list_items").select("*").order("created_at"),
    supabase.from("messages").select("id, group_id, sender_id, body, created_at, sender:profiles!sender_id(display_name)").order("created_at", { ascending: false }).limit(200),
    supabase.rpc("my_earnings")
  ]);

  const results = { profile, places, groups, members, runs, requests, nearby, listItems, messages, earnings };
  for (const [name, result] of Object.entries(results)) {
    if (result.error) throw new Error(`${name}: ${result.error.message}`);
  }
  return {
    profile: profile.data,
    places: places.data ?? [],
    groups: groups.data ?? [],
    members: members.data ?? [],
    runs: runs.data ?? [],
    requests: requests.data ?? [],
    nearby: nearby.data ?? [],
    listItems: listItems.data ?? [],
    messages: messages.data ?? [],
    earnings: earnings.data?.[0] ?? { completed_count: 0, earned_cents: 0, active_count: 0 }
  };
}

export async function createRequest(payload) {
  return one(await supabase.from("requests").insert(payload).select(REQUEST_SELECT).single());
}

export async function createRun(payload) {
  return one(await supabase.from("runs").insert(payload).select(RUN_SELECT).single());
}

export async function acceptRequest(requestId, runId = null) {
  return one(await supabase.rpc("accept_request", { p_request_id: requestId, p_run_id: runId }));
}

export async function advanceRequest(requestId, status) {
  return one(await supabase.rpc("advance_request", { p_request_id: requestId, p_status: status }));
}

export async function releaseRequest(requestId) {
  return one(await supabase.rpc("release_request", { p_request_id: requestId }));
}

export async function cancelRequest(requestId) {
  return one(await supabase.rpc("cancel_request", { p_request_id: requestId }));
}

export async function requestFromRun(runId, title, details, budgetCents) {
  return one(await supabase.rpc("request_from_run", {
    p_run_id: runId,
    p_title: title,
    p_details: details,
    p_merchandise_budget_cents: budgetCents
  }));
}

export async function updateRunStatus(runId, status) {
  return one(await supabase.from("runs").update({ status }).eq("id", runId));
}

export async function createGroup(name) {
  return one(await supabase.rpc("create_group", { p_name: name }));
}

export async function joinGroup(inviteCode) {
  return one(await supabase.rpc("join_group", { p_invite_code: inviteCode }));
}

export async function joinBuilding(groupId) {
  return one(await supabase.rpc("join_building_group", { p_group_id: groupId }));
}

export async function leaveGroup(groupId) {
  return one(await supabase.rpc("leave_group", { p_group_id: groupId }));
}

export async function setHomePlace(placeId) {
  return one(await supabase.rpc("set_home_place", { p_place_id: placeId || null }));
}

export async function updateDisplayName(userId, displayName) {
  return one(await supabase.from("profiles").update({ display_name: displayName }).eq("id", userId));
}

export async function sendGroupMessage(groupId, body) {
  return one(await supabase.from("messages").insert({ group_id: groupId, body }));
}

export async function addListItem(groupId, runId, body) {
  return one(await supabase.from("list_items").insert({ group_id: groupId, run_id: runId || null, body }));
}

export async function setListItem(itemId, picked) {
  return one(await supabase.from("list_items").update({ status: picked ? "picked" : "needed" }).eq("id", itemId));
}

export async function deleteListItem(itemId) {
  return one(await supabase.from("list_items").delete().eq("id", itemId));
}

export async function loadRequestMessages(requestId) {
  return one(await supabase.from("request_messages")
    .select("id, request_id, sender_id, body, created_at, sender:profiles!sender_id(display_name)")
    .eq("request_id", requestId)
    .order("created_at"));
}

export async function sendRequestMessage(requestId, body) {
  return one(await supabase.from("request_messages").insert({ request_id: requestId, body }));
}

export async function deleteAccount() {
  return one(await supabase.rpc("delete_my_account"));
}

export function subscribeToChanges(onChange) {
  let timer;
  const refresh = () => {
    window.clearTimeout(timer);
    timer = window.setTimeout(onChange, 350);
  };
  const channel = supabase.channel("grab-web-live");
  for (const table of ["requests", "runs", "messages", "list_items", "request_messages", "group_members"]) {
    channel.on("postgres_changes", { event: "*", schema: "public", table }, refresh);
  }
  channel.subscribe();
  return () => supabase.removeChannel(channel);
}
