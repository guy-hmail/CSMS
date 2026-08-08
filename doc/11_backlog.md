# Church Statistics Management System (CSMS)

# Frontend & Backend Product Backlog

อัปเดตล่าสุด: 8 สิงหาคม 2026

Version: 1.1  
Status: Active Product Backlog

Production Status: ✅ Go-Live แล้วเมื่อ 8 สิงหาคม 2026

เอกสารนี้รวม backlog เดิม (`BE-*`, `FE-*`, `RP-*`) เข้ากับ Task งานตามหน้า UI ปัจจุบัน โดยสถานะด้านล่างอ้างอิงจากโค้ด, migrations และ tests ที่มีอยู่จริงใน repository

## สถานะ

- ✅ เสร็จแล้วและมีการเชื่อมต่อใช้งานจริง
- 🟡 ทำแล้วบางส่วนหรือต้องเก็บงานเพิ่ม
- ⬜ ยังไม่เริ่มหรือยังใช้ข้อมูลตัวอย่าง

## ภาพรวม

| Task | Feature / หน้า | สถานะ |
| --- | --- | --- |
| 1 | Tenant Settings (`/app/settings/tenant`) | 🟡 ทำแล้วเป็นส่วนใหญ่ |
| 2 | Organization & Members (`/app/organization`) | ✅ ผ่าน Definition of Done |
| 3 | Weekly Submission (`/app/submissions`) | ✅ ผ่าน Definition of Done |
| 4 | Approval (`/app/approval`) | ✅ ผ่าน Definition of Done |
| 5 | Dashboard (`/app`, `/app/dashboard`) | ✅ ผ่าน Definition of Done |
| 6 | Reports (`/app/reports`) | ✅ ผ่าน Definition of Done |
| 7 | User Settings (`/app/settings`) | ✅ ผ่าน Definition of Done |
| 8 | Super Admin (`/super-admin/tenants`) | ✅ ผ่าน Definition of Done |
| 9 | Notifications Phase (In-app + CSMS LINE OA กลาง) | ⬜ Planned |
| Production | Vercel + Hosted Supabase | ✅ Go-Live แล้ว |

การ Go-Live หมายถึง production baseline ถูกนำขึ้นใช้งานแล้ว งาน Task 1 ที่ยังเหลือและรายการ Technical Debt ด้านล่างเป็นงานปรับปรุงหลัง Go-Live ไม่ใช่ตัวบล็อกสถานะ deployment ปัจจุบัน

## Mapping กับ Backlog เดิม

| Legacy ID | Feature เดิม | Priority | สถานะปัจจุบัน | Task ที่เกี่ยวข้อง |
| --- | --- | --- | --- | --- |
| BE-001 | Database migrations | P0 | ✅ เสร็จแล้ว | ทุก Task |
| BE-002 | Row Level Security | P0 | ✅ Core RLS เสร็จแล้ว | ทุก Task |
| BE-003 | Authentication bridge | P0 | ✅ LINE/Supabase bridge ใช้งานได้ | Task 2, 7, 8 |
| BE-004 | Organization CRUD RPC | P0 | ✅ Organization/member mutation พร้อม permission, RLS, audit และ tests | Task 2 |
| BE-005 | Weekly submission RPC | P0 | ✅ เชื่อม context, draft, submit, revision, permission และ tenant isolation แล้ว | Task 3 |
| BE-006 | Recursive summary RPC | P0 | ✅ Summary, completeness, child rollup และ trend พร้อม permission tests | Task 5 |
| BE-007 | Audit logging | P0 | ✅ Infrastructure เสร็จแล้ว | ทุก mutation |
| BE-008 | Seed data | P1 | ✅ Seed และ default tenant data มี tests | Task 1, 8 |
| BE-009 | Approval workflow | P1 | ✅ Queue, detail, approve, reject, return, override, concurrency และ audit พร้อม | Task 4 |
| BE-010 | Notification service | P2 | ⬜ Planned | Task 9 |
| FE-001 | LINE Login | P0 | ✅ ใช้งานได้ รวม LIFF Invite flow | Task 2, 7 |
| FE-002 | Dashboard | P0 | ✅ เชื่อมทุก panel และทดสอบ desktop/mobile แล้ว | Task 5 |
| FE-003 | Organization Management | P0 | ✅ เชื่อม backend และทดสอบ desktop/mobile แล้ว | Task 2 |
| FE-004 | Weekly Submission | P0 | ✅ ใช้ backend จริงและทดสอบ desktop/mobile แล้ว | Task 3 |
| FE-005 | Reports | P0 | ✅ เชื่อม backend, export และทดสอบ desktop/mobile แล้ว | Task 6 |
| FE-006 | Approval Queue | P1 | ✅ เชื่อม backend และทดสอบ desktop/mobile แล้ว | Task 4 |
| FE-007 | Settings | P1 | 🟡 Personal Settings เสร็จแล้ว; Tenant Settings ยังเหลือ Task 1 | Task 1, 7 |
| FE-008 | Notification Center | P2 | ⬜ Planned | Task 9 |
| RP-001 | Weekly Report | P0 | ✅ | Task 6 |
| RP-002 | Monthly Report | P0 | ✅ | Task 6 |
| RP-003 | Yearly Report | P0 | ✅ | Task 6 |
| RP-004 | KPI Dashboard | P1 | ✅ | Task 5 |
| RP-005 | Trend Analysis | P1 | ✅ Dashboard และ Reports ใช้ข้อมูล approved จริงแล้ว | Task 5, 6 |
| RP-006 | Ranking | P2 | ⬜ Future | Future |
| RP-007 | AI Summary | P3 | ⬜ Future | Future |
| RP-008 | Forecast | P3 | ⬜ Future | Future |

---

## Task 1 — Tenant Settings

หน้า: `/app/settings/tenant`

สถานะรวม: 🟡 ทำแล้วเป็นส่วนใหญ่

### Frontend

- [x] โหลดข้อมูลทั่วไปของ tenant
- [x] แก้ชื่อ tenant, timezone, วันสิ้นสุดรอบ และ approval mode
- [x] แสดงรายการ OU Type ของ active tenant
- [x] สร้างและแก้ไข OU Type
- [x] เปิด/ปิด OU Type
- [x] แสดงรายการ Statistic Metric ของ active tenant
- [x] สร้างและแก้ไข Statistic Metric
- [x] เปิด/ปิด Statistic Metric
- [x] กำหนด required, aggregation, min/max และ sort order
- [x] เลือก Primary Metric
- [ ] ซ่อนหรือ disable action ตาม permission ก่อนกด
- [ ] เพิ่ม confirmation เมื่อปิด OU Type หรือ Metric ที่มีการใช้งานแล้ว
- [ ] เพิ่ม unsaved-change warning ก่อนออกจากหน้า

### Backend

- [x] RPC อัปเดต Tenant Settings
- [x] RPC สร้าง/แก้ไข OU Type
- [x] RPC สร้าง/แก้ไข Statistic Metric
- [x] Default Statistic Metric 9 รายการสำหรับ tenant ใหม่
- [x] Default OU Type `CARE / แคร์` ลำดับ 50 สำหรับ seed และ tenant ใหม่
- [x] แยกค่าตั้งต้นเป็นข้อมูลคนละชุดของแต่ละ tenant
- [x] RLS และ permission validation ระดับ tenant
- [x] Database regression tests สำหรับ Tenant Settings และ defaults
- [ ] กำหนด policy ชัดเจนสำหรับการปิด Metric ที่มีรายงานเก่า

### Acceptance Criteria

- [ ] การแก้ Metric ต้องสะท้อนในหน้ากรอกรายงานโดยไม่แก้ frontend code
- [ ] การเปลี่ยนค่าของ tenant หนึ่งต้องไม่กระทบ tenant อื่น
- [ ] ผู้ไม่มีสิทธิ์ Admin ต้องไม่สามารถแก้ Tenant Settings ได้

---

## Task 2 — Organization, OU และ Members

หน้า: `/app/organization`

สถานะรวม: ✅ ผ่าน Definition of Done (ทดสอบล่าสุด 1 สิงหาคม 2026)

### Frontend

- [x] โหลด Organization Tree ตาม active tenant และ permission
- [x] เลือก OU และโหลดสมาชิกราย OU
- [x] สร้าง OU ใหม่
- [x] สร้าง OU-scoped Invite Link
- [x] เลือก role และวันหมดอายุของ Invite
- [x] รองรับ LIFF Invite token ทั้ง `invite` และ `liff.state`
- [x] รองรับ user เดิมรับสิทธิ์เพิ่มใน OU อื่น
- [x] เชื่อมการแก้ไขชื่อ, code, type และ parent ของ OU พร้อมอัปเดต path/level ของ subtree
- [x] เชื่อม soft delete OU
- [x] เชื่อม Assign Existing Account
- [x] เชื่อมเปลี่ยน role และ `canOverride` ของสมาชิกกับ backend จริง
- [x] เชื่อมถอดสมาชิกออกจาก OU แบบ soft delete
- [x] แสดงสถานะ Invite: pending, accepted, expired และ revoked
- [x] เพิ่ม revoke และ reissue Invite Link
- [x] เพิ่ม confirmation และ error state สำหรับ mutation

### Backend

- [x] RPC โหลด Accessible OU Tree
- [x] RPC โหลดสมาชิกของ OU
- [x] RPC สร้าง, แก้ไข และ soft delete OU
- [x] RPC สร้าง OU Invite Link แบบ token hash และใช้ครั้งเดียว
- [x] RPC รับ Invite จาก LINE user
- [x] Schema รองรับ 1 user มีหลาย OU assignments และต่าง role กัน
- [x] เก็บ assignment เดิมเมื่อรับ Invite ของ OU ใหม่
- [x] Audit log สำหรับสร้างและรับ Invite
- [x] Database tests สำหรับ multi-OU assignments
- [x] RPC assign existing user เข้า OU
- [x] RPC update member assignment role/canOverride
- [x] RPC deactivate/remove member assignment
- [x] RPC list/revoke/reissue invitations
- [x] Permission validation แยก admin/manager, ป้องกัน source assignment และ Last Root Admin
- [x] RLS/direct-mutation/cross-tenant/audit regression tests

### Acceptance Criteria

- [x] Admin ที่ Church OU รับ `data_entry` ที่ PG ได้โดยสิทธิ์เดิมไม่หาย
- [x] การแก้ role/`canOverride` และถอดสมาชิกจาก UI บันทึกจริงและ refresh แล้วไม่ย้อนกลับ
- [x] ไม่อนุญาตลบ OU ที่ยังมี child OU หรือข้อมูลรายงานโดยไม่มีขั้นตอนที่ปลอดภัย

### Definition of Done — Task 2

- [x] UI ใช้ข้อมูล backend จริง ไม่มี member/OU mutation แบบข้อมูลตัวอย่าง
- [x] มี loading, empty, success และ error states
- [x] Backend ตรวจ permission, tenant isolation และ cross-tenant references
- [x] Organization, assignment และ invitation mutation มี audit log
- [x] Database และ frontend/backend integration regression tests ผ่าน
- [x] `npm run check` ผ่านโดยไม่มี error หรือ warning
- [x] ทดสอบ `/app/organization` จริงบน desktop และ mobile รวม create/edit/move OU, assign/update/remove member, refresh persistence, soft delete และ invitation lifecycle

---

## Task 3 — Weekly Submission

หน้า: `/app/submissions`

สถานะรวม: ✅ ผ่าน Definition of Done (ทดสอบล่าสุด 1 สิงหาคม 2026)

### Frontend

- [x] มี Dynamic Metric Form และ validation component
- [x] โหลดวันอาทิตย์ปัจจุบันและย้อนหลัง 4 สัปดาห์จาก backend
- [x] โหลดเฉพาะ OU ที่ user มีสิทธิ์กรอกข้อมูล
- [x] โหลด Metric จริงของ active tenant
- [x] โหลด Draft/Submission เดิมเมื่อเปลี่ยน OU หรือ period
- [x] เชื่อมปุ่มบันทึกแบบร่าง
- [x] เชื่อมปุ่มส่งข้อมูล
- [x] แสดงสถานะ Draft, Submitted, Approved, Rejected และ Returned
- [x] รองรับ revision conflict และโหลดข้อมูลรุ่นล่าสุดอัตโนมัติ
- [x] ล็อกฟอร์มหลัง submit/approve; การแก้ approved ต้องผ่าน Return workflow (Task 4) ก่อน ไม่แก้ค่าที่อนุมัติแล้วโดยตรง
- [x] Loading, empty, retry และ success state

### Backend

- [x] RPC `save_statistics_draft`
- [x] RPC `submit_statistics`
- [x] RPC `get_submission_detail`
- [x] Unique submission ต่อ tenant/period/OU
- [x] Revision number และ idempotency support
- [x] Backend validation ตาม Metric definition
- [x] Database tests สำหรับ draft, submit และ recursive data
- [x] RPC ค้นหา submission ด้วย OU + period โดยไม่ต้องรู้ submission ID
- [x] API สำหรับรายการ period, OU ที่ submit ได้ และ Metric ของ active tenant
- [x] กำหนด policy หลัง submit/approve: ห้ามแก้โดยตรง และต้อง Return ผ่าน approval workflow ก่อน

### Acceptance Criteria

- [x] ผู้ใช้บันทึก Draft ปิดหน้า และกลับมาแก้ต่อได้
- [x] Required field และ min/max ถูกตรวจทั้ง frontend และ backend
- [x] ส่งข้อมูลซ้ำไม่สร้าง submission ซ้ำ
- [x] Metric ของแต่ละ tenant แสดงแยกจากกันถูกต้อง

### Definition of Done — Task 3

- [x] UI ใช้ period, OU, Metric และ Submission จาก backend จริง ไม่มีข้อมูลตัวอย่างค้างอยู่
- [x] มี loading, empty, success, retry และ error states
- [x] Backend ตรวจ permission, tenant isolation และป้องกัน cross-tenant context
- [x] Draft/submit mutation มี revision history, idempotency และ audit log
- [x] Database tests 15/15 และ frontend/backend integration test ผ่าน
- [x] `npm run check` ผ่าน 0 error / 0 warning และ production build ผ่าน
- [x] ทดสอบ `/app/submissions` จริงบน desktop/mobile ครบ validation, save, reload persistence, submit, status lock และ OU context switch

---

## Task 4 — Approval

หน้า: `/app/approval`

สถานะรวม: ✅ ผ่าน Definition of Done (ทดสอบล่าสุด 1 สิงหาคม 2026)

### Frontend

- [x] สร้างหน้ารายการรออนุมัติ
- [x] Filter ตาม period, OU และ status
- [x] แสดงรายละเอียด Submission และ Metric values
- [x] ปุ่ม Approve
- [x] ปุ่ม Reject/Return พร้อมเหตุผล
- [x] แสดงประวัติการอนุมัติ
- [x] จำกัด UI ตาม approver/admin, nearest responsible approver และ override permission

### Backend

- [x] มี schema `approval_logs` และสถานะ submission รองรับ workflow
- [x] มี audit infrastructure
- [x] RPC `list_pending_submissions`
- [x] RPC `get_approval_submission_detail`
- [x] RPC `approve_submission`
- [x] RPC `reject_submission`
- [x] RPC `return_submission_for_edit`
- [x] ตรวจ approval mode: auto approve หรือ approval required
- [x] Permission, nearest approver, override, idempotency และ concurrency tests

### Acceptance Criteria

- [x] Tenant แบบ auto approve ต้องไม่ค้างในคิว
- [x] Tenant แบบ approval required ต้องไม่นำข้อมูลไปสรุปก่อนอนุมัติ
- [x] ทุก action บันทึก actor, เวลา, เหตุผล และ audit log

### Definition of Done — Task 4

- [x] UI ใช้ queue, submission detail, metric values และ approval history จาก backend จริง
- [x] มี loading, empty, success, retry, validation และ concurrency-conflict states
- [x] Backend ตรวจ tenant isolation, nearest approver, Root Admin fallback และ `can_override`
- [x] Approve, reject และ return ใช้ row lock, revision check, idempotency, approval log และ audit log
- [x] Database tests 16/16 และ frontend/backend integration test ผ่าน
- [x] `npm run check` ผ่าน 0 error / 0 warning และ production build ผ่าน
- [x] ทดสอบ `/app/approval` จริงบน desktop/mobile ครบ filter, detail, return/resubmit, approve, reject, history และ auto-approve empty queue

---

## Task 5 — Dashboard

หน้า: `/app` และ `/app/dashboard`

สถานะรวม: ✅ ผ่าน Definition of Done (ทดสอบล่าสุด 1 สิงหาคม 2026)

### Frontend

- [x] โหลด OU options จาก Accessible OU Tree
- [x] โหลดวันอาทิตย์ปัจจุบันและย้อนหลัง 4 สัปดาห์
- [x] เปลี่ยน period/OU แล้วโหลด Summary ใหม่
- [x] แสดง Dynamic KPI จาก Metric จริง
- [x] แสดงช่วงวันที่แบบภาษาไทย
- [x] เชื่อม Submission Status panel กับข้อมูลจริง
- [x] เชื่อม Child OU Summary table กับข้อมูลจริงครบถ้วน
- [x] เชื่อม Trend chart
- [x] Drill down จาก KPI หรือ OU
- [x] แสดง empty state แยกจาก backend error

### Backend

- [x] RPC `get_recursive_summary`
- [x] RPC `ensure_recent_sunday_periods`
- [x] Aggregation ตาม OU subtree
- [x] Compare period และ growth percent
- [x] Database tests สำหรับ recursive summary และ recent Sundays
- [x] RPC `get_submission_status_summary` สำหรับ completeness/status ของ reporting OU
- [x] RPC `get_child_ou_summary` สำหรับ direct-child subtree rollup
- [x] RPC `get_dashboard_trend` หลาย period ในครั้งเดียว
- [x] Policy รวมเฉพาะ approved submissions ทั้ง auto-approve และ approval-required

### Acceptance Criteria

- [x] ตัวเลข Dashboard ตรงกับผลรวม approved Submission ที่เข้าเงื่อนไข
- [x] Parent/Child aggregation ไม่เกิดการนับซ้ำ และ parent direct submission เป็น additive เพียงครั้งเดียว
- [x] เปลี่ยน tenant แล้วข้อมูลทุกส่วน reset และ refresh จาก active tenant context

### Definition of Done — Task 5

- [x] KPI, submission status, child summary และ trend ใช้ backend ของ active tenant จริง
- [x] มี loading, empty, success, retry และ backend error states แยกกัน
- [x] Backend ตรวจ OU visibility, tenant isolation และรวมเฉพาะ approved submissions
- [x] Database tests 17/17 และ frontend/backend integration test ผ่าน
- [x] `npm run check` ผ่าน 0 error / 0 warning และ production build ผ่าน
- [x] ทดสอบ `/app` จริงบน desktop/mobile ครบ period/OU filter, approved total, completeness, KPI trend drill-down, OU drill-down และ empty state

---

## Task 6 — Reports และ Export

หน้า: `/app/reports`

สถานะรวม: ✅ ผ่าน Definition of Done

### Frontend

- [x] เปลี่ยน OU, period, Metric และ rows ตัวอย่างเป็น backend data
- [x] Filter รายสัปดาห์และรายเดือน
- [x] Filter รายปีตาม Product Backlog `RP-003`
- [x] ตารางเปรียบเทียบ OU
- [x] Trend chart จากข้อมูลจริง
- [x] Submission completeness report
- [x] Export CSV
- [x] Export Excel/PDF หลัง CSV ใช้งานได้
- [x] แสดง filter ที่ใช้และเวลาสร้างไฟล์

### Backend

- [x] RPC `get_report_table`
- [x] RPC `get_report_trend`
- [x] RPC `get_submission_completeness`
- [x] Edge Function หรือ endpoint สำหรับ export file
- [x] จำกัดข้อมูลตาม OU permission และ tenant RLS
- [x] Integration tests ให้ยอด Reports ตรงกับ Dashboard

### Acceptance Criteria

- [x] Filter เดียวกันต้องได้ยอดรวมตรงกับ Dashboard
- [x] Export ต้องตรงกับข้อมูลที่แสดงบนหน้าจอ
- [x] ห้าม export ข้อมูล OU ที่ user ไม่มีสิทธิ์

หลักฐานการทดสอบ: DB regression 18/18, frontend-backend integration, auth tests, `svelte-check`, production build และ UAT `/app/reports` รายสัปดาห์/รายเดือน/รายปีบน desktop/mobile ผ่านแล้ว; weekly ATTENDANCE = 175 ตรง Dashboard, monthly/yearly = 265 และ CSV/XLSX/PDF ใช้ rows ที่กรองบนหน้าจอชุดเดียวกัน

---

## Task 7 — User Settings และ Tenant Context

หน้า: `/app/settings`

สถานะรวม: ✅ ผ่าน Definition of Done

### Frontend

- [x] โหลด My Profile
- [x] โหลด OU ที่ user มีสิทธิ์
- [x] แสดง tenant context ปัจจุบัน
- [x] มี tenant switching ใน shared tenant context
- [x] บันทึกชื่อ, ภาษา และหน้าเริ่มต้น
- [x] บันทึก default OU
- [x] บันทึก notification preferences
- [x] แยก Personal Settings และ Tenant Settings ให้ชัดเจน
- [x] Logout ทุกอุปกรณ์หรือ reconnect LINE account

### Backend

- [x] RPC `get_my_profile`
- [x] RPC `list_my_tenants`
- [x] Edge Function `switch-active-tenant`
- [x] Schema `user_preferences`
- [x] RPC get/update user preferences
- [x] Validation landing page และ default OU ตาม permission
- [x] Tests สำหรับ persistence ข้าม session และ tenant

### Acceptance Criteria

- [x] ตั้งค่าแล้ว refresh หรือ login ใหม่ ค่ายังคงอยู่
- [x] Default OU ต้องอยู่ใน tenant ปัจจุบันและ user ต้องเข้าถึงได้
- [x] การสลับ tenant ต้อง refresh permissions และข้อมูลทุกหน้า

หลักฐานการทดสอบ: DB regression 19/19, frontend-backend integration, auth tests, `svelte-check`, production build และ UAT `/app/settings` บน desktop/mobile ผ่านแล้ว; profile/workspace/notification คงค่าหลัง refresh, default OU ถูกใช้บน Dashboard/Reports, cross-tenant OU ถูกปฏิเสธ และ global logout กลับหน้า Login สำเร็จ

---

## Task 8 — Super Admin Tenant Management

หน้า: `/super-admin/tenants`

สถานะรวม: ✅ ผ่าน Definition of Done (ทดสอบล่าสุด 1 สิงหาคม 2026)

### Frontend

- [x] Login สำหรับ local System Admin
- [x] แสดงและค้นหา tenant
- [x] สร้าง tenant
- [x] สร้าง Root Admin Invite Link
- [x] Suspend/Reactivate tenant
- [x] แสดงจำนวนสมาชิกและ OU จาก backend
- [x] Tenant detail page
- [x] แก้ข้อมูล tenant และ configuration
- [x] แสดงและออก Invite ใหม่
- [x] แสดงสถานะ provisioning และ invitation
- [x] แสดง audit/activity ของ tenant
- [x] นำ email/password local login ออกจาก production UI

### Backend

- [x] RPC `list_platform_tenants`
- [x] RPC `create_platform_tenant`
- [x] RPC `set_platform_tenant_status`
- [x] RPC `create_platform_admin_invite_link`
- [x] Provision Root OU, OU Types และ 9 default Metrics
- [x] System Admin permission checks
- [x] Database tests สำหรับ tenant provisioning และ admin invite
- [x] RPC tenant detail/update
- [x] RPC invitation list/revoke/regenerate
- [x] Closed tenant lifecycle และ retention policy
- [x] Platform audit query API

### Acceptance Criteria

- [x] Tenant ใหม่มี Root OU, default OU Types และ default Metrics แยกเป็นของตัวเอง
- [x] Root Admin รับ Invite ผ่าน LINE ได้
- [x] Suspend tenant แล้ว user ภายในต้องใช้งานไม่ได้ทุก endpoint
- [x] ทุก platform mutation ต้องค้นย้อนหลังได้จาก audit log

### Definition of Done — Task 8

- [x] UI ใช้ข้อมูล backend จริง พร้อม loading, empty, success และ error states
- [x] System Admin permission, tenant isolation และ suspended-tenant enforcement อยู่ที่ RPC/RLS scope กลาง
- [x] Platform mutation สำคัญบันทึกและค้นย้อนหลังได้จาก tenant activity
- [x] มี database และ frontend-backend integration regression tests
- [x] `npm run check` ผ่าน 0 error / 0 warning และ production build ผ่าน
- [x] Production bundle ไม่มี email/password local login UI
- [x] ทดสอบ `/super-admin/tenants` และ Tenant Detail จริงบน desktop/mobile แล้ว

---

## Task 9 — Notifications Phase

ช่องทาง: In-app Notification Center + CSMS LINE OA กลาง

สถานะรวม: ⬜ Planned

แผนละเอียด: `doc/15_Notifications_Phase_Plan.md`

### Scope

- [ ] Notification schema, RLS, indexes และ idempotent event key
- [ ] Transactional enqueue/outbox สำหรับ business events
- [ ] Notification list, unread count, mark read/all read และ archive APIs
- [ ] Notification Center และ badge ที่แยก Tenant ถูกต้อง
- [ ] Auto event: submitted, approved, returned และ edit request
- [ ] Auto event: OU assignment/invitation
- [ ] Supabase Edge Function ส่งผ่าน CSMS LINE OA กลาง
- [ ] Retry, dead-letter และ provider-error classification
- [ ] Scheduled missing-submission reminder
- [ ] Pending-approval daily digest
- [ ] Add Friend CTA/QR และ In-app fallback
- [ ] Monitoring, runbook, secret rotation และ production canary

### Architecture Decisions

- Tenant OA เป็น entry point/Rich Menu เท่านั้น
- Messaging API credentials เก็บใน Supabase Edge Function secrets ระดับ Platform
- In-app notification เป็น source of truth; LINE เป็น delivery channel
- Business RPC enqueue event แต่ไม่เรียก LINE provider โดยตรง
- Scheduled reminders ต้อง deduplicate ตาม Tenant, recipient, OU, period และ reminder window

### Acceptance Criteria

- [ ] Event เดียวกันไม่สร้างหรือส่ง notification ซ้ำ
- [ ] ผู้ใช้เห็นเฉพาะ notification ของตนใน active Tenant
- [ ] Recipient selection เคารพ role, OU subtree, active membership และ preferences
- [ ] LINE ส่งไม่สำเร็จแล้ว In-app notification ยังอยู่
- [ ] Retry มีขอบเขตและ permanent failure เข้า dead letter
- [ ] Reminder ข้าม OU ที่ส่งแล้ว, period ปิด, user/OU inactive
- [ ] Secret/token ไม่ปรากฏใน browser, database payload, audit หรือ logs
- [ ] มี kill switch ปิด outbound LINE โดยไม่ปิด In-app notification

### Definition of Done — Task 9

- [ ] P0 event notifications ทำงานทั้ง In-app และ LINE OA กลาง
- [ ] Missing-submission scheduled reminder ทำงานและไม่ส่งซ้ำ
- [ ] Database, Edge Function, integration และ frontend tests ผ่าน
- [ ] `npm run check`, production build และ database lint ผ่าน
- [ ] Preview/canary test และ production smoke evidence ถูกบันทึก
- [ ] Monitoring, quota/provider outage, replay และ secret-rotation runbook พร้อมใช้งาน

---

## ลำดับงานถัดไปที่แนะนำ

1. เริ่ม Task 9 Stage A: Notification schema, RLS, enqueue และ read APIs
2. กลับมาปิด Task 1 ส่วน Reporting Periods และ Metric delete/deactivate
3. บันทึกผล production smoke test, monitoring และ backup/restore evidence
4. จัดรอบ regression test หลังการเปลี่ยนแปลง production ทุกครั้ง

## Definition of Done สำหรับทุก Task

- [ ] UI ใช้ข้อมูล backend จริง ไม่มีข้อมูลตัวอย่างค้างอยู่
- [ ] มี loading, empty, success และ error states
- [ ] Backend ตรวจ permission และ tenant isolation
- [ ] Mutation ที่สำคัญมี audit log
- [ ] มี database/integration regression tests
- [ ] `npm run check` ผ่านโดยไม่มี error หรือ warning
- [ ] ทดสอบเส้นทางใช้งานจริงบน desktop และ mobile

## Future Enhancements

- QR Attendance
- Member Management นอกเหนือจาก OU permissions
- Donation Management
- Event Registration
- Multi-language UI
- Offline Mode
- Mobile Application
- AI Chat Assistant และ AI Summary
- Predictive Analytics และ Forecast
- Integration APIs

## Technical Debt และ Post-Go-Live Operations

- Optimize recursive queries และพิจารณา materialized views เมื่อข้อมูลโตขึ้น
- เพิ่ม caching layer ตามผล performance test
- Partition ตารางขนาดใหญ่เมื่อถึงเกณฑ์ที่กำหนด
- เพิ่ม monitoring, structured logging และ alerting
- Security review และยืนยัน RLS ทุก role/tenant
- Backup, restore drill และ retention policy
- Dependency updates และ security patches
- UX/accessibility review

## Release Strategy

- Current Production Baseline — ✅ Live: Authentication, Organization, Weekly Submission, Approval, Dashboard, Reports/Export, Settings, Super Admin และ Audit
- Version 1.0 — MVP: Authentication, Organization, Weekly Submission, Dashboard, Reports และ Audit
- Version 1.1 — Approval Workflow และ Notification
- Version 1.2 — Reporting/Export enhancements
- Version 2.0 — AI Analytics, Advanced Reporting และ Mobile Support

## References

- `PROJECT_ROADMAP.md`
- `doc/02_Database_Design.md`
- `doc/03_RLS_and_Permissions.md`
- `doc/09_Coding_Convention.md`
- `doc/10_AI_Context.md`
