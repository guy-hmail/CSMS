import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

function filesUnder(root) {
  return readdirSync(root).flatMap((name) => {
    const path = join(root, name);
    return statSync(path).isDirectory() ? filesUnder(path) : [path];
  });
}

const clientFiles = filesUnder('src').filter((path) => /\.(?:ts|svelte|js)$/.test(path));
const prohibitedClientSecrets = [
  'SUPABASE_SERVICE_ROLE_KEY',
  'LINE_MESSAGING_CHANNEL_ACCESS_TOKEN',
  'LINE_MESSAGING_CHANNEL_SECRET',
  'LINE_CHANNEL_SECRET'
];

for (const path of clientFiles) {
  const source = readFileSync(path, 'utf8');
  for (const secret of prohibitedClientSecrets) {
    assert(!source.includes(secret), `${secret} must not appear in browser source: ${path}`);
  }
}

for (const path of ['.env.example', '.env.production.example']) {
  const source = readFileSync(path, 'utf8');
  assert(!/^PUBLIC_.*(?:TOKEN|SECRET|SERVICE_ROLE)/m.test(source), `${path} exposes a public secret-like variable`);
}

const operationsMigration = readFileSync(
  'supabase/migrations/20260812050000_notification_operations.sql',
  'utf8'
);
for (const exposedField of [
  "'recipientUserId'",
  "'lineUserId'",
  "'title'",
  "'body'",
  "'deepLink'",
  "'errorMessage'"
]) {
  assert(!operationsMigration.includes(exposedField), `operations payload exposes ${exposedField}`);
}

const deliveryWorker = readFileSync('supabase/functions/send-line-notification/index.ts', 'utf8');
assert(!/console\.(?:info|error|warn)\([^\n]*(?:channelAccessToken|line_user_id|\.body|\.title)/.test(deliveryWorker), 'delivery worker logs a sensitive field');

console.log(`Notification security review passed (${clientFiles.length} client files scanned)`);
