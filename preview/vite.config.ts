import { defineConfig } from "vite";

// Relative base so the built preview also opens from any sub-path (GitHub Pages, an artifact, a local folder server).
export default defineConfig({
  base: "./",
  build: { outDir: "dist", emptyOutDir: true },
});
