import { spawn } from 'node:child_process';
import { resolve } from 'node:path';

const liffId = process.env.PUBLIC_LINE_LIFF_ID?.trim();
const localUrl = process.env.LIFF_LOCAL_APP_URL?.trim() || 'http://127.0.0.1:5173/';
const proxyPort = process.env.LIFF_LOCAL_PROXY_PORT?.trim() || '9000';

if (!liffId || liffId === 'replace-with-line-liff-id') {
  console.error(
    [
      'PUBLIC_LINE_LIFF_ID is not configured.',
      'Set the LIFF ID from your LINE Developers test channel in .env, then run npm run liff:serve.'
    ].join('\n')
  );
  process.exit(1);
}

const cliPath = resolve('node_modules/@line/liff-cli/index.js');
const args = [
  cliPath,
  'serve',
  '--liff-id',
  liffId,
  '--url',
  localUrl,
  '--local-proxy-port',
  proxyPort
];

console.log(`Starting LIFF HTTPS proxy for ${localUrl}`);
console.log(`Local HTTPS proxy: https://localhost:${proxyPort}/`);

const child = spawn(process.execPath, args, { stdio: 'inherit' });

child.on('exit', (code, signal) => {
  if (signal) process.kill(process.pid, signal);
  process.exit(code ?? 1);
});
