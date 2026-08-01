import { extractInviteToken } from '../src/lib/auth/inviteToken';

const cases: Array<{ search: string; expected: string; label: string }> = [
  {
    search: '?invite=direct-token',
    expected: 'direct-token',
    label: 'direct invite query'
  },
  {
    search: '?liff.state=%3Finvite%3Dline-token',
    expected: 'line-token',
    label: 'LINE encoded liff.state'
  },
  {
    search: '?liff.state=%252Finvite%253Ddouble-token',
    expected: 'double-token',
    label: 'double encoded liff.state'
  },
  {
    search: '?liff.state=%2Fapp%3Finvite%3Dpath-token',
    expected: 'path-token',
    label: 'LIFF state containing a path'
  },
  {
    search: '?invite=direct-wins&liff.state=%3Finvite%3Dnested-token',
    expected: 'direct-wins',
    label: 'direct query takes precedence'
  },
  {
    search: '?liff.state=%2Fapp',
    expected: '',
    label: 'state without invitation'
  }
];

for (const testCase of cases) {
  const actual = extractInviteToken(testCase.search);
  if (actual !== testCase.expected) {
    throw new Error(`${testCase.label}: expected ${testCase.expected}, received ${actual}`);
  }
}

console.log('INVITE_TOKEN_TESTS_PASSED');
