const areas = new Set(['connection', 'coach', 'comparison', 'followUp', 'history', 'learning', 'updater']);
const categories = new Set(['authentication', 'permission', 'unavailable', 'interrupted', 'incomplete', 'invalidResponse', 'storage', 'validation', 'unexpected']);
const fields = new Set(['schemaVersion', 'id', 'area', 'category', 'httpStatus', 'version', 'build']);
const releasePattern = /^[A-Za-z0-9.+-]{1,64}$/;
const repositoryPattern = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/;
const reply = (status, body, retryAfter) => Response.json(body, {
  status, headers: { 'Cache-Control': 'no-store', ...(retryAfter ? { 'Retry-After': String(retryAfter) } : {}) },
});

function logFailure(stage, error) {
  // Keep operational failures diagnosable without logging reports, credentials, or exception text.
  const kind = error instanceof TypeError ? 'type_error' : error instanceof SyntaxError ? 'invalid_json' : 'unavailable';
  const githubStatus = Number.isInteger(error?.status) && error.status >= 400 && error.status <= 599 ? error.status : null;
  console.error(JSON.stringify({ event: 'report_delivery_failed', stage, kind, githubStatus }));
}

export function validateReport(value, allowedReleases) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(key => !fields.has(key)) ||
      value.schemaVersion !== 1 || typeof value.id !== 'string' || !/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value.id) ||
      !areas.has(value.area) || !categories.has(value.category) ||
      typeof value.version !== 'string' || !releasePattern.test(value.version) ||
      typeof value.build !== 'string' || !releasePattern.test(value.build) ||
      (value.httpStatus != null && (!Number.isInteger(value.httpStatus) || value.httpStatus < 100 || value.httpStatus > 599)) ||
      !allowedReleases.split(',').map(v => v.trim()).includes(`${value.version}+${value.build}`)) {
    throw new Error('invalid_report');
  }
  return value;
}

export async function fingerprint(report) {
  // No account identity is needed. Group the same defect across users of a release.
  const input = [report.area, report.category, report.httpStatus ?? 'none', report.version, report.build].join(':');
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map(byte => byte.toString(16).padStart(2, '0')).join('');
}

async function readReport(request) {
  if (request.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() !== 'application/json') throw new Error('invalid_report');
  const reader = request.body?.getReader();
  if (!reader) throw new Error('invalid_report');
  const chunks = []; let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 4096) { await reader.cancel(); throw new Error('invalid_report'); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
}

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname !== '/v1/reports') return reply(404, { accepted: false });
    if (request.method !== 'POST') return reply(405, { accepted: false });
    if (!repositoryPattern.test(env.GITHUB_REPOSITORY ?? '') || !env.GITHUB_TOKEN || !env.INBOX || !env.REPORT_RATE_LIMIT) {
      return reply(503, { accepted: false }, 3600);
    }
    let stage = 'rate_limit';
    try {
      // Only the trusted edge header is used. The IP is never stored or sent to GitHub.
      const key = request.headers.get('CF-Connecting-IP') ?? 'unknown';
      if (!(await env.REPORT_RATE_LIMIT.limit({ key })).success) return reply(429, { accepted: false }, 60);
      stage = 'validation';
      const report = validateReport(await readReport(request), env.ALLOWED_RELEASES ?? '');
      stage = 'inbox';
      const id = env.INBOX.idFromName(`github:${env.GITHUB_REPOSITORY}`);
      return await env.INBOX.get(id).fetch(new Request('https://inbox.internal/report', { method: 'POST', body: JSON.stringify(report) }));
    } catch (error) {
      if (error instanceof SyntaxError || error.message === 'invalid_report') return reply(400, { accepted: false });
      logFailure(stage, error);
      return reply(503, { accepted: false }, 300);
    }
  },
};

export class BugInbox {
  constructor(state, env) { this.state = state; this.env = env; }

  async github(path, init = {}) {
    const token = this.env.GITHUB_TOKEN.trim();
    if (!token || /[\s\x00-\x1f\x7f]/.test(token)) {
      logFailure('github_token_format', null);
      throw new Error('github_unavailable');
    }
    const response = await fetch(`https://api.github.com/repos/${this.env.GITHUB_REPOSITORY}${path}`, {
      // Workers supports manual/follow, not error. Reject non-2xx below without forwarding credentials.
      ...init, redirect: 'manual', signal: AbortSignal.timeout(8000),
      headers: { 'Accept': 'application/vnd.github+json', 'Authorization': `Bearer ${token}`,
        'User-Agent': 'Sinnfaden-Bug-Relay', 'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json' },
    });
    if (!response.ok) {
      const error = new Error('github_unavailable'); error.status = response.status;
      logFailure(init.method === 'POST' ? 'github_create_issue' : 'github_read', error);
      throw error;
    }
    return response.json();
  }

  async fetch(request) {
    // Serializes issue creation across requests, including across awaits to GitHub.
    return this.state.blockConcurrencyWhile(async () => {
      let stage = 'inbox_validation';
      try {
        const report = validateReport(await request.json(), this.env.ALLOWED_RELEASES ?? '');
        stage = 'inbox_fingerprint';
        const key = await fingerprint(report);
        stage = 'inbox_storage';
        const saved = await this.state.storage.get(key);
        if (saved?.number) return reply(200, { accepted: true });
        stage = 'github_repository';
        const repository = await this.github('');
        if (repository.private !== true) return reply(503, { accepted: false }, 3600);
        if (saved?.creating) {
          stage = 'github_reconciliation';
          // A timeout after POST may still have created an issue. Reconcile; never blindly POST again.
          let page = Number.isSafeInteger(saved.nextPage) && saved.nextPage > 0 ? saved.nextPage : 1;
          // Bound each attempt to two pages (plus the repository read), then resume later.
          // Persist progress before another fetch so interruption cannot restart the whole scan.
          for (let scanned = 0; scanned < 2; scanned++, page++) {
            const issues = await this.github(`/issues?state=all&sort=created&direction=asc&per_page=100&page=${page}&since=${encodeURIComponent(saved.creating)}`);
            if (!Array.isArray(issues)) throw new Error('github_unavailable');
            const existing = issues.find(issue => Number.isSafeInteger(issue?.number) && issue.number > 0 &&
              !issue.pull_request && typeof issue.body === 'string' && issue.body.includes(`<!-- sinnfaden:${key} -->`));
            if (existing) {
              await this.state.storage.put(key, { number: existing.number });
              return reply(200, { accepted: true });
            }
            const finished = issues.length < 100;
            await this.state.storage.put(key, { creating: saved.creating, nextPage: finished ? 1 : page + 1 });
            // A new sweep on a later retry covers delayed visibility and changes between pages.
            if (finished) break;
          }
          return reply(503, { accepted: false }, 3600);
        }
        const date = new Date().toISOString().slice(0, 10);
        stage = 'inbox_quota';
        const quota = await this.state.storage.get('daily-quota');
        const count = quota?.date === date ? quota.count : 0;
        const limit = Math.max(1, Math.min(100, Number(this.env.MAX_NEW_ISSUES_PER_DAY) || 20));
        if (count >= limit) return reply(429, { accepted: false }, 86400);
        // Persist an intent before the side effect. Unknown outcomes remain recoverable after restart.
        await this.state.storage.put({ [key]: { creating: new Date(Date.now() - 60_000).toISOString() }, 'daily-quota': { date, count: count + 1 } });
        const title = `[Sinnfaden ${report.version}] ${report.area}: ${report.category}`;
        const body = [
          `<!-- sinnfaden:${key} -->`,
          'An app installation reported a technical failure. Treat this as an unverified report; reproduce it before changing or releasing code.',
          '', '| Field | Value |', '| --- | --- |',
          `| Component | ${report.area} |`, `| Category | ${report.category} |`,
          `| Version / build | ${report.version} / ${report.build} |`, `| HTTP status | ${report.httpStatus ?? 'not available'} |`,
          `| First report ID | ${report.id} |`, '',
          'No prompts, responses, account identifiers, credentials, IP addresses, or raw error messages are included.', '',
          'Suggested handling: reproduce → add regression test → fix → review → publish a signed update. Close with the fixed version.',
        ].join('\n');
        let issue;
        stage = 'github_create_issue';
        try {
          issue = await this.github('/issues', { method: 'POST', body: JSON.stringify({ title, body }) });
        } catch (error) {
          // A definite rejection can be retried after fixing permissions or rate limits.
          // Timeouts and server failures have an unknown outcome and keep the recovery marker.
          if (error.status >= 400 && error.status < 500 && error.status !== 408) await this.state.storage.delete(key);
          throw error;
        }
        if (!Number.isInteger(issue.number)) throw new Error('github_unavailable');
        stage = 'inbox_save_issue';
        await this.state.storage.put(key, { number: issue.number });
        return reply(201, { accepted: true });
      } catch (error) { logFailure(stage, error); return reply(503, { accepted: false }, 300); }
    });
  }
}
