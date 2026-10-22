export const DEFAULT_PET_SHORTCUT = "CommandOrControl+Shift+Space";
export const PET_SIZE = { width: 290, height: 330 };
export type Point = { x: number; y: number };
export type Area = Point & { width: number; height: number };

export function validPetShortcut(value: string): boolean {
  const parts = value.split("+");
  const key = parts.pop() ?? "";
  return (
    parts.length > 0 &&
    parts.length <= 4 &&
    parts.every((p) =>
      /^(?:CommandOrControl|CmdOrCtrl|Command|Cmd|Control|Ctrl|Alt|Option|Shift|Super|Meta)$/i.test(
        p,
      ),
    ) &&
    parts.some((p) => !/^Shift$/i.test(p)) &&
    /^(?:Space|Enter|Return|[A-Z0-9]|F(?:[1-9]|1\d|2[0-4]))$/i.test(key)
  );
}
export function shortcutLabel(value: string, mac: boolean): string {
  return value
    .split("+")
    .map((p) => {
      if (/^(?:CommandOrControl|CmdOrCtrl)$/i.test(p))
        return mac ? "⌘" : "Ctrl";
      if (/^(?:Command|Cmd|Meta|Super)$/i.test(p)) return mac ? "⌘" : "Win";
      if (/^(?:Control|Ctrl)$/i.test(p)) return mac ? "⌃" : "Ctrl";
      if (/^(?:Option|Alt)$/i.test(p)) return mac ? "⌥" : "Alt";
      if (/^Shift$/i.test(p)) return mac ? "⇧" : "Shift";
      return p;
    })
    .join(mac ? "" : "+");
}
export function clampPetPosition(point: Point, area: Area): Point {
  return {
    x: Math.round(
      Math.max(area.x, Math.min(point.x, area.x + area.width - PET_SIZE.width)),
    ),
    y: Math.round(
      Math.max(
        area.y,
        Math.min(point.y, area.y + area.height - PET_SIZE.height),
      ),
    ),
  };
}
export function summonedPetPosition(cursor: Point, area: Area): Point {
  return clampPetPosition(
    { x: cursor.x + 20, y: cursor.y - PET_SIZE.height / 2 },
    area,
  );
}
