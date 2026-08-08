# Notifications Phase — Implementation Prompt

ใช้ Prompt ด้านล่างเพื่อเริ่ม implementation ใน branch `codex/notifications-phase` โดยอ้างอิงแผนหลักที่ `doc/15_Notifications_Phase_Plan.md`

---

## Copy-ready Prompt

คุณกำลังพัฒนา Church Statistics Management System (CSMS) ใน repository `D:\Projects\ST10`

ให้ดำเนินการ Notifications Phase ตาม `doc/15_Notifications_Phase_Plan.md`, `doc/11_backlog.md` Task 9 และ Notification API contract ใน `doc/04_API_Design.md`

### เป้าหมาย

สร้างระบบ Notification แบบ multi-tenant ที่มี In-app notification เป็น source of truth และส่ง LINE Push ผ่าน CSMS LINE OA กลางเป็น delivery channel รองรับ event ทันที, scheduled reminder, preferences, retry/dead-letter, monitoring และ production-safe rollout

### Architecture ที่ต้องยึด

- Tenant LINE OA ใช้ Rich Menu/entry point เท่านั้น ห้ามใช้ส่ง notification
- LINE notification ทุก Tenant ส่งผ่าน CSMS LINE OA กลาง
- In-app notification ต้องถูกสร้างก่อนและยังคงอยู่แม้ LINE ส่งไม่สำเร็จ
- Business RPC สร้าง notification/outbox transactionally แต่ห้ามเรียก LINE provider โดยตรง
- Edge Function เป็นส่วนเดียวที่อ่าน Messaging API secrets และเรียก LINE API
- ห้ามเก็บ Channel Access Token, Channel Secret, LINE ID token หรือ provider secret ใน Tenant Settings, browser, notification payload หรือ audit log
- ทุก notification ต้องมี `church_id`, recipient และ server-enforced Tenant/OU scope
- ใช้ deterministic `event_key` และ unique constraint ป้องกัน notification ซ้ำ
- ตรวจ active membership, role, OU subtree และ user preferences ก่อนสร้าง optional delivery
- Deep link ใช้ Platform Production LIFF/Web URL และ target page ต้องตรวจ permission ซ้ำ
- Outbound LINE ต้องมี kill switch โดยไม่ปิด In-app notification

### วิธีดำเนินงาน

ทำตาม Stage และ Task ID ในแผน ห้ามข้าม Stage A:

1. Stage A — NT-001 ถึง NT-005
   - ตรวจ configuration contract ของ central OA
   - เพิ่ม `notifications` และ `notification_deliveries`
   - เพิ่ม indexes, constraints, RLS และ tenant-isolation tests
   - เพิ่ม preference resolver
   - เพิ่ม idempotent enqueue/outbox function
   - เพิ่ม list, unread count, mark read, mark all read และ archive APIs

2. Stage B — NT-006
   - เพิ่ม Notification Center, bell badge, list/empty/loading/error state
   - รองรับ tenant switching และ deep links
   - ทดสอบ desktop/mobile และ accessibility

3. Stage C — NT-007 และ NT-008
   - เชื่อม submitted, approved, returned, edit-request และ OU assignment events
   - Recipient selection ต้องทำใน backend
   - Business transaction ต้องไม่ล้มเพียงเพราะ LINE provider unavailable

4. Stage D — NT-009, NT-010 และ NT-013
   - สร้าง `send-line-notification` Edge Function แบบ queue worker
   - เพิ่ม bounded retry, permanent/retryable classification และ dead letter
   - เพิ่ม Add Friend CTA/QR และข้อความเมื่อ LINE delivery unavailable

5. Stage E — NT-011 และ NT-012
   - เพิ่ม scheduled missing-submission reminder
   - เพิ่ม pending-approval daily digest
   - เคารพ Tenant timezone, period status และ deduplication window

6. Stage F — NT-014 ถึง NT-016
   - เพิ่ม delivery monitoring/operations query
   - Security review, secret redaction, concurrency tests
   - Preview canary, production smoke test, rollback และ runbook

### Notification events ขั้นต่ำ

- `submission_submitted`
- `submission_approved`
- `submission_returned`
- `edit_request_created`
- `edit_request_resolved`
- `ou_assignment_created`
- `missing_submission_reminder`
- `pending_approval_digest`

### Retry policy

- ครั้งที่ 1: ทันที
- ครั้งที่ 2: 1 นาที
- ครั้งที่ 3: 5 นาที
- ครั้งที่ 4: 30 นาที
- ครั้งที่ 5: 2 ชั่วโมง แล้วเปลี่ยนเป็น `dead_letter`
- ห้าม retry permanent recipient errors

### Implementation constraints

- ใช้ migration ใหม่เท่านั้น ห้ามแก้ migration ที่ deploy แล้ว
- Production มีข้อมูลจริง ห้าม reset, truncate หรือ delete ข้อมูล production
- RLS และ security-definer functions ต้อง fail closed
- ห้ามเชื่อข้อมูล `church_id`, recipient, role หรือ deep link ที่ browser ส่งมาโดยไม่ resolve/validate ฝั่ง server
- Mutation สำคัญต้องมี audit log แต่ห้ามบันทึก secret หรือ message payload ที่อ่อนไหว
- Preserve user changes และหลีกเลี่ยง unrelated refactor
- ใช้ `apply_patch` สำหรับแก้ไฟล์
- อัปเดต `DATA_DICTIONARY.md`, `doc/04_API_Design.md`, `doc/11_backlog.md`, test plan และ production runbook พร้อม code

### Verification ที่ต้องผ่าน

- Database tests: schema, RLS, tenant isolation, recipient scope, preferences, idempotency, read/archive ownership และ reminder dedupe
- Edge Function tests: success, missing secret, 4xx permanent, 429/5xx retry, concurrent claim, stale-processing recovery และ log redaction
- Frontend tests/check: badge, list, tenant switch, mark read/all, deep link, empty/error/loading และ mobile
- `npm.cmd run check`
- `npm.cmd run build`
- `npx.cmd supabase db lint`
- Relevant Supabase DB tests
- Preview smoke test ก่อน production

### Production safety

- เริ่มจาก In-app only โดย outbound LINE ปิดอยู่
- เปิด LINE delivery เฉพาะ test Tenant/user ใน canary
- ทดสอบ submitted → approver และ returned → submitter
- รัน reminder scan ซ้ำและยืนยันว่าไม่ duplicate
- ตรวจ queue depth, success/failure rate และ dead-letter count
- จัดทำ rollback/kill-switch และ secret-rotation procedure ก่อนเปิดทุก Tenant

### วิธีรายงานผล

เมื่อจบแต่ละ Stage ให้รายงาน:

1. Task IDs ที่เสร็จ
2. Files/migrations/functions/routes ที่เพิ่มหรือแก้
3. Security และ tenant-isolation decisions
4. Tests ที่รันและผลลัพธ์
5. งานค้าง/blocker
6. Production action ที่ยังไม่ได้ทำ

เริ่มจากตรวจ repository และ implementation ปัจจุบันก่อน จากนั้นทำเฉพาะ Stage A ให้เสร็จพร้อม tests และเอกสาร ห้ามเริ่ม LINE provider integration จนกว่า Stage A จะผ่าน Definition of Done

---

## Recommended First Run

เริ่ม Prompt ด้านบนด้วยขอบเขต Stage A เท่านั้น เพื่อให้ schema, RLS, idempotency และ In-app APIs แข็งแรงก่อนเชื่อม UI หรือ LINE provider
