# CSMS Full-Loop Integration Test Plan

Production status: ✅ Go-Live completed on 8 August 2026

The automated and UI/UAT results recorded in this document are the latest pre-go-live validation results from 1 August 2026. Production smoke-test evidence and subsequent regression runs must be appended separately rather than replacing this historical result.

อัปเดตล่าสุด: 1 สิงหาคม 2026  
ขอบเขต: Task 1–8, backend/RLS, frontend integration และ UI desktop/mobile

## 1. เป้าหมาย

ยืนยันว่า workflow ตั้งแต่การสร้าง Tenant จนถึงการปิดรอบการใช้งานทำงานต่อเนื่องด้วยข้อมูลจริง ค่าที่บันทึกในแต่ละขั้นต้องถูกส่งต่อไปยังหน้า Dashboard, Reports, Approval และ Audit อย่างถูกต้อง โดยไม่รั่วข้าม Tenant

## 2. Test Data และ Expected Values

| ข้อมูล | ค่าใช้ทดสอบ | ผลที่คาดหวัง |
| --- | --- | --- |
| Tenant | ชื่อ/slug สุ่ม prefix `full-loop` | สร้างได้และค้นจาก control plane ได้ |
| Provisioning | Root OU / OU Types / Metrics | `1` / `>= 5` / `9` และ `ready=true` |
| Root Admin Invite | token แบบใช้ครั้งเดียว | `pending → accepted`; ใช้ซ้ำไม่สร้าง assignment ซ้ำ |
| Child OU | `FULL-LOOP-GROUP` | แสดงใต้ Root และอนุญาตกรอกข้อมูล |
| Member | invite role `viewer` | `viewer → approver + canOverride → removed` |
| User Preferences | default OU = Child OU | refresh แล้วค่าเดิมยังอยู่ |
| Weekly value | draft `42`, submit `45` | revision เพิ่มและค่าที่อ่านกลับเป็น `45` |
| Approval | `approval_required` | `submitted → approved` พร้อม history/audit |
| Dashboard | Attendance | current value `45` |
| Report | ช่วงวันที่ของ period ที่ส่ง | total Attendance `45`, 1 row |
| Completeness | Child OU | approved `1`, missing `0` |
| Suspend | Tenant lifecycle | tenant RPC/RLS ใช้งานไม่ได้; control plane ยังจัดการได้ |
| Closed | Retention | status `closed`, ไม่ hard delete และเปิดกลับไม่ได้ |

## 3. Automated Full Loop

1. Reset local database และใช้ clean deterministic seed
2. System Admin สร้าง Tenant และตรวจ provisioning defaults
3. ออก Root Admin Invite และจำลอง service-role acceptance หลัง LINE identity verification
4. Root Admin ตรวจ profile, permission และ tenant isolation
5. แก้ Tenant Settings เป็น `approval_required`
6. สร้าง/แก้ OU และทดสอบ safe soft-delete
7. Invite สมาชิก, accept, เปลี่ยน role/override และ remove assignment
8. บันทึก User Preferences และอ่านกลับ
9. สร้าง draft, refresh/readback, submit และตรวจ idempotency
10. ตรวจ Approval Queue/Detail แล้ว approve
11. ตรวจ parity ระหว่าง Submission, Dashboard และ Reports
12. ตรวจ Audit actions สำคัญ
13. Suspend/Reactivate และตรวจ central tenant enforcement
14. Close tenant และตรวจ retention/terminal lifecycle

คำสั่งหลัก: `npm run test:full-loop`

## 4. UI/UAT Matrix

| หน้า | สิ่งที่ตรวจ | Viewport |
| --- | --- | --- |
| `/super-admin/tenants` | login local เฉพาะ dev, list/search/status/detail | Desktop + Mobile |
| Tenant Detail | provisioning, edit persistence, invite, audit, lifecycle | Desktop + Mobile |
| `/app/settings/tenant` | ค่า tenant, OU Types, Metrics | Desktop |
| `/app/organization` | tree, member/invite/action states | Desktop + Mobile |
| `/app/submissions` | selectors, metric values, draft/submit/status | Desktop + Mobile |
| `/app/approval` | queue, detail, action/history | Desktop + Mobile |
| `/app/dashboard` | totals, completeness, trend, child rollup | Desktop + Mobile |
| `/app/reports` | table/trend/completeness/export controls | Desktop + Mobile |
| `/app/settings` | profile, default OU, notifications, persistence | Desktop + Mobile |

ทุกหน้าตรวจ loading/empty/success/error, label/ค่าที่แสดง, responsive overflow และ navigation ที่สัมพันธ์กับ permission

## 5. Quality Gates

- Database regression ทุกไฟล์ผ่าน
- Auth token tests ผ่าน
- Existing frontend-backend integration ผ่าน
- Full-loop integration ผ่านทุก checkpoint
- `svelte-check` ต้องเป็น 0 error / 0 warning
- Production build ผ่านและไม่มี local credential UI ใน bundle
- UI desktop/mobile ไม่มี critical rendering หรือ horizontal overflow
- หลังทดสอบ reset ฐานข้อมูลกลับ clean seed

## 6. Test Result

สถานะ: **PASS — ไม่มี critical defect ที่เปิดอยู่**  
ทดสอบล่าสุด: 1 สิงหาคม 2026

### Automated Results

- `npm run test:full-loop`: ผ่าน 14/14 checkpoints
- Database regression: ผ่าน 20/20 files
- Existing frontend-backend integration: ผ่าน
- Auth token tests: ผ่าน
- `svelte-check`: 0 error / 0 warning
- Production build: ผ่าน

### Value Reconciliation

| จุดตรวจ | Expected | Actual | ผล |
| --- | ---: | ---: | --- |
| Tenant provisioning | Root 1 / OU Types >=5 / Metrics 9 | 1 / 5 / 9 | PASS |
| Full-loop draft → submit | 42 → 45 | 42 → 45, revision 2 | PASS |
| Full-loop approval | approved, history >=2 | approved, history 2 | PASS |
| Full-loop Dashboard/Report parity | 45 / 45 | 45 / 45 | PASS |
| Full-loop completeness | approved 1 / missing 0 | 1 / 0 | PASS |
| Seed Dashboard attendance | current 175 / previous 90 | 175 / 90, +94.4% | PASS |
| Seed Report | total 175 / rows 2 / approved 2 / missing 0 | 175 / 2 / 2 / 0 | PASS |
| Seed Submission กลุ่ม A | Attendance 100, approved, revision 1 | 100, approved, revision 1 | PASS |

### UI/UAT Results

- ตรวจ 9 routes หลักบน desktop และ mobile 390×844
- ทุก route โหลด heading/ข้อมูลจริงได้ และไม่มี active error alert
- Dashboard, Submission, Approval และ Reports แสดงค่าตรงกัน
- CSV, PDF และ Excel แสดงสถานะ export สำเร็จด้วยข้อมูล 2 หน่วยงาน
- พบ mobile overflow ที่ `/app/settings` (`scrollWidth 898` บน viewport 390) และแก้ด้วย grid/flex min-width constraints
- Retest หลังแก้: ทุก route `scrollWidth 380`, horizontal overflow = false

### Known Coverage Boundaries

- LINE identity provider จริงไม่ได้ถูกเรียกจาก local test; full-loop ทดสอบ provider boundary ด้วย service-role token acceptance เดียวกับ Edge Function
- Reporting Period management UI ยังขึ้น “ยังไม่เปิดใช้งาน” ตาม Task 1 ที่ยังอยู่ใน backlog จึงไม่ถือเป็น regression ของ Task 2–8

## 7. Notifications Stage A Regression

Stage A adds `supabase/tests/be_026_notification_foundation.sql` and must pass before Stage B starts. Coverage includes:

- schema constraints, recursive secret-key rejection and relative deep-link allowlist
- own-recipient RLS, active-Tenant switching and non-disclosing cross-Tenant ownership failures
- active membership and OU-subtree recipient scope
- `notify_missing`, `notify_submitted` and `notify_approval` resolution for optional LINE outbox creation
- deterministic event replay and unique delivery-channel idempotency
- list/unread/mark-read/mark-all/archive ownership and sanitized audit metadata
- revoked anonymous APIs, internal-only enqueue and browser-inaccessible delivery rows

Required command set for Stage A: `npm.cmd run check`, `npm.cmd run build`, `npx.cmd supabase db lint`, and `npx.cmd supabase test db supabase/tests/be_026_notification_foundation.sql` (or the complete DB suite). The database commands require the local Supabase stack. Stage A does not call LINE and must not be treated as LINE delivery smoke evidence.

### Stage A verification — 12 August 2026

- clean local migration replay through `20260812010000_notification_foundation.sql`: PASS
- `be_026_notification_foundation.sql`: PASS
- updated global RLS coverage (`be_002_rls.sql`): PASS
- complete DB suite: 25/26 files PASS; the unrelated pre-existing `be_015_task2_organization_members.sql` assertion still expects parent-move behavior that the later `20260808050000_system_generated_ou_codes.sql` replacement of `update_organization_unit` no longer implements
- database lint: PASS with legacy unused-variable warnings only; no new Stage A lint issue
- `npm.cmd run check`: PASS, 0 errors / 0 warnings
- `npm.cmd run build`: PASS

The Task 2 parent-move regression is not changed in the Notifications Stage A patch and remains follow-up work. Production migration, Preview canary, central OA owner confirmation, secrets, and production smoke tests were not performed.

## 8. Notifications Stage B UI Regression

Stage B adds the header Notification Center and `scripts/notification-links.test.ts`. Required coverage:

- tenant-aware unread badge and feed refresh
- loading, populated, empty, error and retry states
- mark read, mark all read and archive badge reconciliation
- safe deep-link navigation followed by destination-route permission checks
- active-Tenant switch clears stale items and loads only the new Tenant feed
- Escape/close/outside-click behavior, labelled controls and keyboard focus restoration
- desktop layout and mobile viewport 390×844 without horizontal overflow

### Local browser result — 12 August 2026

- desktop populated panel with unread badge `3`: PASS
- mark all read and badge reconciliation: PASS
- deep link `/app/approval` navigation: PASS
- archive all and empty state: PASS
- database unavailable → error alert → database restored → retry/empty state: PASS
- mobile 390×844: panel width 356px at x=12px; document scroll width 380px; no horizontal overflow
- Tenant switch: Demo Tenant feed `3` → Stage B Test Tenant feed `1`, with no stale/cross-Tenant item: PASS
- `npm.cmd run test:notification-links`: PASS for route allowlist, external URL, traversal and unsafe query rejection

The browser fixture is `supabase/fixtures/stage_b_notification_ui.sql` and is local-test-only. It lives outside `supabase/tests` so the TAP runner does not treat fixture SQL as a test. Stage B creates no business event notifications automatically; those integrations begin in Stage C.

## 9. Notifications Stage C Business-Event Regression

Stage C adds `20260812020000_notification_business_events.sql` and `be_027_notification_business_events.sql`. Required coverage:

- submitted recipient selection for active admin/manager/approver assignments in the target OU ancestry
- approved/returned delivery to the recorded submitter
- edit-request creation only to administrators/managers who can resolve it, and resolution to the requester
- direct OU assignment and accepted-invitation notification to the assigned member
- sibling-OU exclusion, active membership checks and deterministic replay
- preference-disabled optional LINE outbox without suppressing the In-app record
- transaction-local event context restoration so direct maintenance/fixture writes emit nothing
- internal mutation implementations inaccessible to browser/service roles and payloads free of LINE IDs, tokens, secrets and authorization fields

### Stage C verification — 12 August 2026

- clean migration replay through `20260812020000_notification_business_events.sql` and seed: PASS; baseline notification and delivery counts remain zero
- `be_027_notification_business_events.sql`: PASS
- wrapped RPC regression (`be_005`, `be_010`, `be_017`, `be_020`, `be_026`): PASS, 6/6 including Stage C
- complete DB suite: 26/27 files PASS; only the previously documented unrelated `be_015_task2_organization_members.sql` parent-move assertion fails
- no LINE provider call, Edge Function deployment, production migration, Preview canary or production smoke test was performed

## 10. Notifications Stage D LINE Delivery Regression

Stage D adds `20260812030000_notification_line_delivery.sql`, `be_028_notification_line_delivery.sql`, the `send-line-notification` Edge Function, shared provider helpers, and the Add Friend state/CTA. Required coverage:

- service-role-only claim, completion, replay, and attempt-history access
- row-lock concurrency exclusion and ten-minute stale-processing recovery
- retryable attempt schedule of 30 minutes and 2 hours, capped at three attempts
- immediate dead letter for permanent responses and a new audited cycle for manual replay
- recipient membership/preference/scope recheck at claim time and explicit Tenant canary exclusion
- stable `X-Line-Retry-Key`, 2xx/409 accepted classification, 408/429/network/5xx retry, and other 4xx permanent classification
- secret/error redaction and log contexts without LINE user IDs, title, body, or access token
- missing/invalid configuration fails closed; disabled kill switch claims no rows
- valid/invalid central OA Basic ID and frontend type-check for LIFF friendship/Add Friend fallback

### Stage D verification — 12 August 2026

- clean migration replay through `20260812030000_notification_line_delivery.sql` and seed: PASS
- `be_028_notification_line_delivery.sql`: PASS
- shared Deno tests: PASS, 9/9
- Deno type-check for `send-line-notification` with `supabase/functions/deno.json`: PASS
- `npm.cmd run test:line-oa`: PASS
- `npm.cmd run check`: PASS, 0 errors / 0 warnings
- no production migration, Edge Function deployment, secret change, scheduler, real provider call, Preview canary, or production smoke test was performed

## 11. Notifications Stage E Scheduled-Event Regression

Stage E adds `20260812040000_notification_schedules.sql`, `be_029_notification_schedules.sql`, `scan-missing-submissions`, and `send-pending-approval-digest`. Required coverage:

- exact service-role authorization, schedule kill switch, local-hour validation, and explicit Tenant canary scope
- Tenant timezone conversion before/after the configured daily hour
- only the latest period inside its snapshotted submission window, requiring administratively `open` status
- existing draft/submission, inactive OU, sibling data-entry user, and closed period exclusion
- exact data-entry plus ancestor-manager reminder recipient resolution
- actionable nearest-approver digest resolution and per-recipient pending count
- `notify_missing`/`notify_approval` suppression of optional LINE outbox without suppressing In-app records
- repeated same-local-day invocation produces no duplicate, while the next local day creates a new digest window
- browser denial and audit metadata free of recipient IDs, bodies, tokens, or secrets

### Stage E verification — 12 August 2026

- clean migration replay through `20260812040000_notification_schedules.sql` and seed: PASS
- `be_029_notification_schedules.sql`: PASS
- shared Deno tests including schedule configuration/auth: PASS, 12/12
- Deno type-check for both scheduled Edge Functions: PASS
- no hosted Cron job, production migration, environment change, canary enablement, or provider call was performed

## 12. Notifications Stage F Production-Readiness Regression

Stage F adds `20260812050000_notification_operations.sql`, `be_030_notification_operations.sql`, the System Admin operations panel, automated security review, expanded CI/preflight, and production evidence template.

Required coverage:

- System Admin-only operations access and strict single-Tenant filtering
- exact queue depth, stale processing, sent/dead-letter counts and rates
- privacy-minimized dead-letter correlation fields and sanitized error code only
- no recipient, LINE identity, title/body, deep link, payload, error details, or cross-Tenant values in output
- browser roles retain no delivery/attempt table access
- browser source and public environment examples contain no service-role/provider credentials
- Edge tests and type-checks run in CI
- prior system-generated OU behavior is reflected in the Task 2 regression baseline

### Stage F verification — 12 August 2026

- clean migration replay through `20260812050000_notification_operations.sql` and seed: PASS
- full database regression suite: PASS, 30/30 files
- database lint (`--level error`): PASS, no findings
- `be_030_notification_operations.sql`: PASS
- `be_015_task2_organization_members.sql` updated to the deployed immutable code/hierarchy contract: PASS
- notification security scan: PASS
- System Admin frontend type-check: PASS, 0 errors / 0 warnings
- notification Edge Function format/type-check: PASS, 3/3 workers
- notification Edge unit tests: PASS, 12/12 tests
- production preflight (configuration, security, frontend build, dependency audit): PASS
- production execution evidence remains pending in `doc/18_Notifications_Production_Evidence.md`

### Tenant-owned schedule verification — 15 August 2026

- migration `20260815010000_tenant_notification_schedule_settings.sql` and seed replay: PASS
- direct Root OU Admin schedule update and audit regression: PASS
- enabled/disabled, selected weekday, independent local hours, and invalid weekday regression: PASS
- full database regression suite: PASS, 31/31 files
- database lint (`--level error`): PASS, no findings
- frontend type-check: PASS, 0 errors / 0 warnings
- scheduled worker format/type-check: PASS, 2/2 workers
- Edge unit tests: PASS, 11/11 tests
- notification security scan: PASS, 59 client files
