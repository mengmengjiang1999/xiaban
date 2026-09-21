/* P1 release-build acceptance. All gameplay actions use real browser input.
 * The opt-in p1_qa=1 bridge only publishes snapshots; it has no control methods.
 * Setup: npm install --prefix .tools/browser-qa playwright
 * Run: node tools/test_browser.cjs (local server must be running on port 8766).
 */
const { chromium } = require('../.tools/browser-qa/node_modules/playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const BASE = process.env.P1_URL || 'http://127.0.0.1:8766/';
const HEADLESS = process.env.P1_HEADLESS === '1';
const OUT = path.resolve('.logs/p1-browser');
fs.mkdirSync(OUT, { recursive: true });
const results = [];
const skipped = [];
const logs = [];
const errors = [];
let browser;
let browserVersion;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const angle = (a,b) => Math.atan2(Math.sin(a-b), Math.cos(a-b));
const flatDistance = (a,b) => Math.hypot(a[0]-b[0],a[2]-b[2]);
function check(condition, description, evidence={}) {
  const record = {pass:!!condition, description, evidence}; results.push(record);
  console.log(`${condition?'PASS':'FAIL'}: ${description}`,JSON.stringify(evidence));
  assert.ok(condition, description);
}
async function state(frame) {
  return frame.evaluate(()=> window.xiabanP1State ? JSON.parse(window.xiabanP1State) : null);
}
async function waitState(frame, phase) {
  await frame.waitForFunction(p=>window.xiabanP1State && JSON.parse(window.xiabanP1State).phase===p,phase,{timeout:15000});
  return state(frame);
}
async function locked(frame) { return frame.evaluate(()=>document.pointerLockElement?.tagName==='CANVAS'); }
async function exitFullscreen(frame) {
  // The API promise can resolve before fullscreenchange and the canvas resize.
  // Wait for the real event and rendered frames before clicking the next menu.
  await frame.evaluate(()=>new Promise((resolve,reject)=>{
    if(!document.fullscreenElement) return resolve();
    document.addEventListener('fullscreenchange',()=>requestAnimationFrame(()=>requestAnimationFrame(resolve)),{once:true});
    document.exitFullscreen().catch(reject);
  }));
}
async function screenshot(page,name) { await page.screenshot({path:path.join(OUT,`${name}.png`)}); }
async function clickButton(page, frame, name) {
  const s=await state(frame);
  const info=s.buttons[name];
  assert.ok(info?.visible, `Visible ${name} button`);
  const rect=info.rect;
  const box=await frame.locator('canvas').boundingBox();
  assert.ok(box);
  const x=box.x+(rect[0]+rect[2]/2)*box.width/s.viewport[0];
  const y=box.y+(rect[1]+rect[3]/2)*box.height/s.viewport[1];
  await page.mouse.click(x,y);
}
async function resume(page, frame) {
  await clickButton(page,frame,'primary');
  await waitState(frame,'playing');
  await sleep(1100);
  check((await state(frame)).phase==='playing' && await locked(frame),'Start/continue maintains pointer lock beyond capture grace');
}
async function hold(page,key,ms) {await page.keyboard.down(key);await sleep(ms);await page.keyboard.up(key);await sleep(100);}
function listen(page,label) {
  page.on('console',m=>{
    const r={label,type:m.type(),message:m.text()}; logs.push(r);
    if(m.text().includes('P1_')) console.log('GAME',label,m.text());
    if(m.type()==='error' && !m.text().includes('404')) errors.push(r);
  });
  page.on('pageerror',e=>errors.push({label,type:'pageerror',message:e.message}));
}
async function openGame(context) {
  const p=await context.newPage();listen(p,'standalone');
  await p.goto(BASE+'?p1_qa=1');await waitState(p,'menu');await p.bringToFront();return p;
}
async function route(page) {
  // Read every rendered frame while using normal keyboard input. This records
  // camera discontinuities that a successful endpoint-only route would miss.
  await page.evaluate(()=>{
    window.p1RouteTrace=[];
    window.p1RecordingRoute=true;
    const sample=()=>{
      if(!window.p1RecordingRoute) return;
      const s=window.xiabanP1State && JSON.parse(window.xiabanP1State);
      if(s) window.p1RouteTrace.push({time:s.elapsed,phase:s.phase,position:s.position,camera:s.camera_position,yaw:s.camera_yaw,alpha:s.camera_alpha});
      requestAnimationFrame(sample);
    };
    requestAnimationFrame(sample);
  });
  const points=[[5.5,21.5],[5.5,17.4],[8.8,17.4],[8.8,13.25],[18.5,13.25],[18.5,8.4],[11.5,8.4],[11.5,6],[4.5,6],[4.5,3],[4.5,1.5]];
  const held=new Set();
  async function set(key,down){if(down!==held.has(key)){if(down){await page.keyboard.down(key);held.add(key);}else{await page.keyboard.up(key);held.delete(key);}}}
  const deadline=Date.now()+100000;
  for (let i=0;i<points.length;i++) {
    while(Date.now()<deadline) {
      const s=await state(page);
      if(s.phase==='won') break;
      assert.equal(s.phase,'playing','Route stays playing');
      const dx=points[i][0]-s.position[0], dz=points[i][1]-s.position[2];
      if(Math.hypot(dx,dz)<0.17) break;
      const delta=angle(Math.atan2(-dx,-dz),s.heading);
      await set('a',delta>0.035);await set('d',delta< -0.035);await set('w',Math.abs(delta)<0.14);
      await sleep(20);
    }
    for(const key of ['w','a','d']) await set(key,false);
    console.log('ROUTE',i+1,JSON.stringify((await state(page)).position));
    if(i===4) await screenshot(page,'office-corner');
    if((await state(page)).phase==='won') break;
    assert.ok(Date.now()<deadline,'Route completes before timeout');
  }
  const s=await waitState(page,'won');
  const trace=await page.evaluate(()=>{window.p1RecordingRoute=false;return window.p1RouteTrace;});
  fs.writeFileSync(path.join(OUT,'route-frames.json'),JSON.stringify(trace));
  console.log('ROUTE_FRAMES',trace.length);
  let sampledFrames=0, maxCameraSpeed=0;
  for(let i=1;i<trace.length;i++) {
    const a=trace[i-1], b=trace[i], delta=b.time-a.time;
    if(a.phase!=='playing' || b.phase!=='playing' || delta<=0) continue;
    sampledFrames++;
    maxCameraSpeed=Math.max(maxCameraSpeed,Math.hypot(...b.camera.map((value,j)=>value-a.camera[j]))/delta);
  }
  // Allow normal translation/turning and account for variable render cadence.
  // The former corner bug jumped ~3 m in one 60 Hz frame (~180 m/s).
  check(sampledFrames>300 && maxCameraSpeed<21,'Rendered route has no abrupt camera jumps',{sampledFrames,maxCameraSpeed,maxStepEquivalentAt60Hz:maxCameraSpeed/60});
  check(s.travel_distance>35 && !(await locked(page)),'Browser keyboard input completes the office route and releases mouse at exit',{time:s.elapsed,distance:s.travel_distance});
  await screenshot(page,'completed');
}
(async()=>{
  browser=await chromium.launch({channel:'chrome',headless:HEADLESS});
  const context=await browser.newContext({viewport:{width:1152,height:720}});
  const page=await openGame(context);
  browserVersion=await browser.version();
  console.log('BROWSER',browserVersion,HEADLESS?'headless':'headed');
  await screenshot(page,'menu');
  check(!(await locked(page)),'Menu leaves mouse released');
  await resume(page,page);
  const initial=await state(page);
  await hold(page,'w',500);
  const forward=await state(page);
  check(forward.position[2]<initial.position[2]-1 && Math.abs(forward.position[0]-initial.position[0])<0.04,'W moves forward along actor heading');
  await hold(page,'s',350);
  const backward=await state(page);
  check(backward.position[2]>forward.position[2]+0.7 && Math.abs(angle(backward.heading,forward.heading))<0.01 && Math.abs(angle(backward.camera_yaw,forward.camera_yaw))<0.02,'S backs up without rotating actor or camera');
  await hold(page,'a',250);const left=await state(page);
  check(left.heading>backward.heading+0.3 && flatDistance(left.position,backward.position)<0.03,'A turns left without strafing');
  await hold(page,'d',250);const right=await state(page);
  check(right.heading<left.heading-0.3 && flatDistance(right.position,left.position)<0.03,'D turns right without strafing');
  await sleep(800);
  const beforeOrbit=await state(page);
  await page.mouse.down({button:'right'});await page.mouse.move(750,350,{steps:8});await sleep(150);
  const orbit=await state(page);
  check(orbit.observing && Math.abs(angle(orbit.camera_yaw,beforeOrbit.camera_yaw))>0.2 && Math.abs(angle(orbit.heading,beforeOrbit.heading))<0.01,'Right drag orbits camera without turning actor');
  await hold(page,'w',250);const observingWalk=await state(page);
  const expected=[-Math.sin(orbit.heading),-Math.cos(orbit.heading)];
  const movement=[observingWalk.position[0]-orbit.position[0],observingWalk.position[2]-orbit.position[2]];
  check(Math.abs(angle(observingWalk.camera_yaw,orbit.camera_yaw))<0.02 && movement[0]*expected[0]+movement[1]*expected[1]>0.4,'Observation has priority while W remains actor-relative');
  await page.mouse.up({button:'right'});await sleep(600);
  const released=await state(page);
  check(!released.observing && Math.abs(angle(released.camera_yaw,orbit.camera_yaw))<0.02,'Stationary release retains the observation angle');
  await page.mouse.wheel(0,-120);await sleep(200);const closer=await state(page);
  await page.mouse.wheel(0,120);await sleep(200);const farther=await state(page);
  check(closer.desired_distance<released.desired_distance && farther.desired_distance>closer.desired_distance,'Mouse wheel changes camera distance in both directions');
  await page.mouse.wheel(0,120);await sleep(150);const chosen=(await state(page)).desired_distance;
  await page.keyboard.press('f');await sleep(500);const centered=await state(page);
  check(Math.abs(angle(centered.camera_yaw,centered.heading))<0.015 && centered.desired_distance===chosen,'F recenters on actor heading and keeps chosen zoom');
  await page.mouse.down({button:'right'});await page.mouse.move(440,350,{steps:8});await page.mouse.up({button:'right'});await sleep(150);
  const drift=await state(page);await hold(page,'s',500);await sleep(500);const auto=await state(page);
  check(Math.abs(angle(drift.camera_yaw,drift.heading))>0.2 && Math.abs(angle(auto.camera_yaw,auto.heading))<0.03 && auto.desired_distance===chosen,'Backward walking smoothly recenters after observation and keeps zoom');
  await screenshot(page,'camera-controls');
  await page.keyboard.press('Escape');const paused=await waitState(page,'paused');await sleep(350);const frozen=await state(page);
  check(!(await locked(page)) && Math.abs(frozen.elapsed-paused.elapsed)<0.03 && flatDistance(frozen.position,paused.position)<0.01,'Escape releases mouse and freezes time and movement');
  await screenshot(page,'paused');
  await page.keyboard.press('Escape');await sleep(200);check((await state(page)).phase==='paused','Escape while paused does not silently recapture mouse');
  await resume(page,page);
  const other=await context.newPage();await other.goto('about:blank');await page.bringToFront();
  if((await state(page)).phase==='paused') await resume(page,page);
  await page.keyboard.down('w');await page.mouse.down({button:'right'});await page.mouse.move(670,340,{steps:4});await sleep(100);
  await other.bringToFront();await other.keyboard.up('w');await other.mouse.up({button:'right'});await sleep(400);
  check((await state(page)).phase==='paused' && !(await locked(page)),'Switching to another real tab while W/right button are held safely pauses');
  await page.bringToFront();await sleep(200);check((await state(page)).phase==='paused','Returning to the game tab does not auto-resume');
  await resume(page,page);const resumed=await state(page);await sleep(350);const noStuck=await state(page);
  check(flatDistance(resumed.position,noStuck.position)<0.01 && !noStuck.observing && noStuck.move_input===0,'Resume after background key release has no stuck movement or observation');
  await other.close();
  if (!HEADLESS) {
    const windowContext=await browser.newContext();
    const otherWindow=await windowContext.newPage();await otherWindow.goto('about:blank');await otherWindow.bringToFront();await sleep(350);
    check((await state(page)).phase==='paused' && !(await locked(page)),'Switching to a separate browser window pauses and releases mouse');
    await page.bringToFront();await resume(page,page);await windowContext.close();
  } else {
    skipped.push('Native window focus requires headed Chrome; headless contexts do not create OS windows.');
    console.log('SKIP',skipped.at(-1));
  }
  await page.keyboard.press('Escape');await waitState(page,'paused');
  await clickButton(page,page,'fullscreen');await page.waitForFunction(()=>!!document.fullscreenElement);
  check(await page.evaluate(()=>!!document.fullscreenElement),'Pause-menu fullscreen button enters browser fullscreen');
  await resume(page,page);
  await exitFullscreen(page);await waitState(page,'paused');await sleep(200);
  check(!(await locked(page)) && !(await page.evaluate(()=>!!document.fullscreenElement)),'Native fullscreen exit event pauses gameplay and releases mouse');
  await clickButton(page,page,'fullscreen');await page.waitForFunction(()=>!!document.fullscreenElement);await resume(page,page);
  await page.keyboard.press('Escape');await waitState(page,'paused');await sleep(200);
  check(!(await locked(page)),'Real Escape key in fullscreen pauses and releases mouse',{fullscreenAfterEscape:await page.evaluate(()=>!!document.fullscreenElement)});
  if(await page.evaluate(()=>!!document.fullscreenElement)) await exitFullscreen(page);
  await resume(page,page);await page.keyboard.press('Escape');await waitState(page,'paused');
  await clickButton(page,page,'restart');await waitState(page,'playing');await sleep(1000);
  const reset=await state(page);check(flatDistance(reset.position,[5.5,0,27])<0.05 && reset.desired_distance===4.8 && !reset.observing,'Restart restores spawn, camera distance and input state');
  await route(page);
  await clickButton(page,page,'menu');await waitState(page,'menu');
  await screenshot(page,'returned-menu');
  const standaloneErrors=errors.filter(e=>e.label==='standalone');
  check(standaloneErrors.length===0,'Standalone Chrome has no game script or runtime errors',{errors:standaloneErrors});
  const plain=await context.newPage();listen(plain,'ordinary-url');await plain.goto(BASE);
  await plain.waitForFunction(()=>typeof window.xiabanPause==='function');await sleep(300);
  check(await plain.evaluate(()=>typeof window.xiabanP1State==='undefined'),'Ordinary release URL does not enable the test observation bridge');
  await plain.bringToFront();await plain.mouse.click(576,415);await sleep(1200);
  check(await locked(plain),'Ordinary release URL also starts and keeps pointer lock');
  await hold(plain,'w',300);await screenshot(plain,'ordinary-release-playing');
  await plain.keyboard.press('Escape');await sleep(300);
  check(!(await locked(plain)) && logs.some(l=>l.label==='ordinary-url' && l.message==='P1_STATE paused'),'Ordinary release URL pauses and releases on Escape');
  await plain.close();
  // A same-origin sandboxed iframe exercises the hosted-game permission boundary.
  const embed=await context.newPage();listen(embed,'iframe');
  const embedURL=new URL('/p1-iframe-test',BASE).href;
  await embed.route(embedURL,route=>route.fulfill({contentType:'text/html',body:`<!doctype html><body style="margin:0"><button id="outside">Parent page focus</button><iframe title="P1" src="/?p1_qa=1" sandbox="allow-scripts allow-same-origin allow-pointer-lock" allow="fullscreen" allowfullscreen style="display:block;width:1152px;height:720px;border:0"></iframe></body>`}));
  await embed.goto(embedURL);await embed.setViewportSize({width:1200,height:800});
  const frame=embed.frames().find(f=>f.parentFrame());await waitState(frame,'menu');await embed.bringToFront();await resume(embed,frame);
  await hold(embed,'w',250);check((await state(frame)).travel_distance>0.5,'Sandbox iframe receives gameplay keyboard input');
  await embed.keyboard.press('Escape');await waitState(frame,'paused');
  await clickButton(embed,frame,'fullscreen');await frame.waitForFunction(()=>!!document.fullscreenElement);
  await resume(embed,frame);await exitFullscreen(frame);await waitState(frame,'paused');
  check(!(await locked(frame)),'Fullscreen exit also safely pauses the embedded game');
  await resume(embed,frame);
  // Chromium pointer lock hides the cursor: explicitly end the browser lock,
  // then focus the actual parent element. Both generate native DOM events.
  await frame.evaluate(()=>document.exitPointerLock());await waitState(frame,'paused');
  await embed.locator('#outside').click();await sleep(200);
  check((await state(frame)).phase==='paused','Focusing the iframe parent preserves paused state');
  await resume(embed,frame);await screenshot(embed,'iframe-playing');
  await embed.keyboard.press('Escape');await waitState(frame,'paused');
  const iframeErrors=errors.filter(e=>e.label==='iframe');check(iframeErrors.length===0,'Allowed sandbox iframe has no game runtime errors',{errors:iframeErrors});
  await embed.close();
  const denied=await context.newPage();listen(denied,'denied-iframe');
  const deniedURL=new URL('/p1-iframe-denied',BASE).href;
  await denied.route(deniedURL,route=>route.fulfill({contentType:'text/html',body:`<!doctype html><iframe src="/?p1_qa=1" sandbox="allow-scripts allow-same-origin" style="width:1152px;height:720px;border:0"></iframe>`}));
  await denied.goto(deniedURL);const noLock=denied.frames().find(f=>f.parentFrame());await waitState(noLock,'menu');await denied.bringToFront();
  await clickButton(denied,noLock,'primary');await waitState(noLock,'paused');await sleep(1000);
  check(!(await locked(noLock)) && (await state(noLock)).phase==='paused','Iframe denied pointer-lock permission returns to a usable paused state');
  await clickButton(denied,noLock,'menu');await waitState(noLock,'menu');check(true,'Denied-capture iframe can return to the menu');
  await screenshot(denied,'iframe-denied-menu');
  console.log('P1_BROWSER_RESULT',results.length,'passed');
})().catch(error=>{
  console.error(error.stack);results.push({pass:false,description:'Uncaught test failure',evidence:{message:error.message}});process.exitCode=1;
}).finally(async()=>{
  fs.writeFileSync(path.join(OUT,'report.json'),JSON.stringify({date:new Date().toISOString(),browserVersion,headless:HEADLESS,results,skipped,logs,errors},null,2));
  if(browser) await browser.close();
});
