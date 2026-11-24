// Lays out a Roblox GUI tree the way the engine does and draws it with absolutely positioned elements.
// Covered: UDim2 size and position, AnchorPoint, AutomaticSize, Visible, ZIndex, Rotation, ClipsDescendants,
// UIPadding, UIListLayout, UIGridLayout, UICorner, UIStroke, UIGradient and the text properties the game uses.

import { BLACK, GREY, WHITE, bool, color, enumItem, num, rgba, sequence, str, udim, udim2, vector2 } from "./props";
import type { UDim2Value, UiNode } from "./types";

const GUI = new Set(["Frame", "TextLabel", "TextButton", "TextBox", "ScrollingFrame", "ImageLabel", "ImageButton"]);
const TEXT = new Set(["TextLabel", "TextButton", "TextBox"]);
const DEFAULT_SIZE: UDim2Value = { __t: "UDim2", xs: 0, xo: 100, ys: 0, yo: 100 };
const ZERO: UDim2Value = { __t: "UDim2", xs: 0, xo: 0, ys: 0, yo: 0 };

interface FontSpec {
  family: string;
  weight: number;
}

const EMOJI = "'Noto Color Emoji'";
const FONTS: Record<string, FontSpec> = {
  FredokaOne: { family: `'Fredoka', ${EMOJI}, sans-serif`, weight: 600 },
  GothamBold: { family: `'Montserrat', ${EMOJI}, sans-serif`, weight: 700 },
  GothamMedium: { family: `'Montserrat', ${EMOJI}, sans-serif`, weight: 500 },
  GothamBlack: { family: `'Montserrat', ${EMOJI}, sans-serif`, weight: 900 },
};

function font(node: UiNode): FontSpec {
  return FONTS[enumItem(node, "Font", "GothamMedium")] ?? FONTS.GothamMedium;
}

const canvas = document.createElement("canvas");
const ctx = canvas.getContext("2d");

function textWidth(node: UiNode): number {
  const text = str(node, "Text") ?? "";
  if (!ctx || text === "") {
    return 0;
  }
  const f = font(node);
  ctx.font = `${f.weight} ${num(node, "TextSize", 14)}px ${f.family}`;
  return Math.ceil(ctx.measureText(text).width) + 2;
}

function guiChildren(node: UiNode): UiNode[] {
  return node.children.filter((c) => GUI.has(c.class) && bool(c, "Visible", true));
}

function child(node: UiNode, cls: string): UiNode | undefined {
  return node.children.find((c) => c.class === cls);
}

interface Box {
  l: number;
  t: number;
  r: number;
  b: number;
}

function padding(node: UiNode, w: number, h: number): Box {
  const p = child(node, "UIPadding");
  if (!p) {
    return { l: 0, t: 0, r: 0, b: 0 };
  }
  const get = (key: string, base: number): number => {
    const u = udim(p, key);
    return u.s * base + u.o;
  };
  return { l: get("PaddingLeft", w), t: get("PaddingTop", h), r: get("PaddingRight", w), b: get("PaddingBottom", h) };
}

function autoAxes(node: UiNode): { x: boolean; y: boolean } {
  const a = enumItem(node, "AutomaticSize", "None");
  return { x: a === "X" || a === "XY", y: a === "Y" || a === "XY" };
}

interface Size {
  w: number;
  h: number;
}

// The size of `node` inside a parent whose content area is pw × ph.
export function measure(node: UiNode, pw: number, ph: number): Size {
  const size = udim2(node, "Size", DEFAULT_SIZE);
  let w = size.xs * pw + size.xo;
  let h = size.ys * ph + size.yo;
  const auto = autoAxes(node);
  if (auto.x || auto.y) {
    const content = contentSize(node, w, h);
    if (auto.x) {
      w = Math.max(w, content.w);
    }
    if (auto.y) {
      h = Math.max(h, content.h);
    }
  }
  return { w, h };
}

function contentSize(node: UiNode, w: number, h: number): Size {
  const pad = padding(node, w, h);
  const innerW = Math.max(0, w - pad.l - pad.r);
  const innerH = Math.max(0, h - pad.t - pad.b);
  let cw = 0;
  let ch = 0;
  if (TEXT.has(node.class)) {
    cw = textWidth(node);
    ch = num(node, "TextSize", 14) * 1.2;
  }
  const kids = guiChildren(node);
  const list = child(node, "UIListLayout");
  const grid = child(node, "UIGridLayout");
  if (list) {
    const horizontal = enumItem(list, "FillDirection", "Vertical") === "Horizontal";
    const gap = udim(list, "Padding").o;
    let along = 0;
    let across = 0;
    kids.forEach((k, i) => {
      const s = measure(k, innerW, innerH);
      along += (horizontal ? s.w : s.h) + (i > 0 ? gap : 0);
      across = Math.max(across, horizontal ? s.h : s.w);
    });
    cw = Math.max(cw, horizontal ? along : across);
    ch = Math.max(ch, horizontal ? across : along);
  } else if (grid) {
    const cells = gridCells(grid, kids.length, innerW, innerH);
    cw = Math.max(cw, cells.width);
    ch = Math.max(ch, cells.height);
  } else {
    for (const k of kids) {
      const s = measure(k, innerW, innerH);
      const pos = udim2(k, "Position", ZERO);
      cw = Math.max(cw, pos.xs * innerW + pos.xo + s.w);
      ch = Math.max(ch, pos.ys * innerH + pos.yo + s.h);
    }
  }
  return { w: cw + pad.l + pad.r, h: ch + pad.t + pad.b };
}

interface GridCells {
  cellW: number;
  cellH: number;
  gapX: number;
  gapY: number;
  columns: number;
  width: number;
  height: number;
}

function gridCells(grid: UiNode, count: number, innerW: number, innerH: number): GridCells {
  const cell = udim2(grid, "CellSize", { __t: "UDim2", xs: 0, xo: 100, ys: 0, yo: 100 });
  const gap = udim2(grid, "CellPadding", { __t: "UDim2", xs: 0, xo: 5, ys: 0, yo: 5 });
  const cellW = cell.xs * innerW + cell.xo;
  const cellH = cell.ys * innerH + cell.yo;
  const gapX = gap.xs * innerW + gap.xo;
  const gapY = gap.ys * innerH + gap.yo;
  const columns = Math.max(1, Math.floor((innerW + gapX) / (cellW + gapX)));
  const rows = Math.ceil(count / columns);
  return {
    cellW,
    cellH,
    gapX,
    gapY,
    columns,
    width: Math.min(count, columns) * (cellW + gapX) - gapX,
    height: rows * (cellH + gapY) - gapY,
  };
}

function layoutOrder(a: UiNode, b: UiNode): number {
  const d = num(a, "LayoutOrder", 0) - num(b, "LayoutOrder", 0);
  if (d !== 0) {
    return d;
  }
  return (a.name ?? "").localeCompare(b.name ?? "");
}

interface Placed {
  node: UiNode;
  x: number;
  y: number;
  w: number;
  h: number;
}

// Positions of the GUI children inside a w × h element.
function placeChildren(node: UiNode, w: number, h: number): Placed[] {
  const pad = padding(node, w, h);
  const innerW = Math.max(0, w - pad.l - pad.r);
  const innerH = Math.max(0, h - pad.t - pad.b);
  const kids = guiChildren(node);
  const list = child(node, "UIListLayout");
  const grid = child(node, "UIGridLayout");
  const out: Placed[] = [];

  if (list) {
    const horizontal = enumItem(list, "FillDirection", "Vertical") === "Horizontal";
    const gap = udim(list, "Padding").s * (horizontal ? innerW : innerH) + udim(list, "Padding").o;
    const hAlign = enumItem(list, "HorizontalAlignment", "Left");
    const vAlign = enumItem(list, "VerticalAlignment", "Top");
    const sorted = [...kids].sort(layoutOrder);
    const sizes = sorted.map((k) => measure(k, innerW, innerH));
    const total = sizes.reduce((sum, s, i) => sum + (horizontal ? s.w : s.h) + (i > 0 ? gap : 0), 0);
    const mainAlign = horizontal ? hAlign : vAlign;
    const mainSpace = (horizontal ? innerW : innerH) - total;
    let cursor =
      mainAlign === "Center" ? mainSpace / 2 : mainAlign === "Right" || mainAlign === "Bottom" ? mainSpace : 0;
    sorted.forEach((k, i) => {
      const s = sizes[i];
      const crossAlign = horizontal ? vAlign : hAlign;
      const crossSpace = (horizontal ? innerH : innerW) - (horizontal ? s.h : s.w);
      const cross =
        crossAlign === "Center" ? crossSpace / 2 : crossAlign === "Right" || crossAlign === "Bottom" ? crossSpace : 0;
      out.push({
        node: k,
        x: pad.l + (horizontal ? cursor : cross),
        y: pad.t + (horizontal ? cross : cursor),
        w: s.w,
        h: s.h,
      });
      cursor += (horizontal ? s.w : s.h) + gap;
    });
    return out;
  }

  if (grid) {
    const sorted = [...kids].sort(layoutOrder);
    const cells = gridCells(grid, sorted.length, innerW, innerH);
    const hAlign = enumItem(grid, "HorizontalAlignment", "Left");
    const offset = hAlign === "Center" ? (innerW - cells.width) / 2 : hAlign === "Right" ? innerW - cells.width : 0;
    sorted.forEach((k, i) => {
      const col = i % cells.columns;
      const row = Math.floor(i / cells.columns);
      out.push({
        node: k,
        x: pad.l + offset + col * (cells.cellW + cells.gapX),
        y: pad.t + row * (cells.cellH + cells.gapY),
        w: cells.cellW,
        h: cells.cellH,
      });
    });
    return out;
  }

  for (const k of kids) {
    const s = measure(k, innerW, innerH);
    const pos = udim2(k, "Position", ZERO);
    const anchor = vector2(k, "AnchorPoint");
    out.push({
      node: k,
      x: pad.l + pos.xs * innerW + pos.xo - anchor.x * s.w,
      y: pad.t + pos.ys * innerH + pos.yo - anchor.y * s.h,
      w: s.w,
      h: s.h,
    });
  }
  return out;
}

const JUSTIFY: Record<string, string> = { Left: "flex-start", Center: "center", Right: "flex-end" };
const ALIGN: Record<string, string> = { Top: "flex-start", Center: "center", Bottom: "flex-end" };

function paint(node: UiNode, el: HTMLElement, w: number, h: number): void {
  const transparency = num(node, "BackgroundTransparency", 0);
  const background = color(
    node,
    "BackgroundColor3",
    node.class === "Frame" || node.class === "ScrollingFrame" ? GREY : WHITE,
  );
  const gradient = child(node, "UIGradient");
  if (transparency < 1) {
    const seq = gradient ? sequence(gradient, "Color") : undefined;
    if (seq && gradient) {
      const angle = num(gradient, "Rotation", 0) + 90;
      el.style.background = `linear-gradient(${angle}deg, ${rgba(seq.a, transparency, background)}, ${rgba(seq.b, transparency, background)})`;
    } else {
      el.style.background = rgba(background, transparency);
    }
  }

  const corner = child(node, "UICorner");
  if (corner) {
    const r = udim(corner, "CornerRadius");
    el.style.borderRadius = `${r.s * Math.min(w, h) + r.o}px`;
  }

  const stroke = child(node, "UIStroke");
  if (stroke) {
    const t = num(stroke, "Thickness", 1);
    el.style.boxShadow = `0 0 0 ${t}px ${rgba(color(stroke, "Color", BLACK), num(stroke, "Transparency", 0))}`;
  }

  if (bool(node, "ClipsDescendants", false) || node.class === "ScrollingFrame") {
    el.style.overflow = "hidden";
  }
  const rotation = num(node, "Rotation", 0);
  if (rotation !== 0) {
    el.style.transform = `rotate(${rotation}deg)`;
  }

  if (TEXT.has(node.class)) {
    const text = str(node, "Text") ?? "";
    if (text !== "") {
      const f = font(node);
      const wrapped = bool(node, "TextWrapped", false);
      el.style.display = "flex";
      el.style.justifyContent = JUSTIFY[enumItem(node, "TextXAlignment", "Center")] ?? "center";
      el.style.alignItems = ALIGN[enumItem(node, "TextYAlignment", "Center")] ?? "center";
      el.style.fontFamily = f.family;
      el.style.fontWeight = String(f.weight);
      el.style.fontSize = `${num(node, "TextSize", 14)}px`;
      el.style.lineHeight = "1.15";
      el.style.color = rgba(color(node, "TextColor3", BLACK), num(node, "TextTransparency", 0));
      const span = document.createElement("span");
      span.textContent = text;
      span.style.maxWidth = "100%";
      span.style.textAlign = (enumItem(node, "TextXAlignment", "Center") || "center").toLowerCase();
      if (wrapped) {
        span.style.whiteSpace = "normal";
        span.style.overflowWrap = "anywhere";
      } else {
        span.style.whiteSpace = "pre";
        span.style.overflow = "hidden";
        span.style.textOverflow = enumItem(node, "TextTruncate", "None") === "AtEnd" ? "ellipsis" : "clip";
      }
      el.appendChild(span);
    }
  }
}

export function draw(node: UiNode, parent: HTMLElement, x: number, y: number, w: number, h: number): void {
  const el = document.createElement("div");
  el.dataset.name = node.name ?? node.class;
  el.dataset.class = node.class;
  el.style.position = "absolute";
  el.style.boxSizing = "border-box";
  el.style.left = `${x}px`;
  el.style.top = `${y}px`;
  el.style.width = `${Math.max(0, w)}px`;
  el.style.height = `${Math.max(0, h)}px`;
  el.style.zIndex = String(num(node, "ZIndex", 1));
  paint(node, el, w, h);
  parent.appendChild(el);
  for (const placed of placeChildren(node, w, h)) {
    draw(placed.node, el, placed.x, placed.y, placed.w, placed.h);
  }
}
