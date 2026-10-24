import { describe } from "../describe";
import { icon } from "../icons";
import { ACCESSORIES, ACCESSORY_NAMES, CUSTOM, normalizeLook, PALETTE_NAMES, PALETTES, SPECIES, STYLE_NAMES, STYLES } from "../pet/look";
import { ROSTER } from "../routing";
import { PRESETS } from "./comfort";
import { badge, type State } from "../states";
import { invoke, type Look, type PetStatus } from "./api";
import type { App } from "./app";
import { agentShort, button, folder, h } from "./dom";
import { LivePreview, portraitImage } from "./portrait";
import { back, empty, header, petLine, petState, sessionLabel, sessionOf } from "./ui";

// Crew: every companion with its project and status (resting ones included), and a page per
// companion for its appearance, name and project. Changing the look never touches its name,
// project or work sessions.

const FILTERS: [string, string, (s: State) => boolean][] = [
  ["all", "All", () => true],
  ["needs", "Needs you", (s) => s === "alert"],
  ["resting", "Resting", (s) => s === "resting"],
];
let filter = "all";

export function renderCrew(app: App) {
  const { status } = app.state;
  const view = h("div", { class: "view" }, ...header("Your crew", "A familiar face for each project."));
  const group = h("div", { class: "segmented", role: "radiogroup", "aria-label": "Show" });
  for (const [key, label] of FILTERS)
    group.append(
      button(label, () => {
        filter = key;
        app.redraw(true);
      }, "", { role: "radio", "aria-checked": String(filter === key) }),
    );
  view.append(h("div", { class: "toolbar" }, group, button([icon("plus"), "Add a companion for a project…"], () => void addForProject(app), "primary")));

  const test = FILTERS.find(([key]) => key === filter)![2];
  const rows = status.pets.filter((p) => test(petState(p, status.waiting)));
  const list = h("section", { class: "card list roster", "aria-label": "Companions" });
  for (const pet of rows) {
    const state = petState(pet, status.waiting);
    list.append(
      button(
        [
          portraitImage(pet.look, "", "avatar large"),
          h("span", { class: "roster-text" }, h("strong", { text: pet.name }), h("span", { class: "meta", text: pet.main ? "Main companion · everything else" : pet.project ? folder(pet.project) : "A work session" })),
          badge(state),
          icon("chevron"),
        ],
        () => app.go("pet", pet.id),
        "roster-row",
        { "aria-label": `${pet.name}, ${pet.main ? "main companion" : pet.project ? folder(pet.project) : "work session"}, ${state === "alert" ? "needs you" : state}` },
      ),
    );
  }
  if (!rows.length) list.append(h("p", { class: "muted", text: filter === "needs" ? "Nobody needs you right now." : "Nobody is resting right now." }));
  view.append(list);
  view.append(h("p", { class: "hint", text: "Resting companions stay out of the way and come back when their project needs you." }));
  return view;
}

async function addForProject(app: App) {
  const project = await invoke<string | null>("pick_project").catch((error) => (app.toast(String(error), undefined, true), null));
  if (!project) return;
  // The chosen folder is confirmed before anything changes.
  pendingProject = { pet: "new", project };
  app.go("pet", "new");
}

/** A project picked but not yet confirmed: for a new companion, or to move one. */
let pendingProject: { pet: string; project: string } | null = null;
/** Unsaved appearance changes per companion, kept across live redraws. */
const drafts = new Map<string, Look>();
let removing: string | null = null;

function lookOf(app: App, id: string): Look | null {
  if (id === "main") return app.state.crew.main.look;
  return app.state.crew.pets.find((p) => p.id === id)?.look ?? null;
}

export function renderPet(app: App, id: string) {
  if (id === "new") return renderNew(app);
  const pet = app.state.status.pets.find((p) => p.id === id);
  const saved = lookOf(app, id);
  const view = h("div", { class: "view pet-page" }, back("Back to crew", () => app.go("crew")));
  if (!pet || !saved) {
    view.append(empty("This companion is gone.", "It may have been removed from your crew.", button("Back to crew", () => app.go("crew"))));
    return view;
  }
  view.append(...header(pet.name, pet.main ? "Main companion. It speaks for every project without a companion of its own." : `Looks after ${pet.project ? folder(pet.project) : "one work session"}.`));

  // Status: updated live without rebuilding the previews below.
  const status = h("section", { class: "card", "aria-label": "Status" });
  const fillStatus = () => {
    const now = app.state.status.pets.find((p) => p.id === id);
    if (!now) return app.redraw(true);
    status.replaceChildren(...statusCard(app, now));
  };
  fillStatus();
  app.live(fillStatus);
  view.append(status);

  view.append(appearance(app, pet, saved));
  view.append(nameCard(app, pet));
  if (!pet.main) view.append(projectCard(app, pet), removeCard(app, pet));
  return view;
}

function statusCard(app: App, pet: PetStatus) {
  const state = petState(pet, app.state.status.waiting);
  const session = sessionOf(pet);
  const nodes: HTMLElement[] = [h("div", { class: "row" }, h("h2", { text: "Right now" }), badge(state)), h("p", { text: petLine(pet) })];
  if (pet.sessions.length > 1) {
    const list = h("ul", { class: "sessions" });
    for (const s of pet.sessions)
      list.append(
        h(
          "li",
          {},
          h("span", { text: `${agentShort(s.source)} · ${sessionLabel(s.id)} · ${s.verb}` }),
          s.id ? button("Open", () => void app.openSession({ source: s.source, session: s.id, cwd: s.cwd || s.project }), "small") : null,
        ),
      );
    nodes.push(list);
  }
  const actions = h("div", { class: "actions" });
  if (session)
    actions.append(
      button([icon(session.live ? "open" : "terminal"), session.live ? `Open ${agentShort(session.source)} session` : `Continue in ${agentShort(session.source)}`], () => void app.openSession(session), "primary"),
    );
  if (!pet.main)
    actions.append(
      pet.out
        ? button("Send home", () => void app.petAction({ action: "run", id: pet.id, text: `send ${pet.name} home` }, `${pet.name} is going back to rest.`))
        : button("Call to the desktop", () => void app.petAction({ action: "call", id: pet.id }, `${pet.name} is coming.`)),
    );
  if (session?.live) actions.append(button("Continue in a new terminal", () => void app.openSession(session, true), "quiet"));
  nodes.push(actions);
  return nodes;
}

/** Character first, then art style, coat and extra, with idle and "needs you" previews. */
function appearance(app: App, pet: PetStatus, saved: Look) {
  const draft = drafts.get(pet.id) ?? saved;
  const changed = JSON.stringify(draft) !== JSON.stringify(saved);
  const set = (change: Partial<Look>) => {
    drafts.set(pet.id, normalizeLook({ ...draft, ...change }) as Look);
    app.redraw(true);
  };
  const card = h("section", { class: "card appearance", "aria-labelledby": "appearance-title" }, h("h2", { id: "appearance-title", text: "Appearance" }));
  card.append(h("p", { class: "muted", text: "Looks change. The name, project and work sessions stay connected." }));

  const previews = h("div", { class: "previews" });
  for (const [clip, label] of [
    ["idle", "Idle"],
    ["alert", "Needs you"],
  ] as const) {
    const canvas = h("canvas", { width: 160, height: 180, "aria-hidden": "true" });
    previews.append(h("figure", {}, canvas, h("figcaption", {}, badge(clip === "idle" ? "idle" : "alert"), h("span", { class: "sr", text: `${label} preview` }))));
    const live = new LivePreview(canvas, clip);
    void live.show(draft).catch(() => canvas.classList.add("missing"));
    app.onLeave(() => live.stop());
  }
  card.append(previews);

  const choice = (legend: string, options: { value: string; label: string; small?: string; extra?: Node; disabled?: string }[], selected: string, pick: (v: string) => void, className = "") => {
    const group = h("div", { class: `choices ${className}`, role: "radiogroup", "aria-label": legend });
    for (const o of options) {
      const b = button(
        [o.extra ?? null, h("span", { text: o.label }), o.disabled || o.small ? h("small", { text: o.disabled ?? o.small }) : null],
        () => pick(o.value),
        "choice",
        { role: "radio", "aria-checked": String(o.value === selected), disabled: !!o.disabled, "aria-disabled": o.disabled ? "true" : undefined },
      );
      group.append(b);
    }
    return h("div", { class: "fieldset" }, h("span", { class: "legend", text: legend }), group);
  };

  // Character first: each one in its designed look. Picking one starts from that look; the
  // companion keeps its own name, project and work sessions.
  const models = customModels.get() ?? [];
  const characters = [{ name: "Pip", look: PRESETS.friendly.look }, ...Object.values(ROSTER)];
  card.append(
    choice(
      "Character",
      [
        ...characters.map((c) => ({ value: c.name, label: c.name, small: SPECIES[c.look.species as keyof typeof SPECIES]?.label, extra: portraitImage(c.look, "", "thumb") })),
        ...models.map((m) => ({ value: CUSTOM + m, label: m.replace(/\.glb$/, ""), small: "Imported", extra: portraitImage({ ...draft, species: CUSTOM + m }, "", "thumb") })),
      ],
      characters.find((c) => c.look.species === draft.species)?.name ?? draft.species,
      (value) => {
        const c = characters.find((x) => x.name === value);
        set(c ? c.look : { species: value });
      },
      "characters",
    ),
    // The same character in each art family; name, project and status stay the same.
    choice(
      "Art style",
      STYLE_NAMES.map((n) => ({ value: n as string, label: STYLES[n].label, extra: portraitImage({ ...draft, style: n }, "", "thumb") })),
      draft.style ?? "soft",
      (style) => set({ style }),
      "characters",
    ),
    choice(
      "Coat",
      PALETTE_NAMES.map((n) => ({ value: n as string, label: PALETTES[n].label, extra: h("span", { class: "swatch", style: `background:${PALETTES[n].body};border-color:${PALETTES[n].points}` }) })),
      draft.palette,
      (palette) => set({ palette }),
      "coats",
    ),
    choice(
      "Extra",
      ACCESSORY_NAMES.map((n) => ({ value: n as string, label: ACCESSORIES[n] })),
      draft.accessory,
      (accessory) => set({ accessory }),
    ),
  );

  const actions = h(
    "div",
    { class: "actions" },
    button(
      "Save appearance",
      async () => {
        if (await app.petAction({ action: "look", id: pet.id, look: draft }, `${pet.name}'s new look is saved.`)) {
          drafts.delete(pet.id);
          setTimeout(() => void app.refresh(), 400);
        }
      },
      "primary",
      { disabled: !changed },
    ),
    changed ? button("Undo changes", () => (drafts.delete(pet.id), app.redraw(true)), "quiet") : null,
  );
  card.append(actions);

  // Other ways to pick a look: words (local), a photo (asks Claude), a 3D model file.
  const words = h("input", { type: "text", id: "describe", placeholder: "A sleepy charcoal cat with glasses", autocomplete: "off" });
  const wordsError = h("p", { class: "field-error", id: "describe-error", role: "alert" });
  words.setAttribute("aria-describedby", "describe-error");
  const more = h(
    "details",
    { class: "more" },
    h("summary", { text: "Other ways to choose a look" }),
    h("label", { for: "describe", text: "Describe it in a few words" }),
    h(
      "div",
      { class: "inline" },
      words,
      button("Try these words", () => {
        const change = describe(words.value);
        if (!Object.keys(change).length) return void (wordsError.textContent = "Try a color and an animal, like “a black cat with glasses”.");
        set(change as Partial<Look>);
      }),
    ),
    wordsError,
    h("div", { class: "row" }, h("div", {}, h("strong", { text: "From a photo" }), h("p", { class: "muted", text: "Claude (Haiku) looks at one photo and suggests a coat and extra. Uses a little of your Claude quota." })), button("Choose a photo…", () => void fromPhoto(app, pet.id, draft))),
    h("div", { class: "row" }, h("div", {}, h("strong", { text: "A 3D model of your own" }), h("p", { class: "muted", text: "A .glb file made for Sidefolk (see docs/CREATORS.md). It's checked before it's used." })), button("Import a model…", () => void importModel(app, pet.id, draft))),
  );
  card.append(more);
  return card;
}

const customModels = (() => {
  let list: string[] | null = null;
  return {
    get: () => {
      if (list === null) {
        list = [];
        void invoke<string[]>("list_models").then((m) => (list = m)).catch(() => {});
      }
      return list;
    },
    reset: () => (list = null),
  };
})();

async function fromPhoto(app: App, id: string, draft: Look) {
  try {
    app.toast("Asking Claude to look at the photo…");
    const json = await invoke<string | null>("describe_photo");
    if (!json) return;
    // The model's answer is untrusted; keep only valid settings it named.
    const named = JSON.parse(json) as Record<string, unknown>;
    const valid = normalizeLook(named);
    const change = Object.fromEntries(Object.entries(valid).filter(([key, value]) => named[key] === value));
    drafts.set(id, normalizeLook({ ...draft, ...change }) as Look);
    app.toast(Object.keys(change).length ? "Here's a suggestion. Save it if you like it." : "Claude couldn't suggest a look from that photo.");
    app.redraw(true);
  } catch (error) {
    app.toast(String(error), undefined, true);
  }
}

async function importModel(app: App, id: string, draft: Look) {
  try {
    const name = await invoke<string | null>("import_model");
    if (!name) return;
    customModels.reset();
    drafts.set(id, { ...draft, species: CUSTOM + name });
    app.redraw(true);
  } catch (error) {
    app.toast(`That model doesn't fit: ${error}`, undefined, true);
  }
}

function nameCard(app: App, pet: PetStatus) {
  const field = h("input", { type: "text", id: "pet-name", value: pet.name, maxlength: 24, autocomplete: "off", "aria-describedby": "pet-name-error" });
  const error = h("p", { class: "field-error", id: "pet-name-error", role: "alert" });
  const form = h(
    "form",
    { class: "card" },
    h("h2", { text: "Name" }),
    h("label", { for: "pet-name", text: "What should this companion be called?" }),
    h("div", { class: "inline" }, field, h("button", { type: "submit", text: "Save name" })),
    error,
  );
  form.addEventListener("submit", (event) => {
    event.preventDefault();
    const name = field.value.replace(/\s+/g, " ").trim();
    const taken = app.state.status.pets.some((p) => p.id !== pet.id && p.name.toLowerCase() === name.toLowerCase());
    error.textContent = !name ? "Enter a name." : taken ? `${name} is already in your crew.` : "";
    if (error.textContent || name === pet.name) return;
    void app.petAction({ action: "rename", id: pet.id, name }, `Renamed to ${name}.`).then(() => setTimeout(() => void app.refresh(), 400));
    field.blur();
  });
  return form;
}

function projectCard(app: App, pet: PetStatus) {
  const pending = pendingProject?.pet === pet.id ? pendingProject.project : null;
  const card = h("section", { class: "card" }, h("h2", { text: "Project this companion looks after" }));
  card.append(h("p", { class: "path", text: pet.project ?? "One work session (it leaves when the session ends)" }));
  if (pending) {
    card.append(
      h("p", { text: `Move ${pet.name} to ${pending}? Work from that folder will come to ${pet.name}.` }),
      h(
        "div",
        { class: "actions" },
        button("Cancel", () => ((pendingProject = null), app.redraw(true))),
        button(`Move to ${folder(pending)}`, async () => {
          pendingProject = null;
          await app.petAction({ action: "assign", id: pet.id, project: pending }, `${pet.name} now looks after ${folder(pending)}.`);
          setTimeout(() => void app.refresh(), 400);
        }, "primary"),
      ),
    );
  } else
    card.append(
      h(
        "div",
        { class: "actions" },
        button([icon("folder"), "Change project…"], async () => {
          const project = await invoke<string | null>("pick_project").catch(() => null);
          if (!project) return;
          pendingProject = { pet: pet.id, project };
          app.redraw(true);
        }),
      ),
    );
  return card;
}

function removeCard(app: App, pet: PetStatus) {
  const main = app.state.crew.main.name;
  const card = h("section", { class: "card" }, h("h2", { text: "Remove from your crew" }));
  if (removing !== pet.id) {
    card.append(h("p", { class: "muted", text: `${pet.project ? `${folder(pet.project)}'s` : "Its"} work goes back to ${main}. Your projects and sessions don't change.` }), h("div", { class: "actions" }, button(`Remove ${pet.name}…`, () => ((removing = pet.id), app.redraw(true)))));
    return card;
  }
  card.append(
    h("p", { text: `Remove ${pet.name}? ${main} will speak for ${pet.project ? folder(pet.project) : "its work"} instead. You can add a new companion later.` }),
    h(
      "div",
      { class: "actions" },
      button(`Keep ${pet.name}`, () => ((removing = null), app.redraw(true))),
      button(`Remove ${pet.name}`, async () => {
        removing = null;
        await app.petAction({ action: "forget", id: pet.id }, `${pet.name} was removed from your crew.`);
        setTimeout(() => void app.refresh(), 400);
        app.go("crew");
      }),
    ),
  );
  return card;
}

/** Confirms the folder picked for a new companion. */
function renderNew(app: App) {
  const view = h("div", { class: "view" }, back("Back to crew", () => app.go("crew")));
  const project = pendingProject?.pet === "new" ? pendingProject.project : null;
  if (!project) {
    view.append(...header("Add a companion"), empty("No folder chosen.", "Choose the project folder this companion should look after.", button("Choose a folder…", () => void addForProject(app), "primary")));
    return view;
  }
  view.append(
    ...header("Add a companion", "It comes out when this project needs you and rests otherwise."),
    h(
      "section",
      { class: "card" },
      h("h2", { text: "Project folder" }),
      h("p", { class: "path", text: project }),
      h(
        "div",
        { class: "actions" },
        button("Choose another folder…", () => void addForProject(app)),
        button(`Add a companion for ${folder(project)}`, async () => {
          pendingProject = null;
          await app.petAction({ action: "create", project }, `A companion for ${folder(project)} is on its way.`);
          setTimeout(() => void app.refresh(), 600);
          app.go("crew");
        }, "primary"),
      ),
    ),
  );
  return view;
}
