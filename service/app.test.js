'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createServer } = require('./app');

// Starts the server on a random port, runs fn(baseUrl), then closes it.
async function withServer(env, fn) {
  const server = createServer(env);
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  try {
    await fn(`http://127.0.0.1:${port}`);
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
}

test('GET / returns app, version and pod from env', () =>
  withServer({ APP_NAME: 'shop', VERSION: '9.9.9' }, async (base) => {
    const res = await fetch(`${base}/`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.equal(body.app, 'shop');
    assert.equal(body.version, '9.9.9');
    assert.equal(typeof body.pod, 'string');
    assert.ok(body.pod.length > 0);
  }));

test('GET / reflects env values changed at runtime', () => {
  const env = { APP_NAME: 'a', VERSION: '1' };
  return withServer(env, async (base) => {
    env.VERSION = '2';
    const body = await (await fetch(`${base}/`)).json();
    assert.equal(body.version, '2');
  });
});

test('GET /healthz returns 200', () =>
  withServer({}, async (base) => {
    const res = await fetch(`${base}/healthz`);
    assert.equal(res.status, 200);
  }));

test('unknown path returns 404', () =>
  withServer({}, async (base) => {
    assert.equal((await fetch(`${base}/nope`)).status, 404);
  }));

test('non-GET method returns 405', () =>
  withServer({}, async (base) => {
    const res = await fetch(`${base}/`, { method: 'POST' });
    assert.equal(res.status, 405);
  }));
