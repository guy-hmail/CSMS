import assert from 'node:assert/strict';
import {
  buildLineOaAddFriendUrl,
  normalizeLineOaBasicId
} from '../src/lib/notifications/lineOa';

assert.equal(normalizeLineOaBasicId(' church-central '), '@church-central');
assert.equal(normalizeLineOaBasicId('@church.central'), '@church.central');
assert.equal(normalizeLineOaBasicId('replace-with-central-oa-basic-id'), '');
assert.equal(buildLineOaAddFriendUrl('@church-central')?.toString(), 'https://line.me/R/ti/p/%40church-central');
assert.equal(buildLineOaAddFriendUrl(''), null);
assert.equal(buildLineOaAddFriendUrl('@bad value'), null);

console.log('LINE Official Account configuration tests passed');
