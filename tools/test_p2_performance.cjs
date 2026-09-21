/* Dedicated four-actor rendering fixture, separate from the P2 playable export.
 * Export "Web P2 Benchmark", serve builds/p2-benchmark on 8768, then run this.
 * No artificial clock, fixed FPS, actor control API, or production query mode.
 */
const { chromium } = require('../.tools/browser-qa/node_modules/playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');

const out = path.resolve('.logs/p2-performance-web');
const url = process.env.P2_BENCHMARK_URL || 'http://127.0.0.1:8768/';
fs.mkdirSync(out, { recursive: true });
(async () => {
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  const errors = [];
  const messages = [];
  try {
    const page = await browser.newPage({ viewport: { width: 1152, height: 720 } });
    const started = Date.now();
    let sceneReadyMs = null;
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', entry => {
      messages.push({ type: entry.type(), text: entry.text() });
      if (entry.text().includes('P2_READY')) sceneReadyMs = Date.now() - started;
    });
    await page.goto(url);
    await page.waitForFunction(() => ['complete', 'failed'].includes(window.xiabanP2Benchmark?.status), null, { timeout: 120000 });
    const report = await page.evaluate(() => window.xiabanP2Benchmark);
    report.browser = { version: await browser.version(), mode: 'headless', url,
      scene_ready_ms: sceneReadyMs, total_load_and_measurement_ms: Date.now() - started };
    report.browser_errors = errors;
    fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
    fs.writeFileSync(path.join(out, 'console.json'), JSON.stringify(messages, null, 2));
    await page.screenshot({ path: path.join(out, 'four-actors.png') });
    assert.equal(errors.length, 0, 'No browser runtime errors');
    assert.equal(report.status, 'complete', 'The fixture completed successfully');
    assert.equal(report.configuration.actors, 4, 'Four real skinned actors');
    assert.ok(report.measurement.seconds >= 5, 'At least five seconds of real rendering');
    assert.ok(report.measurement.animation_evidence.every(actor => actor.playing && actor.pose_changed),
      'All four actors animate during measurement');
    assert.ok(report.grounding.passed, 'Imported animation geometry passes the grounding scan');
    console.log('P2_WEB_PERFORMANCE_OK', JSON.stringify({
      fps: report.measurement.average_fps, frame_ms: report.measurement.frame_time_ms,
      gpu: report.device.gpu, browser: report.browser.version, report: path.join(out, 'report.json')
    }));
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
