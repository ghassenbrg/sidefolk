// Records a scripted showreel frame by frame (fixed 30 fps, independent of the real frame rate)
// and posts the frames to serve.py, which saves them for ffmpeg. Open index.html?record=<name>.
export const SHOWREEL = [
  [0.0, (m) => { m.setState('idle'); m.lookAt(0, 0.15); }],
  [1.2, (m) => { m.play('wave'); m.say(`Hi! I'm ${m.C.name}, your little helper.`); }],
  [5.0, (m) => m.play('lookAround')],
  [8.6, (m) => { m.lookAt(0, 0.15); m.play('hop'); }],
  [10.2, (m) => m.play('dance')],
  [17.0, (m) => m.setState('thinking')],
  [21.0, (m) => { m.setState('idle'); m.play('nod'); m.say('Got it!'); }],
  [23.0, (m) => m.play('love')],
  [26.3, (m) => m.play('surprised')],
  [28.2, (m) => m.play('giggle')],
  [30.4, (m) => m.play('bow')],
  [33.4, (m) => m.play('sad')],
  [37.0, (m) => m.play('angry')],
  [39.6, (m) => m.setState('working')],
  [43.5, (m) => { m.setState('idle'); m.setPosture('sit'); }],
  [45.0, (m) => m.say('Want to take a little break with me?')],
  [48.5, (m) => m.setState('sleeping')],
  [55.0, (m) => { m.setState('idle'); m.setPosture('stand'); }],
  [56.8, (m) => m.play('stretch')],
  [59.6, (m) => m.play('cheer')],
  [62.8, null],
];

export async function record(mochi, name, script = SHOWREEL, size = 900) {
  const r = mochi.renderer;
  mochi.pause();
  mochi.nextFidget = 1e9;
  mochi.canvas.style.cssText = `position:fixed;left:0;top:0;width:${size}px;height:${size}px`;
  r.setPixelRatio(1);
  r.setClearColor(0xe9eef6, 1);
  mochi.resize();
  const end = script[script.length - 1][0];
  let cue = 0, n = 0;
  for (let t = 0; t <= end; t += 1 / 30) {
    while (cue < script.length && script[cue][0] <= t + 1e-6) { script[cue][1]?.(mochi); cue++; }
    mochi.update(1 / 60); mochi.update(1 / 60);
    r.render(mochi.scene, mochi.camera);
    const blob = await new Promise((res) => mochi.canvas.toBlob(res, 'image/jpeg', 0.9));
    await fetch(`/frame/${name}/${n++}.jpg`, { method: 'POST', body: blob });
    window.recProgress = n;
  }
  window.recDone = n;
  return n;
}
