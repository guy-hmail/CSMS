import { safeNotificationDeepLink } from '../src/lib/notifications/notificationLinks';

const accepted = [
  '/app/approval',
  '/app/approval?status=submitted',
  '/app/submissions#current',
  '/app/organization/assigned-ou',
  '/app/settings/tenant'
];

const rejected = [
  null,
  '',
  '/',
  '/app',
  '/app/help',
  '//evil.example/app/approval',
  'https://evil.example/app/approval',
  '/app/approval/../../super-admin/tenants',
  '/app/approval?next=https://evil.example'
];

for (const value of accepted) {
  if (safeNotificationDeepLink(value) !== value) {
    throw new Error(`Expected notification deep link to be accepted: ${value}`);
  }
}

for (const value of rejected) {
  if (safeNotificationDeepLink(value) !== null) {
    throw new Error(`Expected notification deep link to be rejected: ${String(value)}`);
  }
}

console.log('NOTIFICATION_LINK_TESTS_PASSED');
