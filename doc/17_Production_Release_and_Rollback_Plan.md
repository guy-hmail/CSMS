# Production Release and Rollback Plan

สถานะ: **Production deployed — notification delivery/schedules disabled; canary pending**

Production URL: `https://csms-rouge.vercel.app/`

Baseline production commit ก่อน release: `297ec64`

Feature candidate commit: `f63d51c`

## Release result — 22 August 2026

- Decision: **RELEASE SUCCESS for disabled infrastructure. CANARY NO-GO until LINE credentials, OA Basic ID, test Tenant and recipient evidence are complete.**
- Git/CI: `f63d51c`; GitHub Actions run `32559682901` passed application, Edge Function and database jobs
- Backup checkpoint: `D:\Projects\ST10-backups\25690822-142238` at 22 August 2026 14:22 Asia/Bangkok; 17 tables and 46 COPY sections
- Database: migrations `20260812010000`–`20260812050000`, `20260815010000` and `20260816010000`–`20260816030000` applied; Local/Remote history matches
- Preview: `dpl_3bz2TteXk6384FCkd31MDfwDdx9c` / `https://csms-o6le8j48x-hpstat.vercel.app`, Ready
- Production: `dpl_3b6buq5af4S9xgsVrKQuKC7HHrbn` / `https://csms-pypectn7i-hpstat.vercel.app`, Ready
- Production alias: `https://csms-rouge.vercel.app`
- Frontend rollback target: `dpl_5qe33Qg2mZaFh2BjaTYkjyTdzm5g`
- `LINE_DELIVERY_ENABLED=false` and `NOTIFICATION_SCHEDULE_ENABLED=false`
- Disabled worker evidence: LINE claimed 0; missing reminder and pending approval digest each created 0
- Public smoke: `/`, `/app`, `/app/help`, `/app/submissions`, `/app/dashboard` and `/app/reports` returned HTTP 200
- Immediate Vercel error/HTTP 500 queries: no logs found
- Remaining observation: authenticated LIFF/business flows and notification canary require user-session and dedicated-recipient verification

Manual backup checksums — 22 August 2026:

| File | Bytes | SHA-256 |
|---|---:|---|
| `roles.sql` | 297 | `25873CEC56A2CC6514E204F420231777F85C03DA818CAA7090CDCDFA89776ECD` |
| `schema.sql` | 310557 | `D33D17BCCE93220B461566764073C2681E77087134864C048F79F3D2AEE043B2` |
| `data.sql` | 520144 | `8379E0A43F67680FDBED132B2046AB4330C8046152061A9E51A0F69DB9920F1E` |

## Readiness snapshot — 8 August 2026

- ✅ `npm run preflight:production` ผ่าน: Svelte check 0 error/warning, auth tests ผ่าน, production build ผ่าน และ audit พบ 0 vulnerabilities
- ✅ Vercel CLI authentication ใช้งานได้ และ local workspace link ไป project `hpstat/csms`
- ✅ Product owner ยืนยันว่า Vercel project/scope ปัจจุบันควบคุม production URL `csms-rouge.vercel.app`; ต้องบันทึก last-known-good deployment ID ก่อน promote
- ✅ Product owner ยืนยันว่า Supabase production project คือ `AdenWork` (`obouxyorkjnbwjpllhyg`) และตรงกับ workspace link
- ✅ ใช้ database password ผ่าน secure local environment แล้ว `migration list --linked` และ `db push --dry-run` เชื่อม production สำเร็จ; remote history ตรงกับ local ถึง `20260801160000`
- ✅ Dry-run พบ 6 pending migrations รวม `20260802010000_production_reference_data.sql`; production `CSMS_DEFAULT` มี 9 metrics และ checksum `7d3f7319060c808db8389cc073cac081` ตรงกับ migration ขณะที่ `created_by` ยัง `NOT NULL` จึงยืนยันว่า migration จะไม่ overwrite template customization
- ✅ Free Plan manual logical backup สำเร็จเมื่อ 8 August 2026 23:50 Asia/Bangkok ที่ local checkpoint `25690808-234537`: schema 17 tables, data 44 COPY sections และไฟล์ทั้งสามมี SHA-256 checksum
- ✅ Last-known-good Vercel production deployment: `dpl_Fy2cLUrzWk1JvwPiUqvNRB4tqY2m` / `https://csms-h9nmg102t-hpstat.vercel.app`, status Ready, alias `csms-rouge.vercel.app`
- ✅ Product owner approved production deployment on 8 August 2026 after backup and dry-run review

**Decision: RELEASE SUCCESS.** Database migrations, source push, Vercel production deployment และ unauthenticated smoke checks สำเร็จแล้ว ต้องติดตาม authenticated business-flow smoke test และ logs ต่อใน observation window

Release result — 8 August 2026:

- Database: migrations `20260802010000` และ `20260808010000`–`20260808050000` applied; Local/Remote history ตรงกัน
- Git: `main` pushed through commit `297ec64`
- Vercel: deployment `dpl_5qe33Qg2mZaFh2BjaTYkjyTdzm5g`, URL `https://csms-hancxr4ee-hpstat.vercel.app`, status Ready
- Production alias: `https://csms-rouge.vercel.app`
- Rollback target: `dpl_Fy2cLUrzWk1JvwPiUqvNRB4tqY2m`
- Public smoke: `/`, `/app`, `/app/help` returned HTTP 200
- Immediate Vercel production 5xx query: no logs found
- Remaining observation: LINE LIFF login and authenticated tenant/report/dashboard/OU flows require user-session smoke verification

Manual backup checksums:

| File | Bytes | SHA-256 |
|---|---:|---|
| `roles.sql` | 297 | `25873CEC56A2CC6514E204F420231777F85C03DA818CAA7090CDCDFA89776ECD` |
| `schema.sql` | 304373 | `DD9938F2E92A3BFEF623F24AA4FCA1E102A3FD832F326274E5110699E7F49E6F` |
| `data.sql` | 299130 | `453D9D53F5FAAC82937B1BE4EFCA39983DD6BB007BB46A7CD846043D56F1309D` |

Supabase CLI role remediation:

1. ห้ามส่ง database password ผ่าน chat หรือ commit ลง repository
2. ทางเลือกแรกคือใช้ Session Pooler connection string จาก Dashboard → **Connect** กับ database password ผ่าน secure local environment แล้วรัน `migration list --db-url` และ `db push --dry-run --db-url`
3. หาก project เคย clone/restore และ `cli_login_postgres` เป็น custom role ที่ผิด ownership ให้ตรวจ role/dependencies ก่อนดำเนินการ ตามเอกสาร Supabase สามารถ drop role ที่ผิดเพื่อให้ CLI สร้างใหม่ได้ แต่ต้องทำหลังยืนยัน backup และได้รับอนุมัติเท่านั้น
4. ห้ามใช้ `migration repair` เพื่อแก้ permission error นี้

## 1. Release decision

ควร deploy feature baseline ชุดปัจจุบันก่อนเริ่ม Notifications Phase เพื่อให้:

- แยก incident ของ Report, Dashboard, LIFF และ OU ออกจาก Notification/outbox/LINE delivery
- มี production baseline และ migration history ที่ชัดเจน
- สามารถ rollback frontend ไปยัง deployment ก่อนหน้าได้โดยไม่ต้องย้อน schema
- หยุด release ได้ก่อน Notifications Phase หาก smoke test พบ regression

ห้าม deploy Notifications Phase รวมใน release นี้

## 2. Release scope

Frontend/API scope:

- Report export ครบทุก raw/calculated metric และไม่แสดง Metric Code เป็นหัวคอลัมน์
- Tenant calculated fields และ Dashboard metric selection/order
- Platform-managed LIFF configuration แบบ production/development
- OU parent auto-disable, system-generated OU code และซ่อน internal OU code จาก UI
- คู่มือและ production documentation ที่เกี่ยวข้อง

Production database migrations ตามลำดับ:

1. `20260802010000_production_reference_data.sql`
2. `20260808010000_calculated_report_metrics.sql`
3. `20260808020000_auto_disable_parent_data_entry.sql`
4. `20260808030000_dashboard_metric_configuration.sql`
5. `20260808040000_default_dashboard_metrics.sql`
6. `20260808050000_system_generated_ou_codes.sql`

Migration `20260802010000` อยู่ใน source control ตั้งแต่ production baseline แต่ยังไม่มีใน remote migration history การเปลี่ยนแปลงเป็น additive/idempotent: ปลด `NOT NULL` ของ `metric_template_sets.created_by` และ upsert platform-owned `CSMS_DEFAULT` template ไม่มี delete/truncate

ไม่มี Edge Function ใหม่ใน release นี้

## 3. Rollback strategy

ใช้หลัก **expand/forward-compatible schema**:

- Frontend failure: Vercel Instant Rollback ไป last-known-good deployment
- Database logic failure: deploy corrective forward migration ใหม่
- ห้ามแก้หรือลบ migration ที่ถูก apply แล้ว
- ห้ามใช้ `supabase db reset`, seed, truncate หรือ destructive down migration กับ production
- Physical/PITR restore ใช้เฉพาะ data corruption หรือ migration ที่แก้ด้วย forward migration ไม่ได้ และต้องประกาศ maintenance window

เหตุผล: การ restore database ย้อนเวลาอาจทำให้ข้อมูลที่ผู้ใช้บันทึกหลัง release สูญหาย และ Supabase project จะไม่พร้อมใช้งานระหว่าง restore

## 4. Required roles

ต้องระบุผู้รับผิดชอบก่อนเริ่ม:

| Role | Responsibility |
|---|---|
| Release owner | สั่ง deploy, บันทึกเวลา/SHA/deployment URL |
| Database owner | ตรวจ backup, migration list, dry-run และ `db push` |
| Smoke-test owner | ทดสอบ LINE login และ business flows |
| Rollback approver | ตัดสินใจ rollback/maintenance/PITR |

คนเดียวทำได้หลาย role แต่ต้องมีชื่อและช่องทางติดต่อใน release record

## 5. Pre-deployment gate

ห้ามเริ่ม production migration หากข้อใดข้อหนึ่งไม่ผ่าน:

- [ ] Working tree สะอาด และ release commit อยู่บน `main`
- [ ] GitHub CI ผ่านจาก clean runner
- [ ] `npm run preflight:production` ผ่าน
- [ ] Relevant Supabase DB regression tests ผ่าน
- [ ] `npx supabase db lint` ไม่มี error ใหม่
- [ ] Preview deployment ผ่าน smoke test
- [ ] Supabase CLI linked ไป production project ที่ถูกต้อง
- [x] `npx supabase migration list --linked` ยืนยัน remote history ตรงกับ local ถึง `20260801160000`
- [x] `npx supabase db push --dry-run` แสดงเฉพาะ 6 migrations ใน scope
- [x] ตรวจ `metric_template_sets.created_by` และ `CSMS_DEFAULT` current state ก่อน apply `20260802010000`; checksum ตรงและ migration เป็น idempotent
- [x] ยืนยัน Free Plan manual logical backup checkpoint และบันทึกเวลา/checksums
- [x] บันทึก last-known-good Vercel deployment URL/ID
- [ ] ตรวจ production environment: Supabase URL/key, production LIFF ID, production app URL และ `PUBLIC_APP_ENV=production`
- [ ] กำหนด maintenance/observation window และแจ้งผู้ใช้งาน

หาก production ไม่มี backup/PITR ที่ยอมรับได้ ให้หยุด release

## 6. Deployment sequence

### A. Freeze and record

1. หยุด merge feature อื่นเข้า `main` ชั่วคราว
2. บันทึก release commit SHA, เวลาเริ่ม, operator และ last-known-good Vercel deployment
3. ตรวจว่า Notifications Phase ยังไม่ถูกรวมใน diff

### B. Preview

1. Deploy candidate เป็น Vercel Preview
2. ใช้ production-like environment แต่ห้ามส่ง LINE notification จริง
3. ทดสอบ Login, tenant switching, submission, approval, reports/export, calculated fields, Dashboard และ OU creation
4. ตรวจ browser console, Vercel logs และ Supabase logs

### C. Database

รันจาก clean checkout ของ release commit และให้ operator เพียงคนเดียวทำ migration:

```powershell
npx supabase link --project-ref YOUR_PRODUCTION_PROJECT_REF
npx supabase migration list --linked
npx supabase db push --dry-run
npx supabase db push
npx supabase migration list --linked
```

หยุดทันทีถ้า dry-run มี migration นอก scope, migration history ไม่ตรง หรือคำสั่งใดล้มเหลว ห้ามใช้ `migration repair` จนกว่าจะตรวจ actual schema กับ migration history แล้ว

### D. Frontend

1. Deploy production build จาก release commit เดียวกับที่ผ่าน Preview
2. บันทึก Vercel deployment URL/ID และ commit SHA
3. ตรวจว่า `https://csms-rouge.vercel.app/` ชี้ไป deployment ใหม่

### E. Smoke test and observation

ทดสอบด้วย tenant ทดสอบก่อน แล้วจึงตรวจ read-only กับ tenant จริง:

- [ ] LINE LIFF login และ external browser login
- [ ] Tenant switching และ permission/OU scope
- [ ] สร้าง OU ลูก: parent ถูกปิดรับข้อมูลและมีคำเตือน
- [ ] OU code ถูกสร้างอัตโนมัติและไม่แสดงใน UI
- [ ] Weekly submission → submit → approve/return
- [ ] Report raw + calculated metrics
- [ ] CSV/XLSX export ครบทุก metric และไม่มี Metric Code header
- [ ] Tenant เลือก/เรียง Dashboard metrics และ Dashboard แสดงตรงตามตั้งค่า
- [ ] Tenant Settings แสดง production LIFF/Web URL แบบ read-only
- [ ] Audit logs มีรายการสำคัญและไม่มี secret
- [ ] ไม่มี error spike ใน Vercel/Supabase logs

เฝ้าดูอย่างน้อย 30 นาทีหลัง deploy และบันทึกหลักฐาน

## 7. Rollback decision matrix

| Incident | Immediate action | Database action |
|---|---|---|
| Frontend rendering/build/runtime failure | Vercel Instant Rollback | คง schema ใหม่ไว้ |
| Environment/LIFF value ผิด | rollback frontend หากกระทบ login; แก้ env แล้ว redeploy | ไม่เปลี่ยน DB |
| RPC response regression แต่ข้อมูลไม่เสีย | rollback frontend ถ้าช่วยลดผลกระทบ; ทำ forward-fix migration | ห้าม down migration |
| Migration apply บางส่วน/ประวัติไม่ตรง | หยุด frontend promotion, maintenance mode | ตรวจ schema/history แล้วทำ corrective migration; `migration repair` แก้เฉพาะ history ไม่ได้ย้อน SQL |
| Data corruption หรือ writes ผิดวงกว้าง | ปิด write path/maintenance ทันที | ประเมิน PITR/backup restore และข้อมูลหลัง restore point |
| Tenant isolation/RLS leak | ปิดระบบหรือ affected route ทันที | forward-fix policy/function ก่อนเปิดใหม่; security incident review |

Trigger ให้ rollback frontend ทันที:

- Login ใช้งานไม่ได้
- Tenant isolation หรือ permission ผิด
- Submission/approval เขียนข้อมูลผิด
- Dashboard/Report ทำให้ production error ต่อเนื่อง
- HTTP 5xx หรือ client error เพิ่มขึ้นอย่างมีนัยสำคัญหลัง release

## 8. Frontend rollback procedure

```powershell
npx vercel rollback
npx vercel rollback status
```

หรือเลือก last-known-good deployment จาก Vercel Dashboard → **Instant Rollback** แล้วตรวจ domains/aliases ก่อนยืนยัน

หลัง rollback:

1. ทดสอบ Login, Dashboard, Reports และ submission flow
2. ตรวจ production logs อย่างน้อย 15 นาที
3. ระวังว่า Vercel rollback ใช้ build/environment snapshot ของ deployment เดิม และ auto-assignment ของ production domain อาจถูกปิดจนกว่าจะ promote deployment ใหม่
4. เปิด incident และทำ fix ผ่าน Preview ก่อน `vercel promote` หรือ production deploy ครั้งถัดไป

## 9. Database recovery procedure

ลำดับที่ต้องเลือก:

1. ปิด/จำกัด write path ที่ผิด
2. เก็บ error evidence, เวลาเริ่ม incident และ affected tenant/rows
3. ทำ forward corrective migration ที่ idempotent และผ่าน test
4. หากแก้ด้วย forward migration ไม่ได้ ให้คำนวณ RPO/RTO และรายการ writes หลัง restore point
5. ขออนุมัติ rollback approver ก่อน Supabase backup/PITR restore
6. ประกาศ downtime เพราะ project จะใช้งานไม่ได้ระหว่าง restore
7. หลัง restore ให้ตรวจ migration history, Auth, RLS, Edge Functions, Storage metadata และ reconcile ข้อมูลที่เกิดหลัง restore point

ห้าม restore เพียงเพื่อต้องการเอา schema เก่า เพราะ frontend เดิมสามารถทำงานกับ additive schema ชุดนี้ได้ และ restore เสี่ยงสูญเสียข้อมูลใหม่มากกว่า

## 10. Release record template

```text
Release commit:
Previous production commit/deployment:
Production deployment URL/ID:
Supabase project ref (masked):
Backup/PITR checkpoint and timezone:
Migration list before:
Migration list after:
Release owner:
Database owner:
Smoke-test owner:
Start/end time (Asia/Bangkok):
Smoke evidence:
Observed errors:
Decision: success / frontend rollback / forward DB fix / PITR restore
Follow-up incident/task:
```

## 11. Notification Stage A rollout and rollback

Stage A is an additive database release only: `notifications`, `notification_deliveries`, internal resolver/enqueue helpers, and owner-scoped read/archive RPCs. It contains no LINE provider integration.

Before applying the migration:

- keep `LINE_DELIVERY_ENABLED=false`; do not deploy or invoke a LINE sender
- run the full DB regression suite, notification test, database lint, frontend check and production build on Preview/local
- confirm production migration history and backup/PITR checkpoint
- verify no Tenant table or browser environment contains Messaging API credentials

After applying the migration:

- smoke-test list, unread count, mark read, mark all and archive with two users and two Tenants
- verify cross-Tenant/other-recipient IDs return `NOTIFICATION_NOT_FOUND`
- verify queue depth is zero unless a trusted canary deliberately requested optional delivery creation
- inspect audit rows for action/count metadata only; notification body/payload and secrets must be absent

Rollback is a forward fix. The additive tables must not be dropped or truncated in production. If read APIs regress, disable the future Notification Center route (Stage B) and apply a corrective migration. If isolation is incorrect, disable the affected API/route immediately, keep LINE disabled, treat it as a security incident, and forward-fix RLS/functions before reopening.

Production actions intentionally deferred after Stage A: apply the migration, confirm central OA Basic ID/Channel ID/quota owner, set secrets, create the canary recipient, deploy the Stage D worker, and collect Preview/production smoke evidence.

## 12. Notification Stage C rollout and rollback

Stage C adds transactional event emission to existing submission, approval, edit-request, OU-assignment and invitation-acceptance RPCs. It can create pending `line` outbox rows, but it does not deploy or call a LINE provider worker. Keep `LINE_DELIVERY_ENABLED=false` throughout this release.

Before applying `20260812020000_notification_business_events.sql`:

- verify Stage A is present and take the normal production migration-history and backup/PITR checkpoint
- run `be_005`, `be_010`, `be_017`, `be_020`, `be_026`, `be_027`, database lint, frontend check and production build
- record queue depth before migration; existing pending rows must not be replayed by this migration

After applying:

- submit one canary report and confirm only actionable in-scope recipients receive `submission_submitted`
- approve and return canary reports and confirm the recorded submitter receives one deterministic event per revision
- create and resolve an edit request and confirm managers/admins receive the request while the requester receives the resolution
- assign one canary user directly and through an invitation; verify one In-app record and the preference-eligible pending outbox row
- confirm audit and notification payloads contain no LINE user ID, access token, secret or authorization value

Rollback is a forward fix. Do not drop notifications or delivery rows. If recipient selection is wrong, immediately stop the affected business mutation endpoint or apply a corrective migration while outbound LINE remains disabled. Because function implementations were moved behind internal wrappers, rollback must preserve the public RPC signatures and grants; do not expose the internal `app_security.*_without_notification_events` functions as a shortcut.

## 13. Notification Stage D rollout and rollback

Stage D adds the protected `send-line-notification` worker, bounded attempt history/manual replay, and central OA Add Friend guidance. The database migration is additive and does not send messages by itself.

Before applying `20260812030000_notification_line_delivery.sql`:

- take the normal backup/PITR checkpoint and record pending/failed/dead-letter queue depth
- run `be_028`, the shared Deno tests, Deno function type-check, frontend check, production build, and database lint
- confirm the central OA owner, quota owner, incident owner, Messaging API access token, public Basic ID, HTTPS production app URL, and one test Tenant UUID
- keep `LINE_DELIVERY_ENABLED=false`; never start with `LINE_DELIVERY_CANARY_CHURCH_IDS=*`

Deploy the worker with JWT verification disabled only because the function performs its own exact service-role credential check. Configure a protected scheduler with that credential, confirm a disabled invocation claims zero rows, then enable only the approved Tenant UUID. Verify one In-app record remains available before and after a successful Push, a safe deep link opens through normal authorization, and no sensitive values appear in logs or attempt history.

Rollback does not drop or truncate delivery/attempt tables. Set `LINE_DELIVERY_ENABLED=false` first; this immediately stops new claims while preserving In-app records and durable queue rows. If a provider call was accepted but finalization failed, retain the same delivery UUID retry key so LINE can deduplicate the retry. Forward-fix schema/function defects. Replay dead letters only after root cause correction and an operator review; each replay creates a new cycle and audit record.

## 14. Notification Stage E rollout and rollback

Stage E is additive: it deploys two protected scheduled functions and database RPCs but creates no Cron job automatically. Keep `NOTIFICATION_SCHEDULE_ENABLED=false` while applying `20260812040000_notification_schedules.sql` and deploying functions.

Before canary enablement, run `be_029`, shared Deno tests, both function type-checks, frontend check/build, and database lint. Confirm the test Tenant timezone, latest due period/status, active reminder recipients, active approver assignments, and preference settings. Create hourly Cron jobs using a Vault-held credential, record job IDs/owners, and verify disabled zero-count responses.

Enable one Tenant UUID only. Invoke twice and verify deterministic same-day deduplication, correct OU/approval scope, and that In-app records remain when optional LINE preferences are disabled. Rollback by setting `NOTIFICATION_SCHEDULE_ENABLED=false` and disabling both Cron jobs. Do not delete notifications/outbox rows or revert the additive RPC migration. If recipient logic is wrong, treat it as a notification-scope incident and forward-fix before re-enabling. `LINE_DELIVERY_ENABLED=false` remains the independent emergency stop for outbound messages.

## 15. Notification Stage F production gate

Stage F adds privacy-minimized operations visibility and release evidence, not automatic production authorization. Before migration/deployment, the release commit must pass the full database suite, Edge tests/checks, frontend build, dependency audit, database lint, and automated notification security review.

Deploy with both notification kill switches false. Capture disabled evidence, then use one dedicated recipient and one Tenant. The System Admin operations panel is the primary queue-health view; logs and database access remain restricted. Do not promote to `*` until every checkbox in `doc/18_Notifications_Production_Evidence.md` has an owner and evidence reference.

For provider outage/quota exhaustion, stop LINE only and retain In-app/schedules. For recipient-scope/security concerns, stop both LINE and schedules and treat the event as an incident. Rotate secrets while delivery is disabled, test a single recipient, revoke old credentials, and restore canary scope. Manual replay is per delivery after root-cause correction; never truncate or bulk-reset the queue.

## 16. Production release record — 22 Aug 2026

- Application commits: `343f252` (`feat: improve dark mode and submission rollover`) and `18de1a3` (`fix: open pre-created submission periods on rollover`)
- Previous production deployment: `dpl_3b6buq5af4S9xgsVrKQuKC7HHrbn` (`https://csms-pypectn7i-hpstat.vercel.app`)
- Preview deployment: `dpl_8aFajfBCE7ymtmroFQuWv5WN3BtV` (`https://csms-actwffnfq-hpstat.vercel.app`)
- Production deployment: `dpl_CvLSemegYtgCjaqYt1bVY2KtSSFc` (`https://csms-qo0f3860h-hpstat.vercel.app`), aliased to `https://csms-rouge.vercel.app`
- CI evidence: GitHub Actions runs `32566345131` and `32566770891`; application, Edge and database jobs passed
- Production backup checkpoint: `D:\Projects\ST10-backups\25690822-170029` (Asia/Bangkok)
  - `roles.sql`: SHA-256 `25873CEC56A2CC6514E204F420231777F85C03DA818CAA7090CDCDFA89776ECD`
  - `schema.sql`: SHA-256 `A479FE23D5EB171A8A5298DCDB509326FA5F9ABF1C2C1092F492D01C8D39244D`
  - `data.sql`: SHA-256 `0C3F1E73B56DC64FA30891462C07009BBC895F10A06A352194A0F30FF5475331`
- Production migrations: `20260822010000_submission_period_rollover.sql` and corrective migration `20260822020000_submission_rollover_existing_periods.sql`; local and remote migration histories match
- Authenticated smoke: Submissions selected 17–23 Aug 2026 (week 34), opened immediately, due 24 Aug 2026 23:59; Dashboard and Reports remained on 10–16 Aug 2026 (week 33)
- Public smoke: `/`, `/app`, `/app/submissions`, `/app/dashboard`, `/app/reports`, and `/app/settings/tenant` returned HTTP 200; HSTS and `X-Frame-Options: DENY` present
- Observed issue: the first production smoke found an already-created future period retaining its later `opens_at`; fixed forward by `20260822020000` and reverified before release completion
- Decision: success after forward database fix. Frontend rollback target remains `dpl_3b6buq5af4S9xgsVrKQuKC7HHrbn`; database restore checkpoint is the backup above and requires the approval/reconciliation procedure in section 9
- Notification delivery remains disabled; this release does not authorize LINE delivery or scheduled notification enablement

## 17. References

- [Vercel: Rolling back a production deployment](https://vercel.com/docs/deployments/rollback-production-deployment)
- [Vercel: Instant Rollback](https://vercel.com/docs/instant-rollback)
- [Supabase: Database migrations](https://supabase.com/docs/guides/deployment/database-migrations)
- [Supabase: Database backups and PITR](https://supabase.com/docs/guides/platform/backups)
