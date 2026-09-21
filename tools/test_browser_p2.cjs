/* P2 release-build acceptance. Gameplay uses real browser keyboard/mouse input.
 * The opt-in p1_qa=1 / p2_qa=1 bridges are read-only observations.
 * Setup: npm install --prefix .tools/browser-qa playwright
 * Run after exporting/serving P2: node tools/test_browser_p2.cjs
 * P2_URL defaults to http://127.0.0.1:8767/; P2_HEADLESS=0 opts into a window.
 * P2_ASSET_ONLY=1 checks revised assets/controls in a separate report directory.
 */
const { chromium } = require('../.tools/browser-qa/node_modules/playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');

const BASE = process.env.P2_URL || 'http://127.0.0.1:8767/';
const HEADLESS = process.env.P2_HEADLESS !== '0';
const ASSET_ONLY = process.env.P2_ASSET_ONLY === '1';
const COVERAGE = ASSET_ONLY ? 'targeted-assets-and-controls' : 'full-browser-acceptance';
const OUT = path.resolve(ASSET_ONLY ? '.logs/p2-browser-assets' : '.logs/p2-browser');
const ACTIONS = ['idle', 'walk', 'run', 'crouch_idle', 'crouch_walk', 'roll'];
const qaURL = new URL(BASE);
qaURL.searchParams.set('p1_qa', '1');
qaURL.searchParams.set('p2_qa', '1');
const ordinaryURL = new URL(BASE);
ordinaryURL.searchParams.delete('p1_qa');
ordinaryURL.searchParams.delete('p2_qa');
const results = [];
const skipped = [];
const logs = [];
const errors = [];
let browser;
let browserVersion;
let activePage;
const timings = {};
fs.mkdirSync(OUT, { recursive: true });

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const angle = (a, b) => Math.atan2(Math.sin(a - b), Math.cos(a - b));
const flatDistance = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2]);
const distance = (a, b) => Math.hypot(...a.map((value, i) => value - b[i]));
const htmlEscape = text => text.replaceAll('&', '&amp;').replaceAll('"', '&quot;').replaceAll('<', '&lt;');

function check(condition, description, evidence = {}) {
  results.push({ pass: !!condition, description, evidence });
  console.log(`${condition ? 'PASS' : 'FAIL'}: ${description}`, JSON.stringify(evidence));
  assert.ok(condition, description);
}

function listen(page, label) {
  page.on('console', message => {
    const record = { label, type: message.type(), message: message.text() };
    logs.push(record);
    if (/P[12]_/.test(record.message)) console.log('GAME', label, record.message);
    if (message.type() === 'error' && !record.message.includes('404')) errors.push(record);
  });
  page.on('pageerror', error => errors.push({ label, type: 'pageerror', message: error.message }));
}

function expectedPermissionError(error) {
  // Chromium may report a deliberately denied sandbox request as either a
  // console error or a pageerror. Match the precise permission failure only.
  return error.label === 'denied-iframe' && /pointer.?lock/i.test(error.message) && /sandbox|allow-pointer-lock/i.test(error.message);
}

async function state(frame) {
  return frame.evaluate(() => {
    if (!window.xiabanP1State || !window.xiabanP2State) return null;
    return { ...JSON.parse(window.xiabanP1State), ...JSON.parse(window.xiabanP2State) };
  });
}

async function waitState(frame, phase) {
  await frame.waitForFunction(expected => {
    if (!window.xiabanP1State || !window.xiabanP2State) return false;
    return JSON.parse(window.xiabanP1State).phase === expected && JSON.parse(window.xiabanP2State).phase === expected;
  }, phase, { timeout: 30000 });
  return state(frame);
}

async function waitAction(frame, action, preview = action) {
  await frame.waitForFunction(expected => {
    if (!window.xiabanP2State) return false;
    const snapshot = JSON.parse(window.xiabanP2State);
    return snapshot.preview_action === expected.preview && snapshot.animation_status.action === expected.action;
  }, { action, preview }, { timeout: 5000 });
  return state(frame);
}

async function locked(frame) {
  return frame.evaluate(() => document.pointerLockElement?.tagName === 'CANVAS');
}

async function screenshot(page, name) {
  await page.screenshot({ path: path.join(OUT, `${name}.png`) });
}

async function clickButton(page, frame, name) {
  const snapshot = await state(frame);
  const button = snapshot.buttons[name];
  assert.ok(button?.visible, `Visible ${name} button`);
  const box = await frame.locator('canvas').boundingBox();
  assert.ok(box, 'Canvas has browser geometry');
  const rect = button.rect;
  await page.mouse.click(
    box.x + (rect[0] + rect[2] / 2) * box.width / snapshot.viewport[0],
    box.y + (rect[1] + rect[3] / 2) * box.height / snapshot.viewport[1]
  );
}

async function resume(page, frame, description = 'Start/continue maintains pointer lock beyond capture grace') {
  await clickButton(page, frame, 'primary');
  await waitState(frame, 'playing');
  await sleep(1100);
  check((await state(frame)).phase === 'playing' && await locked(frame), description);
}

async function hold(page, key, duration) {
  await page.keyboard.down(key);
  try { await sleep(duration); } finally { await page.keyboard.up(key); }
  await sleep(100);
}

async function advancingTimes(frame, count = 5) {
  const samples = [];
  for (let i = 0; i < count; i++) {
    samples.push((await state(frame)).animation_status.time);
    await sleep(90);
  }
  // Looping clips can wrap, so progression does not require monotonic time.
  return { samples, advances: samples.some((time, i) => i > 0 && Math.abs(time - samples[i - 1]) > 0.02) };
}

async function loopingTimes(frame) {
  const samples = [];
  const deadline = Date.now() + 8000;
  let wrapIndex = -1;
  while (Date.now() < deadline) {
    const time = (await state(frame)).animation_status.time;
    samples.push(time);
    const index = samples.length - 1;
    if (index > 0 && time < samples[index - 1] - 0.1) wrapIndex = index;
    // Require a real loop boundary followed by fresh forward playback.
    if (wrapIndex >= 0 && index > wrapIndex && time - samples[wrapIndex] > 0.04) break;
    await sleep(90);
  }
  return { samples, looped: wrapIndex >= 0 && samples.at(-1) - samples[wrapIndex] > 0.04 };
}

async function movementAndCamera(page) {
  const initial = await state(page);
  await page.keyboard.down('w');
  await sleep(500);
  const forward = await state(page);
  await page.keyboard.up('w');
  const direction = [-Math.sin(initial.heading), -Math.cos(initial.heading)];
  const projected = (forward.position[0] - initial.position[0]) * direction[0] + (forward.position[2] - initial.position[2]) * direction[1];
  check(projected > 0.45 && Math.abs(angle(forward.heading, initial.heading)) < 0.01,
    'W moves forward along the actor heading', { projected });
  check(forward.animation_status.action === 'walk' && forward.animation_status.rate > 0 && !forward.animation_status.paused,
    'Forward movement plays the imported walk animation', forward.animation_status);
  await sleep(120);
  const beforeBack = await state(page);
  await page.keyboard.down('s');
  await waitAction(page, 'walk', '');
  const backwardTimes = [];
  for (let i = 0; i < 5; i++) {
    backwardTimes.push((await state(page)).animation_status.time);
    await sleep(70);
  }
  const backward = await state(page);
  await page.keyboard.up('s');
  const backProjected = (backward.position[0] - beforeBack.position[0]) * direction[0] + (backward.position[2] - beforeBack.position[2]) * direction[1];
  check(backProjected < -0.30 && Math.abs(angle(backward.heading, beforeBack.heading)) < 0.01 && Math.abs(angle(backward.camera_yaw, beforeBack.camera_yaw)) < 0.02,
    'S backs up without rotating the actor or camera', { projected: backProjected });
  check(backward.animation_status.action === 'walk' && backward.animation_status.rate < 0,
    'Backward movement reverses the imported walk animation', backward.animation_status);
  check(backwardTimes.filter((time, i) => i > 0 && time < backwardTimes[i - 1] - 0.02).length >= 2,
    'Holding S actually advances walk animation time backwards', { times: backwardTimes });
  await sleep(100);
  await hold(page, 'a', 250);
  const left = await state(page);
  check(angle(left.heading, backward.heading) > 0.3 && flatDistance(left.position, backward.position) < 0.06,
    'A turns left without strafing');
  await hold(page, 'd', 250);
  const right = await state(page);
  check(angle(right.heading, left.heading) < -0.3 && flatDistance(right.position, left.position) < 0.03,
    'D turns right without strafing');
  await sleep(800);
  const beforeOrbit = await state(page);
  await page.mouse.down({ button: 'right' });
  await page.mouse.move(750, 350, { steps: 8 });
  await sleep(150);
  const orbit = await state(page);
  check(orbit.observing && Math.abs(angle(orbit.camera_yaw, beforeOrbit.camera_yaw)) > 0.2 && Math.abs(angle(orbit.heading, beforeOrbit.heading)) < 0.01,
    'Right drag orbits the camera without turning the actor');
  await hold(page, 'w', 250);
  const observingWalk = await state(page);
  const observedTravel = (observingWalk.position[0] - orbit.position[0]) * -Math.sin(orbit.heading) + (observingWalk.position[2] - orbit.position[2]) * -Math.cos(orbit.heading);
  check(Math.abs(angle(observingWalk.camera_yaw, orbit.camera_yaw)) < 0.02 && observedTravel > 0.20,
    'Observation keeps its angle while W remains actor-relative', { projected: observedTravel });
  await page.mouse.up({ button: 'right' });
  await sleep(600);
  const released = await state(page);
  check(!released.observing && Math.abs(angle(released.camera_yaw, orbit.camera_yaw)) < 0.02,
    'Stationary release retains the observation angle');
  await page.mouse.wheel(0, -120);
  await sleep(200);
  const closer = await state(page);
  await page.mouse.wheel(0, 120);
  await sleep(200);
  const farther = await state(page);
  check(closer.desired_distance < released.desired_distance && farther.desired_distance > closer.desired_distance,
    'Mouse wheel changes camera distance in both directions');
  await page.mouse.wheel(0, 120);
  await sleep(150);
  const chosen = (await state(page)).desired_distance;
  await page.keyboard.press('f');
  await sleep(1300);
  const centered = await state(page);
  check(Math.abs(angle(centered.camera_yaw, centered.heading)) < 0.015 && centered.desired_distance === chosen,
    'F recenters on the actor heading and preserves zoom');
  await screenshot(page, 'camera-controls');
}

async function previews(page) {
  const baseline = await state(page);
  for (let i = 0; i < ACTIONS.length; i++) {
    const action = ACTIONS[i];
    await page.keyboard.press(String(i + 1));
    await waitAction(page, action);
    const timing = await loopingTimes(page);
    const snapshot = await state(page);
    check(snapshot.preview_action === action && snapshot.animation_status.action === action && timing.looped && !snapshot.animation_status.paused,
      `Key ${i + 1} previews ${action} through a loop and continues playing`, timing);
    check(flatDistance(snapshot.position, baseline.position) < 0.01 && Math.abs(angle(snapshot.heading, baseline.heading)) < 0.01 && distance(snapshot.camera_position, baseline.camera_position) < 0.025 && Math.abs(angle(snapshot.camera_yaw, baseline.camera_yaw)) < 0.01,
      `${action} leaves the stationary actor transform and camera unchanged`, {
        actorDrift: flatDistance(snapshot.position, baseline.position),
        cameraDrift: distance(snapshot.camera_position, baseline.camera_position)
      });
    await screenshot(page, `preview-${i + 1}-${action}`);
  }
  await page.keyboard.press('5');
  await waitAction(page, 'crouch_walk');
  const beforeHeld = await state(page);
  await page.keyboard.down('w');
  await page.keyboard.down('a');
  try { await sleep(500); } finally {
    await page.keyboard.up('w');
    await page.keyboard.up('a');
  }
  const afterHeld = await state(page);
  check(flatDistance(afterHeld.position, beforeHeld.position) < 0.01 && Math.abs(angle(afterHeld.heading, beforeHeld.heading)) < 0.01 && distance(afterHeld.camera_position, beforeHeld.camera_position) < 0.025 && afterHeld.move_input === 0 && afterHeld.turn_input === 0,
    'Holding W/A during a preview cannot move or turn the actor or its camera');
  // Pause well inside the clip so a mistaken restart at zero is distinguishable.
  await page.waitForFunction(() => {
    const time = JSON.parse(window.xiabanP2State).animation_status.time;
    return time > 0.4 && time < 0.7;
  }, null, { timeout: 6000 });
  await page.keyboard.press('Escape');
  await waitState(page, 'paused');
  await sleep(100);
  const paused = await state(page);
  await sleep(400);
  const frozen = await state(page);
  check(!(await locked(page)) && frozen.animation_status.paused && Math.abs(frozen.animation_status.time - paused.animation_status.time) < 0.001 && Math.abs(frozen.elapsed - paused.elapsed) < 0.001 && distance(frozen.position, paused.position) < 0.001,
    'Escape releases the mouse and freezes animation, game time and position', { before: paused.animation_status.time, after: frozen.animation_status.time });
  await screenshot(page, 'paused-preview');
  await clickButton(page, page, 'primary');
  const firstResumed = await waitState(page, 'playing');
  const expectedTime = frozen.animation_status.time + (firstResumed.elapsed - frozen.elapsed);
  check(Math.abs(firstResumed.animation_status.time - expectedTime) < 0.10,
    'Continue resumes from the paused animation time without restarting the clip', {
      pausedTime: frozen.animation_status.time, resumedTime: firstResumed.animation_status.time, expectedTime
    });
  await sleep(1100);
  check((await state(page)).phase === 'playing' && await locked(page),
    'Continue resumes the preview and maintains pointer lock');
  const continued = await state(page);
  const continuedTiming = await advancingTimes(page);
  check(continued.preview_action === 'crouch_walk' && continued.animation_status.action === 'crouch_walk' && !continued.animation_status.paused && continuedTiming.advances && flatDistance(continued.position, frozen.position) < 0.01,
    'Continue preserves the selected clip and resumes its animation without movement', continuedTiming);
  await page.keyboard.press('0');
  await waitAction(page, 'idle', '');
  const normal = await state(page);
  await page.keyboard.down('w');
  await sleep(350);
  const walking = await state(page);
  await page.keyboard.up('w');
  check(walking.preview_action === '' && walking.animation_status.action === 'walk' && flatDistance(walking.position, normal.position) > 0.3,
    'Key 0 returns from preview to normal walking');
  await sleep(150);
  await page.keyboard.press('6');
  await waitAction(page, 'roll');
  await page.keyboard.press('Escape');
  await waitState(page, 'paused');
  await clickButton(page, page, 'restart');
  await waitState(page, 'playing');
  await sleep(1100);
  const reset = await state(page);
  check(reset.preview_action === '' && reset.animation_status.action === 'idle' && !reset.animation_status.paused && flatDistance(reset.position, [5.5, 0, 27]) < 0.05 && reset.desired_distance === 4.8 && !reset.observing && reset.move_input === 0 && reset.turn_input === 0 && await locked(page),
    'Restart clears preview and restores the spawn, camera and neutral controls', reset.animation_status);
}

async function route(page) {
  // Record rendered snapshots without passing any data back to the game.
  await page.evaluate(() => {
    window.p2RouteTrace = [];
    window.p2RecordingRoute = true;
    const sample = () => {
      if (!window.p2RecordingRoute) return;
      const first = window.xiabanP1State && JSON.parse(window.xiabanP1State);
      const second = window.xiabanP2State && JSON.parse(window.xiabanP2State);
      if (first && second) window.p2RouteTrace.push({
        time: first.elapsed, phase: first.phase, position: first.position,
        camera: first.camera_position, yaw: first.camera_yaw, alpha: first.camera_alpha,
        action: second.animation_status.action, animationTime: second.animation_status.time,
        rate: second.animation_status.rate
      });
      requestAnimationFrame(sample);
    };
    requestAnimationFrame(sample);
  });
  const points = [[5.5, 21.5], [5.5, 17.4], [8.8, 17.4], [8.8, 13.25], [18.5, 13.25], [18.5, 8.4], [11.5, 8.4], [11.5, 6], [4.5, 6], [4.5, 3], [4.5, 1.5]];
  const held = new Set();
  async function set(key, down) {
    if (down === held.has(key)) return;
    if (down) { await page.keyboard.down(key); held.add(key); }
    else { await page.keyboard.up(key); held.delete(key); }
  }
  const deadline = Date.now() + 140000;
  let trace = [];
  try {
    for (let i = 0; i < points.length; i++) {
      while (Date.now() < deadline) {
        const snapshot = await state(page);
        if (snapshot.phase === 'won') break;
        assert.equal(snapshot.phase, 'playing', 'Route stays playing');
        const dx = points[i][0] - snapshot.position[0];
        const dz = points[i][1] - snapshot.position[2];
        if (Math.hypot(dx, dz) < 0.17) break;
        const delta = angle(Math.atan2(-dx, -dz), snapshot.heading);
        await set('a', delta > 0.035);
        await set('d', delta < -0.035);
        await set('w', Math.abs(delta) < 0.14);
        await sleep(20);
      }
      for (const key of ['w', 'a', 'd']) await set(key, false);
      const snapshot = await state(page);
      console.log('ROUTE', i + 1, JSON.stringify(snapshot.position));
      if (i === 4) await screenshot(page, 'office-corner');
      if (snapshot.phase === 'won') break;
      assert.ok(Date.now() < deadline, 'Route completes within the 140 second budget');
    }
    await waitState(page, 'won');
  } finally {
    for (const key of [...held]) await set(key, false);
    trace = await page.evaluate(() => { window.p2RecordingRoute = false; return window.p2RouteTrace; });
    fs.writeFileSync(path.join(OUT, 'route-frames.json'), JSON.stringify(trace));
  }
  let sampledFrames = 0;
  let maxCameraSpeed = 0;
  let maxCameraStep = 0;
  for (let i = 1; i < trace.length; i++) {
    const previous = trace[i - 1], current = trace[i];
    const delta = current.time - previous.time;
    if (previous.phase !== 'playing' || current.phase !== 'playing' || delta <= 0) continue;
    sampledFrames++;
    const step = distance(current.camera, previous.camera);
    maxCameraStep = Math.max(maxCameraStep, step);
    maxCameraSpeed = Math.max(maxCameraSpeed, step / delta);
  }
  check(sampledFrames > 300 && maxCameraSpeed < 21,
    'The rendered humanoid route has no abrupt camera jumps', { sampledFrames, maxCameraSpeed, maxCameraStep });
  const completed = await state(page);
  check(completed.travel_distance > 35 && !(await locked(page)),
    'Real browser keyboard input completes the office route and releases the mouse', { time: completed.elapsed, distance: completed.travel_distance });
  check(trace.some(sample => sample.action === 'walk' && sample.rate > 0),
    'The office route drives the imported walk animation');
  await screenshot(page, 'completed');
}

async function ordinaryRelease(context) {
  const page = await context.newPage();
  activePage = page;
  listen(page, 'ordinary-url');
  await page.goto(ordinaryURL.href);
  await page.waitForFunction(() => typeof window.xiabanPause === 'function', null, { timeout: 30000 });
  await sleep(500);
  check(await page.evaluate(() => typeof window.xiabanP1State === 'undefined' && typeof window.xiabanP2State === 'undefined'),
    'An ordinary release URL publishes neither QA observation bridge');
  await page.bringToFront();
  await page.locator('canvas').focus();
  await page.keyboard.press('Enter');
  await sleep(1200);
  check(await locked(page), 'Enter starts the ordinary release and maintains pointer lock');
  await hold(page, 'w', 300);
  await screenshot(page, 'ordinary-release-playing');
  await page.keyboard.press('Escape');
  await sleep(300);
  check(!(await locked(page)) && logs.some(record => record.label === 'ordinary-url' && record.message === 'P1_STATE paused'),
    'The ordinary release pauses and releases the mouse on Escape');
  await page.close();
}

async function embeddedSmoke(context, allowPointerLock) {
  const label = allowPointerLock ? 'iframe' : 'denied-iframe';
  const page = await context.newPage();
  activePage = page;
  listen(page, label);
  await page.setViewportSize({ width: 1200, height: 800 });
  const address = new URL(`/p2-browser-${label}`, BASE).href;
  const permission = allowPointerLock ? ' allow-pointer-lock' : '';
  await page.route(address, intercepted => intercepted.fulfill({
    contentType: 'text/html',
    body: `<!doctype html><body style="margin:0"><button id="outside">Parent page focus</button><iframe title="P2" src="${htmlEscape(qaURL.href)}" sandbox="allow-scripts allow-same-origin${permission}" allow="fullscreen" allowfullscreen style="display:block;width:1152px;height:720px;border:0"></iframe></body>`
  }));
  await page.goto(address);
  const frame = await page.locator('iframe').elementHandle().then(element => element.contentFrame());
  assert.ok(frame, 'Embedded game frame exists');
  await waitState(frame, 'menu');
  await page.bringToFront();
  if (allowPointerLock) {
    await resume(page, frame, 'The permitted sandbox iframe starts with pointer lock');
    await hold(page, 'w', 300);
    check((await state(frame)).travel_distance > 0.20, 'The permitted iframe receives real keyboard movement');
    await page.keyboard.press('5');
    await waitAction(frame, 'crouch_walk');
    const timing = await advancingTimes(frame);
    check(timing.advances, 'The permitted iframe plays an imported crouch-walk preview', timing);
    await screenshot(page, 'iframe-preview');
    await page.keyboard.press('Escape');
    await waitState(frame, 'paused');
    check(!(await locked(frame)) && (await state(frame)).animation_status.paused,
      'Escape also releases the mouse and pauses the embedded animation');
  } else {
    await clickButton(page, frame, 'primary');
    await waitState(frame, 'paused');
    await sleep(1000);
    const snapshot = await state(frame);
    check(!(await locked(frame)) && snapshot.phase === 'paused' && snapshot.animation_status.paused,
      'An iframe denied pointer lock returns to a paused, usable state');
    await clickButton(page, frame, 'menu');
    await waitState(frame, 'menu');
    check(true, 'The denied-capture iframe can return to its menu');
    await screenshot(page, 'iframe-denied-menu');
  }
  await page.close();
}

(async () => {
  console.log('COVERAGE', COVERAGE);
  const pckURL = new URL('index.pck', BASE).href;
  const response = await fetch(pckURL);
  assert.ok(response.ok, `Served PCK is available: HTTP ${response.status}`);
  const pck = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(path.join(OUT, 'tested-build.json'), JSON.stringify({
    recorded_at: new Date().toISOString(), served_url: pckURL, coverage: COVERAGE,
    size_bytes: pck.length, sha256: createHash('sha256').update(pck).digest('hex')
  }, null, 2));
  const launchStarted = Date.now();
  browser = await chromium.launch({ channel: 'chrome', headless: HEADLESS });
  timings.browserLaunchMs = Date.now() - launchStarted;
  browserVersion = await browser.version();
  console.log('BROWSER', browserVersion, HEADLESS ? 'headless' : 'headed');
  const context = await browser.newContext({ viewport: { width: 1152, height: 720 } });
  const page = await context.newPage();
  activePage = page;
  listen(page, 'standalone');
  const loadStarted = Date.now();
  await page.goto(qaURL.href);
  const menu = await waitState(page, 'menu');
  timings.initialMenuLoadMs = Date.now() - loadStarted;
  console.log('INITIAL_MENU_LOAD_MS', timings.initialMenuLoadMs);
  await page.bringToFront();
  await screenshot(page, 'menu');
  check(!(await locked(page)), 'The P2 menu leaves the mouse released');
  check(menu.animation_status.bones >= 15 && menu.animation_status.meshes >= 2,
    'P2 loads a skinned humanoid with real bones and multiple meshes', menu.animation_status);
  check(ACTIONS.every(action => menu.animation_status.actions.includes(action)),
    'The imported humanoid contains all six required animation clips', { actions: menu.animation_status.actions });
  await resume(page, page);
  await movementAndCamera(page);
  await previews(page);
  if (ASSET_ONLY) {
    skipped.push('Targeted revised-asset coverage: office route, ordinary URL and iframe scenarios retain their separate full-run evidence.');
  } else {
    await route(page);
    await clickButton(page, page, 'menu');
    await waitState(page, 'menu');
    check(true, 'The completed humanoid route can return to the menu');
    await screenshot(page, 'returned-menu');
    await ordinaryRelease(context);
    await embeddedSmoke(context, true);
    await embeddedSmoke(context, false);
  }
  const unexpected = errors.filter(error => !expectedPermissionError(error));
  check(unexpected.length === 0, 'Browser scenarios have no unexpected script or runtime errors', { errors: unexpected });
  skipped.push('Native application/window focus and native Godot rendering are not verified by this browser script.');
  if (HEADLESS) skipped.push('Headless Chrome does not provide a native OS window; its results are browser acceptance only.');
  console.log('P2_BROWSER_RESULT', COVERAGE, results.filter(result => result.pass).length, 'passed');
})().catch(async error => {
  console.error(error.stack);
  if (activePage && !activePage.isClosed()) {
    try { await screenshot(activePage, 'failure'); } catch (_) { /* Preserve the original failure. */ }
  }
  results.push({ pass: false, description: 'Uncaught test failure', evidence: { message: error.message } });
  process.exitCode = 1;
}).finally(async () => {
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({
    date: new Date().toISOString(), url: BASE, coverage: COVERAGE,
    mode: HEADLESS ? 'headless' : 'headed', version: browserVersion,
    browserVersion, headless: HEADLESS, nativeWindowVerified: false,
    timings,
    pass: results.filter(result => result.pass).length,
    failed: results.filter(result => !result.pass).length,
    results, skipped, logs, errors,
    expectedPermissionErrors: errors.filter(expectedPermissionError),
    unexpectedErrors: errors.filter(error => !expectedPermissionError(error))
  }, null, 2));
  if (browser) await browser.close();
});
