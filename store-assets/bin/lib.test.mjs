import { test } from 'node:test';
import assert from 'node:assert/strict';
import { fontFormat, pickIphoneColor, outputRoot } from './lib.mjs';

test('fontFormat maps extensions to CSS format hints', () => {
  assert.equal(fontFormat('a/b.woff2'), 'woff2');
  assert.equal(fontFormat('a/b.woff'), 'woff');
  assert.equal(fontFormat('a/B.TTF'), 'truetype');
  assert.equal(fontFormat('a/b.otf'), 'opentype');
  assert.throws(() => fontFormat('a/b.eot'));
});

test('pickIphoneColor: explicit > background lookup > first valid color', () => {
  const args = { byBackground: { '#f7f7f7': 'Black', '#04081f': 'Silver' }, validColors: ['Black', 'Silver'] };
  assert.equal(pickIphoneColor({ ...args, explicit: 'Silver', background: '#f7f7f7' }), 'Silver');
  assert.equal(pickIphoneColor({ ...args, explicit: null, background: '#04081f' }), 'Silver');
  assert.equal(pickIphoneColor({ ...args, explicit: null, background: '#abcdef' }), 'Black');
});

test('outputRoot defaults and honours output_dir', () => {
  assert.equal(outputRoot('/p', {}), '/p/native/store-assets/generated');
  assert.equal(outputRoot('/p', { output_dir: '.store-assets/generated' }), '/p/.store-assets/generated');
});
