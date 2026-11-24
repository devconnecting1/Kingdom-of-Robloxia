// Typed readers for the props of a UiNode, with Roblox's defaults when a prop is absent.

import type {
  Color3Value,
  ColorSequenceValue,
  EnumValue,
  PropValue,
  UDim2Value,
  UDimValue,
  UiNode,
  Vector2Value,
} from "./types";

function tagged<T extends { __t: string }>(value: PropValue | undefined, tag: T["__t"]): T | undefined {
  if (typeof value === "object" && value !== null && value.__t === tag) {
    return value as unknown as T;
  }
  return undefined;
}

export function udim2(node: UiNode, key: string, fallback: UDim2Value): UDim2Value {
  return tagged<UDim2Value>(node.props[key], "UDim2") ?? fallback;
}

export function udim(node: UiNode, key: string): UDimValue {
  return tagged<UDimValue>(node.props[key], "UDim") ?? { __t: "UDim", s: 0, o: 0 };
}

export function vector2(node: UiNode, key: string): Vector2Value {
  return tagged<Vector2Value>(node.props[key], "Vector2") ?? { __t: "Vector2", x: 0, y: 0 };
}

export function color(node: UiNode, key: string, fallback: Color3Value): Color3Value {
  return tagged<Color3Value>(node.props[key], "Color3") ?? fallback;
}

export function sequence(node: UiNode, key: string): ColorSequenceValue | undefined {
  return tagged<ColorSequenceValue>(node.props[key], "ColorSequence");
}

export function enumItem(node: UiNode, key: string, fallback: string): string {
  return tagged<EnumValue>(node.props[key], "Enum")?.v ?? fallback;
}

export function num(node: UiNode, key: string, fallback: number): number {
  const value = node.props[key];
  return typeof value === "number" ? value : fallback;
}

export function bool(node: UiNode, key: string, fallback: boolean): boolean {
  const value = node.props[key];
  return typeof value === "boolean" ? value : fallback;
}

export function str(node: UiNode, key: string): string | undefined {
  const value = node.props[key];
  return typeof value === "string" ? value : undefined;
}

export function rgba(c: Color3Value, transparency = 0, tint?: Color3Value): string {
  const r = tint ? (c.r * tint.r) / 255 : c.r;
  const g = tint ? (c.g * tint.g) / 255 : c.g;
  const b = tint ? (c.b * tint.b) / 255 : c.b;
  return `rgba(${Math.round(r)}, ${Math.round(g)}, ${Math.round(b)}, ${1 - transparency})`;
}

export const WHITE: Color3Value = { __t: "Color3", r: 255, g: 255, b: 255 };
export const GREY: Color3Value = { __t: "Color3", r: 163, g: 162, b: 165 };
export const BLACK: Color3Value = { __t: "Color3", r: 0, g: 0, b: 0 };
