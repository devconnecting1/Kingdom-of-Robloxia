// Serves the built preview and saves one PNG per scene with Playwright's Chromium.
// Usage (after `npm run build`): node scripts/screenshot.mjs [outDir]

import { createReadStream, existsSync, mkdirSync, readFileSync, statSync } from "node:fs";
import { createServer } from "node:http";
import { extname, join, resolve } from "node:path";
import { chromium } from "playwright";

const root = resolve("dist");
const outDir = resolve(process.argv[2] ?? "../docs/screenshots");
const types = { ".html": "text/html", ".js": "text/javascript", ".json": "application/json", ".css": "text/css" };

const server = createServer((req, res) => {
  const path = decodeURIComponent(new URL(req.url, "http://x").pathname);
  let file = join(root, path === "/" ? "index.html" : path);
  if (!file.startsWith(root) || !existsSync(file) || statSync(file).isDirectory()) {
    file = join(root, "index.html");
  }
  res.writeHead(200, { "content-type": types[extname(file)] ?? "application/octet-stream" });
  createReadStream(file).pipe(res);
});
await new Promise((ok) => server.listen(0, "127.0.0.1", ok));
const base = `http://127.0.0.1:${server.address().port}`;

const scenes = JSON.parse(readFileSync(join(root, "scenes", "index.json"), "utf8"));
mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
let failed = 0;
for (const scene of scenes) {
  const page = await browser.newPage({
    viewport: { width: scene.width, height: scene.height },
    deviceScaleFactor: scene.scale ?? 1,
  });
  page.on("pageerror", (err) => console.error(`  ${scene.name}: ${err.message}`));
  await page.goto(`${base}/?scene=${encodeURIComponent(scene.name)}`);
  await page.waitForSelector("body[data-ready]", { timeout: 90_000 });
  const ready = await page.getAttribute("body", "data-ready");
  if (ready !== "1") {
    failed += 1;
    console.error(`✗ ${scene.name}: ${await page.textContent("body")}`);
  } else {
    const file = join(outDir, `${scene.name}.png`);
    await page.screenshot({ path: file });
    console.log(`✓ ${file}`);
  }
  await page.close();
}
await browser.close();
server.close();
process.exit(failed > 0 ? 1 : 0);
