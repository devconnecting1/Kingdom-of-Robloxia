// Opens one scene (?scene=01-kingdom) or, without a parameter, a gallery of every scene.

import { draw, measure } from "./layout";
import type { Scene, SceneInfo } from "./types";

const FONT_FAMILIES = ["600 20px Fredoka", "500 20px Montserrat", "700 20px Montserrat", "900 20px Montserrat"];

async function loadFonts(): Promise<void> {
  await Promise.all(FONT_FAMILIES.map((f) => document.fonts.load(f, "Aa🏰")));
  await document.fonts.load("20px 'Noto Color Emoji'", "🏰⚔️🌾");
  await document.fonts.ready;
}

async function showScene(name: string): Promise<void> {
  const response = await fetch(`scenes/${encodeURIComponent(name)}.json`);
  if (!response.ok) {
    throw new Error(`scene ${name}: HTTP ${response.status}`);
  }
  const scene = (await response.json()) as Scene;
  await loadFonts();
  const stage = document.createElement("div");
  stage.className = "stage";
  stage.style.width = `${scene.width}px`;
  stage.style.height = `${scene.height}px`;
  document.body.appendChild(stage);
  const size = measure(scene.root, scene.width, scene.height);
  draw(scene.root, stage, 0, 0, size.w, size.h);
}

async function showGallery(): Promise<void> {
  const response = await fetch("scenes/index.json");
  const scenes = (await response.json()) as SceneInfo[];
  const list = document.createElement("ul");
  list.className = "gallery";
  for (const scene of scenes) {
    const item = document.createElement("li");
    const link = document.createElement("a");
    link.href = `?scene=${encodeURIComponent(scene.name)}`;
    link.textContent = `${scene.name} (${scene.width}×${scene.height})`;
    item.appendChild(link);
    list.appendChild(item);
  }
  document.body.appendChild(list);
}

const scene = new URLSearchParams(window.location.search).get("scene");
(scene ? showScene(scene) : showGallery())
  .then(() => {
    document.body.dataset.ready = "1";
  })
  .catch((error: unknown) => {
    document.body.dataset.ready = "error";
    document.body.textContent = String(error);
  });
