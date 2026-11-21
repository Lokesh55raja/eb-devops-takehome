'use strict';

const http = require('node:http');
const os = require('node:os');

// APP_NAME and VERSION are read from the environment on every request.
// In the cluster they come from the ConfigMap via envFrom (see chart/).
function readConfig(env = process.env) {
  return {
    app: env.APP_NAME || 'unknown',
    version: env.VERSION || 'unknown',
  };
}

function send(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Content-Length': Buffer.byteLength(payload),
  });
  res.end(payload);
}

function createServer(env = process.env) {
  return http.createServer((req, res) => {
    const { pathname } = new URL(req.url, 'http://localhost');

    if (req.method !== 'GET') {
      res.setHeader('Allow', 'GET');
      return send(res, 405, { error: 'method not allowed' });
    }
    if (pathname === '/') {
      const { app, version } = readConfig(env);
      return send(res, 200, { app, version, pod: os.hostname() });
    }
    if (pathname === '/healthz') {
      return send(res, 200, { status: 'ok' });
    }
    return send(res, 404, { error: 'not found' });
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT) || 8080;
  const server = createServer();
  server.listen(port, '0.0.0.0', () => {
    console.log(JSON.stringify({ msg: 'listening', port }));
  });
  // kubelet sends SIGTERM on pod stop; finish in-flight requests, then exit.
  const shutdown = () => server.close(() => process.exit(0));
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

module.exports = { createServer, readConfig };
