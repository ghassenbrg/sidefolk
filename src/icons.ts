// Line icons (24 px grid, drawn with currentColor) and the Pip Signal mark. Static markup only:
// nothing here ever contains agent or user text.

const PATHS = {
  more: '<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
  home: '<path d="M3.5 10.5 12 3.5l8.5 7V20a1 1 0 0 1-1 1H15v-6.5H9V21H4.5a1 1 0 0 1-1-1z"/>',
  requests: '<path d="M20.5 15a2 2 0 0 1-2 2H8l-4.5 3.5V5.5a2 2 0 0 1 2-2h13a2 2 0 0 1 2 2z"/>',
  crew: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20a6.5 6.5 0 0 1 13 0M16 4.5a3.5 3.5 0 0 1 0 7M18 14a6.5 6.5 0 0 1 3.5 6"/>',
  reminders: '<path d="M6 9a6 6 0 0 1 12 0c0 6.5 2.5 8 2.5 8h-17S6 15.5 6 9M10.3 20.5a2 2 0 0 0 3.4 0"/>',
  notes: '<path d="M6 3.5h11.5a1 1 0 0 1 1 1v15a1 1 0 0 1-1 1H6a1.5 1.5 0 0 1-1.5-1.5v-14A1.5 1.5 0 0 1 6 3.5zM9 8.5h6M9 12h6M9 15.5h3.5"/>',
  settings: '<path d="M4 6.5h9M17 6.5h3M4 12h3M11 12h9M4 17.5h11M19 17.5h1"/><circle cx="15" cy="6.5" r="2"/><circle cx="9" cy="12" r="2"/><circle cx="17" cy="17.5" r="2"/>',
  back: '<path d="M19 12H5m6 6-6-6 6-6"/>',
  next: '<path d="M5 12h14m-6-6 6 6-6 6"/>',
  chevron: '<path d="m9 6 6 6-6 6"/>',
  copy: '<rect x="9" y="9" width="11.5" height="11.5" rx="2"/><path d="M5.5 15H5a1.5 1.5 0 0 1-1.5-1.5V5A1.5 1.5 0 0 1 5 3.5h8.5A1.5 1.5 0 0 1 15 5v.5"/>',
  open: '<path d="M14 4h6v6M20 4l-9 9M18 14v5a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h5"/>',
  terminal: '<rect x="3" y="4.5" width="18" height="15" rx="2"/><path d="m7 9.5 3 2.5-3 2.5M12.5 15h4.5"/>',
  folder: '<path d="M3.5 7a2 2 0 0 1 2-2h3.5l2 2h7.5a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  activity: '<path d="M3 12h4l3 7 4-14 3 7h4"/>',
  info: '<circle cx="12" cy="12" r="9"/><path d="M12 11v5.5M12 7.8v.1"/>',
  // Status glyphs: one shape per state, so color is never the only cue.
  idle: '<circle cx="12" cy="12" r="5.5"/>',
  think: '<path d="M6.5 12h.1M12 12h.1M17.5 12h.1" stroke-width="3.2"/>',
  work: '<circle cx="12" cy="12" r="3.2"/><path d="M12 3.5v3M12 17.5v3M3.5 12h3M17.5 12h3M6 6l2.1 2.1M15.9 15.9 18 18M6 18l2.1-2.1M15.9 8.1 18 6"/>',
  alert: '<path d="M12 5v9M12 18.5v.1" stroke-width="3.2"/>',
  done: '<path d="m5 12.5 4.5 4.5L19 7.5" stroke-width="3"/>',
  failed: '<path d="m7 7 10 10M17 7 7 17" stroke-width="3"/>',
  sleep: '<path d="M19.5 14.5A7.5 7.5 0 1 1 9.5 4.5a6 6 0 0 0 10 10z" fill="currentColor"/>',
} as const;

export type IconName = keyof typeof PATHS;

export function icon(name: IconName, className = "icon"): SVGSVGElement {
  const holder = document.createElement("span");
  holder.innerHTML = `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${PATHS[name]}</svg>`;
  const svg = holder.firstElementChild as SVGSVGElement;
  svg.setAttribute("class", className);
  return svg;
}

/** Pip Signal (scripts/make_icons.py): the bunny head follows the ink color, so it works in both themes. */
export function mark(size: number, label = "Sidefolk"): SVGSVGElement {
  const holder = document.createElement("span");
  holder.innerHTML = `<svg class="mark" viewBox="0 0 100 100" width="${size}" height="${size}" role="img" aria-label="${label}">
    <g fill="currentColor">
      <ellipse cx="37" cy="33" rx="10.5" ry="25" transform="rotate(-9 37 33)"/>
      <ellipse cx="63.5" cy="36" rx="10" ry="22" transform="rotate(9 63.5 36)"/>
      <ellipse cx="50" cy="67" rx="33" ry="24.5"/>
    </g>
    <g class="eyes"><circle cx="40" cy="65" r="3.6"/><circle cx="60" cy="65" r="3.6"/></g>
    <circle class="signal" cx="86" cy="17" r="7.5"/>
  </svg>`;
  return holder.firstElementChild as SVGSVGElement;
}
