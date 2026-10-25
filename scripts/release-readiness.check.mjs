import { test } from 'node:test';
import assert from 'node:assert/strict';
import { configuration, problems } from './release-readiness.mjs';
const base = { bundle: { macOS: { minimumSystemVersion: '14.0', hardenedRuntime: true, entitlements: 'Entitlements.plist' } } };
test('missing release inputs stay visibly blocked', () => {
  const config = configuration(base, {});
  assert.equal(config.plugins.updater.pubkey, '');
  assert.deepEqual(config.plugins.updater.endpoints, []);
  assert.equal(problems(config).length, 2);
});
test('reject insecure or placeholder feeds and keys', () => {
  for (const feed of ['http://github.com/o/r/releases/latest/download/latest.json', 'https://example.com/latest.json', 'https://github.com/<owner>/r/releases/latest/download/latest.json']) {
    const config = configuration(base, { SIDEFOLK_RELEASE_FEED: feed, SIDEFOLK_UPDATER_PUBLIC_KEY: '<pubkey>' });
    assert.equal(problems(config).length, 2);
  }
});
