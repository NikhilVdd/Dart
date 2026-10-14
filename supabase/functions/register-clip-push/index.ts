import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type Registration = {
  request_id: string;
  tracking_secret: string;
  token: string;
  token_kind: "alert" | "liveactivity";
  bundle_id: string;
  environment: "sandbox" | "production";
};

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });

  try {
    const registration = await request.json() as Registration;
    if (!valid(registration)) return Response.json({ error: "Invalid registration" }, { status: 400 });

    const { data: trackingLink, error: linkError } = await supabase
      .from("request_tracking_links")
      .select("request_id")
      .eq("request_id", registration.request_id)
      .eq("secret", registration.tracking_secret)
      .maybeSingle();
    if (linkError) throw linkError;
    if (!trackingLink) return Response.json({ error: "Tracking link not found" }, { status: 404 });

    const { error } = await supabase.from("clip_push_tokens").upsert({
      request_id: registration.request_id,
      token: registration.token,
      token_kind: registration.token_kind,
      bundle_id: registration.bundle_id,
      environment: registration.environment,
      updated_at: new Date().toISOString(),
    }, { onConflict: "request_id,token,token_kind" });
    if (error) throw error;

    return Response.json({ registered: true });
  } catch (error) {
    console.error(error);
    return Response.json({ error: "Registration failed" }, { status: 500 });
  }
});

function valid(value: Registration) {
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  const token = /^[0-9a-f]{32,512}$/;
  return uuid.test(value?.request_id ?? "") && uuid.test(value?.tracking_secret ?? "") &&
    token.test(value?.token ?? "") && ["alert", "liveactivity"].includes(value?.token_kind) &&
    ["sandbox", "production"].includes(value?.environment) &&
    typeof value?.bundle_id === "string" && value.bundle_id.length >= 3 && value.bundle_id.length <= 255;
}
