\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-026 assertion: %', message; end if;
end;
$$;

-- Two recipients in tenant one: one scoped recipient and one deliberately unscoped.
insert into public.users(id, auth_user_id, line_user_id, display_name)
values
  ('80000000-0000-4000-8000-000000000026', '80000000-0000-4000-8000-000000000126', 'line-notification-recipient', 'Notification Recipient'),
  ('80000000-0000-4000-8000-000000000027', '80000000-0000-4000-8000-000000000127', 'line-notification-unscoped', 'Notification Unscoped');
insert into public.church_members(id, church_id, user_id, status)
values
  ('82000000-0000-4000-8000-000000000026', '81000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000026', 'active'),
  ('82000000-0000-4000-8000-000000000027', '81000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000027', 'active');
insert into public.ou_members(church_id, ou_id, church_member_id, permission)
values ('81000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000004', '82000000-0000-4000-8000-000000000026', 'viewer');

-- One other tenant for active-tenant isolation checks.
insert into public.churches(id, code, slug, name, status)
values ('81000000-0000-4000-8000-000000000026', 'NOTIFY2', 'notification-two', 'Notification Two', 'active');
insert into public.church_members(id, church_id, user_id, status)
values ('82000000-0000-4000-8000-000000000028', '81000000-0000-4000-8000-000000000026', '80000000-0000-4000-8000-000000000001', 'active');

-- The seed admin opts out of submitted LINE delivery but keeps missing reminders.
insert into public.user_preferences(
  church_id, church_member_id, notify_missing, notify_submitted, notify_approval
) values (
  '81000000-0000-4000-8000-000000000001', '82000000-0000-4000-8000-000000000001', true, false, true
)
on conflict (church_id, church_member_id) do update set
  notify_missing = excluded.notify_missing,
  notify_submitted = excluded.notify_submitted,
  notify_approval = excluded.notify_approval;

select app_security.enqueue_notification(
  '81000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'submission_submitted', 'submission:89000000-0000-4000-8000-000000000002:submitted',
  'มีรายงานรออนุมัติ', 'กลุ่ม A ส่งรายงานแล้ว',
  '84000000-0000-4000-8000-000000000004', '/app/approval',
  '{"submissionId":"89000000-0000-4000-8000-000000000002"}'::jsonb, true
) as admin_submitted_id \gset

select app_security.enqueue_notification(
  '81000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'submission_submitted', 'submission:89000000-0000-4000-8000-000000000002:submitted',
  'ข้อความ replay ต้องไม่เขียนทับ', 'ข้อความ replay ต้องไม่เขียนทับ',
  '84000000-0000-4000-8000-000000000004', '/app/approval', '{}'::jsonb, true
) as admin_submitted_replay_id \gset

select app_security.enqueue_notification(
  '81000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000001',
  'missing_submission_reminder', 'missing:88000000-0000-4000-8000-000000000002:84000000-0000-4000-8000-000000000004:2026-08-12',
  'ยังไม่ได้ส่งรายงาน', 'กรุณาส่งรายงานประจำสัปดาห์',
  '84000000-0000-4000-8000-000000000004', '/app/submissions',
  '{"periodId":"88000000-0000-4000-8000-000000000002"}'::jsonb, true
) as admin_missing_id \gset

select app_security.enqueue_notification(
  '81000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000026',
  'ou_assignment_created', 'ou-assignment:82000000-0000-4000-8000-000000000026:viewer',
  'ได้รับสิทธิ์ใหม่', 'คุณได้รับสิทธิ์เข้าถึงกลุ่ม A',
  '84000000-0000-4000-8000-000000000004', '/app/organization', '{}'::jsonb, true
) as recipient_notification_id \gset

select pg_temp.assert_true(app_security.enqueue_notification(
  '81000000-0000-4000-8000-000000000001',
  '80000000-0000-4000-8000-000000000027',
  'missing_submission_reminder', 'missing:unscoped:2026-08-12',
  'ไม่ควรถูกสร้าง', 'ผู้รับไม่มี OU scope',
  '84000000-0000-4000-8000-000000000004', '/app/submissions', '{}'::jsonb, true
) is null, 'recipient outside OU scope is rejected without a row');

select app_security.enqueue_notification(
  '81000000-0000-4000-8000-000000000026',
  '80000000-0000-4000-8000-000000000001',
  'ou_assignment_created', 'tenant-two:welcome',
  'Tenant two', 'Active Tenant isolation', null, '/app/organization', '{}'::jsonb, false
) as tenant_two_notification_id \gset

select pg_temp.assert_true(:'admin_submitted_id' = :'admin_submitted_replay_id', 'deterministic event replay returns the original notification');
select pg_temp.assert_true((select title = 'มีรายงานรออนุมัติ' from public.notifications where id = :'admin_submitted_id'), 'event replay does not overwrite source-of-truth content');
select pg_temp.assert_true((select count(*) = 1 from public.notifications where church_id = '81000000-0000-4000-8000-000000000001' and recipient_user_id = '80000000-0000-4000-8000-000000000001' and event_key like 'submission:%'), 'idempotency constraint prevents duplicate notifications');
select pg_temp.assert_true((select count(*) = 0 from public.notification_deliveries where notification_id = :'admin_submitted_id'), 'disabled submitted preference suppresses optional LINE delivery only');
select pg_temp.assert_true((select count(*) = 1 from public.notification_deliveries where notification_id = :'admin_missing_id' and status = 'pending'), 'enabled missing preference creates durable optional delivery');

do $$ begin
  perform app_security.enqueue_notification(
    '81000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000001',
    'submission_approved', 'unsafe:payload', 'Unsafe', 'Unsafe', null, '/app/submissions',
    '{"nested":{"channelAccessToken":"must-not-persist"}}'::jsonb, false
  );
  raise exception 'BE-026 assertion: sensitive payload should fail';
exception when others then if sqlerrm <> 'UNSAFE_NOTIFICATION_PAYLOAD' then raise; end if; end $$;

do $$ begin
  perform app_security.enqueue_notification(
    '81000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000001',
    'submission_approved', 'unsafe:link', 'Unsafe', 'Unsafe', null, 'https://evil.example/app', '{}'::jsonb, false
  );
  raise exception 'BE-026 assertion: external deep link should fail';
exception when others then if sqlerrm <> 'INVALID_NOTIFICATION_DEEP_LINK' then raise; end if; end $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);

select pg_temp.assert_true(jsonb_array_length(public.list_notifications() #> '{data,items}') = 2, 'feed returns only caller notifications in active tenant');
select pg_temp.assert_true((public.get_unread_notification_count() #>> '{data,count}')::integer = 2, 'unread count excludes other recipients and tenants');
select pg_temp.assert_true((select count(*) = 2 from public.notifications), 'direct RLS select exposes only own active-tenant rows');
select pg_temp.assert_true(not has_table_privilege('authenticated', 'public.notification_deliveries', 'SELECT'), 'delivery table is not browser-readable');

do $$ declare target_id uuid; begin
  select id into target_id from public.notifications where event_key = 'ou-assignment:82000000-0000-4000-8000-000000000026:viewer';
  perform public.mark_notification_read(target_id);
  raise exception 'BE-026 assertion: another recipient notification should not be mutable';
exception when others then if sqlerrm <> 'NOTIFICATION_NOT_FOUND' then raise; end if; end $$;
do $$ declare target_id uuid; begin
  select id into target_id from public.notifications where event_key = 'tenant-two:welcome';
  perform public.archive_notification(target_id);
  raise exception 'BE-026 assertion: cross-tenant notification should not be mutable';
exception when others then if sqlerrm <> 'NOTIFICATION_NOT_FOUND' then raise; end if; end $$;

select public.mark_notification_read(:'admin_submitted_id'::uuid);
select pg_temp.assert_true((public.get_unread_notification_count() #>> '{data,count}')::integer = 1, 'mark read updates only the owned row');
select pg_temp.assert_true((public.mark_all_notifications_read() #>> '{data,count}')::integer = 1, 'mark all updates the remaining unread owned row');
select pg_temp.assert_true((public.get_unread_notification_count() #>> '{data,count}')::integer = 0, 'mark all clears the active-tenant unread count');
select public.archive_notification(:'admin_missing_id'::uuid);
select pg_temp.assert_true((public.get_unread_notification_count() #>> '{data,count}')::integer = 0, 'archived notification is read and excluded from unread count');
select pg_temp.assert_true(jsonb_array_length(public.list_notifications() #> '{data,items}') = 1, 'default feed excludes archived rows');
select pg_temp.assert_true(jsonb_array_length(public.list_notifications(20, null, null, true) #> '{data,items}') = 2, 'explicit feed can include archived owned rows');

do $$ begin
  perform app_security.enqueue_notification(
    '81000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000001',
    'submission_approved', 'browser:forbidden', 'Forbidden', 'Forbidden'
  );
  raise exception 'BE-026 assertion: browser must not execute enqueue helper';
exception when insufficient_privilege then null; end $$;

select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000026"}}', true);
select pg_temp.assert_true(jsonb_array_length(public.list_notifications() #> '{data,items}') = 1, 'tenant switch exposes only the same user active-tenant feed');
select pg_temp.assert_true((select count(*) = 1 from public.notifications), 'direct RLS follows active tenant switch');

reset role;
select pg_temp.assert_true(not has_function_privilege('authenticated', 'app_security.enqueue_notification(uuid,uuid,text,text,text,text,uuid,text,jsonb,boolean)', 'EXECUTE'), 'enqueue helper is internal-only');
select pg_temp.assert_true(not has_function_privilege('anon', 'public.list_notifications(integer,timestamptz,uuid,boolean)', 'EXECUTE'), 'anonymous notification reads are revoked');
select pg_temp.assert_true((select count(*) >= 2 from public.audit_logs where action in ('mark_notification_read', 'archive_notification') and metadata = '{}'::jsonb), 'read/archive mutations are audited without notification payload');

select 'ok 1 - Stage A notification schema, isolation, preferences, idempotency and ownership APIs';
rollback;
