// In-memory interaction model only. No network, native APIs, or persistent storage.
const screen = document.getElementById('screen');
const feedback = document.getElementById('feedback');
const initial = () => ({view:'home', request:'pending', name:'Slate', look:'Professional', art:'3D', draftLook:'Professional', step:1, reminders:[], settings:{motion:true, capture:true, sound:false, presence:'Only when needed', detail:'Project and status'}});
let state = initial();
let messageTimer;
const esc = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const button = (label, action, cls='') => `<button class="${cls}" data-action="${action}">${label}</button>`;
const viewButton = (label, view, cls='') => `<button class="${cls}" data-view="${view}">${label}</button>`;
const heading = (title, subtitle, eyebrow='Your workspace') => `<div class="eyebrow">${eyebrow}</div><h1 tabindex="-1">${title}</h1><p class="intro">${subtitle}</p>`;
const identity = () => `<div class="identity"><span class="avatar" aria-hidden="true">${esc(state.name.slice(0,1))}</span><div><strong>${esc(state.name)} · Website refresh</strong><div class="meta">Codex · Session 04</div></div></div>`;
const choices = () => `<div class="choice-grid" role="group" aria-label="Appearance collection">${[['Friendly','Pip · warm and expressive'],['Professional','Slate · quiet and composed'],['Minimal','Dot · simple and discreet']].map(([name,desc])=>`<button class="choice" data-look="${name}" aria-pressed="${state.draftLook===name}"><strong>${name}</strong><small>${desc}</small></button>`).join('')}</div>`;
const preset = () => state.draftLook==='Friendly' ? 'Appearance only. Your comfort settings will stay as they are.' : 'Suggested comfort changes: reduced motion, sound off, project-and-status previews, and '+(state.draftLook==='Minimal'?'menu bar only.':'desktop presence only when needed.');
function notice(text){clearTimeout(messageTimer);feedback.textContent=text;messageTimer=setTimeout(()=>{feedback.textContent='';},5500);}
function navigate(view){state.view=view;render(true);}
function applyAppearance(name,art){
  state.name=name.trim()||'Slate';state.look=state.draftLook;state.art=art;
  if(state.look!=='Friendly'){state.settings.motion=true;state.settings.sound=false;state.settings.detail='Project and status';state.settings.presence=state.look==='Minimal'?'Menu bar only':'Only when needed';}
}
function home(){return heading('A little more room to focus.',state.request==='pending'?'One thing needs your attention.':"You're all caught up on requests.")+`
  ${state.request==='pending'?`<section class="card attention"><div class="row">${identity()}<span class="badge">! Needs you</span></div><h2 class="request-title">Codex wants to run project tests.</h2><p>Review the action and choose what happens next.</p><div class="actions">${viewButton('Review request →','review','primary')}</div></section>`:`<section class="card"><span class="badge done">✓ Request reviewed</span><h2 style="margin-top:18px">Your choice is recorded in this demo.</h2><p>${state.request==='allowed'?'Allowed once':'Declined'} · Website refresh. No command was run.</p></section>`}
  <section class="card"><div class="row"><div class="identity"><span class="avatar" aria-hidden="true">F</span><div><strong>Finch · Launch notes</strong><div class="meta">Claude Code · sample activity</div></div></div><span class="badge working">◷ Working</span></div><p>Claude Code is updating your notes.</p></section>
  <section class="card"><div class="row"><div><h3>Make space for what matters.</h3><p>Add a reminder for your next small step.</p></div>${viewButton('Add reminder','reminders')}</div></section>
  <p class="hint">This workspace is illustrative. No tools are connected and no activity is live.</p>`;}
function requests(){return heading('Requests',state.request==='pending'?'One work session is waiting for your answer.':'No requests are waiting for you.')+(state.request==='pending'?`<section class="card"><div class="row">${identity()}<span class="badge">! Needs you</span></div><h2 style="margin-top:22px">Run project tests?</h2><p>Codex is asking to run a command in Website refresh.</p><div class="actions">${viewButton('Review request','review','primary')}</div></section>`:`<section class="card empty"><strong>You're all caught up.</strong><p>Your sample request was ${state.request==='allowed'?'allowed once':'declined'}. No command was run.</p>${viewButton('See decision','review')}</section>`);}
function review(){return viewButton('← Back to requests','requests','quiet')+heading('Review request','A clear choice, for the right project.','Request details')+`<section class="card">${identity()}<h2 class="request-title">Run project tests?</h2><p>Codex is asking to run this command in Website refresh.</p><div class="command"><small>Command</small><code class="mono">npm test</code><small>Working folder</small><code class="mono">/work/website</code></div><details><summary>Technical details</summary><p class="mono">Tool: Codex\nWork session: 04\nRequest: demo-request-001\nType: command execution</p><p class="hint">This sample command has not been inspected or executed by the prototype.</p></details><p>Review the command before allowing it.</p>${state.request==='pending'?`<div class="actions equal">${button('Decline','decline')}${button('Allow once','allow','primary')}</div>`:`<div class="result"><strong>${state.request==='allowed'?'Allowed once':'Declined'} — demo only</strong><br>Your choice was recorded locally. No command was run.</div>`}</section>`;}
function crew(){return heading('Your crew','A familiar face for each project.')+`<section class="card"><div class="row">${identity()}<span class="badge">${state.request==='pending'?'! Needs you':'✓ Reviewed'}</span></div><p>Appearance: ${esc(state.look)} · ${esc(state.art)} concept. Project and session stay connected when the look changes.</p></section><section class="card"><h2>Make it feel like you.</h2><p>Choose a collection. Review the suggested comfort changes before applying.</p>${choices()}<form id="appearance-form"><div class="form-grid"><label class="field">Companion name<input id="companion-name" name="companion" maxlength="30" required value="${esc(state.name)}"></label><label class="field">Art style<select name="art"><option ${state.art==='3D'?'selected':''}>3D</option><option ${state.art==='2D'?'selected':''}>2D</option></select><small>Concept preview only; this does not load a new model.</small></label></div><p class="notice">${preset()}</p><button class="primary" type="submit">Apply appearance &amp; shown preferences</button></form></section><img class="art" src="images/08-professional-crew.png" alt="Studio Collection: Calder, Finch, Orbit, Slate, Vale and Dot in 2D and 3D"><p class="hint">All six Studio characters are concepts. The current app ships bunny, cat and fox bases.</p>`;}
function reminders(){return heading('Reminders','Small things, remembered.')+`<section class="card"><form id="reminder-form"><label class="field">What would you like to remember?<input name="title" maxlength="160" placeholder="Review launch notes" required></label><label class="field">When?<input name="due" type="datetime-local" required><small>Uses this browser's local timezone. This demo won't send a notification.</small></label><button class="primary" type="submit">Add reminder</button></form></section><section aria-label="Your reminders">${state.reminders.length?state.reminders.map(r=>`<article class="card"><div class="row"><div><strong class="${r.done?'complete':''}">${esc(r.title)}</strong><div class="meta">${esc(new Date(r.due).toLocaleString())}</div></div>${r.done?'<span class="badge done">✓ Completed</span>':`<button data-complete="${r.id}">Mark complete</button>`}</div></article>`).join(''):'<div class="card empty"><strong>A little space for later.</strong><p>Your reminders will appear here. Try adding one above.</p></div>'}</section>`;}
function settings(){return heading('Make Sidefolk comfortable.','Your workspace, your preferences.')+`<section class="card"><form id="settings-form">${[['motion','Reduce motion','Keep gestures gentle and use a static state when possible.'],['capture','Hide from screen recordings','Request capture protection where supported. It cannot hide the overlay from every recording tool.'],['sound','Sound cues','Play a short sound when something needs you.']].map(([id,title,desc])=>`<div class="setting"><label for="${id}">${title}<small>${desc}</small></label><input type="checkbox" id="${id}" name="${id}" ${state.settings[id]?'checked':''}></div>`).join('')}<label class="field">Desktop presence<select name="presence">${['Always visible','Only when needed','Menu bar only'].map(x=>`<option ${state.settings.presence===x?'selected':''}>${x}</option>`).join('')}</select><small>Requests remain reachable from the menu bar in this proposed design.</small></label><label class="field">Notification detail<select name="detail">${['Full preview','Project and status','Status only'].map(x=>`<option ${state.settings.detail===x?'selected':''}>${x}</option>`).join('')}</select></label><button class="primary" type="submit">Save preview settings</button></form></section><p class="hint">Prototype settings stay in this page only. They do not change your Mac or the running Sidefolk app.</p>`;}
function welcome(){
  const top=`<div class="welcome"><div class="row"><span class="eyebrow">Welcome to Sidefolk</span><span class="pill">${state.step} of 3</span></div>`;
  if(state.step===1)return top+`<div class="welcome-brand"><img src="references/selected-pip-signal.png" alt="Pip Signal bunny"></div>`+heading('A little help,<br>by your side.','See what needs you. Keep track of your work.','')+`<section class="card"><h3>Know when your tools need an answer.</h3><p>Connect an AI tool, give each project a familiar face, and keep reminders nearby.</p></section><div class="actions equal">${button('Get started','next','primary')}${viewButton('Try a demo','home')}</div></div>`;
  if(state.step===2)return top+heading('Make yourself at home.','Choose a look. Everything here can change later.','')+choices()+`<form id="setup-form"><label class="field">Name<input name="companion" maxlength="30" required value="${esc(state.name)}"></label><p class="notice">${preset()}</p><div class="actions equal">${button('Back','back')}<button class="primary" type="submit">Apply &amp; continue</button></div></form></div>`;
  return top+heading("Connect when you're ready.",'Connect an AI tool to see its progress and requests here.','')+['Claude Code','Codex'].map(tool=>`<section class="card row"><div><strong>${tool}</strong><div class="meta">Not connected</div></div><button data-tool="${tool}">Set up</button></section>`).join('')+`<p class="notice">Sidefolk will explain each change before setup. This preview cannot install or connect tools.</p><div class="actions equal">${button('Back','back')}${viewButton('Use reminders for now','reminders','primary')}</div></div>`;
}
function render(focus=false){
  const pages={home,requests,review,crew,reminders,settings,welcome};
  screen.innerHTML=(pages[state.view]||home)();
  document.querySelectorAll('nav [data-view]').forEach(b=>{if(b.dataset.view===state.view||(state.view==='review'&&b.dataset.view==='requests'))b.setAttribute('aria-current','page');else b.removeAttribute('aria-current');});
  document.getElementById('request-count').textContent=state.request==='pending'?'1':'0';
  if(focus)screen.querySelector('h1')?.focus();
}
document.addEventListener('click',event=>{
  const b=event.target.closest('button');if(!b)return;
  if(b.dataset.view){if(b.dataset.view==='welcome')state.step=1;navigate(b.dataset.view);return;}
  if(b.dataset.look){state.draftLook=b.dataset.look;render();screen.querySelector(`[data-look="${b.dataset.look}"]`)?.focus();return;}
  if(b.dataset.tool){notice(`${b.dataset.tool} setup is a preview. In the app, you would review the changes and confirm before installation.`);return;}
  if(b.dataset.complete){const r=state.reminders.find(r=>r.id===Number(b.dataset.complete));if(r){r.done=true;render(true);notice('Reminder marked complete in this preview.');}return;}
  switch(b.dataset.action){
    case 'reset':state=initial();render(true);notice('Demo reset. All sample changes cleared.');break;
    case 'next':state.step=Math.min(3,state.step+1);render(true);break;
    case 'back':event.preventDefault();state.step=Math.max(1,state.step-1);render(true);break;
    case 'allow':case 'decline':if(state.request==='pending'){state.request=b.dataset.action==='allow'?'allowed':'declined';render(true);notice('Choice recorded in the demo. Nothing was sent to an agent.');}break;
  }
});
document.addEventListener('submit',event=>{
  event.preventDefault();const f=event.target;const d=new FormData(f);
  if(f.id==='appearance-form'||f.id==='setup-form'){
    const name=String(d.get('companion')||'').trim();
    if(!name){f.querySelector('input').setCustomValidity('Enter a companion name.');f.querySelector('input').reportValidity();return;}
    applyAppearance(name,String(d.get('art')||state.art));
    if(f.id==='setup-form'){state.step=3;render(true);}else{render(true);notice('Appearance and shown preferences applied in this preview.');}
  }else if(f.id==='reminder-form'){
    const title=String(d.get('title')||'').trim();const due=String(d.get('due')||'');
    if(!title||!due||Number.isNaN(new Date(due).getTime())){notice('Enter a reminder and a valid date and time.');return;}
    state.reminders.push({id:Date.now(),title,due,done:false});render(true);notice('Reminder added to this preview only. No notification is scheduled.');
  }else if(f.id==='settings-form'){
    state.settings={motion:d.has('motion'),capture:d.has('capture'),sound:d.has('sound'),presence:String(d.get('presence')),detail:String(d.get('detail'))};notice('Preview settings saved until this page reloads.');
  }
});
document.addEventListener('input',event=>{if(event.target instanceof HTMLInputElement)event.target.setCustomValidity('');});
render();
