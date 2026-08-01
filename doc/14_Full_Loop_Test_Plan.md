# CSMS Full-Loop Integration Test Plan

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
