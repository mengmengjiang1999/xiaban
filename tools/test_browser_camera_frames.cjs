/* Bounded frame-stall diagnosis: two identical real-key sweeps in one page.
 * No video recording, screenshots, input injection into Godot, or frame filters.
 * All >40ms intervals retain their neighboring camera/alpha/guard observations.
 * RELEASE_URL selects the exported build; RELEASE_OUT selects evidence output.
 * CAMERA_MAX_FRAME_MS optionally turns the diagnosis into a strict frame limit.
 */
const { chromium } = require('../.tools/browser-qa/node_modules/playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const BASE = process.env.RELEASE_URL || 'http://127.0.0.1:8774/';
const OUT = path.resolve(process.env.RELEASE_OUT || '.logs/release-browser-camera-frames');
const MAX_FRAME_MS = Number(process.env.CAMERA_MAX_FRAME_MS || '0');
const url = new URL(BASE);
for (const key of ['p1_qa', 'p3_qa', 'p4b_qa', 'release_qa']) url.searchParams.set(key, '1');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const rounds = [], errors = [], crashes = [];
let browser, context, page, loadedBuild, browserVersion, closing = false;
fs.mkdirSync(OUT, { recursive: true });
async function state() {
  return page.evaluate(() => Object.assign({}, ...['xiabanP1State', 'xiabanP3State', 'xiabanP4BState', 'xiabanReleaseState']
    .map(name => JSON.parse(window[name]))));
}
async function waitPhase(phase) {
  await page.waitForFunction(expected => window.xiabanP1State && window.xiabanP3State && window.xiabanP4BState &&
    window.xiabanReleaseState && JSON.parse(window.xiabanP1State).phase === expected, phase, { timeout: 30000 });
}
async function click(name) {
  const snapshot = await state(), button = snapshot.buttons[name];
  assert.ok(button?.visible);
  const box = await page.locator('canvas').boundingBox(), rect = button.rect;
  await page.mouse.click(box.x + (rect[0] + rect[2] / 2) * box.width / snapshot.viewport[0],
    box.y + (rect[1] + rect[3] / 2) * box.height / snapshot.viewport[1]);
}
async function hold(key, ms) {
  await page.keyboard.down(key);
  try { await sleep(ms); } finally { await page.keyboard.up(key); }
  await sleep(40);
}
async function sweep(round) {
  await page.evaluate(() => {
    const capture = { active: true, frames: [] };
    window.__cameraFrameCapture = capture;
    function frame(now) {
      if (!capture.active) return;
      const snapshot = Object.assign({}, ...['xiabanP1State', 'xiabanP3State', 'xiabanP4BState', 'xiabanReleaseState']
        .map(name => JSON.parse(window[name])));
      capture.frames.push({ now, phase: snapshot.phase, elapsed: snapshot.elapsed, position: snapshot.position,
        heading: snapshot.heading, state: snapshot.state, camera_yaw: snapshot.camera_yaw, camera_pitch: snapshot.camera_pitch,
        camera_alpha: snapshot.camera_alpha, camera_position: snapshot.camera_position, guards: snapshot.guards });
      requestAnimationFrame(frame);
    }
    requestAnimationFrame(frame);
  });
  await hold('ArrowRight', 2500);
  await hold('ArrowUp', 1100);
  await hold('ArrowLeft', 2500);
  await hold('ArrowDown', 1400);
  const frames = await page.evaluate(() => {
    window.__cameraFrameCapture.active = false;
    const frames = window.__cameraFrameCapture.frames;
    delete window.__cameraFrameCapture;
    return frames;
  });
  const intervals = frames.slice(1).map((frame, i) => frame.now - frames[i].now);
  const sorted = [...intervals].sort((a, b) => a - b);
  const stalls = intervals.flatMap((interval, i) => interval > 40 ? [{ interval_ms: interval,
    before: frames[i], after: frames[i + 1], since_start_ms: frames[i + 1].now - frames[0].now }] : []);
  const duration = frames.at(-1).now - frames[0].now;
  const metrics = { round, frames: frames.length, duration_ms: duration, fps: intervals.length * 1000 / duration,
    p95_ms: sorted[Math.floor(sorted.length * 0.95)], max_ms: Math.max(...intervals), stalls_over_40ms: stalls,
    alpha_min: Math.min(...frames.map(frame => frame.camera_alpha)), alpha_max: Math.max(...frames.map(frame => frame.camera_alpha)),
    phases: [...new Set(frames.map(frame => frame.phase))] };
  fs.writeFileSync(path.join(OUT, `round-${round}-frames.json`), JSON.stringify(frames));
  rounds.push(metrics);
  console.log('CAMERA_FRAME_ROUND', JSON.stringify({ ...metrics, stalls_over_40ms: stalls.map(stall => ({
    interval_ms: stall.interval_ms, since_start_ms: stall.since_start_ms,
    before: { alpha: stall.before.camera_alpha, yaw: stall.before.camera_yaw, pitch: stall.before.camera_pitch },
    after: { alpha: stall.after.camera_alpha, yaw: stall.after.camera_yaw, pitch: stall.after.camera_pitch } })) }));
  assert.ok(metrics.phases.length === 1 && metrics.phases[0] === 'playing', 'The entire sweep remains in active gameplay');
}
(async () => {
  browser = await chromium.launch({ channel: 'chrome', headless: true });
  browserVersion = browser.version();
  browser.on('disconnected', () => { if (!closing) crashes.push('unexpected browser disconnect'); });
  context = await browser.newContext({ viewport: { width: 1152, height: 720 } });
  await context.addInitScript(() => {
    const nativeFetch = window.fetch;
    window.__frameResponses = []; window.__frameHashes = [];
    window.fetch = async function (...args) {
      const response = await nativeFetch.apply(this, args);
      if (/\/index\.(pck|wasm)$/.test(new URL(response.url).pathname)) {
        window.__frameResponses.push(response);
        window.__frameHashes.push(response.clone().arrayBuffer().then(async bytes => ({ url: response.url,
          size_bytes: bytes.byteLength, sha256: Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256', bytes)),
            value => value.toString(16).padStart(2, '0')).join('') })));
      }
      return response;
    };
  });
  page = await context.newPage();
  page.on('console', message => {
    if ((message.type() === 'error' && !/favicon\.ico$/.test(message.location().url)) ||
      /webgl.*context.*lost|out of memory|runtimeerror|script error/i.test(message.text())) errors.push(message.text());
  });
  page.on('pageerror', error => errors.push(error.message));
  page.on('crash', () => crashes.push('page crash'));
  page.on('requestfailed', request => { if (!closing) errors.push(`${request.url()}: ${request.failure()?.errorText}`); });
  await page.goto(url.href); await waitPhase('menu');
  await page.waitForFunction(() => !document.getElementById('status'));
  loadedBuild = (await page.evaluate(() => Promise.all(window.__frameHashes))).find(build => build.url.endsWith('/index.pck'));
  await page.bringToFront(); await click('primary'); await waitPhase('playing'); await sleep(1000);
  for (let round = 1; round <= 2; round++) {
    if (round > 1) {
      await page.keyboard.press('Escape'); await waitPhase('paused');
      await click('restart'); await waitPhase('playing'); await sleep(1000);
    }
    await sweep(round);
  }
  if (MAX_FRAME_MS > 0) assert.ok(rounds.every(round => round.max_ms <= MAX_FRAME_MS),
    `Both complete sweeps must retain every frame within ${MAX_FRAME_MS}ms`);
  await page.keyboard.press('Escape'); await waitPhase('paused');
  assert.equal(errors.length, 0, 'No unexpected browser errors');
  assert.equal(crashes.length, 0, 'No crashes');
})().catch(error => { errors.push(error.stack); console.error(error.stack); process.exitCode = 1; }).finally(async () => {
  closing = true;
  if (context) await context.close();
  if (browser) await browser.close();
  fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify({ date: new Date().toISOString(), url: BASE,
    browserVersion, headless: true, video_recording: false, max_frame_limit_ms: MAX_FRAME_MS || null, loadedBuild, rounds, errors, crashes,
    note: 'All frame intervals are retained. This diagnostic reports >40ms stalls without relaxing or filtering them.' }, null, 2));
});
