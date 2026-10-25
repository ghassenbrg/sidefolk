/** Design-only exporter/validator. Uses the repository's existing Playwright dependency.
 * Serve the repo root on 127.0.0.1:4178, then: node creative-design/review-2026-10-25/render.mjs
 * No native desktop capture, domain mutations or model calls occur.
 */
import { webkit } from 'playwright';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import assert from 'node:assert/strict';
const root=fileURLToPath(new URL('.',import.meta.url));
const screens=JSON.parse(await readFile(path.join(root,'screens.json'),'utf8'));
const base=process.env.SIDEFOLK_DESIGN_URL||'http://127.0.0.1:4178/creative-design/review-2026-10-25/index.html';
const browser=await webkit.launch();
const context=await browser.newContext({timezoneId:'Asia/Tokyo',colorScheme:'light',deviceScaleFactor:1});
const page=await context.newPage();
const report={date:'2026-10-25',engine:'Playwright WebKit',kind:'Design prototype only',screens:[],responsive:[],interactions:[],errors:[]};
page.on('pageerror',e=>report.errors.push(e.message));
page.on('console',m=>{if(m.type()==='error')report.errors.push(m.text())});
page.on('response',r=>{if(r.status()>=400)report.errors.push(`${r.status()} ${r.url()}`)});
async function load(id,extra=''){
 await page.goto(base+'?screen='+id+extra);
 await page.evaluate(async()=>{await document.fonts.ready;await Promise.all(Array.from(document.images).map(i=>i.decode().catch(()=>{})))});
}
async function integrity(){
 const data=await page.evaluate(()=>({
  horizontalOverflow:document.documentElement.scrollWidth>innerWidth,
  missingImages:Array.from(document.images).filter(i=>!i.naturalWidth).map(i=>i.src),
  nestedButtons:document.querySelectorAll('button button').length,
  unnamedButtons:Array.from(document.querySelectorAll('button')).filter(b=>!b.textContent.trim()&&!b.getAttribute('aria-label')).length
 }));
 assert.equal(data.horizontalOverflow,false,'Document must not overflow horizontally');
 assert.deepEqual(data.missingImages,[]);assert.equal(data.nestedButtons,0);assert.equal(data.unnamedButtons,0);
 return data;
}
try{
 for(const spec of screens){
  await page.setViewportSize({width:spec.width,height:spec.height});
  await load(spec.id);
  const checks=await integrity();
  await page.screenshot({path:path.join(root,spec.image),fullPage:true});
  report.screens.push({id:spec.id,image:spec.image,viewport:[spec.width,spec.height],theme:spec.theme,...checks});
 }
 console.log(`Rendered ${screens.length} design images in WebKit.`);
 for(const [width,height] of [[1100,760],[900,680],[640,480]]){
  await page.setViewportSize({width,height});
  for(const theme of ['light','dark']){
   for(const id of ['today','calm','reminders','reminder-edit','work-log','request','settings','setup']){
    await load(id,`&theme=${theme}&native=1`);
    report.responsive.push({id,width,height,theme,...await integrity()});
    if(theme==='light'&&['today','work-log'].includes(id)&&width!==900){
     await mkdir(path.join(root,'images/native'),{recursive:true});
     await page.screenshot({path:path.join(root,`images/native/${id}-${width}x${height}.png`)});
    }
   }
  }
 }
 console.log(`Checked ${report.responsive.length} native-size theme/layout combinations.`);
 await page.setViewportSize({width:1100,height:760});
 await load('today','&native=1');
 await page.getByRole('button',{name:'Quick add ⌘ K'}).click();
 assert(await page.getByRole('dialog').isVisible());
 assert.equal(await page.locator('#quick-text').evaluate(e=>document.activeElement===e),true);
 await page.keyboard.press('Escape');
 assert.equal(await page.getByRole('dialog').count(),0);
 report.interactions.push('Quick add opens focused, native dialog closes with Escape');
 await page.getByRole('button',{name:'Add reminder',exact:true}).click();
 assert.equal(await page.locator('#rem-title').inputValue(),'');
 await page.getByRole('button',{name:'Save reminder',exact:true}).click();
 assert.equal(await page.locator('#rem-title').getAttribute('aria-invalid'),'true');
 report.interactions.push('Add reminder opens create mode; blank title stays in editor');
 await load('quick-ambiguity','&native=1');
 assert(await page.getByRole('button',{name:'Choose a time',exact:true}).isDisabled());
 await page.getByRole('button',{name:'15:00 today',exact:true}).click();
 await page.getByRole('button',{name:'Save reminder',exact:true}).click();
 assert.match(await page.getByRole('status').innerText(),/15:00 today/);
 report.interactions.push('Ambiguous time requires a choice; confirmation preserves that choice');
 await load('notebook-choice','&native=1');
 await page.getByRole('button',{name:'Evaluation H2 2026',exact:true}).click();
 await page.getByRole('button',{name:'Save note',exact:true}).click();
 assert.match(await page.getByRole('status').innerText(),/Evaluation H2 2026/);
 report.interactions.push('Notebook choice preserves the selected destination in confirmation');
 await load('work-log','&native=1');
 await page.getByRole('button',{name:/Add a note to Log/}).click();
 await page.locator('#new-note').fill('Keep this unfinished thought.');
 await page.getByRole('button',{name:'Sidefolk',exact:true}).click();
 assert.equal(await page.locator('#new-note').inputValue(),'Keep this unfinished thought.');
 assert.equal(await page.locator('#log-entries .entry:visible').count(),1);
 report.interactions.push('Notebook changes filter entries and preserve an unsaved draft');
 await load('request-released','&native=1');
 assert.equal(await page.getByRole('button',{name:'Allow once',exact:true}).count(),0);
 assert(await page.getByRole('button',{name:'Open session',exact:true}).isVisible());
 report.interactions.push('Released request has Open and no Allow');
 await load('request-long','&native=1');
 assert.equal(await page.getByRole('button',{name:'Allow once',exact:true}).count(),0);
 await page.locator('.long-operation').evaluate(e=>{e.scrollTop=e.scrollHeight});
 await page.waitForFunction(()=>!!document.querySelector('.request-foot [data-action=allow]'));
 report.interactions.push('Long operation has no Allow before complete scroll review');
 await load('calm','&native=1');
 assert.equal(await page.getByRole('button',{name:/Sessions/}).count(),0);
 assert.doesNotMatch(await page.locator('main').innerText(),/Claude|Codex|MCP|terminal|hook/i);
 report.interactions.push('Everyday Today has no Sessions or developer vocabulary');
 await page.setViewportSize({width:640,height:480});
 await load('today','&native=1');
 await page.getByRole('button',{name:'Add reminder',exact:true}).click();
 const box=await page.locator('#rem-title').boundingBox();
 assert(box&&box.y>=0&&box.y+box.height<=480);
 assert.equal(await page.locator('#rem-title').evaluate(e=>document.activeElement===e),true);
 await page.screenshot({path:path.join(root,'images/native/new-reminder-640x480.png')});
 report.interactions.push('At 640×480, opening Add reminder immediately shows and focuses the title field');
 // Scope reduced-motion check to design artifacts; no animation should be required for state.
 await page.emulateMedia({reducedMotion:'reduce'});
 await load('today','&native=1');await integrity();
 report.interactions.push('Reduced-motion rendering retains the same readable states');
 assert.deepEqual(report.errors,[]);
 report.result='passed';
}catch(e){report.result='failed';report.failure=e.stack;throw e;}
finally{
 await writeFile(path.join(root,'verification.json'),JSON.stringify(report,null,2)+'\n');
 await browser.close();
}
console.log(`Validated ${report.interactions.length} interaction scenarios. No native release gate is asserted.`);
