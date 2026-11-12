#!/usr/bin/env node
// Throttling reverse proxy for /field-test iOS runs (Network Link Conditioner is Mac-wide and would throttle the
// Claude API too, so the slow network lives in front of the local backend only).
//
// Usage: slow-proxy.mjs --listen <port> --target <http://host:port> [--latency <ms>] [--kbps <n>] [--mode normal|offline]
//   normal   every request waits `latency` ms before it is forwarded, the response body is paced to `kbps` kbit/s.
//   offline  every request is answered with 503 right away (after `latency`), nothing is forwarded.
// Defaults: latency 2000, kbps 400 (Slow 3G), mode normal. Plain http only, no dependencies.
// Prints "PROXY_READY <port>" on stdout once listening. Stop with SIGTERM.

import http from 'node:http';

const FLAGS = { '--listen': 'listen', '--target': 'target', '--latency': 'latency', '--kbps': 'kbps', '--mode': 'mode' };

export function parseArgs(argv) {
  const o = { latency: '2000', kbps: '400', mode: 'normal' };
  for (let i = 0; i < argv.length; i++) {
    const key = FLAGS[argv[i]];
    if (!key) throw new Error(`unknown argument ${argv[i]}`);
    const v = argv[++i];
    if (v === undefined || v.startsWith('--')) throw new Error(`${argv[i - 1]} needs a value`);
    o[key] = v;
  }
  if (!o.listen || !o.target) throw new Error('--listen and --target are required');
  if (!['normal', 'offline'].includes(o.mode)) throw new Error('--mode must be normal or offline');
  const out = { listen: Number(o.listen), latency: Number(o.latency), kbps: Number(o.kbps), mode: o.mode, target: new URL(o.target) };
  if (![out.listen, out.latency, out.kbps].every(Number.isFinite) || out.kbps <= 0 || out.latency < 0) throw new Error('--listen, --latency, --kbps must be positive numbers');
  return out;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** Writes `buf` to `res` at `kbps` kbit/s, in 50 ms slices. */
async function paced(res, buf, kbps) {
  const slice = Math.max(1, Math.floor((kbps * 1000 / 8) * 0.05));
  for (let off = 0; off < buf.length; off += slice) {
    if (res.destroyed) return;
    res.write(buf.subarray(off, off + slice));
    await sleep(50);
  }
}

export function createProxy(opts) {
  return http.createServer(async (req, res) => {
    await sleep(opts.latency);
    if (opts.mode === 'offline') {
      res.writeHead(503, { 'content-type': 'text/plain' });
      res.end('offline (field-test slow-proxy)');
      return;
    }
    const up = http.request({
      hostname: opts.target.hostname, port: opts.target.port || 80, path: req.url, method: req.method,
      headers: { ...req.headers, host: opts.target.host },
    }, async (upRes) => {
      const chunks = [];
      for await (const c of upRes) chunks.push(c);
      const body = Buffer.concat(chunks);
      const headers = { ...upRes.headers, 'content-length': String(body.length) };
      delete headers['transfer-encoding'];
      res.writeHead(upRes.statusCode, headers);
      await paced(res, body, opts.kbps);
      res.end();
    });
    up.on('error', () => { if (!res.headersSent) res.writeHead(502); res.end('bad gateway (field-test slow-proxy)'); });
    req.pipe(up);
  });
}

if (import.meta.url === `file://${process.argv[1]}`) {
  let opts;
  try { opts = parseArgs(process.argv.slice(2)); } catch (e) { console.error(`slow-proxy: ${e.message}`); process.exit(2); }
  createProxy(opts).listen(opts.listen, '127.0.0.1', () => console.log(`PROXY_READY ${opts.listen}`));
  process.on('SIGTERM', () => process.exit(0));
}
