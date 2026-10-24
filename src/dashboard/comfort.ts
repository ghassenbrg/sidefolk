import { SPECIES } from "../pet/look";
import type { Look, Settings } from "./api";

// Comfort presets (creative-design/APP-UX.md, "Choose your comfort"). A preset only suggests:
// every change is listed, can be unticked, and nothing is applied before "Apply". Looks never
// change what an AI tool may do.

export type Comfort = Settings["comfort"];

export type Suggestion = { key: string; label: string; change: Partial<Settings> };

export const PRESETS: Record<Comfort, { label: string; who: string; describe: string; look: Look; name: string; settings: Suggestion[] }> = {
  friendly: {
    label: "Friendly",
    who: "Pip",
    describe: "Warm and expressive",
    name: "Pip",
    look: { species: "bunny", palette: "snow", accessory: "none", style: "soft" },
    settings: [],
  },
  professional: {
    label: "Professional",
    who: "Slate",
    describe: "Quiet and composed",
    name: "Slate",
    look: { species: "penguin", palette: "charcoal", accessory: "none", style: "soft" },
    settings: [
      { key: "calm", label: "Reduce motion", change: { calm: true } },
      { key: "sounds", label: "Sound cues off", change: { sounds: false } },
      { key: "presence", label: "Companions come out only when needed", change: { presence: "needed" } },
      { key: "detail", label: "Cards show project and status, not commands", change: { detail: "project" } },
    ],
  },
  minimal: {
    label: "Minimal",
    who: "Dot",
    describe: "Simple and discreet",
    name: "Dot",
    look: { species: "capsule", palette: "snow", accessory: "none", style: "soft" },
    settings: [
      { key: "calm", label: "Reduce motion", change: { calm: true } },
      { key: "sounds", label: "Sound cues off", change: { sounds: false } },
      { key: "presence", label: "Menu bar only: no companion on the desktop", change: { presence: "menubar" } },
      { key: "detail", label: "Notifications show project and status, not commands", change: { detail: "project" } },
    ],
  },
};

/** The preset's own character exists in this build (Slate and Dot need their models). */
export const lookAvailable = (look: Look) => look.species in SPECIES;

/** Suggestions that would actually change something. */
export function suggestions(preset: Comfort, settings: Settings): Suggestion[] {
  return PRESETS[preset].settings.filter((s) => Object.entries(s.change).some(([k, v]) => settings[k as keyof Settings] !== v));
}
