// Times the in-page pass — the half that runs inside every web view — on the
// documents tool/benchmark.dart writes, in Chromium at 1x and with the CPU
// throttled 6x (roughly a low-end Android phone), and in WebKit.
//
//     dart run tool/benchmark.dart && node tool/node/bench.mjs
import { chromium, webkit } from '@playwright/test';
import { readdirSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

import { packageRoot } from './engine.mjs';

const dir = join(packageRoot, 'build', 'bench');
const files = readdirSync(dir).filter((f) => f.endsWith('.html')).sort();
const RUNS = 7;

async function measure(page, file) {
  const times = [];
  let info;
  for (let i = 0; i < RUNS; i++) {
    await page.goto(pathToFileURL(join(dir, file)).href);
    await page.waitForLoadState('load');
    info = await page.evaluate(() => ({
      ms: window.__t1 - window.__t0,
      els: document.getElementsByTagName('*').length,
      source: document.documentElement.getAttribute('data-kdm-source'),
      stats: document.documentElement.getAttribute('data-kdm-stats'),
    }));
    times.push(info.ms);
  }
  times.sort((a, b) => a - b);
  return { median: times[Math.floor(RUNS / 2)], ...info };
}

for (const [name, engine, throttle] of [
  ['chromium 1x', chromium, 1],
  ['chromium 6x', chromium, 6],
  ['webkit 1x', webkit, 1],
]) {
  const browser = await engine.launch();
  const page = await browser.newPage({ viewport: { width: 360, height: 740 } });
  if (throttle > 1) {
    const cdp = await page.context().newCDPSession(page);
    await cdp.send('Emulation.setCPUThrottlingRate', { rate: throttle });
  }
  console.log(`\n${name}`);
  for (const file of files) {
    const r = await measure(page, file);
    console.log(`  ${file.padEnd(28)} ${r.median.toFixed(1).padStart(7)} ms   ${String(r.els).padStart(5)} elements   ${r.source}`);
  }
  await browser.close();
}
