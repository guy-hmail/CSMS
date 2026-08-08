# Production Release and Rollback Plan

สถานะ: **Release candidate — ต้องผ่าน gate ก่อน deploy**

Production URL: `https://csms-rouge.vercel.app/`

Baseline production commit ก่อน release: `14f457f` (`origin/main` ณ วันที่จัดทำแผน)

Feature candidate commit: `d385a4b`

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

## 11. References

- [Vercel: Rolling back a production deployment](https://vercel.com/docs/deployments/rollback-production-deployment)
- [Vercel: Instant Rollback](https://vercel.com/docs/instant-rollback)
- [Supabase: Database migrations](https://supabase.com/docs/guides/deployment/database-migrations)
- [Supabase: Database backups and PITR](https://supabase.com/docs/guides/platform/backups)
