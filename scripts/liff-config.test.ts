import assert from 'node:assert/strict';
import {
  buildLiffUrl,
  extractRuntimeLiffId,
  normalizeLiffId
} from '../src/lib/auth/liffConfig';

const productionId = '2010847344-9t9Iytma';
const developmentId = '2010847344-NjSsWBNU';

assert.equal(normalizeLiffId('https://liff.line.me/2010847344-9t9Iytma'), productionId);
assert.equal(
  extractRuntimeLiffId('?liff.state=%2F%3Finvite%3Dtoken%26liffId%3D2010847344-NjSsWBNU'),
  developmentId
);

const inviteUrl = buildLiffUrl(developmentId, 'line/share-invite');
assert.equal(inviteUrl?.origin + inviteUrl?.pathname, `https://liff.line.me/${developmentId}/line/share-invite`);
assert.equal(inviteUrl?.searchParams.get('liffId'), developmentId);

console.log('LIFF environment configuration tests passed');
