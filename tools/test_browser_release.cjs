/* Release acceptance through real browser keyboard/mouse input.
 * Read-only observations: ?p1_qa=1&p3_qa=1&p4b_qa=1&release_qa=1.
 * No game state is injected. A test-only fetch observer retains/clones each
 * original streamed response for byte inspection without replacing it.
 * Run against the exported game: node tools/test_browser_release.cjs
 * RELEASE_FINAL_ONLY=1 verifies the final package, frame cadence and complete route.
 * RELEASE_SMOKE_ONLY=1 verifies normal entry and real localhost iframe embedding.
 * RELEASE_MENU_ONLY=1 verifies settings persistence, fullscreen, focus and embedding.
 * RELEASE_URL defaults to http://127.0.0.1:8772/; RELEASE_HEADLESS=0 uses a window.
 * On macOS launch outside the filesystem sandbox; sandboxed Chrome can crash
 * during native initialization before it loads the game.
 */
const { chromium } = require('../.tools/browser-qa/node_modules/playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { createHash } = require('node:crypto');
const BASE = process.env.RELEASE_URL || 'http://127.0.0.1:8772/';
const HEADLESS = process.env.RELEASE_HEADLESS !== '0';
const FINAL_ONLY = process.env.RELEASE_FINAL_ONLY === '1';
const SMOKE_ONLY = process.env.RELEASE_SMOKE_ONLY === '1';
const MENU_ONLY = process.env.RELEASE_MENU_ONLY === '1';
const OUT = path.resolve(MENU_ONLY ? '.logs/release-browser-menu' : SMOKE_ONLY ? '.logs/release-browser-smoke' : FINAL_ONLY ? '.logs/release-browser-final' : '.logs/release-browser');
const qaURL = new URL(BASE);
qaURL.searchParams.set('p1_qa', '1');
qaURL.searchParams.set('p3_qa', '1');
qaURL.searchParams.set('p4b_qa', '1');
qaURL.searchParams.set('release_qa', '1');
const ordinaryURL = new URL(BASE);
for (const key of ['p1_qa', 'p2_qa', 'p3_qa', 'p4b_qa', 'release_qa']) ordinaryURL.searchParams.delete(key);
const results = [], skipped = [], logs = [], errors = [], crashes = [];
const timings = {};
const loadedBuilds = [], networkTasks = [], expectedNetworkAborts = [];
const closingPages = new WeakSet();
const iframeHosts = [];
const networkTimeline = [];
const reloadIntents = new WeakMap();
const pendingWasm = new WeakMap();
async function closePage(page) { closingPages.add(page); await page.close(); }
let prefetchedBuild;
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

function isFavicon(url) {
  try { return new URL(url).pathname === '/favicon.ico'; } catch { return false; }
}
function listen(page, label) {
  page.on('framenavigated', frame => { if (frame === page.mainFrame()) networkTimeline.push({ label, event: 'navigation', url: frame.url(), time: Date.now() }); });
  page.on('request', request => { if (/index\.(wasm|pck)$/.test(new URL(request.url()).pathname)) networkTimeline.push({ label, event: 'request', url: request.url(), time: Date.now() }); });
  page.on('requestfinished', request => { if (/index\.(wasm|pck)$/.test(new URL(request.url()).pathname)) networkTimeline.push({ label, event: 'finished', url: request.url(), time: Date.now() }); });
  page.on('console', message => {
    const record = { label, type: message.type(), message: message.text(), url: message.location().url };
    logs.push(record);
    if (/P[134]B?_|RELEASE_/.test(record.message)) console.log('GAME', label, record.message);
    if (message.type() === 'error' && !(isFavicon(record.url) && /404/.test(record.message))) errors.push(record);
    if (/webgl.*context.*lost|out of memory|runtimeerror|script error/i.test(record.message)) errors.push(record);
  });
  page.on('response', response => {
    if (response.status() >= 400 && !(response.status() === 404 && isFavicon(response.url()))) {
      errors.push({ label, type: 'http-error', url: response.url(), status: response.status() });
    }
    if (new URL(response.url()).pathname.endsWith('/index.wasm')) pendingWasm.set(page, response.finished());
    if (new URL(response.url()).pathname.endsWith('/index.pck')) {
      const task = response.body().then(bytes => {
        loadedBuilds.push({ label, url: response.url(), status: response.status(), size_bytes: bytes.length,
          sha256: createHash('sha256').update(bytes).digest('hex'), recorded_at: new Date().toISOString() });
        fs.writeFileSync(path.join(OUT, 'chrome-loaded-builds.json'), JSON.stringify(loadedBuilds, null, 2));
      }).catch(error => errors.push({ label, type: 'pck-response-read', message: error.message }));
      networkTasks.push(task);
    }
  });
  page.on('requestfailed', request => {
    const message = request.failure()?.errorText || 'unknown request failure';
    networkTimeline.push({ label, event: 'failed', url: request.url(), message, time: Date.now(), reloadIntent: reloadIntents.get(page) });
    if ((closingBrowser || closingPages.has(page) || page.isClosed()) && /ERR_ABORTED|cancelled/i.test(message)) {
      expectedNetworkAborts.push({ label, url: request.url(), message, time: new Date().toISOString() }); return;
    }
    errors.push({ label, type: 'request-failed', url: request.url(), message });
  });
  page.on('pageerror', error => errors.push({ label, type: 'pageerror', message: error.message }));
  page.on('crash', () => crashes.push({ label, type: 'page-crash', time: new Date().toISOString() }));
}

function expectedPermissionError(error) {
  return error.label === 'denied-iframe' && /pointer.?lock/i.test(error.message) && /sandbox|allow-pointer-lock/i.test(error.message);
}

async function state(frame) {
  return frame.evaluate(() => {
    if (!window.xiabanP1State || !window.xiabanP3State || !window.xiabanP4BState || !window.xiabanReleaseState) return null;
    return { ...JSON.parse(window.xiabanP1State), ...JSON.parse(window.xiabanP3State), ...JSON.parse(window.xiabanP4BState), ...JSON.parse(window.xiabanReleaseState) };
  });
}

async function waitState(frame, values, timeout = 10000) {
  if (typeof values === 'string') values = { phase: values };
  await frame.waitForFunction(expected => {
    if (!window.xiabanP1State || !window.xiabanP3State || !window.xiabanP4BState || !window.xiabanReleaseState) return false;
    const snapshot = { ...JSON.parse(window.xiabanP1State), ...JSON.parse(window.xiabanP3State), ...JSON.parse(window.xiabanP4BState), ...JSON.parse(window.xiabanReleaseState) };
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
    snapshot.guards.every(guard => guard.state === 'working' && !guard.confirmed && guard.heard_origin === null && guard.progress === 0),
  'Restart resets player controls, all three office routines, sound targets, detection and spawn');
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

async function waitGuard(page, index, guardState, timeout = 16000) {
  await page.waitForFunction(([index, expected]) => window.xiabanP4BState &&
    JSON.parse(window.xiabanP4BState).guards[index].state === expected, [index, guardState], { timeout });
  return state(page);
}

async function moveTo(page, x, z, limit = 60000) {
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
        heading: snapshot.heading, state: snapshot.state, guards: snapshot.guards });
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

const OBSERVATION = [[5.5, 34], [18.5, 22.2], [5.5, 10.45]];
const EXPOSURE = [[5.5, 29], [18.5, 18.5], [5.5, 6.7]];
const CORRIDORS = [[[5.5, 24.45], [18.5, 24.45]], [[18.5, 12.3], [5.5, 12.3]]];
const routeTrace = [];
async function travel(page, x, z) {
  const trace = await moveTo(page, x, z);
  routeTrace.push(...trace);
  fs.writeFileSync(path.join(OUT, 'route-frames.json'), JSON.stringify(routeTrace));
}
async function lookAtLeader(page, index, name) {
  const before = await state(page);
  const observer = before.guards[index];
  const yaw = Math.atan2(-(observer.position[0] - before.position[0]), -(observer.position[2] - before.position[2]));
  // Camera orbit is real mouse input. It never changes actor heading.
  const delta = angle(yaw, before.camera_yaw);
  await page.mouse.move(576, 360);
  await page.mouse.down({ button: 'right' });
  await page.mouse.move(576 - delta / 0.004, 360, { steps: 12 });
  await sleep(120);
  const observed = await state(page);
  await page.mouse.up({ button: 'right' });
  check(Math.abs(angle(observed.heading, before.heading)) < 0.001 && flatDistance(observed.position, before.position) < 0.01,
    `Observation in encounter ${index + 1} preserves actor direction and position`);
  await screenshot(page, name);
  await page.keyboard.press('f');
  await sleep(350);
}
async function approach(page, index) {
  if ((await state(page)).stance === 'standing') await toggleCrouch(page);
  await travel(page, ...OBSERVATION[index]);
  await waitGuard(page, index, 'watching');
  await waitGuard(page, index, 'working');
  await travel(page, ...EXPOSURE[index]);
  await waitGuard(page, index, 'watching');
  if ((await state(page)).guards[index].remaining < 0.8) {
    await waitGuard(page, index, 'working');
    await waitGuard(page, index, 'watching');
  }
  await sleep(450);
  const hidden = await state(page);
  check(hidden.phase === 'playing' && hidden.guards[index].progress === 0 && !hidden.guards[index].confirmed &&
    hidden.guards[index].fan_visible && hidden.stance === 'crouched',
  `Encounter ${index + 1}: real crouched movement reaches low cover and stays hidden during observation`);
  return hidden;
}
async function faceNorth(page) {
  const held = new Set();
  const deadline = Date.now() + 6000;
  try {
    while (Date.now() < deadline) {
      const snapshot = await state(page);
      assert.equal(snapshot.phase, 'playing', 'Direction alignment remains playable');
      const error = angle(0, snapshot.heading);
      if (Math.abs(error) < 0.045) return;
      for (const [key, needed] of [['a', error > 0], ['d', error < 0]]) {
        if (needed && !held.has(key)) { await page.keyboard.down(key); held.add(key); }
        if (!needed && held.has(key)) { await page.keyboard.up(key); held.delete(key); }
      }
      await sleep(15);
    }
    assert.fail('Real A/D alignment to the roll direction timed out');
  } finally { for (const key of held) await page.keyboard.up(key); }
}
async function leaveEncounter(page, index, record = false) {
  await travel(page, EXPOSURE[index][0], EXPOSURE[index][1] - 2.1);
  await faceNorth(page);
  await waitGuard(page, index, 'watching');
  await waitGuard(page, index, 'working');
  const before = await state(page);
  await page.keyboard.press('Space');
  const began = await waitState(page, { state: 'roll' });
  if (record) {
    await sleep(280);
    await screenshot(page, `encounter-${index + 1}-roll`);
  }
  const finished = await waitState(page, index === 2 ? 'won' : { state: 'crouch_idle' });
  check(began.guards[index].state === 'working' && began.noise_count === before.noise_count &&
    finished.noise_count === before.noise_count && finished.guards.every(guard => !guard.confirmed) &&
    flatDistance(before.position, finished.position) > 2.1,
  `Encounter ${index + 1}: waiting for work permits a quiet forward roll past the exposed edge`,
    { before: { position: before.position, heading: before.heading, noise: before.noise_count },
      began: { state: began.state, guard: began.guards[index].state, noise: began.noise_count },
      finished: { position: finished.position, phase: finished.phase, noise: finished.noise_count,
        travel: flatDistance(before.position, finished.position), confirmed: finished.guards.map(guard => guard.confirmed) } });
  if (index < 2) for (const point of CORRIDORS[index]) await travel(page, ...point);
}
async function failureByEachLeader(page) {
  for (let target = 0; target < 3; target++) {
    for (let index = 0; index <= target; index++) {
      await approach(page, index);
      if (index < target) await leaveEncounter(page, index);
    }
    await waitGuard(page, target, 'working');
    await waitGuard(page, target, 'watching');
    const before = await state(page);
    const frames = [];
    await page.keyboard.press('c');
    const deadline = Date.now() + 2000;
    while (Date.now() < deadline) {
      const snapshot = await state(page);
      frames.push(snapshot);
      if (snapshot.phase === 'lost') break;
      await sleep(15);
    }
    const lost = await waitState(page, 'lost');
    check(lost.discovered_by === lost.guards[target].guard_id && lost.guards[target].confirmed &&
      lost.stance === 'standing' && flatDistance(before.position, lost.position) < 0.01 &&
      frames.some(frame => frame.phase === 'playing' && frame.guards[target].progress > 0 && frame.guards[target].progress < 1),
    `Encounter ${target + 1}: standing at the same cover independently produces the correct named discovery`,
      { discovered_by: lost.discovered_by, guard: lost.guards[target].guard_id });
    check(lost.guards.every(guard => guard.frozen) && !await locked(page) && lost.move_input === 0 && lost.turn_input === 0,
      `Failure by leader ${target + 1} freezes the entire level and clears mouse/keyboard capture`);
    check(lost.audio.event_counts.notice > 0 && lost.audio.event_counts.lost > 0 && !lost.audio.ambient_playing,
      `Encounter ${target + 1}: discovery cues play and office ambience stops at the actual failure`);
    await screenshot(page, `encounter-${target + 1}-discovered`);
    fs.writeFileSync(path.join(OUT, `encounter-${target + 1}-discovery.json`), JSON.stringify(frames, null, 2));
    await restart(page);
  }
}
async function sprintSound(page) {
  await hold(page, ['Shift', 'w'], 120);
  const raised = await state(page);
  check(raised.noise_count > 0 && raised.guards[0].noise_attention && raised.guards[0].state === 'raising' &&
    raised.guards[0].heard_origin !== null && raised.guards.slice(1).every(guard => guard.heard_origin === null && !guard.noise_attention),
    'A real sprint footstep alerts only the first nearby leader; distant leaders receive no shared target');
  const heard = raised.guards[0].heard_origin;
  await waitGuard(page, 0, 'watching');
  await sleep(420);
  const after = await state(page);
  const offset = [heard[0] - after.guards[0].position[0], heard[2] - after.guards[0].position[2]];
  const alignment = (after.guards[0].facing[0] * offset[0] + after.guards[0].facing[2] * offset[1]) / Math.hypot(...offset);
  check(after.phase === 'playing' && after.guards[0].progress === 0 && alignment > 0.99 &&
    after.guards.every((guard, i) => distance(guard.position, raised.guards[i].position) < 0.001),
  'The first leader observes the recorded sound behind solid cover while all three remain at their desks');
  await screenshot(page, 'sprint-sound-isolation');
  await waitGuard(page, 0, 'working');
  check(!(await state(page)).guards[0].noise_attention, 'An unseen sound reaction finishes and returns to ordinary work');
  await restart(page);
}
async function pauseAndFocus(page, context) {
  await waitGuard(page, 0, 'raising');
  await sleep(120);
  await page.keyboard.press('Escape');
  const paused = await waitState(page, 'paused');
  await sleep(420);
  const frozen = await state(page);
  check(JSON.stringify(paused.guards) === JSON.stringify(frozen.guards) && paused.elapsed === frozen.elapsed &&
    paused.animation_status.time === frozen.animation_status.time && !await locked(page),
  'Escape freezes all three independent clocks, actual head poses and the player');
  await clickButton(page, page, 'primary');
  await waitState(page, 'playing');
  await sleep(120);
  const resumed = await state(page);
  check(resumed.guards.every((guard, i) => !guard.frozen && guard.visual_time > paused.guards[i].visual_time),
    'Continue resumes all three saved routines with pointer capture');
  const foreground = await context.newPage();
  await foreground.goto('about:blank');
  await foreground.bringToFront();
  const blurred = await waitState(page, 'paused');
  check(blurred.guards.every(guard => guard.frozen) && blurred.animation_status.paused && !await locked(page),
    'Switching browser tabs pauses all four characters');
  await closePage(foreground);
  await page.bringToFront();
  await restart(page);
}
async function frameTiming(page) {
  const metrics = await page.evaluate(() => new Promise(resolve => {
    const samples = []; let start, last;
    function frame(now) {
      if (start === undefined) { start = now; last = now; }
      else { samples.push(now - last); last = now; }
      if (now - start < 8000) requestAnimationFrame(frame);
      else {
        const sorted = [...samples].sort((a, b) => a - b);
        resolve({ duration_ms: now - start, frames: samples.length, fps: samples.length * 1000 / (now - start),
          p95_ms: sorted[Math.floor(sorted.length * 0.95)], max_ms: Math.max(...sorted), samples });
      }
    }
    requestAnimationFrame(frame);
  }));
  const snapshot = await state(page);
  fs.writeFileSync(path.join(OUT, 'frame-timing.json'), JSON.stringify(metrics, null, 2));
  timings.fullLevel = { ...metrics, samples: undefined };
  check(snapshot.phase === 'playing' && snapshot.guards.length === 3 && snapshot.guards.every(guard => !guard.frozen),
    'The frame sample runs against all three active office routines in the actual full level');
  check(metrics.fps >= 45 && metrics.p95_ms < 50,
    'The complete three-leader Chrome scene sustains a playable measured frame cadence', timings.fullLevel);
  await restart(page);
}
async function successfulRoute(page) {
  for (let index = 0; index < 3; index++) {
    await approach(page, index);
    await lookAtLeader(page, index, `encounter-${index + 1}-observe`);
    await leaveEncounter(page, index, true);
  }
  const won = await waitState(page, 'won');
  check(won.travel_distance > 58 && won.noise_count === 0 && won.guards.every(guard => guard.frozen && !guard.confirmed) &&
    won.discovered_by === '' && !await locked(page) && won.roll_progress === 0 && won.recovery_remaining === 0,
  'One real-input route observes and passes all three leaders, crosses both corridors and reaches the final exit',
    { elapsed: won.elapsed, distance: won.travel_distance, guards: won.guards.map(guard => guard.guard_id) });
  check(won.audio.event_counts.won > 0 && won.audio.event_counts.roll >= 3 &&
    won.audio.event_counts.crouch > 0 && !won.audio.ambient_playing,
    'The completed real-input route produces movement and success feedback while stopping office ambience', won.audio);
  await screenshot(page, 'escaped-full-first-level');
  await restart(page);
  await page.keyboard.press('Escape');
  await waitState(page, 'paused');
  await clickButton(page, page, 'menu');
  const menu = await waitState(page, 'menu');
  check(menu.guards.every(guard => guard.frozen) && menu.discovered_by === '' && !await locked(page),
    'A completed first level can be retried and returned to its menu');
}
async function ordinaryRelease(context, activation = 'enter') {
  const label = activation === 'enter' ? 'ordinary-url' : 'ordinary-url-click';
  const page = await context.newPage(); activePage = page; listen(page, label);
  await page.goto(ordinaryURL.href);
  await page.waitForFunction(() => typeof window.xiabanPause === 'function' && !document.getElementById('status'), null, { timeout: 30000 });
  if (!logs.some(record => record.label === label && record.message.includes('RELEASE_READY'))) {
    await page.waitForEvent('console', { predicate: message => message.text().includes('RELEASE_READY'), timeout: 10000 });
  }
  await sleep(500);
  check(await page.evaluate(() => ['xiabanP1State', 'xiabanP2State', 'xiabanP3State', 'xiabanP4State', 'xiabanP4BState', 'xiabanReleaseState'].every(key =>
    typeof window[key] === 'undefined')), 'An ordinary full-level URL exposes none of the diagnostic state bridges');
  await page.bringToFront(); await page.locator('canvas').focus();
  if (activation === 'enter') await page.keyboard.press('Enter');
  else {
    const box = await page.locator('canvas').boundingBox();
    // Normal entry never installs diagnostic state. Final menu geometry is passed explicitly.
    const primaryY = Number(process.env.RELEASE_PRIMARY_Y || '0.5042');
    await page.mouse.click(box.x + box.width * 0.5, box.y + box.height * primaryY);
  }
  await sleep(1000);
  check(await locked(page), `${activation === 'enter' ? 'Enter' : 'Clicking Start'} starts the ordinary full release and retains pointer lock`);
  await page.keyboard.press('Escape'); await sleep(200);
  check(!await locked(page), 'Escape pauses the ordinary full release and releases its mouse');
  await screenshot(page, `ordinary-release-${activation}`); await closePage(page);
}
async function embeddedSmoke(context, permitted) {
  const page = await context.newPage(); activePage = page;
  const label = permitted ? 'iframe' : 'denied-iframe'; listen(page, label);
  await page.setViewportSize({ width: 1200, height: 800 });
  // A real localhost document preserves the browser's secure-context rules
  // without Playwright interception or an about:blank/image-document wrapper.
  const html = `<!doctype html><body style="margin:0"><iframe src="${htmlEscape(qaURL.href)}" sandbox="allow-scripts allow-same-origin${permitted ? ' allow-pointer-lock' : ''}" allow="fullscreen" style="width:1152px;height:720px;border:0"></iframe></body>`;
  const host = http.createServer((_request, response) => {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    response.end(html);
  });
  iframeHosts.push(host);
  await new Promise((resolve, reject) => {
    host.once('error', reject);
    host.listen(0, '127.0.0.1', resolve);
  });
  await page.goto(`http://127.0.0.1:${host.address().port}/`);
  const frame = await page.locator('iframe').elementHandle().then(element => element.contentFrame());
  await waitState(frame, 'menu', 30000); await page.bringToFront(); await clickButton(page, frame, 'primary');
  if (permitted) {
    await waitState(frame, 'playing'); await sleep(1000);
    check(await locked(frame) && (await state(frame)).guards.every(guard => !guard.frozen),
      'A permitted iframe starts all three office routines and retains pointer lock');
    await page.keyboard.press('Escape');
    const paused = await waitState(frame, 'paused');
    check(paused.guards.every(guard => guard.frozen) && !await locked(frame), 'The permitted iframe pauses the complete level');
  } else {
    const paused = await waitState(frame, 'paused');
    check(paused.guards.every(guard => guard.frozen) && paused.animation_status.paused && !await locked(frame),
      'Denied iframe pointer lock leaves all four characters paused');
    await clickButton(page, frame, 'menu'); await waitState(frame, 'menu');
    check(true, 'The denied-capture iframe returns to its usable menu');
  }
  await screenshot(page, label); await closePage(page);
}
async function clickSlider(page, name, fraction) {
  const snapshot = await state(page);
  const control = snapshot.controls[name];
  assert.ok(control?.visible, `Release ${name} slider is visible`);
  const box = await page.locator('canvas').boundingBox();
  const rect = control.rect;
  await page.mouse.click(box.x + (rect[0] + 2 + (rect[2] - 4) * fraction) * box.width / snapshot.viewport[0],
    box.y + (rect[1] + rect[3] / 2) * box.height / snapshot.viewport[1]);
  await sleep(200);
  return state(page);
}
async function settingsPersistence(page) {
  const original = (await state(page)).settings;
  const muted = await clickSlider(page, 'volume', 0);
  check(muted.settings.volume === 0 && muted.audio.volume === 0,
    'The visible volume slider reaches mute in both saved settings and the active audio mixer');
  const changed = await clickSlider(page, 'sensitivity', 2 / 3);
  check(changed.settings.sensitivity >= 1.35 && changed.settings.sensitivity <= 1.65,
    'The visible observation sensitivity slider changes the active saved preference', changed.settings);
  await sleep(1000);
  if (pendingWasm.has(page)) await pendingWasm.get(page);
  reloadIntents.set(page, Date.now());
  networkTimeline.push({ event: 'explicit-reload', time: Date.now() });
  await page.reload();
  const restored = await waitState(page, 'menu', 30000);
  check(restored.settings.volume === 0 && restored.audio.volume === 0 &&
    restored.settings.sensitivity === changed.settings.sensitivity,
    'A real page reload preserves muted volume and observation sensitivity', restored.settings);
  const resetVolume = await clickSlider(page, 'volume', original.volume);
  const resetSettings = await clickSlider(page, 'sensitivity', (original.sensitivity - 0.5) / 1.5);
  check(Math.abs(resetVolume.settings.volume - original.volume) <= 0.055 &&
    Math.abs(resetSettings.settings.sensitivity - original.sensitivity) <= 0.11,
    'Real settings controls restore the preferences present at the start of acceptance', resetSettings.settings);
}

async function menuAndFullscreen(page) {
  for (const size of [{ width: 960, height: 600 }, { width: 1600, height: 900 }, { width: 1152, height: 720 }]) {
    await page.setViewportSize(size); await sleep(180);
    const snapshot = await state(page);
    const rect = snapshot.buttons.primary.rect;
    check(snapshot.phase === 'menu' && snapshot.buttons.primary.visible && rect[0] >= 0 && rect[1] >= 0 &&
      rect[0] + rect[2] <= snapshot.viewport[0] && rect[1] + rect[3] <= snapshot.viewport[1],
      `Release menu start control remains reachable at ${size.width}×${size.height}`,
      { viewport: snapshot.viewport, primary: rect });
  }
  await clickButton(page, page, 'fullscreen');
  await page.waitForFunction(() => document.fullscreenElement !== null);
  check(await page.evaluate(() => document.fullscreenElement?.tagName === 'CANVAS'),
    'The actual Fullscreen button activates browser canvas fullscreen');
  await screenshot(page, 'fullscreen-menu');
  // The same visible UI control exits fullscreen without script-driven state changes.
  await clickButton(page, page, 'fullscreen');
  await page.waitForFunction(() => document.fullscreenElement === null);
  check((await state(page)).phase === 'menu' && !await locked(page),
    'The Fullscreen button returns the ordinary uncaptured menu');
  await page.setViewportSize({ width: 1152, height: 720 });
  // Fullscreen exits resize the OS/browser asynchronously before the next click.
  await sleep(350);
}


(async () => {
  const response = await fetch(new URL('index.pck', BASE)); assert.ok(response.ok, 'The served release package is available');
  const pck = Buffer.from(await response.arrayBuffer());
  prefetchedBuild = { recorded_at: new Date().toISOString(), served_url: response.url, size_bytes: pck.length,
    sha256: createHash('sha256').update(pck).digest('hex') };
  fs.writeFileSync(path.join(OUT, 'tested-build.json'), JSON.stringify(prefetchedBuild, null, 2));
  const started = Date.now();
  browser = await chromium.launch({ channel: 'chrome', headless: HEADLESS });
  browser.on('disconnected', () => { if (!closingBrowser) crashes.push({ type: 'unexpected-browser-disconnect' }); });
  browserVersion = await browser.version(); timings.browserLaunchMs = Date.now() - started;
  const context = await browser.newContext({ viewport: { width: 1152, height: 720 } });
  // Keep the original fetch Response alive while Godot consumes its reader.
  // This observes actual served bytes and leaves arguments/response/game state intact.
  await context.addInitScript(() => {
    const nativeFetch = window.fetch;
    window.__releaseObservedResponses = [];
    window.__releaseNetworkHashes = [];
    window.fetch = async function (...args) {
      const response = await nativeFetch.apply(this, args);
      if (/\/index\.(pck|wasm)$/.test(new URL(response.url).pathname)) {
        window.__releaseObservedResponses.push(response);
        const task = response.clone().arrayBuffer().then(async bytes => {
          const digest = await crypto.subtle.digest('SHA-256', bytes);
          return { url: response.url, size_bytes: bytes.byteLength,
            sha256: Array.from(new Uint8Array(digest), value => value.toString(16).padStart(2, '0')).join('') };
        });
        window.__releaseNetworkHashes.push(task);
      }
      return response;
    };
  });
  if (!SMOKE_ONLY) {
  const page = await context.newPage(); activePage = page; listen(page, 'standalone');
  const loadStarted = Date.now(); await page.goto(qaURL.href);
  const menu = await waitState(page, 'menu', 30000); timings.menuLoadMs = Date.now() - loadStarted; await page.bringToFront();
  await Promise.all(networkTasks);
  const loaded = loadedBuilds.find(build => build.label === 'standalone');
  check(loaded?.sha256 === prefetchedBuild.sha256 && loaded?.size_bytes === prefetchedBuild.size_bytes,
    'The actual Chrome PCK response exactly matches the recorded tested package', loaded);
  check(menu.guards.length === 3 && menu.guards.every(guard => guard.frozen) && !await locked(page) && menu.animation_status.bones >= 15,
    'The full level loads three office leaders and the actual skinned player at its uncaptured menu');
  await screenshot(page, 'menu');
  await settingsPersistence(page);
  await menuAndFullscreen(page);
  await resume(page);
  if (!MENU_ONLY) {
  if (!FINAL_ONLY) { await sprintSound(page); await pauseAndFocus(page, context); }
  await frameTiming(page);
  if (!FINAL_ONLY) await failureByEachLeader(page);
  await successfulRoute(page);
  await ordinaryRelease(context);
  if (!FINAL_ONLY) { await embeddedSmoke(context, true); await embeddedSmoke(context, false); }
  } else {
    await pauseAndFocus(page, context);
    await ordinaryRelease(context, 'click');
    await embeddedSmoke(context, true);
    await embeddedSmoke(context, false);
  }
  } else {
    await ordinaryRelease(context);
    await ordinaryRelease(context, 'click');
    await embeddedSmoke(context, true);
    await embeddedSmoke(context, false);
  }
  await Promise.allSettled(networkTasks);
  check(loadedBuilds.length >= 2 && loadedBuilds.every(build => build.status === 200 &&
    build.sha256 === prefetchedBuild.sha256 && build.size_bytes === prefetchedBuild.size_bytes),
    'Every Chrome page loaded the exact same recorded release package', { loadedBuilds });
  check(errors.filter(error => !expectedPermissionError(error)).length === 0,
    'All full-level scenarios complete without unexpected script or WebGL errors', { errors });
  check(crashes.length === 0, 'Chrome and its game tabs remain running throughout full-level acceptance', { crashes });
  skipped.push('Native window focus/rendering and human-perceived footstep volume are not measured by this browser run.');
  console.log('RELEASE_BROWSER_RESULT', results.filter(result => result.pass).length, 'passed');
})().catch(async error => {
  console.error(error.stack);
  if (activePage && !activePage.isClosed()) { try { await screenshot(activePage, 'failure'); } catch (_) {} }
  results.push({ pass: false, description: 'Uncaught test failure', evidence: { message: error.message } }); process.exitCode = 1;
}).finally(async () => {
  await Promise.allSettled(networkTasks);
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({ date: new Date().toISOString(), url: BASE,
    coverage: MENU_ONLY ? 'release-menu-settings-fullscreen-focus-and-embedding' : SMOKE_ONLY ? 'release-final-release-readiness-and-embedding' : FINAL_ONLY ? 'release-final-build-real-input-route-and-rendering' : 'release-real-input-complete-first-level', browserVersion, headless: HEADLESS, nativeWindowVerified: false,
    timings, networkTimeline, pass: results.filter(result => result.pass).length, failed: results.filter(result => !result.pass).length,
    results, skipped, logs, errors, crashes, loadedBuilds, prefetchedBuild, expectedNetworkAborts, expectedPermissionErrors: errors.filter(expectedPermissionError),
    unexpectedErrors: errors.filter(error => !expectedPermissionError(error)) }, null, 2));
  closingBrowser = true; if (browser) await browser.close();
  await Promise.all(iframeHosts.map(host => new Promise(resolve => host.close(resolve))));
});
