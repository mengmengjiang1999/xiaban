/* P4 release acceptance through real browser keyboard/mouse input.
 * Read-only observations: ?p1_qa=1&p3_qa=1&p4_qa=1. No game state is injected.
 * Run against the exported game: node tools/test_browser_p4.cjs
 * P4_URL defaults to http://127.0.0.1:8770/; P4_HEADLESS=0 uses a window.
 * On macOS launch outside the filesystem sandbox; sandboxed Chrome can crash
 * during native initialization before it loads the game.
 */
const { chromium } = require('../.tools/browser-qa/node_modules/playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const BASE = process.env.P4_URL || 'http://127.0.0.1:8770/';
const HEADLESS = process.env.P4_HEADLESS !== '0';
const OUT = path.resolve('.logs/p4-browser');
const qaURL = new URL(BASE);
qaURL.searchParams.set('p1_qa', '1');
qaURL.searchParams.set('p3_qa', '1');
qaURL.searchParams.set('p4_qa', '1');
const ordinaryURL = new URL(BASE);
for (const key of ['p1_qa', 'p2_qa', 'p3_qa', 'p4_qa']) ordinaryURL.searchParams.delete(key);
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
    if (/P[134]_/.test(record.message)) console.log('GAME', label, record.message);
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
    if (!window.xiabanP1State || !window.xiabanP3State || !window.xiabanP4State) return null;
    return { ...JSON.parse(window.xiabanP1State), ...JSON.parse(window.xiabanP3State), ...JSON.parse(window.xiabanP4State) };
  });
}

async function waitState(frame, values, timeout = 10000) {
  if (typeof values === 'string') values = { phase: values };
  await frame.waitForFunction(expected => {
    if (!window.xiabanP1State || !window.xiabanP3State || !window.xiabanP4State) return false;
    const snapshot = { ...JSON.parse(window.xiabanP1State), ...JSON.parse(window.xiabanP3State), ...JSON.parse(window.xiabanP4State) };
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
  const before = await state(page);
  if (before.phase === 'playing') {
    await page.keyboard.press('Escape');
    await waitState(page, 'paused');
  }
  const current = await state(page);
  await clickButton(page, page, current.phase === 'paused' ? 'restart' : 'primary');
  await waitState(page, 'playing');
  await sleep(350);
  const snapshot = await state(page);
  check(snapshot.stance === 'standing' && snapshot.state === 'idle' && snapshot.roll_progress === 0 && snapshot.noise_count === 0 &&
    snapshot.move_input === 0 && snapshot.turn_input === 0 && flatDistance(snapshot.position, snapshot.spawn) < 0.03 && await locked(page) &&
    snapshot.guard.state === 'working' && !snapshot.guard.confirmed && snapshot.guard.heard_origin === null && snapshot.guard.progress === 0,
  'Restart resets player controls, office work, sound target, detection and spawn');
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

async function waitGuard(page, guardState, timeout = 12000) {
  await page.waitForFunction(expected => window.xiabanP4State &&
    JSON.parse(window.xiabanP4State).guard.state === expected, guardState, { timeout });
  return state(page);
}

async function moveTo(page, x, z, limit = 20000) {
  const held = new Set();
  const trace = [];
  async function set(key, down) {
    if (down === held.has(key)) return;
    if (down) { await page.keyboard.down(key); held.add(key); }
    else { await page.keyboard.up(key); held.delete(key); }
  }
  const deadline = Date.now() + limit;
  try {
    while (Date.now() < deadline) {
      const snapshot = await state(page);
      trace.push({ elapsed: snapshot.elapsed, phase: snapshot.phase, position: snapshot.position,
        heading: snapshot.heading, state: snapshot.state, guard: snapshot.guard });
      if (snapshot.phase === 'won') return trace;
      assert.equal(snapshot.phase, 'playing', 'Real movement remains in the playable encounter');
      const dx = x - snapshot.position[0], dz = z - snapshot.position[2];
      if (Math.hypot(dx, dz) < 0.07) return trace;
      const delta = angle(Math.atan2(-dx, -dz), snapshot.heading);
      await set('a', delta > 0.025);
      await set('d', delta < -0.025);
      await set('w', Math.abs(delta) < 0.12);
      await sleep(15);
    }
    assert.fail(`Movement to ${x}, ${z} exceeded its deadline`);
  } finally {
    for (const key of [...held]) await set(key, false);
  }
}

async function coverFailureAndRetry(page) {
  await moveTo(page, 5.5, 8.8);
  await toggleCrouch(page);
  await waitGuard(page, 'watching');
  const behind = await state(page);
  await screenshot(page, 'crouched-behind-cover');
  await sleep(800);
  const hidden = await state(page);
  check(hidden.phase === 'playing' && hidden.stance === 'crouched' && hidden.guard.state === 'watching' &&
    hidden.guard.fan_visible && hidden.guard.progress === 0 && !hidden.guard.confirmed &&
    flatDistance(behind.position, hidden.position) < 0.01,
  'Real C input hides the crouched player behind the low cabinet for sustained active observation');
  const trace = [];
  await page.keyboard.press('c');
  const deadline = Date.now() + 1800;
  while (Date.now() < deadline) {
    const snapshot = await state(page);
    trace.push(snapshot);
    if (snapshot.phase === 'lost') break;
    await sleep(18);
  }
  const lost = await waitState(page, 'lost');
  check(lost.stance === 'standing' && flatDistance(lost.position, hidden.position) < 0.01 && lost.guard.confirmed &&
    trace.some(s => s.guard.progress > 0 && s.guard.progress < 1 && s.phase === 'playing'),
  'Standing at the same position exposes the body, accumulates confirmation and produces failure');
  check(lost.guard.frozen && lost.animation_status.paused && !await locked(page) && lost.move_input === 0 && lost.turn_input === 0,
    'The failure screen freezes both characters, releases the mouse and clears movement');
  await screenshot(page, 'discovered');
  fs.writeFileSync(path.join(OUT, 'discovery-frames.json'), JSON.stringify(trace, null, 2));
  await restart(page);
}

async function unguardedAttempt(page) {
  await page.keyboard.down('w');
  let lost;
  try { lost = await waitState(page, 'lost', 10000); }
  finally { await page.keyboard.up('w'); }
  check(lost.guard.confirmed && lost.stance === 'standing' && lost.noise_count === 0 && lost.position[2] > lost.exit_rect[1] + lost.exit_rect[3],
    'Ordinary W held from the start is discovered before the exit, so the route requires a stealth decision');
  await screenshot(page, 'unguarded-attempt-discovered');
  await restart(page);
}

async function sprintSound(page) {
  // The first footstep occurs while still shielded by the tall cabinet.
  await hold(page, ['Shift', 'w'], 120);
  const raised = await state(page);
  check(raised.noise_count > 0 && raised.guard.noise_attention && raised.guard.state === 'raising' &&
    raised.guard.heard_origin !== null && raised.phase === 'playing',
  'Real sprint movement emits a sound that makes the hidden office leader begin raising its head');
  const heard = raised.guard.heard_origin;
  await waitGuard(page, 'watching');
  await sleep(420);
  const watching = await state(page);
  const dx = heard[0] - watching.guard.position[0], dz = heard[2] - watching.guard.position[2];
  const alignment = (watching.guard.facing[0] * dx + watching.guard.facing[2] * dz) / Math.hypot(dx, dz);
  check(watching.phase === 'playing' && watching.guard.progress === 0 && alignment > 0.99 &&
    distance(watching.guard.position, raised.guard.position) < 0.001 &&
    distance(watching.guard.heard_origin, heard) < 0.001,
  'The leader watches the recorded sound location from its desk without seeing through the tall cabinet');
  await screenshot(page, 'heard-footstep');
  await waitGuard(page, 'working');
  const settled = await state(page);
  check(settled.phase === 'playing' && !settled.guard.noise_attention && !settled.guard.fan_visible,
    'The leader finishes its sound reaction and resumes work without an automatic failure');
  await restart(page);
}

async function pauseAndFocus(page, context) {
  await waitGuard(page, 'raising');
  await sleep(160);
  await page.keyboard.press('Escape');
  const paused = await waitState(page, 'paused');
  await sleep(400);
  const frozen = await state(page);
  check(paused.guard.state === 'raising' && frozen.guard.state_time === paused.guard.state_time &&
    frozen.guard.visual_time === paused.guard.visual_time && distance(frozen.guard.head_position, paused.guard.head_position) < 0.00001 &&
    frozen.elapsed === paused.elapsed && frozen.animation_status.time === paused.animation_status.time && !await locked(page),
  'Escape freezes the live head-raising animation, both game clocks and the player animation');
  await screenshot(page, 'paused-telegraph');
  await clickButton(page, page, 'primary');
  const resumed = await waitState(page, 'playing');
  check(resumed.guard.state === 'raising' && resumed.guard.state_time >= paused.guard.state_time &&
    resumed.guard.state_time - paused.guard.state_time < 0.2 && await locked(page),
  'Continue resumes the same office telegraph and reacquires pointer lock');
  const foreground = await context.newPage();
  await foreground.goto('about:blank');
  await foreground.bringToFront();
  await waitState(page, 'paused');
  const blurred = await state(page);
  check(blurred.guard.frozen && blurred.animation_status.paused && !await locked(page),
    'Moving browser focus to another tab pauses both characters and releases capture');
  await foreground.close();
  await page.bringToFront();
  await restart(page);
}

async function successfulRoute(page) {
  const trace = [];
  trace.push(...await moveTo(page, 5.5, 8.8));
  await toggleCrouch(page);
  await waitGuard(page, 'watching');
  await waitGuard(page, 'working');
  trace.push(...await moveTo(page, 5.5, 6.3));
  const beforeRoll = await state(page);
  await page.keyboard.press('Space');
  const began = await waitState(page, { state: 'roll' });
  check(began.noise_count === 0 && began.guard.state === 'working' && began.guard.heard_origin === null,
    'Real Space begins a silent roll after waiting for the leader to return to work');
  await sleep(380);
  await screenshot(page, 'roll-through-opening');
  const finished = await waitState(page, { state: 'crouch_idle' });
  check(Math.abs(flatDistance(beforeRoll.position, finished.position) - 2.4) < 0.08 &&
    finished.noise_count === 0 && finished.phase === 'playing' && finished.guard.heard_origin === null,
  'The quiet 2.4 metre roll crosses the exposed part of the route without triggering a sound reaction');
  trace.push(...await moveTo(page, 5.5, 1.5));
  const won = await waitState(page, 'won');
  check(won.travel_distance > 11 && !won.guard.confirmed && won.guard.frozen && !await locked(page) &&
    won.state !== 'roll' && won.roll_progress === 0 && won.recovery_remaining === 0,
  'A complete real-input route uses cover, waits, rolls and reaches the green exit successfully',
    { time: won.elapsed, distance: won.travel_distance, noise: won.noise_count });
  await screenshot(page, 'escaped');
  fs.writeFileSync(path.join(OUT, 'route-frames.json'), JSON.stringify(trace));
  await restart(page);
  await page.keyboard.press('Escape');
  await waitState(page, 'paused');
  await clickButton(page, page, 'menu');
  const menu = await waitState(page, 'menu');
  check(menu.guard.frozen && !await locked(page), 'The successful route can be retried and returned to the menu');
}

async function ordinaryRelease(context) {
  const page = await context.newPage();
  activePage = page;
  listen(page, 'ordinary-url');
  await page.goto(ordinaryURL.href);
  await page.waitForFunction(() => typeof window.xiabanPause === 'function', null, { timeout: 30000 });
  await sleep(400);
  check(await page.evaluate(() => ['xiabanP1State', 'xiabanP2State', 'xiabanP3State', 'xiabanP4State'].every(key =>
    typeof window[key] === 'undefined')), 'An ordinary release URL exposes none of the diagnostic state bridges');
  await page.bringToFront();
  await page.locator('canvas').focus();
  await page.keyboard.press('Enter');
  await sleep(1000);
  check(await locked(page), 'Enter starts the ordinary P4 release and retains pointer lock');
  await page.keyboard.press('Escape');
  await sleep(200);
  check(!await locked(page), 'Escape pauses the ordinary P4 release and releases its mouse');
  await screenshot(page, 'ordinary-release');
  await page.close();
}

async function embeddedSmoke(context, permitted) {
  const page = await context.newPage();
  activePage = page;
  const label = permitted ? 'iframe' : 'denied-iframe';
  listen(page, label);
  await page.setViewportSize({ width: 1200, height: 800 });
  const address = new URL(`/p4-browser-${label}`, BASE).href;
  await page.route(address, route => route.fulfill({ contentType: 'text/html', body:
    `<!doctype html><body style="margin:0"><iframe src="${htmlEscape(qaURL.href)}" sandbox="allow-scripts allow-same-origin${permitted ? ' allow-pointer-lock' : ''}" allow="fullscreen" style="width:1152px;height:720px;border:0"></iframe></body>` }));
  await page.goto(address);
  const frame = await page.locator('iframe').elementHandle().then(element => element.contentFrame());
  await waitState(frame, 'menu', 30000);
  await page.bringToFront();
  await clickButton(page, frame, 'primary');
  if (permitted) {
    await waitState(frame, 'playing');
    await sleep(1000);
    const playing = await state(frame);
    check(await locked(frame) && playing.guard.state === 'working' && !playing.guard.frozen,
      'A permitted iframe starts its office encounter and retains mouse capture');
    await page.keyboard.press('Escape');
    const paused = await waitState(frame, 'paused');
    check(paused.guard.frozen && !await locked(frame), 'The permitted iframe pauses both characters and releases capture');
  } else {
    const paused = await waitState(frame, 'paused');
    check(paused.guard.frozen && paused.animation_status.paused && !await locked(frame),
      'Denied iframe pointer lock leaves both characters paused and the menu usable');
    await clickButton(page, frame, 'menu');
    await waitState(frame, 'menu');
    check(true, 'The denied-capture iframe returns safely to its menu');
  }
  await screenshot(page, label);
  await page.close();
}

(async () => {
  const response = await fetch(new URL('index.pck', BASE));
  assert.ok(response.ok, 'The served P4 package is available');
  const pck = Buffer.from(await response.arrayBuffer());
  fs.writeFileSync(path.join(OUT, 'tested-build.json'), JSON.stringify({ recorded_at: new Date().toISOString(),
    served_url: response.url, size_bytes: pck.length, sha256: createHash('sha256').update(pck).digest('hex') }, null, 2));
  const started = Date.now();
  browser = await chromium.launch({ channel: 'chrome', headless: HEADLESS });
  browser.on('disconnected', () => { if (!closingBrowser) crashes.push({ type: 'unexpected-browser-disconnect' }); });
  browserVersion = await browser.version();
  timings.browserLaunchMs = Date.now() - started;
  const context = await browser.newContext({ viewport: { width: 1152, height: 720 } });
  const page = await context.newPage();
  activePage = page;
  listen(page, 'standalone');
  const loadStarted = Date.now();
  await page.goto(qaURL.href);
  const menu = await waitState(page, 'menu', 30000);
  timings.menuLoadMs = Date.now() - loadStarted;
  await page.bringToFront();
  check(menu.guard.frozen && !await locked(page) && menu.animation_status.bones >= 15,
    'P4 loads the actual skinned player and office leader at its uncaptured menu');
  await screenshot(page, 'menu');
  await resume(page);
  await unguardedAttempt(page);
  await coverFailureAndRetry(page);
  await sprintSound(page);
  await pauseAndFocus(page, context);
  await successfulRoute(page);
  await ordinaryRelease(context);
  await embeddedSmoke(context, true);
  await embeddedSmoke(context, false);
  check(errors.filter(error => !expectedPermissionError(error)).length === 0,
    'All P4 browser scenarios complete without unexpected script or WebGL errors', { errors });
  check(crashes.length === 0, 'Chrome and its game tabs remain running throughout the acceptance test', { crashes });
  skipped.push('Native OS window focus, native rendering and human-perceived footstep volume are not measured by this browser run.');
  console.log('P4_BROWSER_RESULT', results.filter(result => result.pass).length, 'passed');
})().catch(async error => {
  console.error(error.stack);
  if (activePage && !activePage.isClosed()) {
    try { await screenshot(activePage, 'failure'); } catch (_) { /* Keep original failure. */ }
  }
  results.push({ pass: false, description: 'Uncaught test failure', evidence: { message: error.message } });
  process.exitCode = 1;
}).finally(async () => {
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({ date: new Date().toISOString(), url: BASE,
    coverage: 'P4a-real-input-browser-acceptance', browserVersion, headless: HEADLESS, nativeWindowVerified: false,
    timings, pass: results.filter(result => result.pass).length, failed: results.filter(result => !result.pass).length,
    results, skipped, logs, errors, crashes, expectedPermissionErrors: errors.filter(expectedPermissionError),
    unexpectedErrors: errors.filter(error => !expectedPermissionError(error)) }, null, 2));
  closingBrowser = true;
  if (browser) await browser.close();
});
