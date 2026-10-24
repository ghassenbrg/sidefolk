import { exportSheet, importCharacter, POSES, resolvePose, type Imported, type Pose } from "../character-import";
import { invoke } from "./api";
import type { App } from "./app";
import { button, h } from "./dom";
import { back, header } from "./ui";

// Characters: make your own companion from a picture. Fill in the template (or use one picture),
// import it, check every pose, save. It can then be Pip's look or a Spark's. All on this Mac;
// each character is a folder you can copy to a friend.

export type Character = { id: string; name: string; poses: string[] };

/** Ready-to-paste brief for an image tool, matching the template's boxes and order. */
export const PROMPT =
  "Fill in this character sheet template with my character, one pose per box, in this order (left to right, top to bottom): idle, blink (eyes closed), listen (head tilted), think (hand at chin), work1 and work2 (busy, e.g. with a laptop), alert (one hand raised), sad, note (holding a note card), write1 and write2 (writing on it), done (happy, arms up), wave, sit, sleep (sitting, eyes closed), dangle (being held up, arms up). Same character, same size and style in every box, feet on the dashed line, fully inside the box, facing the viewer. Plain white background, no shadows, no text, no extra objects.";

let cached: Character[] | null = null;
/** The last list read, for pickers that draw at once (empty until the first read). */
export const cachedCharacters = () => cached ?? [];
export async function characters(refresh = false) {
  if (!cached || refresh) cached = await invoke<Character[]>("list_characters").catch(() => []);
  return cached;
}

let draft: { imported: Imported; layout: "sheet" | "single" } | null = null;

export function renderCharacters(app: App) {
  const view = h("div", { class: "view characters" }, back("Settings", () => app.go("settings", "companion")), ...header("Characters", "Make your own companion from a picture: fill in the template, or start with a single drawing. Everything happens on this Mac."));
  app.live(() => {});
  const mine = h("section", { "aria-label": "Your characters" });
  const fillMine = async () => {
    const list = await characters(true);
    mine.replaceChildren(
      h("h2", { class: "section-title", text: "Your characters" }),
      list.length
        ? h("div", { class: "card list" }, ...list.map((c) => characterRow(app, c, fillMine)))
        : h("p", { class: "muted", text: "None yet. Make one below; it takes a picture and a minute." }),
    );
  };
  void fillMine();
  view.append(mine, maker(app, fillMine));
  return view;
}

function characterRow(app: App, c: Character, refill: () => Promise<void>) {
  const thumb = h("img", { class: "character-thumb", alt: "", width: 63, height: 57 });
  void invoke<Record<string, string>>("character_frames", { id: c.id }).then((f) => (thumb.src = f.idle ?? ""));
  return h(
    "div",
    { class: "row line" },
    h("div", { class: "inline" }, thumb, h("div", { class: "identity-text" }, h("strong", { text: c.name }), h("span", { class: "meta", text: `${c.poses.length} of 16 poses` }))),
    h(
      "div",
      { class: "inline" },
      button("Use for Pip", () => void app.petAction({ action: "look", look: c.id }, `${app.state.crew.main.name} looks like ${c.name} now.`), "small"),
      button("Export", async () => {
        try {
          const frames = await invoke<Record<string, string>>("character_frames", { id: c.id });
          app.toast(await invoke<string>("save_template", { png: await exportSheet(frames), name: c.name }));
        } catch (error) {
          app.toast(String(error), undefined, true);
        }
      }, "small", { title: "One picture in the template's layout: send it to someone and they import it as it is." }),
      button("Delete…", () =>
        app.toast(`Delete ${c.name}? Companions using it go back to their usual look.`, {
          label: "Delete",
          run: () => void invoke("delete_character", { id: c.id }).then(refill, (e) => app.toast(String(e), undefined, true)),
        }), "small"),
    ),
  );
}

function maker(app: App, refill: () => Promise<void>) {
  const box = h("section", { class: "card maker", "aria-label": "Make a character" });
  const preview = h("div", { class: "pose-grid", "aria-live": "polite" });
  const notes = h("ul", { class: "warnings" });
  const name = h("input", { type: "text", id: "character-name", maxlength: 24, autocomplete: "off", placeholder: "Bun" });
  const save = h("button", { type: "submit", class: "primary", text: "Save character", disabled: true });
  const file = h("input", { type: "file", id: "character-file", accept: "image/png,image/jpeg,image/webp" });
  const outline = h("input", { type: "checkbox", id: "character-outline", checked: true });
  const layout = h("select", { id: "character-layout" }, h("option", { value: "sheet", text: "The template (up to 16 poses)" }), h("option", { value: "single", text: "One picture (just standing)" }));

  const show = () => {
    preview.replaceChildren();
    notes.replaceChildren();
    if (!draft) return;
    const have = new Set(Object.keys(draft.imported.frames));
    for (const pose of POSES) {
      const own = draft.imported.frames[pose];
      const src = own ?? draft.imported.frames[resolvePose(have, pose as Pose)];
      preview.append(h("figure", { class: own ? "" : "borrowed" }, src ? h("img", { src, alt: `${pose}${own ? "" : " (borrowed)"}` }) : h("span"), h("figcaption", { text: own ? pose : `${pose} · borrows` })));
    }
    for (const w of draft.imported.warnings) notes.append(h("li", { text: w }));
    save.disabled = !draft.imported.frames.idle;
  };
  const read = async () => {
    const chosen = file.files?.[0];
    if (!chosen) return;
    const url = URL.createObjectURL(chosen);
    try {
      const image = new Image();
      image.src = url;
      await image.decode();
      draft = { imported: await importCharacter(image, layout.value as "sheet" | "single", outline.checked), layout: layout.value as "sheet" | "single" };
      if (!name.value) name.value = chosen.name.replace(/\.[a-z]+$/i, "").replace(/[-_]+/g, " ").slice(0, 24);
      show();
    } catch {
      app.toast("That file couldn't be read as a picture.", undefined, true);
    } finally {
      URL.revokeObjectURL(url);
    }
  };
  // A sheet exported from Sidefolk already has its outline.
  file.addEventListener("change", () => {
    if (file.files?.[0]?.name.endsWith(".sidefolk.png")) outline.checked = false;
    void read();
  });
  outline.addEventListener("change", () => void read());
  layout.addEventListener("change", () => void read());

  const form = h(
    "form",
    {},
    h("div", { class: "form-grid" }, h("div", { class: "field wide" }, h("label", { for: file.id, text: "Your picture" }), file), h("div", { class: "field" }, h("label", { for: layout.id, text: "It is" }), layout)),
    h("label", { class: "inline check", for: outline.id }, outline, " Light outline (keeps it visible on dark wallpapers)"),
    preview,
    notes,
    h("div", { class: "form-grid" }, h("div", { class: "field" }, h("label", { for: name.id, text: "Name" }), name)),
    h("div", { class: "actions" }, save),
  );
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (!draft) return;
    try {
      const c = await invoke<Character>("save_character", { name: name.value || "My character", frames: draft.imported.frames });
      draft = null;
      file.value = "";
      show();
      app.toast(`${c.name} is saved.`, { label: "Use for Pip", run: () => void app.petAction({ action: "look", look: c.id }, `${app.state.crew.main.name} looks like ${c.name} now.`) });
      await refill();
    } catch (error) {
      app.toast(String(error), undefined, true);
    }
  });

  box.append(
    h("h2", { text: "Make a character" }),
    h(
      "ol",
      { class: "steps" },
      h("li", {}, h("strong", { text: "Get the template. " }), "Sixteen boxes, one per pose, with a line for the feet. Only the first box (idle) is needed; empty boxes borrow from the others. ", button("Save template to Downloads", () => void saveTemplate(app), "small")),
      h("li", {}, h("strong", { text: "Draw, paint or generate. " }), "Any app works. With an image AI, attach the template and paste this: ", button("Copy prompt", () => void navigator.clipboard.writeText(PROMPT).then(() => app.toast("Prompt copied.")), "small")),
      h("li", {}, h("strong", { text: "Import it here " }), "and check every pose on light and dark before saving."),
    ),
    form,
  );
  if (draft) show();
  return box;
}

async function saveTemplate(app: App) {
  try {
    const blob = await (await fetch("/character-template.png")).blob();
    const data = await new Promise<string>((resolve) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.readAsDataURL(blob);
    });
    app.toast(await invoke<string>("save_template", { png: data }));
  } catch (error) {
    app.toast(String(error), undefined, true);
  }
}
