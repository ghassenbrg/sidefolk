// Review sheets: plays a list of cues on a companion and lays the frames out in a grid that
// covers the page (for screenshots). From the console: `(await import('./sheet.js')).sheet(mochi)`.
export const CUES = [
  ['neutral', (m) => {}],
  ['happy', (m) => m.setMood('happy')],
  ['laugh', (m) => m.setMood('laugh')],
  ['surprised', (m) => m.setMood('surprised')],
  ['sad', (m) => m.setMood('sad')],
  ['angry', (m) => m.setMood('angry')],
  ['thinking', (m) => m.setState('thinking'), 2],
  ['talking', (m) => m.say('Hello there, how are you doing today?'), 0.55],
  ['wave', (m) => m.play('wave'), 1.0],
  ['bow', (m) => m.play('bow'), 1.2],
  ['cheer', (m) => m.play('cheer'), 0.7],
  ['dance', (m) => m.play('dance'), 1.4],
  ['shy', (m) => m.play('shy'), 1.0],
  ['sit', (m) => m.setPosture('sit'), 2.5],
  ['lie', (m) => m.setPosture('lie'), 2.5],
  ['sleep', (m) => m.setState('sleeping'), 3],
];

export function sheet(m, cues = CUES, { cols = 4, size = 300 } = {}) {
  const rows = Math.ceil(cues.length / cols);
  const out = document.createElement('canvas');
  out.width = cols * size; out.height = rows * size;
  const g = out.getContext('2d');
  m.pause(); m.nextFidget = 1e9;
  const canvas = m.renderer.domElement;
  cues.forEach(([label, fn, t = 1.2], i) => {
    // Back to neutral standing between cues.
    m.actions = []; m.setState('idle'); m.setMood('neutral'); m.setPosture('stand'); m.speech = null;
    m.look.target = null; m.lookAt(0, 0.1);
    m.step(2.5);
    fn(m); m.step(t);
    const s = Math.min(canvas.width, canvas.height);
    g.fillStyle = (i + Math.floor(i / cols)) % 2 ? '#e9eef7' : '#f3f6fb';
    g.fillRect((i % cols) * size, Math.floor(i / cols) * size, size, size);
    g.drawImage(canvas, (canvas.width - s) / 2, (canvas.height - s) / 2, s, s, (i % cols) * size, Math.floor(i / cols) * size, size, size);
    g.fillStyle = '#1e3a8a'; g.font = '600 15px system-ui'; g.fillText(label, (i % cols) * size + 8, Math.floor(i / cols) * size + 20);
  });
  const img = new Image(); img.src = out.toDataURL('image/jpeg', 0.9);
  img.style.cssText = 'position:fixed;inset:0;width:100%;height:100%;object-fit:contain;background:#fff;z-index:9';
  document.body.append(img);
  return img;
}

/** Front, three-quarter, side and back in one strip, like a reference sheet's turnaround row, to
 *  compare with it; saved through serve.py as build/companions-3d/turn-<id>/00001.png. */
export async function turnaround(m, { w = 640, h = 760, yaws = [0, 35, 90, 180] } = {}) {
  m.pause(); m.nextFidget = 1e9;
  m.canvas.style.cssText = `position:fixed;left:0;top:0;width:${w}px;height:${h}px`;
  m.renderer.setPixelRatio(1); m.resize();
  m.actions = []; m.setState('idle'); m.setMood('smile'); m.blink.next = 1e9; m.lookAt(0, 0.1); m.step(2.5);
  const out = document.createElement('canvas'); out.width = w * yaws.length; out.height = h;
  const g = out.getContext('2d'); g.fillStyle = '#eef1f6'; g.fillRect(0, 0, out.width, h);
  yaws.forEach((yaw, i) => { m.root.rotation.y = -yaw * Math.PI / 180; m.step(0.05); g.drawImage(m.canvas, i * w, 0); });
  m.root.rotation.y = 0; m.step(0.05);
  const blob = await new Promise((res) => out.toBlob(res, 'image/png'));
  await fetch(`/frame/turn-${m.C.id}/1.png`, { method: 'POST', body: blob });
  return blob.size;
}

/** One move frame by frame (`frames` across its length), seen from `yaw` degrees: tears and stray
 *  parts show in motion that stills miss. Saved as build/companions-3d/film-<id>-<move>[-<yaw>]/00001.jpg. */
export async function filmstrip(m, move, { frames = 12, yaw = 0, size = 300, cols = 6 } = {}) {
  m.pause(); m.nextFidget = 1e9;
  m.actions = []; m.setState('idle'); m.setMood('neutral'); m.setPosture('stand'); m.speech = null;
  m.look.target = null; m.lookAt(0, 0.1); m.step(2.5);
  m.root.rotation.y = -yaw * Math.PI / 180;
  if (!m.play(move)) return 0;
  const dur = m.actions.at(-1).clip.dur, canvas = m.renderer.domElement, s = Math.min(canvas.width, canvas.height);
  const out = document.createElement('canvas'); out.width = cols * size; out.height = Math.ceil(frames / cols) * size;
  const g = out.getContext('2d'); g.fillStyle = '#eef1f6'; g.fillRect(0, 0, out.width, out.height);
  for (let i = 0; i < frames; i++) {
    m.step(dur / frames);
    g.drawImage(canvas, (canvas.width - s) / 2, (canvas.height - s) / 2, s, s, (i % cols) * size, Math.floor(i / cols) * size, size, size);
  }
  m.root.rotation.y = 0;
  const blob = await new Promise((res) => out.toBlob(res, 'image/jpeg', 0.9));
  await fetch(`/frame/film-${m.C.id}-${move.toLowerCase()}${yaw ? `-${yaw}` : ''}/1.jpg`, { method: 'POST', body: blob });
  return blob.size;
}

/** Close-ups to judge the surface (fur, seams, colour borders) beside a sheet: `shots` are
 *  [yaw degrees, centre height, view height] in world units, each a 900 px square, side by side.
 *  Saved as build/companions-3d/close-<name>/00001.jpg. */
export async function closeups(m, name, shots, size = 900) {
  m.pause(); m.nextFidget = 1e9;
  m.canvas.style.cssText = `position:fixed;left:0;top:0;width:${size}px;height:${size}px`;
  m.renderer.setPixelRatio(1); m.resize();
  m.actions = []; m.setState('idle'); m.setMood('smile'); m.blink.next = 1e9; m.lookAt(0, 0.1); m.step(2.5);
  const out = document.createElement('canvas'); out.width = size * shots.length; out.height = size;
  const g = out.getContext('2d'); g.fillStyle = '#eef1f6'; g.fillRect(0, 0, out.width, size);
  const c = m.camera, D2R = Math.PI / 180;
  shots.forEach(([yaw, cy, h], i) => {
    const dist = h / (2 * Math.tan(c.fov * D2R / 2));
    c.position.set(0, cy, dist); c.lookAt(0, cy, 0);
    m.root.rotation.y = -yaw * D2R; m.step(0.02); g.drawImage(m.canvas, i * size, 0);
  });
  m.root.rotation.y = 0; m.frame('tight');
  const blob = await new Promise((res) => out.toBlob(res, 'image/jpeg', 0.92));
  await fetch(`/frame/close-${name}/1.jpg`, { method: 'POST', body: blob });
  return blob.size;
}

/** The still Settings shows: idle and smiling, transparent, square; saved through serve.py. */
export async function portrait(m, size = 512) {
  m.pause(); m.nextFidget = 1e9;
  m.canvas.style.cssText = `position:fixed;left:0;top:0;width:${size}px;height:${size}px`;
  m.renderer.setPixelRatio(1); m.resize();
  m.setMood('smile'); m.lookAt(0.05, 0.15);
  m.blink.next = 1e9; m.step(3);
  const blob = await new Promise((res) => m.canvas.toBlob(res, 'image/png'));
  await fetch(`/frame/portrait-${m.C.id}/1.png`, { method: 'POST', body: blob });
  return blob.size;
}

// Looking straight ahead while a resting shot is taken: the look-at works in the companion's own
// frame (it doesn't know the turntable turned it), so the camera's place is ahead whatever the view,
// and a side view shows the pose rather than a head wrung round.
function ahead(m) { m.look.target = m.camera.position.clone(); m.look.lastSeen = m.time; }

function restCue(m, rest) {
  m.actions = []; m.speech = null; m.setMood('neutral');
  if (rest === 'sleep') m.setState('sleeping'); else { m.setState('idle'); m.setPosture(rest); }
}

/** The resting postures a desktop shows after a while idle (stand, sit, lie, sleep), each seen from
 *  the front, ¾ and side, plus its head close up from the front. Saved as
 *  build/companions-3d/rest-<id>[-<tag>]/00001.jpg. */
export async function restSheet(m, { tag = '', size = 300, yaws = [0, 35, 90], rests = ['stand', 'sit', 'lie', 'sleep'] } = {}) {
  m.pause(); m.nextFidget = 1e9;
  m.canvas.style.cssText = `position:fixed;left:0;top:0;width:${size}px;height:${size}px`;
  m.renderer.setPixelRatio(1); m.resize();
  const cols = yaws.length + 1, out = document.createElement('canvas');
  out.width = cols * size; out.height = rests.length * size;
  const g = out.getContext('2d'); g.fillStyle = '#eef1f6'; g.fillRect(0, 0, out.width, out.height);
  const c = m.camera, head = c.position.clone();
  rests.forEach((rest, r) => {
    m.root.rotation.y = 0; m.frame(m.opts.frame);
    restCue(m, 'stand'); m.lookAt(0, 0.1); m.step(2.5);
    restCue(m, rest); m.blink.next = 1e9; ahead(m); m.step(4);
    yaws.forEach((yaw, i) => {
      m.root.rotation.y = -yaw * Math.PI / 180; ahead(m); m.step(0.05);
      g.drawImage(m.canvas, i * size, r * size);
    });
    // Close up: the head, a view 1.5 units tall.
    m.root.rotation.y = 0; ahead(m); m.step(0.05);
    m.bones.head.getWorldPosition(head);
    const dist = 1.5 / (2 * Math.tan(c.fov * Math.PI / 360));
    c.position.set(head.x, head.y, head.z + dist); c.lookAt(head.x, head.y, head.z); m.step(0.02);
    g.drawImage(m.canvas, yaws.length * size, r * size);
    g.fillStyle = '#1e3a8a'; g.font = '600 15px system-ui'; g.fillText(rest, 8, r * size + 20);
  });
  m.frame(m.opts.frame); m.root.rotation.y = 0;
  const blob = await new Promise((res) => out.toBlob(res, 'image/jpeg', 0.9));
  await fetch(`/frame/rest-${m.C.id}${tag ? '-' + tag : ''}/1.jpg`, { method: 'POST', body: blob });
  return blob.size;
}

/** The way into a rest and out of it, frame by frame, one row per view: 'lie' goes stand › sit ›
 *  lie › stand (as Sidefolk's idle life does), 'sleep' goes idle › sleeping › idle; `cols` frames to a line. Saved as
 *  build/companions-3d/restfilm-<id>-<kind>[-<tag>]/00001.jpg. */
export async function restFilm(m, kind, { tag = '', yaws = [0, 90], every = 0.5, size = 220, cols = 9 } = {}) {
  const script = kind === 'sleep'
    ? [[0.5, () => restCue(m, 'sleep')], [5, () => restCue(m, 'stand')], [8, null]]
    : [[0.5, () => restCue(m, 'sit')], [3, () => restCue(m, 'lie')], [6.5, () => restCue(m, 'stand')], [9, null]];
  const end = script.at(-1)[0], n = Math.round(end / every), lines = Math.ceil(n / cols);
  m.pause(); m.nextFidget = 1e9;
  m.canvas.style.cssText = `position:fixed;left:0;top:0;width:${size}px;height:${size}px`;
  m.renderer.setPixelRatio(1); m.resize();
  const out = document.createElement('canvas'); out.width = Math.min(n, cols) * size; out.height = yaws.length * lines * size;
  const g = out.getContext('2d'); g.fillStyle = '#eef1f6'; g.fillRect(0, 0, out.width, out.height);
  yaws.forEach((yaw, r) => {
    m.root.rotation.y = 0; restCue(m, 'stand'); m.lookAt(0, 0.1); m.step(2.5);
    m.root.rotation.y = -yaw * Math.PI / 180;
    let cue = 0;
    for (let i = 0; i < n; i++) {
      const t = i * every;
      while (cue < script.length && script[cue][0] <= t + 1e-6) { script[cue][1]?.(); cue++; }
      ahead(m); m.step(every);
      g.drawImage(m.canvas, (i % cols) * size, (r * lines + Math.floor(i / cols)) * size);
    }
  });
  m.root.rotation.y = 0;
  const blob = await new Promise((res) => out.toBlob(res, 'image/jpeg', 0.88));
  await fetch(`/frame/restfilm-${m.C.id}-${kind}${tag ? '-' + tag : ''}/1.jpg`, { method: 'POST', body: blob });
  return blob.size;
}
