import { folder } from "./agents";
import type { Companion } from "./companion";
import { Familiar } from "./familiar";
import { COLORS, colorName } from "./worker-colors";

// Spark workers: a companion per project you choose ("give api a spark"), in its own color with
// the project's name under its feet. It acts out that project's sessions and brings their
// requests; everything else stays with Pip. Nothing appears on its own.

export type WorkerSpec = { project: string; name: string; hue: number };

const MAX = 6;
/** Space between companions standing side by side, in CSS pixels. */
const GAP = 150;

export class Workers {
  specs: WorkerSpec[] = [];

  constructor(
    private readonly companion: Companion,
    private readonly zoom: number,
    /** "spark" once Spark's frames are there, else a recolored Pip. */
    private readonly character: string,
    private readonly save: (specs: WorkerSpec[]) => Promise<unknown>,
  ) {}

  async load(specs: WorkerSpec[]) {
    for (const spec of specs.slice(0, MAX)) await this.place(spec);
  }

  /** Gives a project (a folder path) its Spark; a second call renames or recolors it. */
  async add(project: string, name?: string, hue?: number): Promise<string> {
    const existing = this.specs.find((s) => s.project === project);
    if (!existing && this.specs.length >= MAX) return `That's ${MAX} Sparks already. Remove one first.`;
    // Mint is Pip's own color: a new Spark takes the first color nobody wears yet.
    const used = new Set([0, ...this.specs.map((s) => s.hue)]);
    const spec: WorkerSpec = {
      project,
      name: (name ?? existing?.name ?? "Spark").replace(/\s+/g, " ").trim().slice(0, 24) || "Spark",
      hue: hue ?? existing?.hue ?? (COLORS.find(([, h]) => !used.has(h)) ?? COLORS[0])[1],
    };
    if (existing) this.companion.removeWorker(project);
    this.specs = [...this.specs.filter((s) => s.project !== project), spec];
    await this.place(spec);
    await this.save(this.specs);
    return existing ? `${spec.name} for ${folder(project)} is updated.` : `${spec.name} looks after ${folder(project)} now (${colorName(spec.hue).toLowerCase()}).`;
  }

  async remove(project: string): Promise<string> {
    const spec = this.specs.find((s) => s.project === project || folder(s.project).toLowerCase() === project.toLowerCase());
    if (!spec) return `There's no Spark for ${folder(project)}.`;
    this.companion.removeWorker(spec.project);
    this.specs = this.specs.filter((s) => s !== spec);
    await this.save(this.specs);
    return `${spec.name} went home. ${this.companion.name} looks after ${folder(spec.project)} again.`;
  }

  private async place(spec: WorkerSpec) {
    if (!this.specs.includes(spec)) this.specs = [...this.specs.filter((s) => s.project !== spec.project), spec];
    const worker = await Familiar.create(spec.name, this.zoom * 0.85, { character: this.character, hue: spec.hue, badge: folder(spec.project) });
    // Side by side to Pip's left, in the order they were added.
    const index = this.specs.indexOf(spec);
    const pip = this.companion.pet.mind;
    worker.mind.x = Math.max(80, pip.x - GAP * (index + 1));
    worker.mind.y = pip.y;
    worker.mind.fitBounds();
    this.companion.addWorker(spec.project, worker);
  }
}
