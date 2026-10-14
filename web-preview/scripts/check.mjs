import fs from "node:fs";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const required = [
  "index.html",
  "src/main.js",
  "src/api.js",
  "src/styles.css",
  "public/manifest.webmanifest",
  "public/sw.js",
  "public/icons/icon-192.png",
  "public/icons/icon-512.png"
];

for (const file of required) {
  if (!fs.existsSync(path.join(root, file))) throw new Error(`Missing ${file}`);
}

const manifest = JSON.parse(fs.readFileSync(path.join(root, "public/manifest.webmanifest"), "utf8"));
if (manifest.display !== "standalone") throw new Error("PWA display mode must be standalone");
if (!manifest.icons?.some(icon => icon.sizes === "192x192")) throw new Error("Missing 192px app icon");
if (!manifest.icons?.some(icon => icon.sizes === "512x512")) throw new Error("Missing 512px app icon");

const index = fs.readFileSync(path.join(root, "index.html"), "utf8");
if (!index.includes("manifest.webmanifest")) throw new Error("Manifest is not linked");
if (!index.includes("Content-Security-Policy")) throw new Error("CSP is not configured");

const main = fs.readFileSync(path.join(root, "src/main.js"), "utf8");
for (const launchFeature of ["Search Grab", "Share feedback", "Start using Grab"]) {
  if (!main.includes(launchFeature)) throw new Error(`Missing Friends & Family feature: ${launchFeature}`);
}

const api = fs.readFileSync(path.join(root, "src/api.js"), "utf8");
if (!api.includes('from("launch_feedback")')) throw new Error("Feedback is not connected to Supabase");
if (!api.includes('from("product_events")')) throw new Error("Product events are not connected to Supabase");

console.log("Grab web checks passed");
