/* Release 1.0.1 camera controls and continuous browser-rendering evidence.
 * All interaction uses real keyboard/mouse events. The opt-in QA bridge is read
 * only. Video and frame snapshots retain the actual browser output; no player,
 * guard, camera or clock state is injected. Run only after exporting the build.
 * RELEASE_URL defaults to http://127.0.0.1:8774/; RELEASE_HEADLESS=0 shows Chrome.
 */
const { chromium } = require('../.tools/browser-qa/node_modules/playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const BASE = process.env.RELEASE_URL || 'http://127.0.0.1:8774/';
const OUT = path.resolve('.logs/release-browser-stability');
const HEADLESS = process.env.RELEASE_HEADLESS !== '0';
const url = new URL(BASE);
for (const name of ['p1_qa', 'p3_qa', 'p4b_qa', 'release_qa']) url.searchParams.set(name, '1');
fs.mkdirSync(OUT, { recursive: true });
const results = [], errors = [], crashes = [], logs = [], segments = [];
let browser, context, page, video, browserVersion, testedBuild, loadedBuild;
let closing = false;
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const angle = (a, b) => Math.atan2(Math.sin(a - b), Math.cos(a - b));
const distance = (a, b) => Math.hypot(...a.map((value, i) => value - b[i]));
const planar = (a, b) => Math.hypot(a[0] - b[0], a[2] - b[2]);
function check(ok, description, evidence = {}) {
  results.push({ pass: !!ok, description, evidence });
  console.log(`${ok ? 'PASS' : 'FAIL'}: ${description}`, JSON.stringify(evidence));
  assert.ok(ok, description);
}
async function state() {
  return page.evaluate(() => Object.assign({}, ...['xiabanP1State', 'xiabanP3State', 'xiabanP4BState', 'xiabanReleaseState']
    .map(name => JSON.parse(window[name]))));
}
async function waitState(expected, timeout = 12000) {
  if (typeof expected === 'string') expected = { phase: expected };
  await page.waitForFunction(values => {
    const names = ['xiabanP1State', 'xiabanP3State', 'xiabanP4BState', 'xiabanReleaseState'];
    if (names.some(name => !window[name])) return false;
    const snapshot = Object.assign({}, ...names.map(name => JSON.parse(window[name])));
    return Object.entries(values).every(([key, value]) => snapshot[key] === value);
  }, expected, { timeout });
  return state();
}
async function clickButton(name) {
  const snapshot = await state(), control = snapshot.buttons[name];
  assert.ok(control?.visible, `${name} control is visible`);
  const box = await page.locator('canvas').boundingBox(), rect = control.rect;
  await page.mouse.click(box.x + (rect[0] + rect[2] / 2) * box.width / snapshot.viewport[0],
    box.y + (rect[1] + rect[3] / 2) * box.height / snapshot.viewport[1]);
}
async function locked() { return page.evaluate(() => document.pointerLockElement?.tagName === 'CANVAS'); }
async function restart() {
  if ((await state()).phase === 'playing') {
    await page.keyboard.press('Escape'); await waitState('paused');
  }
  const current = await state();
  await clickButton(current.phase === 'paused' ? 'restart' : 'primary');
  await waitState('playing'); await sleep(180);
  const next = await state();
  assert.ok(await locked(), 'Restart obtains actual mouse capture');
  assert.ok(Math.abs(next.camera_yaw) < 0.001 && Math.abs(next.camera_pitch - 14) < 0.01 &&
    Math.abs(next.desired_distance - 4.8) < 0.001, 'Restart restores the camera defaults');
}
async function hold(keys, ms) {
  if (!Array.isArray(keys)) keys = [keys];
  for (const key of keys) await page.keyboard.down(key);
  try { await sleep(ms); } finally { for (const key of [...keys].reverse()) await page.keyboard.up(key); }
  await sleep(40);
  return state();
}
async function screenshot(name) { await page.screenshot({ path: path.join(OUT, `${name}.png`) }); }
async function startFrames(label) {
  await page.evaluate(label => {
    const capture = { label, started: performance.now(), active: true, frames: [] };
    window.__stabilityCapture = capture;
    function sample(now) {
      if (!capture.active) return;
      const names = ['xiabanP1State', 'xiabanP3State', 'xiabanP4BState', 'xiabanReleaseState'];
      if (names.every(name => window[name])) {
        const snapshot = Object.assign({}, ...names.map(name => JSON.parse(window[name])));
        capture.frames.push({ now, phase: snapshot.phase, elapsed: snapshot.elapsed, state: snapshot.state,
          stance: snapshot.stance, position: snapshot.position, heading: snapshot.heading,
          camera_yaw: snapshot.camera_yaw, camera_pitch: snapshot.camera_pitch,
          camera_position: snapshot.camera_position, camera_alpha: snapshot.camera_alpha,
          camera_look_input: snapshot.camera_look_input, observing: snapshot.observing,
          recenter_hold_remaining: snapshot.recenter_hold_remaining, guards: snapshot.guards });
      }
      requestAnimationFrame(sample);
    }
    requestAnimationFrame(sample);
  }, label);
}
async function stopFrames() {
  const capture = await page.evaluate(() => {
    window.__stabilityCapture.active = false;
    const result = window.__stabilityCapture;
    delete window.__stabilityCapture;
    return result;
  });
  const intervals = capture.frames.slice(1).map((frame, i) => frame.now - capture.frames[i].now);
  const sorted = [...intervals].sort((a, b) => a - b);
  const steps = capture.frames.slice(1).map((frame, i) => distance(frame.camera_position, capture.frames[i].camera_position));
  const duration = capture.frames.at(-1).now - capture.frames[0].now;
  const metrics = { label: capture.label, frames: capture.frames.length, duration_ms: duration,
    fps: intervals.length * 1000 / duration, p95_ms: sorted[Math.floor(sorted.length * 0.95)],
    max_interval_ms: Math.max(...intervals), max_camera_step_m: Math.max(...steps) };
  fs.writeFileSync(path.join(OUT, `${capture.label}-frames.json`), JSON.stringify(capture));
  segments.push(metrics);
  return { frames: capture.frames, metrics };
}

async function keyboardAndMouse() {
  const before = await state();
  await hold(['ArrowRight', 'ArrowUp'], 420);
  const diagonal = await state();
  check(angle(diagonal.camera_yaw, before.camera_yaw) < -0.3 && diagonal.camera_pitch < 6,
    'Real Right/Up arrow keys change horizontal and vertical view',
    { yaw: diagonal.camera_yaw, pitch: diagonal.camera_pitch, input: diagonal.camera_look_input });
  check(planar(before.position, diagonal.position) < 0.002 && Math.abs(angle(before.heading, diagonal.heading)) < 0.001,
    'Camera arrows preserve the character position and heading');
  await sleep(1600);
  const resting = await state();
  check(Math.abs(angle(resting.camera_yaw, diagonal.camera_yaw)) < 0.001 &&
    Math.abs(resting.camera_pitch - diagonal.camera_pitch) < 0.01 && resting.recenter_hold_remaining === 0,
    'An idle player keeps the chosen view after the manual-view hold expires');
  const reversed = await hold(['ArrowLeft', 'ArrowDown'], 240);
  check(angle(reversed.camera_yaw, resting.camera_yaw) > 0.15 && reversed.camera_pitch > resting.camera_pitch + 6,
    'Real Left/Down arrow keys reverse both observation axes');
  const up = await hold('ArrowUp', 1100);
  check(Math.abs(up.camera_pitch + 12) < 0.001, 'Upward observation clamps at -12 degrees', { pitch: up.camera_pitch });
  const down = await hold('ArrowDown', 1400);
  check(Math.abs(down.camera_pitch - 50) < 0.001, 'Downward observation clamps at 50 degrees', { pitch: down.camera_pitch });
  await page.mouse.wheel(0, -100); await sleep(150);
  const zoomed = await state();
  check(zoomed.desired_distance < before.desired_distance, 'A real mouse wheel still adjusts camera distance');
  await page.keyboard.press('f'); await sleep(650);
  const recentered = await state();
  check(Math.abs(angle(recentered.camera_yaw, recentered.heading)) < 0.001 && Math.abs(recentered.camera_pitch - 14) < 0.05 &&
    recentered.desired_distance === zoomed.desired_distance,
    'F restores horizontal heading and vertical pitch while retaining zoom');
  await page.mouse.move(576, 360); await page.mouse.down({ button: 'right' });
  const dragBefore = await state();
  await page.mouse.move(666, 310, { steps: 12 }); await sleep(150);
  const dragged = await state();
  await page.mouse.up({ button: 'right' }); await sleep(50);
  check(dragged.observing && angle(dragged.camera_yaw, dragBefore.camera_yaw) < -0.15 &&
    dragged.camera_pitch < dragBefore.camera_pitch - 5 && Math.abs(angle(dragged.heading, dragBefore.heading)) < 0.001,
    'Right-button dragging retains both-axis observation without turning the character',
    { before: [dragBefore.camera_yaw, dragBefore.camera_pitch], after: [dragged.camera_yaw, dragged.camera_pitch] });
  check(!(await state()).observing, 'Releasing the right button ends mouse observation');
  await screenshot('free-observation');
}

async function movementPriority() {
  await restart();
  await hold(['ArrowRight', 'ArrowUp'], 350);
  const selected = await state();
  await page.keyboard.down('w');
  try {
    await sleep(650);
    const held = await state();
    check(Math.abs(angle(held.camera_yaw, selected.camera_yaw)) < 0.001 && Math.abs(held.camera_pitch - selected.camera_pitch) < 0.01 &&
      selected.position[2] - held.position[2] > 0.7 && held.recenter_hold_remaining > 0,
      'Walking preserves the selected view during the 1.25-second manual-view hold');
    await sleep(850);
    const returning = await state();
    check(Math.abs(returning.camera_yaw) < Math.abs(selected.camera_yaw) - 0.05 && Math.abs(returning.camera_yaw) > 0.025 &&
      returning.camera_pitch > selected.camera_pitch + 1 && returning.camera_pitch < 14,
      'Continued walking gradually recenters both axes after the hold',
      { selected: [selected.camera_yaw, selected.camera_pitch], returning: [returning.camera_yaw, returning.camera_pitch] });
    await sleep(1600);
    const returned = await state();
    check(Math.abs(returned.camera_yaw) < 0.025 && Math.abs(returned.camera_pitch - 14) < 1,
      'Forward movement eventually restores a useful forward view');
  } finally { await page.keyboard.up('w'); }
  await restart();
  const before = await state();
  const simultaneous = await hold(['w', 'ArrowRight'], 620);
  check(before.position[2] - simultaneous.position[2] > 0.8 && Math.abs(simultaneous.heading) < 0.001 && simultaneous.camera_yaw < -0.8,
    'Holding W and Right together walks along actor heading while independently orbiting');
  const turning = await hold(['a', 'ArrowUp'], 350);
  check(turning.heading > simultaneous.heading + 0.35 && Math.abs(angle(turning.camera_yaw, simultaneous.camera_yaw)) < 0.001 &&
    turning.camera_pitch < simultaneous.camera_pitch - 12,
    'Holding A and Up together turns the actor while manual view retains horizontal direction');
  await screenshot('independent-actor-and-view');
}

async function pauseAndFocus() {
  await page.keyboard.down('ArrowRight'); await sleep(120);
  await page.keyboard.press('Escape');
  const paused = await waitState('paused');
  await page.keyboard.up('ArrowRight'); await sleep(400);
  const frozen = await state();
  check(frozen.camera_look_input.every(value => value === 0) && !frozen.observing &&
    distance(paused.camera_position, frozen.camera_position) < 0.0001 && paused.elapsed === frozen.elapsed && !await locked(),
    'Escape clears held camera arrows and freezes the full view');
  await clickButton('primary'); await waitState('playing'); await sleep(450);
  const resumed = await state();
  check(Math.abs(angle(frozen.camera_yaw, resumed.camera_yaw)) < 0.001 &&
    Math.abs(frozen.camera_pitch - resumed.camera_pitch) < 0.01 && await locked(),
    'Continue preserves the paused view with no stuck camera key');
  await page.keyboard.down('ArrowDown'); await page.mouse.down({ button: 'right' }); await sleep(150);
  const foreground = await context.newPage(); await foreground.goto('about:blank'); await foreground.bringToFront();
  const blurred = await waitState('paused');
  check(blurred.camera_look_input.every(value => value === 0) && !blurred.observing &&
    blurred.guards.every(guard => guard.frozen) && !await locked(),
    'Changing tabs clears simultaneous mouse and arrow observation and freezes all leaders');
  await foreground.close(); await page.bringToFront();
  await page.keyboard.up('ArrowDown'); await page.mouse.up({ button: 'right' });
  await restart();
  check(true, 'Retry clears the pending view, zoom and observation input');
}

async function orbitContinuity() {
  await startFrames('near-wall-orbit');
  await hold('ArrowRight', 2500);
  await hold('ArrowUp', 1100);
  await hold('ArrowLeft', 2500);
  await hold('ArrowDown', 1400);
  const sweep = await stopFrames();
  check(sweep.frames.every(frame => frame.phase === 'playing' && frame.camera_position.every(Number.isFinite)) &&
    sweep.metrics.fps > 40 && sweep.metrics.p95_ms < 50,
    'Continuous real-key orbit near the spawn walls stays playable with measured frame cadence', sweep.metrics);
  // Keep all intervals, including stalls: an ordinary-frame-only bound could
  // conceal a real camera jump during material compilation. The separate
  // no-video two-sweep test also applies its strict limit to every frame.
  const singleSteps = sweep.frames.slice(1).map((frame, i) => ({
    dt: frame.now - sweep.frames[i].now, step: distance(frame.camera_position, sweep.frames[i].camera_position) }));
  check(sweep.metrics.max_camera_step_m < 0.30, 'All adjacent browser frames contain no camera jump over 30 cm',
    { max_camera_step_m: sweep.metrics.max_camera_step_m, frames: singleSteps.length,
      longer_frame_intervals: singleSteps.filter(sample => sample.dt > 25).length,
      stalls_over_40ms: singleSteps.filter(sample => sample.dt > 40) });
  await sleep(2000);
  await startFrames('released-view-rest'); await sleep(3200);
  const rest = await stopFrames(), first = rest.frames[0];
  const drift = Math.max(...rest.frames.map(frame => distance(first.camera_position, frame.camera_position)));
  check(drift < 0.0001 && rest.frames.every(frame => frame.camera_pitch === first.camera_pitch &&
    frame.camera_yaw === first.camera_yaw && frame.camera_alpha === first.camera_alpha),
    'The released near-wall view remains motionless for more than three seconds', { drift_m: drift, ...rest.metrics });
}

async function waitWatch() {
  await page.waitForFunction(() => {
    const guard = JSON.parse(window.xiabanP4BState).guards[0];
    return guard.state === 'watching' && guard.remaining > 1.7;
  }, null, { timeout: 16000 });
}
async function watchEvidence() {
  await restart();
  await page.keyboard.press('c'); await waitState({ stance: 'crouched', transition_remaining: 0 });
  await hold('w', 1300);
  await hold('ArrowRight', 410); await hold('ArrowDown', 180);
  await sleep(1500);
  await waitWatch();
  await startFrames('leader-cue-rest');
  for (let i = 0; i < 7; i++) { await screenshot(`leader-cue-rest-${i}`); await sleep(160); }
  const cue = await stopFrames();
  check(cue.frames.length > 35 && cue.frames.every(frame => frame.phase === 'playing' &&
    frame.guards[0].state === 'watching' && frame.guards[0].fan_visible && frame.guards[0].progress === 0),
    'The first leader cue stays continuously visible throughout an actual observation interval behind cover', cue.metrics);
  const before = cue.frames[0];
  const guard = before.guards[0], lastGuard = cue.frames.at(-1).guards[0];
  check(Number.isInteger(guard.fan_revision) && guard.fan_vertex_count > 0 && guard.cue_height_profile === 'crouched' &&
    cue.frames.every(frame => frame.guards[0].fan_revision === guard.fan_revision &&
      frame.guards[0].fan_vertex_count === guard.fan_vertex_count && frame.guards[0].cue_height_profile === 'crouched') &&
    lastGuard.fan_refresh_count - guard.fan_refresh_count >= 5,
    'Repeated cue sampling during real crouched idle animation retains identical geometry',
    { revision: guard.fan_revision, vertices: guard.fan_vertex_count, refreshes: lastGuard.fan_refresh_count - guard.fan_refresh_count });
  check(cue.frames.every(frame => distance(frame.camera_position, before.camera_position) < 0.0001),
    'Continuous cue video and seven screenshots use a stationary view, isolating cue changes from camera movement');
  await page.waitForFunction(() => JSON.parse(window.xiabanP4BState).guards[0].state === 'working');
  await waitWatch();
  await startFrames('leader-cue-stance-transition');
  await page.keyboard.press('c'); await waitState({ stance: 'standing', transition_remaining: 0 });
  await screenshot('leader-cue-standing'); await sleep(300);
  await page.keyboard.press('c'); await waitState({ stance: 'crouched', transition_remaining: 0 });
  await screenshot('leader-cue-crouched'); await sleep(200);
  const transition = await stopFrames();
  check(transition.frames.every(frame => frame.phase === 'playing' && frame.guards[0].progress === 0),
    'Real crouch/stand transitions behind high cover keep detection clear while cue frames are recorded', transition.metrics);
  const profiles = [...new Set(transition.frames.map(frame => frame.guards[0].cue_height_profile))];
  const revisions = transition.frames.map(frame => frame.guards[0].fan_revision);
  check(profiles.includes('transition') && profiles.includes('standing') && profiles.includes('crouched') &&
    Math.max(...revisions) - Math.min(...revisions) <= 4,
    'Crouch/stand cue changes follow bounded stance transitions instead of animation-frame oscillation',
    { profiles, revision_changes: Math.max(...revisions) - Math.min(...revisions) });
  // The high cabinet intentionally hides much of the floor. Move with actual W
  // input to low cover before recording the visibly exposed cue for review.
  await page.keyboard.press('f'); await sleep(550);
  const walking = await state();
  await hold('w', Math.max(0, (walking.position[2] - 29.0) / 0.75 * 1000));
  await hold('ArrowRight', 900); await hold('ArrowDown', 130);
  await sleep(1500); await waitWatch();
  await startFrames('leader-cue-low-cover');
  for (let i = 0; i < 7; i++) { await screenshot(`leader-cue-low-cover-${i}`); await sleep(160); }
  const low = await stopFrames(), lowFirst = low.frames[0];
  check(Math.abs(lowFirst.position[2] - 29) < 0.2 && low.frames.every(frame => frame.phase === 'playing' &&
    frame.guards[0].state === 'watching' && frame.guards[0].fan_visible && frame.guards[0].progress === 0 &&
    frame.guards[0].fan_revision === lowFirst.guards[0].fan_revision &&
    distance(frame.camera_position, lowFirst.camera_position) < 0.0001),
    'Low-cover observation records the exposed cue continuously with stable geometry and view',
    { position: lowFirst.position, revision: lowFirst.guards[0].fan_revision, vertices: lowFirst.guards[0].fan_vertex_count,
      ...low.metrics });
  await page.keyboard.press('Escape'); await waitState('paused');
}

(async () => {
  const response = await fetch(new URL('index.pck', BASE)); assert.ok(response.ok, 'Export is served');
  const bytes = Buffer.from(await response.arrayBuffer());
  testedBuild = { url: response.url, size_bytes: bytes.length, sha256: createHash('sha256').update(bytes).digest('hex') };
  browser = await chromium.launch({ channel: 'chrome', headless: HEADLESS });
  browserVersion = browser.version();
  browser.on('disconnected', () => { if (!closing) crashes.push('unexpected browser disconnect'); });
  context = await browser.newContext({ viewport: { width: 1152, height: 720 },
    recordVideo: { dir: path.join(OUT, 'video'), size: { width: 1152, height: 720 } } });
  await context.addInitScript(() => {
    const nativeFetch = window.fetch;
    window.__stabilityResponses = [];
    window.__stabilityNetworkHashes = [];
    window.__stabilityPck = null;
    window.fetch = async function (...args) {
      const response = await nativeFetch.apply(this, args);
      if (/\/index\.(pck|wasm)$/.test(new URL(response.url).pathname)) {
        window.__stabilityResponses.push(response);
        const inspected = response.clone().arrayBuffer().then(async bytes => ({
          size_bytes: bytes.byteLength, url: response.url,
          sha256: Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)), x => x.toString(16).padStart(2, '0')).join('') }));
        window.__stabilityNetworkHashes.push(inspected);
        if (/\/index\.pck$/.test(new URL(response.url).pathname)) window.__stabilityPck = inspected;
      }
      return response;
    };
  });
  page = await context.newPage(); video = page.video();
  page.on('console', message => {
    logs.push({ type: message.type(), text: message.text() });
    if ((message.type() === 'error' && !/favicon\.ico$/.test(message.location().url)) ||
      /webgl.*context.*lost|out of memory|runtimeerror|script error/i.test(message.text())) errors.push(message.text());
  });
  page.on('pageerror', error => errors.push(error.message));
  page.on('crash', () => crashes.push('game page crashed'));
  page.on('requestfailed', request => { if (!closing) errors.push(`${request.url()}: ${request.failure()?.errorText}`); });
  await page.goto(url.href); await waitState('menu', 30000);
  await page.waitForFunction(() => !document.getElementById('status'));
  loadedBuild = await page.evaluate(() => window.__stabilityPck);
  check(loadedBuild?.sha256 === testedBuild.sha256 && loadedBuild?.size_bytes === testedBuild.size_bytes,
    'The actual browser-loaded PCK matches the stability test package', loadedBuild);
  await page.bringToFront(); await clickButton('primary'); await waitState('playing'); await sleep(1000);
  check(await locked(), 'The final release starts through a real click and retains pointer capture');
  await keyboardAndMouse();
  await movementPriority();
  await pauseAndFocus();
  await orbitContinuity();
  await watchEvidence();
  await page.evaluate(() => Promise.all(window.__stabilityNetworkHashes));
  check(errors.length === 0, 'Camera and cue scenarios finish without script, WebGL or network errors', { errors });
  check(crashes.length === 0, 'Chrome and the game tab remain stable throughout continuous recording', { crashes });
  console.log('STABILITY_BROWSER_RESULT', results.filter(result => result.pass).length, 'passed');
})().catch(async error => {
  console.error(error.stack);
  results.push({ pass: false, description: 'Uncaught stability test failure', evidence: { message: error.message } });
  if (page && !page.isClosed()) { try { await screenshot('failure'); } catch (_) {} }
  process.exitCode = 1;
}).finally(async () => {
  closing = true;
  if (context) await context.close();
  if (video) await video.saveAs(path.join(OUT, 'camera-and-cue.webm'));
  if (browser) await browser.close();
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({ date: new Date().toISOString(), url: BASE,
    coverage: 'real-browser-camera-input-and-continuous-rendering-evidence', browserVersion, headless: HEADLESS,
    pass: results.filter(result => result.pass).length, failed: results.filter(result => !result.pass).length,
    testedBuild, loadedBuild, results, segments, errors, crashes, logs,
    limitations: ['Camera collision contact correctness is tested separately in the engine.',
      'Continuous video and screenshots require visual review for perceptual flicker; cue visibility alone is not a no-flicker proof.'] }, null, 2));
});
