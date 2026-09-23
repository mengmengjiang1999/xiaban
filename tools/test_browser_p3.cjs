/* P3 release acceptance through real browser keyboard/mouse input.
 * Read-only observations: ?p1_qa=1&p3_qa=1. No game state is injected.
 * Run against the exported game: node tools/test_browser_p3.cjs
 * P3_URL defaults to http://127.0.0.1:8769/; P3_HEADLESS=0 uses a window.
 * On macOS launch outside the filesystem sandbox; sandboxed Chrome can crash
 * during native initialization before it loads the game.
 */
const { chromium } = require('../.tools/browser-qa/node_modules/playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const BASE = process.env.P3_URL || 'http://127.0.0.1:8769/';
const HEADLESS = process.env.P3_HEADLESS !== '0';
const OUT = path.resolve('.logs/p3-browser');
const qaURL = new URL(BASE);
qaURL.searchParams.set('p1_qa', '1');
qaURL.searchParams.set('p3_qa', '1');
const ordinaryURL = new URL(BASE);
for (const key of ['p1_qa', 'p2_qa', 'p3_qa']) ordinaryURL.searchParams.delete(key);
const results = [], skipped = [], logs = [], errors = [], crashes = [];
const timings = {};
let browser, browserVersion, activePage;
let closingBrowser = false;
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
    if (/P[13]_/.test(record.message)) console.log('GAME', label, record.message);
    if (message.type() === 'error' && !record.message.includes('404')) errors.push(record);
    if (/webgl.*context.*lost|out of memory|runtimeerror|script error/i.test(record.message)) errors.push(record);
  });
  page.on('pageerror', error => errors.push({ label, type: 'pageerror', message: error.message }));
  page.on('crash', () => crashes.push({ label, type: 'page-crash', time: new Date().toISOString() }));
}

function expectedPermissionError(error) {
  return error.label === 'denied-iframe' && /pointer.?lock/i.test(error.message) && /sandbox|allow-pointer-lock/i.test(error.message);
}

async function state(frame) {
  return frame.evaluate(() => {
    if (!window.xiabanP1State || !window.xiabanP3State) return null;
    return { ...JSON.parse(window.xiabanP1State), ...JSON.parse(window.xiabanP3State) };
  });
}

async function waitState(frame, values, timeout = 10000) {
  if (typeof values === 'string') values = { phase: values };
  await frame.waitForFunction(expected => {
    if (!window.xiabanP1State || !window.xiabanP3State) return false;
    const snapshot = { ...JSON.parse(window.xiabanP1State), ...JSON.parse(window.xiabanP3State) };
    return Object.entries(expected).every(([key, value]) => snapshot[key] === value);
  }, values, { timeout });
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
  await page.mouse.click(box.x + (rect[0] + rect[2] / 2) * box.width / snapshot.viewport[0],
    box.y + (rect[1] + rect[3] / 2) * box.height / snapshot.viewport[1]);
}

async function resume(page, frame = page) {
  await clickButton(page, frame, 'primary');
  await waitState(frame, 'playing');
  await sleep(1000);
  check((await state(frame)).phase === 'playing' && await locked(frame),
    'Start/continue keeps pointer lock beyond the capture grace period');
}

async function restart(page) {
  if ((await state(page)).phase === 'playing') await page.keyboard.press('Escape');
  await waitState(page, 'paused');
  await clickButton(page, page, 'restart');
  await waitState(page, 'playing');
  await sleep(1000);
  const snapshot = await state(page);
  check(snapshot.stance === 'standing' && snapshot.state === 'idle' && snapshot.roll_progress === 0 && snapshot.noise_count === 0 &&
    snapshot.move_input === 0 && snapshot.turn_input === 0 && flatDistance(snapshot.position, [5.5, 0, 27]) < 0.03 && await locked(page),
  'Restart resets stance, one-shot progress, noise, controls and spawn', {
    stance: snapshot.stance, state: snapshot.state, position: snapshot.position, progress: snapshot.roll_progress, noise: snapshot.noise_count
  });
}

async function hold(page, keys, milliseconds) {
  if (!Array.isArray(keys)) keys = [keys];
  for (const key of keys) await page.keyboard.down(key);
  try { await sleep(milliseconds); } finally { for (const key of keys.reverse()) await page.keyboard.up(key); }
}

async function toggleCrouch(page, frame = page) {
  const was = (await state(frame)).stance;
  await page.keyboard.press('c');
  await waitState(frame, { stance: was === 'standing' ? 'crouched' : 'standing', transition_remaining: 0 });
  return state(frame);
}

async function measureMove(page, keys, milliseconds = 500) {
  const before = await state(page);
  for (const key of keys) await page.keyboard.down(key);
  let moving;
  try {
    await sleep(milliseconds);
    moving = await state(page);
  } finally { for (const key of [...keys].reverse()) await page.keyboard.up(key); }
  await sleep(120);
  const projected = (moving.position[0] - before.position[0]) * -Math.sin(before.heading) +
    (moving.position[2] - before.position[2]) * -Math.cos(before.heading);
  return { before, moving, projected, speed: flatDistance(before.position, moving.position) / (moving.elapsed - before.elapsed) };
}

async function standingAndCrouch(page) {
  const initial = await state(page);
  await screenshot(page, 'standing');
  check(initial.stance === 'standing' && initial.state === 'idle' && Math.abs(initial.collider_height - 1.8) < 0.001,
    'The player starts standing with the full-height collision capsule');
  await page.keyboard.press('Space');
  await sleep(200);
  const rejected = await state(page);
  check(rejected.state === 'idle' && rejected.roll_progress === 0 && flatDistance(rejected.position, initial.position) < 0.01,
    'Space while standing refuses to roll or move the player');
  const walk = await measureMove(page, ['w']);
  check(walk.projected > 0.55 && walk.moving.state === 'walk' && walk.moving.animation_status.action === 'walk' && walk.moving.animation_status.rate > 0,
    'W drives standing walk and positive animation playback', { projected: walk.projected, speed: walk.speed, animation: walk.moving.animation_status });
  await measureMove(page, ['s']);
  const crouched = await toggleCrouch(page);
  check(crouched.state === 'crouch_idle' && Math.abs(crouched.collider_height - 1.05) < 0.001 && Math.abs(crouched.position[1] - initial.position[1]) < 0.02,
    'C finishes crouching with a low capsule and unchanged foot height', { height: crouched.collider_height, y: crouched.position[1] });
  await page.keyboard.down('w');
  await sleep(350);
  const crouchForward = await state(page);
  await screenshot(page, 'crouch-walk');
  await page.keyboard.up('w');
  check(crouchForward.state === 'crouch_walk' && crouchForward.animation_status.action === 'crouch_walk' && crouchForward.animation_status.rate > 0 && flatDistance(crouchForward.position, crouched.position) > 0.18,
    'W while crouched moves with the crouch-walk clip', crouchForward.animation_status);
  await sleep(100);
  await page.keyboard.down('s');
  await waitState(page, { state: 'crouch_walk' });
  const times = [];
  for (let i = 0; i < 5; i++) {
    times.push((await state(page)).animation_status.time);
    await sleep(70);
  }
  const crouchBack = await state(page);
  await page.keyboard.up('s');
  check(crouchBack.animation_status.rate < 0 && times.filter((time, i) => i > 0 && time < times[i - 1] - 0.02).length >= 2 &&
    Math.abs(angle(crouchBack.heading, crouchForward.heading)) < 0.01,
  'S backs up in crouch and actually reverses animation time without turning', { times, rate: crouchBack.animation_status.rate });
  await sleep(120);
  const noSprint = await measureMove(page, ['Shift', 'w']);
  check(noSprint.moving.stance === 'crouched' && noSprint.moving.state === 'crouch_walk' && noSprint.speed < 1 && noSprint.moving.noise_count === 0,
    'Shift cannot sprint or emit sprint footsteps while crouched', { speed: noSprint.speed, noise: noSprint.moving.noise_count });
  const stood = await toggleCrouch(page);
  check(stood.stance === 'standing' && stood.state === 'idle' && Math.abs(stood.collider_height - 1.8) < 0.001,
    'C stands up again in unobstructed space');
  await page.keyboard.down('Shift');
  await page.keyboard.down('w');
  const sprintStart = await state(page);
  await sleep(400);
  const sprint = await state(page);
  await screenshot(page, 'sprinting');
  await page.keyboard.up('w');
  await page.keyboard.up('Shift');
  const sprintSpeed = flatDistance(sprint.position, sprintStart.position) / (sprint.elapsed - sprintStart.elapsed);
  check(sprint.state === 'sprint' && sprint.animation_status.action === 'run' && sprintSpeed > walk.speed * 1.8 && sprint.noise_count >= 2,
    'Shift+W sprints faster than walk, plays run and emits audible-footstep events', { walkSpeed: walk.speed, sprintSpeed, noise: sprint.noise_count });
  await sleep(300);
  const stopped = await state(page);
  await sleep(350);
  check(stopped.state === 'idle' && (await state(page)).noise_count === stopped.noise_count,
    'Releasing sprint input stops movement and new sprint-noise events');
  const backward = await measureMove(page, ['Shift', 's']);
  check(backward.moving.state === 'walk' && backward.projected < -0.5 && backward.speed < 2,
    'Shift+S remains normal backward walking instead of a backward sprint');
}

async function rollControl(page) {
  await restart(page);
  await toggleCrouch(page);
  const before = await state(page);
  await page.keyboard.down('Space');
  const began = await waitState(page, { state: 'roll' });
  check(began.animation_status.action === 'roll' && began.roll_remaining > 0 && began.roll_remaining <= 0.85,
    'Space from crouch begins the finite roll action', { remaining: began.roll_remaining, animation: began.animation_status });
  await page.keyboard.down('a');
  await page.keyboard.down('s');
  await page.keyboard.down('Shift');
  await page.mouse.down({ button: 'right' });
  await page.mouse.move(770, 365, { steps: 5 });
  await sleep(90);
  const observed = await state(page);
  await screenshot(page, 'roll-middle');
  check(observed.state === 'roll' && observed.observing && Math.abs(angle(observed.camera_yaw, before.camera_yaw)) > 0.10 &&
    Math.abs(angle(observed.heading, before.heading)) < 0.01 && observed.move_input === 0 && observed.turn_input === 0,
  'A/S/Shift and camera observation cannot change a roll already in progress', { heading: observed.heading, cameraYaw: observed.camera_yaw, progress: observed.roll_progress });
  await page.mouse.up({ button: 'right' });
  for (const key of ['a', 's', 'Shift']) await page.keyboard.up(key);
  const trace = [];
  const deadline = Date.now() + 2200;
  while (Date.now() < deadline) {
    // Repeated keydown carries the browser's repeat flag and exercises echo filtering.
    await page.keyboard.down('Space');
    trace.push(await state(page));
    if (trace.at(-1).state === 'crouch_idle' && trace.some(snapshot => snapshot.state === 'recovery')) break;
    await sleep(35);
  }
  check(trace.some(snapshot => snapshot.state === 'recovery' && snapshot.recovery_remaining > 0 && snapshot.recovery_remaining <= 0.2),
    'Roll enters its bounded recovery interval before returning to crouch');
  const end = await waitState(page, { state: 'crouch_idle' });
  for (let i = 0; i < 8; i++) { await page.keyboard.down('Space'); await sleep(80); }
  const held = await state(page);
  await page.keyboard.up('Space');
  const travelled = flatDistance(before.position, end.position);
  check(Math.abs(travelled - 2.4) < 0.08 && Math.abs(angle(end.heading, before.heading)) < 0.01 && end.stance === 'crouched',
    'An unobstructed roll travels 2.4 metres in the initially locked direction and ends crouched', { travelled, heading: end.heading, elapsedUntilIdle: end.elapsed - before.elapsed });
  check(held.state === 'crouch_idle' && flatDistance(held.position, end.position) < 0.01 && held.roll_progress === 1,
    'Holding Space and repeated keydown do not chain another roll');
  check(trace.every(snapshot => snapshot.noise_count === 0), 'Roll does not emit sprint footsteps');
  fs.writeFileSync(path.join(OUT, 'roll-frames.json'), JSON.stringify(trace, null, 2));
}

async function pauseRollAndCleanup(page) {
  await restart(page);
  await toggleCrouch(page);
  const before = await state(page);
  await page.keyboard.press('Space');
  await waitState(page, { state: 'roll' });
  for (const key of ['w', 'a', 'Shift']) await page.keyboard.down(key);
  await page.waitForFunction(() => {
    const snapshot = JSON.parse(window.xiabanP3State);
    return snapshot.state === 'roll' && snapshot.roll_progress > 0.38 && snapshot.roll_progress < 0.6;
  });
  // This pass retains the default camera, keeping the mid-roll body visible.
  // The separate observation pass can bring a nearby office sign in front of it.
  const picturedRollBefore = await state(page);
  await screenshot(page, 'roll-middle-clear');
  fs.writeFileSync(path.join(OUT, 'roll-middle-clear.json'), JSON.stringify({
    before: picturedRollBefore, after: await state(page), build: 'tested-build.json'
  }, null, 2));
  await page.keyboard.press('Escape');
  await waitState(page, 'paused');
  await sleep(80);
  const paused = await state(page);
  await screenshot(page, 'paused-roll');
  await sleep(350);
  const frozen = await state(page);
  check(paused.state === 'roll' && paused.roll_progress > 0.05 && paused.roll_progress < 0.8 && !(await locked(page)) && frozen.animation_status.paused,
    'Escape pauses in the middle of roll and releases the mouse', { progress: paused.roll_progress });
  check(Math.abs(frozen.roll_progress - paused.roll_progress) < 0.00001 && Math.abs(frozen.animation_status.time - paused.animation_status.time) < 0.001 &&
    Math.abs(frozen.elapsed - paused.elapsed) < 0.001 && distance(frozen.position, paused.position) < 0.001,
  'Paused roll freezes progress, animation, position and game time');
  await clickButton(page, page, 'primary');
  const resumed = await waitState(page, 'playing');
  check(resumed.state === 'roll' && resumed.roll_progress >= paused.roll_progress && resumed.roll_progress - paused.roll_progress < 0.15 &&
    resumed.animation_status.time >= paused.animation_status.time - 0.001,
  'Continue resumes the same roll without restarting its animation or progress', { paused: paused.roll_progress, resumed: resumed.roll_progress });
  await waitState(page, { state: 'crouch_idle' });
  await sleep(450);
  const settled = await state(page);
  await sleep(350);
  const still = await state(page);
  for (const key of ['w', 'a', 'Shift']) await page.keyboard.up(key);
  check(flatDistance(still.position, settled.position) < 0.01 && Math.abs(angle(still.heading, before.heading)) < 0.01 &&
    still.move_input === 0 && still.turn_input === 0 && still.noise_count === 0 && await locked(page),
  'Continue clears old held movement/turn/sprint inputs after the resumed roll finishes');
  check(Math.abs(flatDistance(before.position, still.position) - 2.4) < 0.08,
    'Pausing does not add to or truncate the total 2.4-metre roll distance');
  await page.keyboard.press('Space');
  await waitState(page, { state: 'roll' });
  await page.keyboard.press('Escape');
  await waitState(page, 'paused');
  await clickButton(page, page, 'menu');
  const menu = await waitState(page, 'menu');
  check(menu.roll_progress === 0 && menu.recovery_remaining === 0 && menu.state !== 'roll' && menu.animation_status.paused && !(await locked(page)),
    'Returning to menu cancels an in-flight roll and keeps the mouse released');
  await screenshot(page, 'returned-menu');
  await resume(page);
  const fresh = await state(page);
  check(fresh.stance === 'standing' && fresh.state === 'idle' && fresh.roll_progress === 0 && fresh.noise_count === 0 && flatDistance(fresh.position, [5.5, 0, 27]) < 0.03,
    'Starting from menu restores a clean standing player at spawn');
}

async function route(page) {
  const points = [[5.5, 21.5], [5.5, 17.4], [8.8, 17.4], [8.8, 13.25], [18.5, 13.25], [18.5, 8.4], [11.5, 8.4], [11.5, 6], [4.5, 6], [4.5, 3], [4.5, 1.5]];
  const held = new Set();
  const trace = [];
  async function set(key, down) {
    if (down === held.has(key)) return;
    if (down) { await page.keyboard.down(key); held.add(key); }
    else { await page.keyboard.up(key); held.delete(key); }
  }
  const deadline = Date.now() + 140000;
  try {
    for (let index = 0; index < points.length; index++) {
      while (Date.now() < deadline) {
        const snapshot = await state(page);
        trace.push({ elapsed: snapshot.elapsed, phase: snapshot.phase, position: snapshot.position,
          camera: snapshot.camera_position, heading: snapshot.heading, state: snapshot.state, animation: snapshot.animation_status.action });
        if (snapshot.phase === 'won') break;
        assert.equal(snapshot.phase, 'playing', 'Route stays playing');
        const dx = points[index][0] - snapshot.position[0];
        const dz = points[index][1] - snapshot.position[2];
        if (Math.hypot(dx, dz) < 0.17) break;
        const delta = angle(Math.atan2(-dx, -dz), snapshot.heading);
        await set('a', delta > 0.035);
        await set('d', delta < -0.035);
        await set('w', Math.abs(delta) < 0.14);
        await sleep(20);
      }
      for (const key of ['w', 'a', 'd']) await set(key, false);
      const snapshot = await state(page);
      console.log('ROUTE', index + 1, JSON.stringify(snapshot.position));
      if (index === 4) await screenshot(page, 'office-corner');
      if (snapshot.phase === 'won') break;
      assert.ok(Date.now() < deadline, 'Route completes within 140 seconds');
    }
    await waitState(page, 'won');
  } finally {
    for (const key of [...held]) await set(key, false);
    fs.writeFileSync(path.join(OUT, 'route-frames.json'), JSON.stringify(trace));
  }
  const completed = await state(page);
  check(completed.travel_distance > 35 && !(await locked(page)) && completed.state !== 'roll' && completed.roll_progress === 0,
    'Real browser movement completes the full office route and clears actions on completion', { time: completed.elapsed, distance: completed.travel_distance });
  check(trace.some(snapshot => snapshot.state === 'walk' && snapshot.animation === 'walk'),
    'The complete route uses the real human walk animation');
  await screenshot(page, 'completed');
}

async function ordinaryRelease(context) {
  const page = await context.newPage();
  activePage = page;
  listen(page, 'ordinary-url');
  await page.goto(ordinaryURL.href);
  await page.waitForFunction(() => typeof window.xiabanPause === 'function', null, { timeout: 30000 });
  await sleep(500);
  check(await page.evaluate(() => ['xiabanP1State', 'xiabanP2State', 'xiabanP3State'].every(key => typeof window[key] === 'undefined')),
    'An ordinary release URL exposes no QA state bridge');
  await page.bringToFront();
  await page.locator('canvas').focus();
  await page.keyboard.press('Enter');
  await sleep(1200);
  check(await locked(page), 'Enter starts the ordinary release with sustained pointer lock');
  await page.keyboard.press('c');
  await sleep(250);
  await hold(page, 'w', 300);
  await screenshot(page, 'ordinary-release-playing');
  await page.keyboard.press('Escape');
  await sleep(300);
  check(!(await locked(page)) && logs.some(record => record.label === 'ordinary-url' && record.message === 'P1_STATE paused'),
    'Escape pauses the ordinary release and releases its mouse');
  await page.close();
}

async function embeddedSmoke(context, allowPointerLock) {
  const label = allowPointerLock ? 'iframe' : 'denied-iframe';
  const page = await context.newPage();
  activePage = page;
  listen(page, label);
  await page.setViewportSize({ width: 1200, height: 800 });
  const address = new URL(`/p3-browser-${label}`, BASE).href;
  const permission = allowPointerLock ? ' allow-pointer-lock' : '';
  await page.route(address, intercepted => intercepted.fulfill({ contentType: 'text/html',
    body: `<!doctype html><body style="margin:0"><button id="outside">Parent page focus</button><iframe title="P3" src="${htmlEscape(qaURL.href)}" sandbox="allow-scripts allow-same-origin${permission}" allow="fullscreen" allowfullscreen style="display:block;width:1152px;height:720px;border:0"></iframe></body>` }));
  await page.goto(address);
  const frame = await page.locator('iframe').elementHandle().then(element => element.contentFrame());
  assert.ok(frame, 'Embedded game frame exists');
  await waitState(frame, 'menu', 30000);
  await page.bringToFront();
  if (allowPointerLock) {
    await resume(page, frame);
    await toggleCrouch(page, frame);
    await page.keyboard.down('w');
    await sleep(350);
    const moving = await state(frame);
    await page.keyboard.up('w');
    check(moving.stance === 'crouched' && moving.state === 'crouch_walk' && moving.travel_distance > 0.20,
      'A permitted iframe accepts real crouch and walking controls');
    await screenshot(page, 'iframe-crouch');
    await page.keyboard.press('Space');
    await waitState(frame, { state: 'roll' });
    await page.keyboard.press('Escape');
    const paused = await waitState(frame, 'paused');
    check(!(await locked(frame)) && paused.animation_status.paused && paused.state === 'roll',
      'The permitted iframe can pause its real roll and release capture');
  } else {
    await clickButton(page, frame, 'primary');
    await waitState(frame, 'paused');
    await sleep(1000);
    const snapshot = await state(frame);
    check(!(await locked(frame)) && snapshot.phase === 'paused' && snapshot.animation_status.paused,
      'Denied iframe pointer lock leaves a paused, usable game');
    await clickButton(page, frame, 'menu');
    await waitState(frame, 'menu');
    check(true, 'The denied-capture iframe can return to its menu');
    await screenshot(page, 'iframe-denied-menu');
  }
  await page.close();
}

(async () => {
  const pckURL = new URL('index.pck', BASE).href;
  const response = await fetch(pckURL);
  assert.ok(response.ok, `Served PCK is available: HTTP ${response.status}`);
  const pck = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(path.join(OUT, 'tested-build.json'), JSON.stringify({ recorded_at: new Date().toISOString(), served_url: pckURL,
    size_bytes: pck.length, sha256: createHash('sha256').update(pck).digest('hex') }, null, 2));
  const launchStarted = Date.now();
  browser = await chromium.launch({ channel: 'chrome', headless: HEADLESS });
  browser.on('disconnected', () => { if (!closingBrowser) crashes.push({ type: 'unexpected-browser-disconnect', time: new Date().toISOString() }); });
  timings.browserLaunchMs = Date.now() - launchStarted;
  browserVersion = await browser.version();
  console.log('BROWSER', browserVersion, HEADLESS ? 'headless' : 'headed');
  const context = await browser.newContext({ viewport: { width: 1152, height: 720 } });
  const page = await context.newPage();
  activePage = page;
  listen(page, 'standalone');
  const loadStarted = Date.now();
  await page.goto(qaURL.href);
  const menu = await waitState(page, 'menu', 30000);
  timings.initialMenuLoadMs = Date.now() - loadStarted;
  await page.bringToFront();
  await screenshot(page, 'menu');
  check(!(await locked(page)) && menu.animation_status.bones >= 15 && menu.animation_status.meshes >= 2,
    'P3 menu loads the skinned humanoid and leaves mouse capture released');
  await resume(page);
  await standingAndCrouch(page);
  await rollControl(page);
  await pauseRollAndCleanup(page);
  await route(page);
  await clickButton(page, page, 'menu');
  await waitState(page, 'menu');
  check(true, 'Completion returns to the menu');
  await ordinaryRelease(context);
  await embeddedSmoke(context, true);
  await embeddedSmoke(context, false);
  const unexpected = errors.filter(error => !expectedPermissionError(error));
  check(unexpected.length === 0, 'Browser scenarios have no unexpected script, canvas or runtime errors', { errors: unexpected });
  check(crashes.length === 0, 'Chrome and its game pages do not crash during this acceptance run', { crashes });
  skipped.push('Native OS window focus and native Godot rendering are not checked by this browser script.');
  skipped.push('Footstep event production is observed; human-perceived audio level is not measured.');
  if (HEADLESS) skipped.push('Headless Chrome supplies no native OS window; this is browser acceptance only.');
  console.log('P3_BROWSER_RESULT', results.filter(result => result.pass).length, 'passed');
})().catch(async error => {
  console.error(error.stack);
  if (activePage && !activePage.isClosed()) {
    try { await screenshot(activePage, 'failure'); } catch (_) { /* Keep the original failure. */ }
  }
  results.push({ pass: false, description: 'Uncaught test failure', evidence: { message: error.message } });
  process.exitCode = 1;
}).finally(async () => {
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({ date: new Date().toISOString(), url: BASE,
    coverage: 'full-P3-browser-acceptance', mode: HEADLESS ? 'headless' : 'headed', browserVersion, headless: HEADLESS,
    nativeWindowVerified: false, timings, pass: results.filter(result => result.pass).length,
    failed: results.filter(result => !result.pass).length, results, skipped, logs, errors, crashes,
    expectedPermissionErrors: errors.filter(expectedPermissionError), unexpectedErrors: errors.filter(error => !expectedPermissionError(error)) }, null, 2));
  closingBrowser = true;
  if (browser) await browser.close();
});
