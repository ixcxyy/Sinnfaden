import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { BugInbox, validateReport, fingerprint } from './worker.mjs';

const report = { schemaVersion: 1, id: '12345678-1234-4321-9876-123456789abc', area: 'coach', category: 'invalidResponse', version: '0.4.1', build: '5', httpStatus: 502 };
const env = { GITHUB_REPOSITORY: 'owner/private', GITHUB_TOKEN: 'SERVER-ONLY', ALLOWED_RELEASES: '0.4.1+5', MAX_NEW_ISSUES_PER_DAY: '20' };
const request = (body = report) => new Request('https://relay.test/v1/reports', { method: 'POST', headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '127.0.0.1' }, body: JSON.stringify(body) });
function state() {
  const data = new Map(); let tail = Promise.resolve();
  return {
    data,
    storage: {
      get: async key => data.get(key),
      put: async (key, value) => { if (typeof key === 'object') Object.entries(key).forEach(([k, v]) => data.set(k, v)); else data.set(key, value); },
      delete: async key => data.delete(key),
    },
    blockConcurrencyWhile: work => { const next = tail.then(work); tail = next.catch(() => {}); return next; },
  };
}

test('rejects unknown fields, unsafe text, unknown releases and invalid status', () => {
  assert.equal(validateReport(report, env.ALLOWED_RELEASES), report);
  for (const change of [{ prompt: 'private' }, { area: '@someone' }, { version: '0.4.2' }, { httpStatus: 999 }, { id: 'invalid' }, { category: 'sk-secret' }]) {
    assert.throws(() => validateReport({ ...report, ...change }, env.ALLOWED_RELEASES));
  }
});

test('same error groups across report IDs; different releases stay distinct', async () => {
  assert.equal(await fingerprint(report), await fingerprint({ ...report, id: crypto.randomUUID() }));
  assert.notEqual(await fingerprint(report), await fingerprint({ ...report, build: '6' }));
});

test('unconfigured service fails closed without sending', async () => {
  assert.equal((await worker.fetch(request(), {})).status, 503);
});

test('entrypoint rate limits, rejects oversized bodies and passes only validated reports', async () => {
  let received;
  const config = { ...env, REPORT_RATE_LIMIT: { limit: async () => ({ success: true }) }, INBOX: { idFromName: name => name, get: () => ({ fetch: async req => { received = await req.json(); return Response.json({ accepted: true }); } }) } };
  assert.equal((await worker.fetch(request(), config)).status, 200);
  assert.deepEqual(received, report);
  assert.equal((await worker.fetch(request({ ...report, prompt: 'private' }), config)).status, 400);
  assert.equal((await worker.fetch(request({ ...report, id: 'x'.repeat(5000) }), config)).status, 400);
  config.REPORT_RATE_LIMIT.limit = async () => ({ success: false });
  assert.equal((await worker.fetch(request(), config)).status, 429);
});

test('creates one private issue even when requests overlap', async t => {
  const calls = []; const storage = state(); const inbox = new BugInbox(storage, env);
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    calls.push({ url, init });
    await new Promise(resolve => setTimeout(resolve, 5));
    return Response.json(init.method === 'POST' ? { number: 42 } : { private: true });
  });
  const responses = await Promise.all([inbox.fetch(request()), inbox.fetch(request({ ...report, id: crypto.randomUUID() }))]);
  assert.deepEqual(responses.map(r => r.status), [201, 200]);
  assert.equal(calls.filter(call => call.init.method === 'POST').length, 1);
  const body = JSON.parse(calls.find(call => call.init.method === 'POST').init.body);
  assert.match(body.body, /No prompts/);
  assert.ok(!body.body.includes('SERVER-ONLY'));
  assert.equal(calls[0].init.redirect, 'manual');
});

test('public repository never receives an issue', async t => {
  let calls = 0;
  t.mock.method(globalThis, 'fetch', async () => { calls++; return Response.json({ private: false }); });
  const response = await new BugInbox(state(), env).fetch(request());
  assert.equal(response.status, 503); assert.equal(calls, 1);
});

test('failed POST with unknown outcome is reconciled after restart, never duplicated', async t => {
  const storage = state(); let posts = 0; let savedBody;
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    if (init.method === 'POST') { posts++; savedBody = JSON.parse(init.body).body; throw new Error('connection lost after server accepted'); }
    return Response.json(url.includes('/issues?') ? [{ number: 52, body: savedBody }] : { private: true });
  });
  assert.equal((await new BugInbox(storage, env).fetch(request())).status, 503);
  assert.equal((await new BugInbox(storage, env).fetch(request())).status, 200);
  assert.equal(posts, 1);
});

test('unknown POST outcome without reconciliation does not create another issue', async t => {
  const storage = state(); let posts = 0;
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    if (init.method === 'POST') { posts++; throw new Error('timeout'); }
    return Response.json(url.includes('/issues?') ? [] : { private: true });
  });
  const inbox = new BugInbox(storage, env);
  assert.equal((await inbox.fetch(request())).status, 503);
  assert.equal((await inbox.fetch(request())).status, 503);
  assert.equal(posts, 1);
});

test('daily issue cap bounds public-ingestion abuse', async t => {
  const storage = state(); let posts = 0;
  t.mock.method(globalThis, 'fetch', async (_, init) => {
    if (init.method === 'POST') { posts++; return Response.json({ number: posts }); }
    return Response.json({ private: true });
  });
  const inbox = new BugInbox(storage, { ...env, MAX_NEW_ISSUES_PER_DAY: '1' });
  assert.equal((await inbox.fetch(request())).status, 201);
  assert.equal((await inbox.fetch(request({ ...report, area: 'history' }))).status, 429);
  assert.equal(posts, 1);
});

test('definite GitHub rejection can recover after permissions are corrected', async t => {
  const storage = state(); let posts = 0;
  t.mock.method(globalThis, 'fetch', async (_, init) => {
    if (init.method === 'POST') { posts++; return posts === 1 ? Response.json({}, { status: 403 }) : Response.json({ number: 72 }); }
    return Response.json({ private: true });
  });
  const inbox = new BugInbox(storage, env);
  assert.equal((await inbox.fetch(request())).status, 503);
  assert.equal((await inbox.fetch(request())).status, 201);
  assert.equal(posts, 2);
});

test('operational logs contain only fixed failure metadata, never report or error text', async t => {
  const logs = [];
  t.mock.method(console, 'error', line => logs.push(JSON.parse(line)));
  t.mock.method(globalThis, 'fetch', async () => Response.json({ message: 'SERVER-ONLY private error text' }, { status: 401 }));
  assert.equal((await new BugInbox(state(), env).fetch(request())).status, 503);
  assert.deepEqual(logs, [
    { event: 'report_delivery_failed', stage: 'github_read', kind: 'unavailable', githubStatus: 401 },
    { event: 'report_delivery_failed', stage: 'github_repository', kind: 'unavailable', githubStatus: 401 },
  ]);
  logs.length = 0;
  const config = { ...env, INBOX: {}, REPORT_RATE_LIMIT: { limit: async () => { throw new TypeError('SERVER-ONLY private error text'); } } };
  assert.equal((await worker.fetch(request(), config)).status, 503);
  assert.deepEqual(logs, [{ event: 'report_delivery_failed', stage: 'rate_limit', kind: 'type_error', githubStatus: null }]);
});

test('GitHub redirects are rejected without forwarding the token or creating an issue', async t => {
  let calls = 0;
  t.mock.method(console, 'error', () => {});
  t.mock.method(globalThis, 'fetch', async (url, init) => {
    calls++;
    assert.equal(url, 'https://api.github.com/repos/owner/private');
    assert.equal(init.redirect, 'manual');
    return new Response(null, { status: 302, headers: { Location: 'https://unexpected.example/collect' } });
  });
  assert.equal((await new BugInbox(state(), env).fetch(request())).status, 503);
  assert.equal(calls, 1);
});

test('pasted token whitespace is trimmed while embedded control characters fail closed', async t => {
  let calls = 0;
  t.mock.method(console, 'error', () => {});
  t.mock.method(globalThis, 'fetch', async (_, init) => {
    calls++;
    assert.equal(init.headers.Authorization, 'Bearer SERVER-ONLY');
    return Response.json({ private: true });
  });
  assert.deepEqual(await new BugInbox(state(), { ...env, GITHUB_TOKEN: ' SERVER-ONLY\n' }).github(''), { private: true });
  assert.equal((await new BugInbox(state(), { ...env, GITHUB_TOKEN: 'SERVER\nONLY' }).fetch(request())).status, 503);
  assert.equal(calls, 1);
});
