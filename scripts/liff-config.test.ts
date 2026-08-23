import assert from 'node:assert/strict';
import {
  buildLiffUrl,
  extractRuntimeLiffId,
  extractSafeAppRedirectPath,
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

assert.equal(
  extractSafeAppRedirectPath('?liff.state=%2Fapp%2Fsubmissions'),
  '/app/submissions'
);
assert.equal(
  extractSafeAppRedirectPath('?liff.state=%252Fapp%252Fsubmissions%253FperiodId%253Dperiod-1'),
  '/app/submissions?periodId=period-1'
);
assert.equal(
  extractSafeAppRedirectPath('?next=%2Fapp%2Freports&liff.state=%2Fapp%2Fsubmissions'),
  '/app/reports'
);
assert.equal(extractSafeAppRedirectPath('?liff.state=https%3A%2F%2Fevil.example%2Fapp'), '');
assert.equal(extractSafeAppRedirectPath('?next=%2F%2Fevil.example%2Fapp'), '');

console.log('LIFF environment configuration tests passed');
