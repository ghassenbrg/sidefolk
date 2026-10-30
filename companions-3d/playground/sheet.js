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
