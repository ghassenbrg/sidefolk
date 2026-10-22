import { useState } from "react";
import { Check, Sparkles, Heart, MousePointer2 } from "lucide-react";
import { petCatalog, type PetSpecies } from "../../shared/pets";
import type { Snapshot } from "../../shared/types";
import { api } from "../api";
import Pet from "./Pet";
import { PetIllustration } from "./PetIllustration";
import type { Act } from "./ui";
export function PetGallery({ state, act }: { state: Snapshot; act: Act }) {
  const [species, setSpecies] = useState<PetSpecies>(state.settings.petSpecies),
    [style, setStyle] = useState<"2d" | "3d">(state.settings.petStyle),
    [mood, setMood] = useState<"idle" | "working" | "sleeping" | "reminder">(
      "idle",
    ),
    [saved, setSaved] = useState(false),
    [accessory, setAccessory] = useState(state.settings.petAccessory);
  const selected = petCatalog.find((p) => p.id === species)!;
  return (
    <div className="pet-studio">
      <section className="studio-preview">
        <div className="studio-preview-top">
          <span className="eyebrow">MEET YOUR NEXT SIDEKICK</span>
          <span className="pill">LIVE PREVIEW</span>
        </div>
        <div className="studio-stage">
          <Pet
            key={`${species}-${style}`}
            species={species}
            accessory={accessory}
            style={style}
            color={state.settings.color}
            mood={mood}
          />
        </div>
        <h2>{selected.name}</h2>
        <p>{selected.tag}</p>
        <span className="interaction-hint">
          <MousePointer2 size={13} />
          Click your pet for a little love
        </span>
        <div className="filter-tabs mood-tabs">
          {(["idle", "working", "reminder", "sleeping"] as const).map((m) => (
            <button
              key={m}
              aria-pressed={mood === m}
              onClick={() => setMood(m)}
            >
              {m === "idle"
                ? "Chill"
                : m === "working"
                  ? "Thinking"
                  : m === "reminder"
                    ? "Nudge"
                    : "Sleep"}
            </button>
          ))}
        </div>
        <button
          className="button primary adopt-button"
          disabled={!!state.agent}
          onClick={() =>
            void act(async () => {
              await api.settings({
                ...state.settings,
                petSpecies: species,
                petStyle: style,
                petAccessory: accessory,
              });
              setSaved(true);
            })
          }
        >
          {saved &&
          state.settings.petSpecies === species &&
          state.settings.petStyle === style &&
          state.settings.petAccessory === accessory ? (
            <>
              <Check size={17} />
              Companion updated
            </>
          ) : (
            <>
              <Heart size={17} />
              Make this my companion
            </>
          )}
        </button>
        <p className="studio-note">
          Still {state.settings.petName}. Same memories, a new look.
        </p>
      </section>
      <section className="studio-collection">
        <div className="section-toolbar">
          <div>
            <h2>
              The little collection <span className="count">6</span>
            </h2>
            <p className="muted">Pick a personality. Make it yours.</p>
          </div>
        </div>
        <div className="dimension-picker">
          <button
            aria-pressed={style === "2d"}
            onClick={() => {
              setStyle("2d");
              setSaved(false);
            }}
          >
            <strong>2D · Illustrated</strong>
            <span>Expressive ink & soft color</span>
          </button>
          <button
            aria-pressed={style === "3d"}
            onClick={() => {
              setStyle("3d");
              setSaved(false);
            }}
          >
            <strong>3D · Soft sculpt</strong>
            <span>A little more dimension</span>
          </button>
        </div>
        <div
          className="accessory-picker"
          role="group"
          aria-label="Character accessories"
        >
          {(["none", "glasses", "headphones"] as const).map((a) => (
            <button
              key={a}
              aria-pressed={accessory === a}
              onClick={() => {
                setAccessory(a);
                setSaved(false);
              }}
            >
              {a === "none"
                ? "The original"
                : a === "glasses"
                  ? "Little professor"
                  : "Lo-fi buddy"}
            </button>
          ))}
        </div>
        <div className="pet-gallery">
          {petCatalog.map((p) => (
            <button
              key={p.id}
              className={`pet-option ${species === p.id ? "selected" : ""}`}
              aria-label={`Preview ${p.name}`}
              aria-pressed={species === p.id}
              onClick={() => {
                setSpecies(p.id);
                setSaved(false);
              }}
            >
              <div className="pet-thumbnail">
                <PetIllustration
                  species={p.id}
                  accessory={accessory}
                  color={state.settings.color}
                />
              </div>
              <div>
                <strong>{p.name}</strong>
                <span>{p.id}</span>
              </div>
              {species === p.id && <Check className="pet-selected" size={16} />}
            </button>
          ))}
        </div>
        <div className="collection-note">
          <Sparkles size={18} />
          <p>
            Animated, interactive, and always your own.
            <br />
            <span>Pet interactions run locally. Zero AI tokens.</span>
          </p>
        </div>
      </section>
    </div>
  );
}
