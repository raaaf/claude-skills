// Tests for ui-shots.mjs argument handling and login detection. Run with `node --test screens/bin/`.
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { parseArgs, isLoginUrl } from './ui-shots.mjs';

const creds = join(mkdtempSync(join(tmpdir(), 'ui-shots-test-')), 'creds');
writeFileSync(creds, 'user\npass\n');

test('parseArgs reads url, out and a dev login url', () => {
  assert.deepEqual(parseArgs(['--url', 'http://x/', '--out', '/o', '--login-url', 'http://x/dev']), {
    url: 'http://x/', out: '/o', loginUrl: 'http://x/dev',
  });
});

test('parseArgs reads a form login with its creds file path, never the credentials', () => {
  const opts = parseArgs(['--url', 'http://x/', '--form-login', 'http://x/in', 'email', 'password', '--creds-file', creds]);
  assert.deepEqual(opts.formLogin, { url: 'http://x/in', userField: 'email', passField: 'password' });
  assert.equal(opts.credsFile, creds);
});

test('parseArgs rejects credentials on the command line and other unknown arguments', () => {
  assert.throws(() => parseArgs(['--url', 'http://x/', '--password', 'secret']), /unknown argument/);
  assert.throws(() => parseArgs(['--url', 'http://x/', '--user', 'me']), /unknown argument/);
});

test('parseArgs validates required and incomplete arguments', () => {
  assert.throws(() => parseArgs([]), /--url is required/);
  assert.throws(() => parseArgs(['--url']), /needs a value/);
  assert.throws(() => parseArgs(['--url', 'http://x/', '--form-login', 'http://x/in', 'email', 'password']), /needs --creds-file/);
  assert.throws(() => parseArgs(['--url', 'http://x/', '--form-login', 'http://x/in', 'email']), /needs <url>/);
  assert.throws(() => parseArgs(['--url', 'http://x/', '--creds-file', creds]), /only belongs/);
  assert.throws(() => parseArgs(['--url', 'http://x/', '--login-url', 'http://x/d', '--form-login', 'http://x/in', 'a', 'b', '--creds-file', creds]), /either/);
  assert.throws(() => parseArgs(['--url', 'http://x/', '--form-login', 'http://x/in', 'a', 'b', '--creds-file', '/nonexistent/creds']), /not found/);
});

test('isLoginUrl matches each login path pattern', () => {
  for (const p of ['/login', '/signin', '/sign-in', '/sign_in', '/anmelden', '/session/new', '/auth', '/auth/callback', '/login?next=/a']) {
    assert.equal(isLoginUrl(`http://x${p}`), true, p);
  }
});

test('isLoginUrl leaves ordinary pages alone', () => {
  for (const p of ['/', '/settings', '/family', '/authors', '/loginfo']) {
    assert.equal(isLoginUrl(`http://x${p}`), false, p);
  }
  assert.equal(isLoginUrl('not a url'), false);
});
