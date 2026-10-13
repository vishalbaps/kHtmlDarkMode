// The shipped JavaScript must give the same answer as the Dart engine for
// every golden vector. Both sides read test/golden/vectors.json; Dart wrote it.
import assert from 'node:assert/strict';
import { test } from 'node:test';

import { loadEngine, readVectors, rgb } from '../engine.mjs';

const vectors = readVectors();
const engine = loadEngine(vectors.config, vectors.page);
const hex = (c) => engine.css(c);

function check(name, cases, run) {
  test(`${name}: ${cases.length} cases agree with Dart`, () => {
    const failures = [];
    for (const c of cases) {
      const got = run(c);
      if (String(got).toUpperCase() !== String(c.expected).toUpperCase()) {
        failures.push(`${JSON.stringify({ ...c, expected: undefined })}: JS ${got} !== Dart ${c.expected}`);
      }
    }
    assert.deepEqual(failures, [], failures.slice(0, 20).join('\n'));
  });
}

check('classify', vectors.classify, (c) => engine.classify(rgb(c.input)));

check('mapSurface', vectors.mapSurface, (c) =>
  hex(engine.mapSurface(rgb(c.input), c.parent ? rgb(c.parent) : null, c.parentAuthored ? rgb(c.parentAuthored) : null)));

check('solveForeground', vectors.solveForeground, (c) =>
  hex(engine.solveForeground(rgb(c.input), rgb(c.background), c.target)));

check('mapShadow', vectors.mapShadow, (c) => hex(engine.mapShadow(rgb(c.input))));

check('mapBorder', vectors.mapBorder, (c) => hex(engine.mapBorder(rgb(c.input), rgb(c.background))));

check('composite', vectors.composite, (c) => hex(engine.over(rgb(c.input), c.alpha, rgb(c.backdrop))));

check('targetFor', vectors.targetFor, (c) => engine.targetForSize(c.px, c.bold));
