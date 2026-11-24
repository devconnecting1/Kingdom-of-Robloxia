// Shapes written by tools/render.luau: Roblox datatypes are tagged objects, everything else is plain JSON.

export interface UDimValue {
  __t: "UDim";
  s: number;
  o: number;
}

export interface UDim2Value {
  __t: "UDim2";
  xs: number;
  xo: number;
  ys: number;
  yo: number;
}

export interface Vector2Value {
  __t: "Vector2";
  x: number;
  y: number;
}

export interface Color3Value {
  __t: "Color3";
  r: number;
  g: number;
  b: number;
}

export interface ColorSequenceValue {
  __t: "ColorSequence";
  a: Color3Value;
  b: Color3Value;
}

export interface EnumValue {
  __t: "Enum";
  e: string;
  v: string;
}

export type Tagged = UDimValue | UDim2Value | Vector2Value | Color3Value | ColorSequenceValue | EnumValue;
export type PropValue = string | number | boolean | Tagged;

export interface UiNode {
  class: string;
  name?: string;
  props: Record<string, PropValue | undefined>;
  children: UiNode[];
}

export interface Scene {
  width: number;
  height: number;
  root: UiNode;
}

export interface SceneInfo {
  name: string;
  width: number;
  height: number;
  scale: number;
}
