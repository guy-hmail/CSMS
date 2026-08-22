# Notifications Production Evidence

Status: Production infrastructure deployed disabled; canary pending

Release candidate:

- Git commit: `f63d51c`
- Preview deployment URL: `https://csms-o6le8j48x-hpstat.vercel.app` (`dpl_3bz2TteXk6384FCkd31MDfwDdx9c`)
- Hosted Supabase project reference: `obouxyorkjnbwjpllhyg`
- Migration backup/PITR checkpoint: manual logical backup `D:\Projects\ST10-backups\25690822-142238`, 22 August 2026 14:22 Asia/Bangkok
- Last-known-good frontend deployment: `dpl_5qe33Qg2mZaFh2BjaTYkjyTdzm5g`
- Test Tenant ID:
- Dedicated test recipient owner:
- Operator: Codex release execution with product-owner approval
- Incident owner:
- Quota owner:

## 1. Preflight evidence

- [x] CI application, Edge Function, and database jobs pass on the release commit
- [x] `npm run preflight:production` passes on a clean checkout
- [x] Clean migration replay and full database suite pass
- [x] Database lint reports no errors
- [ ] Messaging API credentials are present only in Supabase secrets
- [ ] Central OA Basic ID and production HTTPS app URL are confirmed
- [x] Backup/PITR restore ownership is confirmed

Attach links/log IDs without copying credentials or notification bodies:

## 2. Disabled deployment evidence

- [x] Migrations A–F applied successfully
- [x] All notification Edge Functions deployed
- [x] `LINE_DELIVERY_ENABLED=false`
- [x] `NOTIFICATION_SCHEDULE_ENABLED=false`
- [x] Disabled delivery worker invocation claims zero rows
- [x] Disabled reminder and digest invocations create zero rows
- [ ] Notification Center still creates/displays In-app notifications

## 3. Preview/canary evidence

- [ ] `LINE_DELIVERY_CANARY_CHURCH_IDS` contains only the test Tenant
- [ ] `NOTIFICATION_SCHEDULE_CANARY_CHURCH_IDS` contains only the test Tenant
- [ ] Dedicated recipient has added/unblocked the central OA
- [ ] Submit one report; actionable approver receives exactly one In-app and one LINE notification
- [ ] Deep link opens the authorized approval view
- [ ] Return one report; submitter receives exactly one In-app and one LINE notification
- [ ] Run missing reminder twice; second run creates zero notifications
- [ ] Run approval digest twice; second run creates zero notifications
- [ ] Tenant outside canary receives no scheduled or outbound LINE delivery
- [ ] Operations panel shows queue/rates without recipient or message data
- [ ] Logs/audit/attempt history contain no token, LINE user ID, title, body, or deep link

Record notification/delivery correlation UUIDs only:

## 4. Failure and rollback drills

- [ ] Disable `LINE_DELIVERY_ENABLED`; new In-app notification remains visible and outbox is preserved
- [ ] Simulate retryable provider failure; verify 30-minute/2-hour bounded schedule and dead letter
- [ ] Correct the cause and manually replay one dead letter; verify a new audited cycle
- [ ] Disable `NOTIFICATION_SCHEDULE_ENABLED`; hourly jobs create no new reminder/digest
- [ ] Disable both Cron jobs and record job IDs
- [ ] Restore last-known-good frontend without reverting/dropping notification data

## 5. Promotion decision

- Decision: Go for disabled infrastructure; No-Go for canary/global delivery
- Approved Tenant scope: none; delivery and schedules remain disabled
- Approval timestamp: 22 August 2026, Asia/Bangkok
- Approver: product owner via release instruction
- Observability window: started after production deployment `dpl_3b6buq5af4S9xgsVrKQuKC7HHrbn`
- Follow-up ticket(s):

Never paste service-role keys, LINE credentials, full provider responses, recipient LINE IDs, or message bodies into this evidence file.
