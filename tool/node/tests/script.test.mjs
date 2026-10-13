// JavaScript-only behaviour with no Dart counterpart: CSS value parsing and the
// gradient / shadow rewriting the in-page pass applies.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { loadEngine, readVectors, rgb } from '../engine.mjs';

const vectors = readVectors();
const engine = loadEngine(vectors.config, vectors.page);
const page = rgb(vectors.page);

test('parseColor reads every form getComputedStyle and authors produce', () => {
  assert.deepEqual(engine.parseColor('rgb(255, 0, 0)'), [1, 0, 0, 1]);
  assert.deepEqual(engine.parseColor('rgba(0, 0, 255, 0.5)'), [0, 0, 1, 0.5]);
  assert.deepEqual(engine.parseColor('rgb(0 128 0 / 50%)'), [0, 128 / 255, 0, 0.5]);
  assert.deepEqual(engine.parseColor('#fff'), [1, 1, 1, 1]);
  assert.deepEqual(engine.parseColor('#00000080'), [0, 0, 0, 128 / 255]);
  for (const v of ['transparent', 'currentcolor', 'inherit', 'var(--x)', 'url(a.png)', '', null, '#12', 'red']) {
    assert.equal(engine.parseColor(v), null, `should not parse ${v}`);
  }
});

test('a brand gradient passes through untouched', () => {
  const g = 'linear-gradient(135deg, rgb(11, 95, 165), rgb(0, 105, 92))';
  assert.equal(engine.mapGradient(g, page), g);
});

test('a pale gradient stop is remapped, a brand stop is kept', () => {
  const g = 'linear-gradient(120deg, rgb(194, 86, 62) 0%, rgb(246, 179, 82) 55%, rgb(255, 243, 196) 100%)';
  const out = engine.mapGradient(g, page);
  assert.ok(out.includes('rgb(194, 86, 62) 0%'), 'brand stop changed');
  assert.ok(out.includes('rgb(246, 179, 82) 55%'), 'brand stop changed');
  assert.ok(!out.includes('rgb(255, 243, 196)'), 'pale stop kept');
});

test('a translucent gradient stop keeps its alpha', () => {
  const out = engine.mapGradient('linear-gradient(rgba(255, 255, 255, 0.5), rgba(255, 255, 255, 0.5))', [1, 1, 1]);
  assert.match(out, /rgba\(\d+,\d+,\d+,0\.5\)/);
});

test('shadows darken and keep their alpha', () => {
  const out = engine.mapShadowValue('rgba(204, 204, 204, 0.5) 0px 2px 8px 0px');
  assert.equal(out, 'rgba(45,45,45,0.5) 0px 2px 8px 0px');
});

test('the gradient average is what text over it is solved against', () => {
  const avg = engine.gradientAverage('linear-gradient(#ffffff, #f0f0f0)', page);
  assert.ok(engine.luminance(avg) < 0.18, 'average of mapped pale stops must be dark');
  assert.equal(engine.gradientAverage('none', page), null);
});
