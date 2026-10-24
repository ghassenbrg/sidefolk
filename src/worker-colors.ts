// A Spark worker's color, shared by the desktop and the window.

/** Named colors (hue turns from Spark's mint), so a worker's color is never the only label. */
export const COLORS: [string, number][] = [
  ["Mint", 0],
  ["Sky", 42],
  ["Lilac", 102],
  ["Rose", 172],
  ["Coral", -148],
  ["Amber", -123],
  ["Lime", -68],
];

export const colorName = (hue: number) => COLORS.find(([, h]) => h === hue)?.[0] ?? "Custom";
