import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";

const here = fileURLToPath(new URL(".", import.meta.url));

export default defineConfig({
  base: "./",
  server: {
    // matching.html is a dev-only prototype that imports ../matching/src. Only index.html is built,
    // so neither reaches the production bundle. Paths are pinned to this folder, so starting Vite
    // from elsewhere can't widen what the dev server will read.
    fs: { allow: [here, fileURLToPath(new URL("../matching", import.meta.url))] }
  },
  build: {
    sourcemap: true,
    target: "es2022"
  }
});
