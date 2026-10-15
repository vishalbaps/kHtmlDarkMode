// The in-page pass, run for real: every document here is the output of
// KHtmlDarkMode.convert (rendered by tool/render_fixtures.dart), loaded into
// Chromium and WebKit at phone width.
//
// The contrast audit measures the rendered page independently of the engine:
// it walks the DOM, composites the backgrounds the browser actually painted,
// and checks every visible line of text against WCAG.
import { expect, test } from '@playwright/test';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

import { packageRoot } from '../engine.mjs';

const OUT = join(packageRoot, 'build', 'browser');
const VERSION = /^version:\s*(\S+)/m.exec(readFileSync(join(packageRoot, 'pubspec.yaml'), 'utf8'))[1];

const DARK = [
  'fragment-message.dark',
  'probe-1-colours.dark',
  'probe-2-images.dark',
  'preserve.dark',
  'probe-1-colours.dark.scaled',
  'probe-1-colours.dark.twice',
  'fragment-message.dark.fit',
  'fragment-message.dark.black',
  'fragment-message.dark.hostcss',
  'fragment-message.dark.trace',
];
const FIXTURES = ['fragment-message', 'probe-1-colours', 'probe-2-images', 'preserve', 'author-dark'];

/** Opens a rendered document and waits for the pass to finish. */
async function open(page, id) {
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(pathToFileURL(join(OUT, `${id}.html`)).href);
  await page.waitForLoadState('load');
  await page.waitForFunction(() => document.documentElement.hasAttribute('data-kdm-source'), null, { timeout: 5000 });
  return errors;
}

async function openOriginal(page, fixture) {
  await page.goto(pathToFileURL(join(OUT, `${fixture}.original.html`)).href);
  await page.waitForLoadState('load');
}

const attrs = (page) =>
  page.evaluate(() => {
    const r = document.documentElement;
    return {
      source: r.getAttribute('data-kdm-source'),
      version: r.getAttribute('data-kdm-version'),
      theme: r.getAttribute('data-kdm-theme'),
      error: r.getAttribute('data-kdm-error'),
      stats: JSON.parse(r.getAttribute('data-kdm-stats') || 'null'),
    };
  });

/** Computed colours of every author element in body, in document order. */
const snapshot = (page) =>
  page.evaluate(() => {
    const SKIP = { SCRIPT: 1, STYLE: 1, META: 1, TITLE: 1, LINK: 1 };
    const out = [];
    for (const el of document.body.querySelectorAll('*')) {
      if (SKIP[el.tagName] || /^(kdm|host)-/.test(el.id)) continue;
      const cs = getComputedStyle(el);
      out.push({
        tag: el.tagName,
        id: el.id,
        text: (el.textContent || '').trim().slice(0, 40),
        bg: cs.backgroundColor,
        color: cs.color,
        fill: cs.fill,
        fontSize: parseFloat(cs.fontSize),
        style: el.getAttribute('style'),
      });
    }
    return out;
  });

/** Every visible run of text, against the background the browser painted. */
const contrastAudit = (page) =>
  page.evaluate(() => {
    function parse(v) {
      const m = /rgba?\(\s*([\d.]+)[\s,]+([\d.]+)[\s,]+([\d.]+)(?:[\s,/]+([\d.]+))?/.exec(v || '');
      return m ? [m[1] / 255, m[2] / 255, m[3] / 255, m[4] === undefined ? 1 : +m[4]] : null;
    }
    const lin = (v) => (v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4));
    const lum = (c) => 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2]);
    const ratio = (a, b) => {
      const x = lum(a), y = lum(b);
      return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
    };
    const mix = (top, under) => [0, 1, 2].map((i) => top[i] * top[3] + under[i] * (1 - top[3]));

    /* The composited backdrop, or null when text sits over an image or a
       gradient — those are best effort by design and not auditable here. */
    function backdrop(el) {
      const layers = [];
      for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
        const cs = getComputedStyle(n);
        if (cs.backgroundImage && cs.backgroundImage !== 'none') return null;
        const c = parse(cs.backgroundColor);
        if (c && c[3] > 0) {
          layers.push(c);
          if (c[3] >= 0.999) break;
        }
      }
      let acc = [1, 1, 1];
      for (let i = layers.length - 1; i >= 0; i--) acc = layers[i][3] >= 0.999 ? layers[i].slice(0, 3) : mix(layers[i], acc);
      return acc;
    }

    const failures = [];
    let checked = 0;
    for (const el of document.body.querySelectorAll('*')) {
      if (/^(SCRIPT|STYLE|TEMPLATE|NOSCRIPT)$/.test(el.tagName)) continue;
      if (el.closest('[data-kdm-preserve]')) continue;
      const own = [...el.childNodes].some((n) => n.nodeType === 3 && n.nodeValue.trim());
      if (!own || !el.getClientRects().length) continue;
      const bg = backdrop(el);
      if (!bg) continue;
      const cs = getComputedStyle(el);
      const fg0 = parse(cs.color);
      const fg = fg0[3] < 0.999 ? mix(fg0, bg) : fg0;
      const size = parseFloat(cs.fontSize);
      const bold = (parseInt(cs.fontWeight, 10) || 400) >= 600;
      const target = size >= 24 || (bold && size >= 18.66) ? 3 : 4.5;
      const r = ratio(fg, bg);
      checked++;
      if (r < target - 0.02) {
        failures.push(`${el.tagName} "${el.textContent.trim().slice(0, 30)}" ${cs.color} on ` +
          `rgb(${bg.map((v) => Math.round(v * 255)).join(', ')}) = ${r.toFixed(2)}:1 (needs ${target})`);
      }
    }
    return { checked, failures };
  });

// ---------------------------------------------------------------- dark mode

for (const id of DARK) {
  test(`${id}: the pass runs, and every line of text meets WCAG AA`, async ({ page }) => {
    const errors = await open(page, id);
    expect(errors, 'page errors').toEqual([]);

    const a = await attrs(page);
    expect(a.error).toBeNull();
    expect(a.theme).toBe('dark');
    expect(a.version).toBe(VERSION);
    expect(a.source).toBe('engine');

    const audit = await contrastAudit(page);
    // The preserve fixture opts most of itself out on purpose.
    expect(audit.checked, 'nothing was audited').toBeGreaterThan(id.startsWith('preserve') ? 0 : 3);
    expect(audit.failures).toEqual([]);
  });
}

test('the pass actually changes a light template', async ({ page }) => {
  await open(page, 'probe-1-colours.dark');
  const a = await attrs(page);
  expect(a.stats.surfaces).toBeGreaterThan(5);
  expect(a.stats.texts).toBeGreaterThan(5);
});

test('seven nested white tables stay one flat surface (I6)', async ({ page }) => {
  await open(page, 'probe-1-colours.dark');
  const levels = await page.evaluate(() => {
    const cells = [...document.querySelectorAll('div')].filter((d) => /^level \d$/.test(d.textContent.trim()));
    return [...new Set(cells.map((d) => getComputedStyle(d.closest('table')).backgroundColor))];
  });
  expect(levels).toHaveLength(1);
});

test('the warm brand ramp is left exactly as authored (I5)', async ({ page }) => {
  await open(page, 'probe-1-colours.dark');
  const ramp = await page.evaluate(() =>
    [...document.querySelectorAll('td.ebCell')].slice(-8, -2).map((td) => getComputedStyle(td).backgroundColor));
  expect(ramp).toEqual([
    'rgb(230, 81, 0)', 'rgb(245, 124, 0)', 'rgb(255, 152, 0)',
    'rgb(255, 179, 0)', 'rgb(255, 210, 90)', 'rgb(255, 235, 59)',
  ]);
});

test('images are never touched, dark icons are lifted, a brand icon is kept', async ({ page }) => {
  await openOriginal(page, 'probe-2-images');
  const before = await snapshot(page);
  await open(page, 'probe-2-images.dark');
  const after = await snapshot(page);

  const imgsBefore = before.filter((e) => e.tag === 'IMG');
  const imgsAfter = after.filter((e) => e.tag === 'IMG');
  expect(imgsAfter.length).toBeGreaterThan(0);
  expect(imgsAfter.map((e) => e.style)).toEqual(imgsBefore.map((e) => e.style));

  const fills = after.filter((e) => e.tag === 'path').map((e) => e.fill);
  expect(fills[0]).not.toBe('rgb(20, 33, 31)'); // #14211F lifted
  expect(fills[1]).not.toBe('rgb(51, 51, 51)'); // #333333 lifted
  expect(fills[2]).toBe('rgb(0, 104, 81)'); // #006851 brand kept
});

test('data-kdm-preserve keeps a subtree exactly as authored', async ({ page }) => {
  await open(page, 'preserve.dark');
  const s = await page.evaluate(() => {
    const c = (sel, p) => getComputedStyle(document.querySelector(sel))[p];
    return {
      convertedBg: c('#converted', 'backgroundColor'),
      keptBg: c('#kept', 'backgroundColor'),
      keptColor: c('#kept', 'color'),
      childColor: c('#kept-child', 'color'),
    };
  });
  expect(s.convertedBg).not.toBe('rgb(240, 240, 240)');
  expect(s.keptBg).toBe('rgb(255, 255, 255)');
  expect(s.keptColor).toBe('rgb(34, 34, 34)');
  expect(s.childColor).toBe('rgb(68, 68, 68)');
});

test('a template with its own dark mode is left to it', async ({ page }) => {
  const errors = await open(page, 'author-dark.dark');
  expect(errors).toEqual([]);
  const a = await attrs(page);
  expect(a.source).toBe('author');
  expect(a.stats.surfaces).toBe(0);
  expect(a.stats.texts).toBe(0);
});

test("a host's own color-scheme CSS is not mistaken for the author's", async ({ page }) => {
  await open(page, 'fragment-message.dark.hostcss');
  expect((await attrs(page)).source).toBe('engine');
});

test('converting twice renders exactly like converting once (I4)', async ({ page }) => {
  await open(page, 'probe-1-colours.dark');
  const once = await snapshot(page);
  await open(page, 'probe-1-colours.dark.twice');
  const twice = await snapshot(page);
  expect(twice.map((e) => [e.bg, e.color])).toEqual(once.map((e) => [e.bg, e.color]));
});

test('font scaling multiplies every text size and keeps the hierarchy', async ({ page }) => {
  await open(page, 'probe-1-colours.dark');
  const base = await snapshot(page);
  await open(page, 'probe-1-colours.dark.scaled');
  const scaled = await snapshot(page);
  const a = await attrs(page);
  expect(a.stats.scaled).toBeGreaterThan(20);

  const own = await page.evaluate(() =>
    [...document.body.querySelectorAll('*')]
      .filter((el) => !/^(SCRIPT|STYLE|META|TITLE|LINK)$/.test(el.tagName) && !/^(kdm|host)-/.test(el.id))
      .map((el) => [...el.childNodes].some((n) => n.nodeType === 3 && n.nodeValue.trim())));
  let checked = 0;
  base.forEach((b, i) => {
    if (!own[i]) return;
    expect(scaled[i].fontSize, `${b.tag} "${b.text}"`).toBeCloseTo(b.fontSize * 1.3, 1);
    checked++;
  });
  expect(checked).toBeGreaterThan(20);
});

test('the page background override paints the page', async ({ page }) => {
  await open(page, 'fragment-message.dark.black');
  const bg = await page.evaluate(() => getComputedStyle(document.documentElement).backgroundColor);
  expect(bg).toBe('rgb(0, 0, 0)');
});

test('fit-to-width scales a 600px table down to a phone', async ({ page }) => {
  await open(page, 'fragment-message.dark.fit');
  await page.waitForFunction(() => window.__host && window.__host.layouts.length > 0);
  const s = await page.evaluate(() => ({
    layout: window.__host.layouts[window.__host.layouts.length - 1],
    transform: document.getElementById('kdm-content').style.transform,
    pageWidth: document.documentElement.scrollWidth,
    viewport: document.documentElement.clientWidth,
  }));
  expect(s.layout.scale).toBeLessThan(1);
  expect(s.layout.height).toBeGreaterThan(0);
  expect(s.transform).toMatch(/^scale\(/);
  expect(s.pageWidth).toBeLessThanOrEqual(s.viewport);
});

test('fit-to-width keeps collapsed edge margins inside the clamped height', async ({ page }) => {
  await open(page, 'fit-margins.dark.fit');
  await page.waitForFunction(() => window.__host && window.__host.layouts.length > 0);
  const s = await page.evaluate(() => ({
    layout: window.__host.layouts[window.__host.layouts.length - 1],
    lastBottom: document.getElementById('last').getBoundingClientRect().bottom,
    rootBottom: document.getElementById('kdm-root').getBoundingClientRect().bottom,
  }));
  expect(s.layout.scale).toBeLessThan(1);
  expect(s.lastBottom, 'the last child is clipped by #kdm-root').toBeLessThanOrEqual(s.rootBottom + 0.5);
  expect(s.layout.height).toBeGreaterThanOrEqual(Math.floor(s.lastBottom));
});

test('fit-to-width leaves sub-pixel overflow unscaled', async ({ page }) => {
  await open(page, 'fit-subpixel.dark.fit');
  await page.waitForFunction(() => window.__host && window.__host.layouts.length > 0);
  const s = await page.evaluate(() => ({
    layout: window.__host.layouts[window.__host.layouts.length - 1],
    transform: document.getElementById('kdm-content').style.transform,
    rootHeight: document.getElementById('kdm-root').style.height,
  }));
  expect(s.layout.scale).toBe(1);
  expect(s.transform || 'none').toBe('none');
  expect(s.rootHeight || 'auto').toBe('auto');
});

test('a host hears kdm:report and kdm:layout from its body-end script', async ({ page }) => {
  await open(page, 'fragment-message.dark');
  await page.waitForFunction(() => window.__host && window.__host.reports.length > 0 && window.__host.layouts.length > 0);
  const host = await page.evaluate(() => ({ ...window.__host, global: window.kdmReport }));
  expect(host.reports[0].source).toBe('engine');
  expect(host.reports[0].v).toBe(VERSION);
  expect(host.reports[0].trace).toBeNull();
  expect(host.global.source).toBe('engine');
  expect(host.layouts[0].height).toBeGreaterThan(0);
});

test('kdm:layout fires once per distinct size and is left on window.kdmLayout', async ({ page }) => {
  await open(page, 'fragment-message.dark');
  await page.waitForFunction(() => window.__host && window.__host.layouts.length > 0);
  const s = await page.evaluate(() => ({ layouts: window.__host.layouts, last: window.kdmLayout }));
  for (let i = 1; i < s.layouts.length; i++) {
    const a = s.layouts[i - 1], b = s.layouts[i];
    expect(a.height !== b.height || a.scale !== b.scale, 'a repeated, identical layout event').toBe(true);
  }
  expect(s.last).toEqual(s.layouts[s.layouts.length - 1]);
});

test('borders dim on every side that has one, and only there', async ({ page }) => {
  // Guards the one-read border shortcut: elements with a border must still be
  // mapped side by side, elements without one must be left alone.
  await open(page, 'fragment-message.dark');
  const s = await page.evaluate(() => {
    const card = getComputedStyle(document.querySelector('.card'));
    const cell = getComputedStyle(document.querySelector('table td'));
    return {
      card: [card.borderTopColor, card.borderRightColor, card.borderBottomColor, card.borderLeftColor],
      cellBottom: cell.borderBottomColor,
      cellTopWidth: cell.borderTopWidth,
    };
  });
  for (const side of s.card) expect(side).not.toBe('rgb(227, 230, 234)'); // #e3e6ea dimmed on all four
  expect(new Set(s.card).size).toBe(1);
  expect(s.cellBottom).not.toBe('rgb(221, 221, 221)'); // #dddddd hairline dimmed
  expect(s.cellTopWidth).toBe('0px');
});

test('debugTrace explains each background decision', async ({ page }) => {
  await open(page, 'fragment-message.dark.trace');
  const trace = await page.evaluate(() => window.kdmReport.trace);
  expect(trace.length).toBeGreaterThan(0);
  expect(trace[0]).toEqual(expect.objectContaining({ el: expect.any(String), a: expect.any(String), k: expect.any(String) }));
});

// --------------------------------------------------------------- light mode

for (const fixture of FIXTURES) {
  test(`${fixture}: light mode changes no authored colour`, async ({ page }) => {
    await openOriginal(page, fixture);
    const before = await snapshot(page);
    const errors = await open(page, `${fixture}.light`);
    expect(errors).toEqual([]);
    const after = await snapshot(page);
    expect((await attrs(page)).source).toBe('light');

    expect(after.length).toBe(before.length);
    const diffs = [];
    before.forEach((b, i) => {
      const a = after[i];
      // The one intended difference: text that never chose a colour inherits
      // the palette's body text (#141417) instead of the browser's black.
      const colourOk = a.color === b.color || (b.color === 'rgb(0, 0, 0)' && a.color === 'rgb(20, 20, 23)');
      if (a.bg !== b.bg || !colourOk || a.fontSize !== b.fontSize) {
        diffs.push(`${b.tag} "${b.text}": bg ${b.bg} -> ${a.bg}, color ${b.color} -> ${a.color}`);
      }
    });
    expect(diffs).toEqual([]);
  });
}
