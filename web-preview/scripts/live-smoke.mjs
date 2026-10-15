import { createClient } from "@supabase/supabase-js";

const url = "https://kqqmdegvjgbycnmygivs.supabase.co";
const key = "sb_publishable_QtetGbFGjZ-ogSrVnogWWA_B8wD8MgV";
const mode = process.argv[2];
if (mode === "cleanup") {
  const [, , , cleanupEmail, cleanupPassword] = process.argv;
  if (!cleanupEmail || !cleanupPassword) throw new Error("Cleanup requires email and password arguments");
  const cleanupClient = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: loginError } = await cleanupClient.auth.signInWithPassword({ email: cleanupEmail, password: cleanupPassword });
  if (loginError) throw loginError;
  const { error: deleteError } = await cleanupClient.rpc("delete_my_account");
  if (deleteError) throw deleteError;
  console.log("Temporary browser account deleted");
  process.exit(0);
}
const keep = mode === "keep";
const email = `grab-web-smoke-${Date.now()}@example.com`;
const password = `Smoke-${Date.now()}-safe`;
const client = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
let created = false;

try {
  const { data: signup, error: signupError } = await client.auth.signUp({
    email,
    password,
    options: { data: { display_name: "Grab Web Smoke Test" } }
  });
  if (signupError) throw signupError;
  if (!signup.session || !signup.user) throw new Error("Sign-up did not create an immediate session");
  created = true;

  const checks = await Promise.all([
    client.from("profiles").select("id, display_name, campus_id").eq("id", signup.user.id).single(),
    client.from("places").select("id, name, kind").limit(3),
    client.from("groups").select("id, name, kind").limit(3),
    client.rpc("open_requests_nearby", { p_lat: null, p_lng: null }).limit(3),
    client.rpc("my_earnings")
  ]);
  for (const result of checks) if (result.error) throw result.error;
  if (checks[0].data.display_name !== "Grab Web Smoke Test") throw new Error("Profile trigger did not preserve display name");
  if (!checks[0].data.campus_id) throw new Error("New account was not assigned a campus");
  if (!checks[1].data.length) throw new Error("No production places were returned");

  console.log(JSON.stringify({
    auth: "ok",
    profile: "ok",
    places: checks[1].data.length,
    groups: checks[2].data.length,
    nearby: checks[3].data.length,
    earnings: "ok",
    ...(keep ? { email, password } : {})
  }));
} finally {
  if (created && !keep) {
    const { error } = await client.rpc("delete_my_account");
    if (error) console.error(`Cleanup warning: ${error.message}`);
  }
  await client.auth.signOut({ scope: "local" });
}
