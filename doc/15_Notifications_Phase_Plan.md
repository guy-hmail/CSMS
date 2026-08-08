# Notifications Phase Plan

Status: Planned

Target release: Version 1.1

Delivery channels: In-app notification and central CSMS LINE OA

## 1. Goal

เพิ่มระบบแจ้งเตือนอัตโนมัติที่แยก Tenant และ OU scope ถูกต้อง รองรับเหตุการณ์ทันทีและ reminder ตามเวลา โดยใช้ CSMS LINE OA กลางเป็นช่องทาง LINE เพียงช่องทางเดียว และเก็บ In-app notification เป็นแหล่งข้อมูลหลัก/fallback

## 2. Product Rules

- Tenant LINE OA ใช้ Rich Menu เพื่อเปิด CSMS เท่านั้น ไม่ใช้ส่ง notification
- Outbound LINE notification ส่งผ่าน CSMS LINE OA กลาง
- ผู้รับต้องมี `line_user_id`, เป็นสมาชิก Tenant ที่ active และ Add Friend กับ OA กลางจึงจะรับ LINE Push ได้
- ถ้าส่ง LINE ไม่สำเร็จ Notification ในแอปยังต้องถูกสร้างและอ่านได้
- ตรวจ `notify_missing`, `notify_submitted` และ `notify_approval` ก่อน enqueue การส่ง
- ทุก record ต้องมี `church_id`; query, count และ mutation ต้องผ่าน tenant/RLS scope
- Event เดียวกันต้องไม่ส่งซ้ำ ใช้ deterministic `event_key` และ unique constraint
- ห้ามเก็บ Channel Access Token หรือ Channel Secret ใน Tenant Settings หรือ browser
- Deep link ต้องใช้ Production LIFF/Web URL ระดับ Platform และตรวจสิทธิ์อีกครั้งเมื่อเปิดหน้า

## 3. Notification Matrix

| Event | Recipient | Timing | Preference | Deep link |
|---|---|---|---|---|
| `submission_submitted` | Admin/Manager/Approver ใน OU scope | ทันที | `notify_submitted` | Approval detail/queue |
| `submission_approved` | ผู้ส่งข้อมูล | ทันที | `notify_approval` | Submission detail |
| `submission_returned` | ผู้ส่งข้อมูล | ทันที | `notify_approval` | Submission edit |
| `edit_request_created` | Admin/Approver ที่อนุมัติได้ | ทันที | `notify_approval` | Edit request queue |
| `edit_request_resolved` | ผู้ขอแก้ไข | ทันที | `notify_approval` | Submission detail |
| `ou_assignment_created` | ผู้ได้รับสิทธิ์ | ทันที | Always in-app; LINE เมื่อพร้อม | Organization/assigned OU |
| `missing_submission_reminder` | Data entry/Manager ของ OU | ตามเวลา | `notify_missing` | Weekly submission form |
| `pending_approval_digest` | Approver | Daily digest | `notify_approval` | Approval queue |

## 4. Data Model

### `notifications`

- `id uuid primary key`
- `church_id uuid not null`
- `recipient_user_id uuid not null`
- `ou_id uuid null`
- `event_type varchar not null`
- `event_key varchar not null`
- `title text not null`
- `body text not null`
- `deep_link text null`
- `payload jsonb not null default '{}'`
- `created_at`, `read_at`, `archived_at`
- unique `(church_id, recipient_user_id, event_key)`

### `notification_deliveries`

- `id uuid primary key`
- `notification_id uuid not null`
- `channel varchar` — v1: `line`
- `status varchar` — `pending`, `processing`, `sent`, `failed`, `dead_letter`
- `attempt_count integer`
- `next_attempt_at`, `sent_at`
- `provider_message_id`, `last_error_code`, `last_error_message`
- unique `(notification_id, channel)`

Do not store LINE access tokens, ID tokens, or provider secrets in either table.

## 5. Task Breakdown

| ID | Task | Priority | Output |
|---|---|---|---|
| NT-001 | Confirm central OA and Messaging API setup | P0 | OA Basic ID, Channel ID, production policy, quota owner |
| NT-002 | Add notification schema, indexes, constraints and RLS | P0 | Migration + DB tests |
| NT-003 | Add notification preference resolver | P0 | One backend function for preference/active-member checks |
| NT-004 | Add transactional notification enqueue function | P0 | Idempotent `enqueue_notification` RPC/helper |
| NT-005 | Add read APIs | P0 | list, unread count, mark read, mark all read, archive |
| NT-006 | Build In-app Notification Center | P1 | Bell badge, list/dropdown, empty/error/loading, deep links |
| NT-007 | Connect submission and approval events | P0 | Submitted, approved, returned, edit-request events |
| NT-008 | Connect OU assignment/invitation events | P1 | Access-change notifications |
| NT-009 | Build `send-line-notification` Edge Function | P0 | Queue claim, LINE Push, status update, sanitized logs |
| NT-010 | Add retry and dead-letter policy | P0 | Exponential backoff, maximum attempts, manual replay contract |
| NT-011 | Build `scan-missing-submissions` scheduled job | P1 | Missing-submission reminders with tenant timezone support |
| NT-012 | Build pending-approval daily digest | P2 | One digest per recipient/day instead of message spam |
| NT-013 | Add Add-Friend state/CTA | P1 | OA QR/link and delivery-unavailable explanation |
| NT-014 | Add operations dashboard/query | P1 | Delivery success/failure/queue depth without exposing message bodies unnecessarily |
| NT-015 | Security and tenant-isolation review | P0 | RLS tests, recipient-scope tests, secret/redaction review |
| NT-016 | End-to-end and production rollout | P0 | Preview smoke test, canary, rollback/runbook, production evidence |

## 6. Implementation Stages

### Stage A — Foundation

Implement NT-001 through NT-005. In-app records are the source of truth. No external message is sent during this stage.

Exit criteria:

- Notification creation is transactional with the business mutation or uses a durable outbox in the same transaction.
- Duplicate event replay creates no duplicate notification.
- Users see only their own records in the active Tenant.
- Cross-tenant IDs are rejected without leaking existence.

### Stage B — In-app Notification Center

Implement NT-006 and deep links. Badge count must be tenant-aware and refresh after read/archive actions.

Exit criteria:

- Desktop/mobile UI supports unread, read, empty, loading and failure states.
- Switching Tenant clears cached counts and reloads the correct scope.
- Deep links enforce normal page permissions.

### Stage C — Automatic Event Notifications

Implement NT-007 and NT-008. Business RPCs enqueue events; they do not call LINE directly.

Exit criteria:

- Submission/approval/access events create correct recipients once.
- Preference flags suppress optional delivery correctly.
- Audit and notification records contain no secret or LINE token.

### Stage D — Central LINE OA Delivery

Implement NT-009, NT-010 and NT-013.

Required Supabase Edge Function secrets:

- `LINE_MESSAGING_CHANNEL_ACCESS_TOKEN`
- `LINE_MESSAGING_CHANNEL_SECRET`
- Platform production LIFF/Web URL values required to build deep links

Exit criteria:

- Edge Function is the only component that reads Messaging API secrets.
- A failed LINE push does not remove or hide the In-app notification.
- Retry is bounded; permanent errors move to dead letter.
- Logs redact tokens, LINE user IDs where practical, and message payload details.

### Stage E — Scheduled Reminders

Implement NT-011 and NT-012 with Supabase Cron calling protected Edge Functions.

Exit criteria:

- Reminder time respects Tenant timezone/reporting schedule.
- One OU/period/reminder window produces one event per recipient.
- Closed periods, inactive OUs/users and already-submitted OUs are skipped.

### Stage F — Production Readiness

Implement NT-014 through NT-016.

Exit criteria:

- Queue depth, success rate, failure rate and dead-letter count are observable.
- Preview test uses a dedicated test recipient before production enablement.
- Feature flag/kill switch can stop outbound LINE delivery while preserving In-app records.
- Runbook covers secret rotation, quota exhaustion, provider outage and replay.

## 7. Retry Policy

- Attempt 1: immediate
- Attempt 2: after 1 minute
- Attempt 3: after 5 minutes
- Attempt 4: after 30 minutes
- Attempt 5: after 2 hours, then `dead_letter`
- Do not retry permanent recipient errors such as invalid/unreachable LINE user; retain failure reason and In-app notification

## 8. Testing Plan

### Database

- RLS and cross-tenant denial
- Recipient selection by OU subtree and role
- Preference enforcement
- Event-key idempotency
- Read/unread/archive ownership
- Reminder deduplication and period/status filtering

### Edge Function

- Valid LINE Push request
- Missing/invalid secret handling
- Provider 4xx permanent failure
- Provider 429/5xx retryable failure
- Queue claim concurrency and stale-processing recovery
- Log redaction

### Frontend

- Badge count and Tenant switching
- Mark one/all as read
- Deep-link navigation and denied target
- LINE unavailable/Add Friend guidance
- Desktop and mobile accessibility

### Production Smoke Test

1. Enable delivery only for a test Tenant/user.
2. Submit one weekly report and verify approver In-app + LINE notification.
3. Return it and verify submitter notification/deep link.
4. Run reminder scan twice and verify no duplicate.
5. Disable outbound delivery and verify In-app still works.

## 9. Definition of Done

- In-app notifications and central LINE OA delivery work for the defined P0 events.
- Scheduled missing-submission reminder is idempotent.
- Preferences, active membership, role and OU scope are enforced server-side.
- No Tenant can configure or read LINE Messaging credentials.
- Every delivery has inspectable status and bounded retry history.
- Database, Edge Function, integration and frontend tests pass.
- `npm run check`, production build and database lint pass.
- Production monitoring, secret rotation and rollback procedures are documented and verified.

## 10. Out of Scope for Version 1.1

- Sending through each Tenant's LINE OA
- Marketing broadcast or audience segmentation
- Email/SMS delivery
- User-authored notification templates
- Two-way LINE chatbot commands
- Mobile push notifications outside LINE
