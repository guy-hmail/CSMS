\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-029 assertion: %', message; end if;
end;
$$;

insert into public.churches(
  id, code, slug, name, timezone, status, approval_mode, reporting_week_ends_on
) values (
  'e1000000-0000-4000-8000-000000000001', 'NTE', 'notification-stage-e',
  'Notification Stage E', 'Asia/Bangkok', 'active', 'approval_required', 0
);

insert into public.users(id, auth_user_id, line_user_id, display_name)
values
  ('e2000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000001', 'U-stage-e-entry', 'Stage E Entry'),
  ('e2000000-0000-4000-8000-000000000002', 'e3000000-0000-4000-8000-000000000002', 'U-stage-e-manager', 'Stage E Manager'),
  ('e2000000-0000-4000-8000-000000000003', 'e3000000-0000-4000-8000-000000000003', 'U-stage-e-root-approver', 'Stage E Root Approver'),
  ('e2000000-0000-4000-8000-000000000004', 'e3000000-0000-4000-8000-000000000004', 'U-stage-e-child-approver', 'Stage E Child Approver'),
  ('e2000000-0000-4000-8000-000000000005', 'e3000000-0000-4000-8000-000000000005', 'U-stage-e-sibling-entry', 'Stage E Sibling Entry');

insert into public.church_members(id, church_id, user_id, status)
values
  ('e4000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000001', 'active'),
  ('e4000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000002', 'active'),
  ('e4000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000003', 'active'),
  ('e4000000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000004', 'active'),
  ('e4000000-0000-4000-8000-000000000005', 'e1000000-0000-4000-8000-000000000001', 'e2000000-0000-4000-8000-000000000005', 'active');

insert into public.organization_unit_types(id, church_id, code, name)
values ('e5000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'GROUP', 'Group');

insert into public.organization_units(
  id, church_id, structure_root_id, parent_id, ou_type_id,
  code, name, path, level, allow_data_entry, is_active
) values
  ('e6000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000001', null, 'e5000000-0000-4000-8000-000000000001', 'ROOT', 'Root', '/root', 1, false, true),
  ('e6000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000001', 'A', 'Group A', '/root/a', 2, true, true),
  ('e6000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000001', 'B', 'Group B', '/root/b', 2, true, true),
  ('e6000000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000001', 'e5000000-0000-4000-8000-000000000001', 'OFF', 'Inactive Group', '/root/off', 2, true, false);

insert into public.ou_members(
  id, church_id, ou_id, church_member_id, permission, can_override
) values
  ('e7000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002', 'e4000000-0000-4000-8000-000000000001', 'data_entry', false),
  ('e7000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002', 'manager', false),
  ('e7000000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000003', 'approver', false),
  ('e7000000-0000-4000-8000-000000000004', 'e1000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002', 'e4000000-0000-4000-8000-000000000004', 'approver', false),
  ('e7000000-0000-4000-8000-000000000005', 'e1000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000003', 'e4000000-0000-4000-8000-000000000005', 'data_entry', false);

insert into public.user_preferences(
  church_id, church_member_id, notify_missing, notify_submitted, notify_approval
) values
  ('e1000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000001', false, true, true),
  ('e1000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000002', true, true, true),
  ('e1000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000003', true, true, true),
  ('e1000000-0000-4000-8000-000000000001', 'e4000000-0000-4000-8000-000000000004', true, true, false);

insert into public.statistic_periods(
  id, church_id, year, week_no, period_start, period_end, label, status,
  submission_opens_at, submission_due_at
) values
  ('e8000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 2026, 33, '2026-08-10', '2026-08-16', '2026-W33', 'open', '2026-08-15 17:00:00+00', '2026-08-17 16:59:59.999999+00'),
  ('e8000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000001', 2026, 32, '2026-08-03', '2026-08-09', '2026-W32', 'open', '2026-08-08 17:00:00+00', '2026-08-10 16:59:59.999999+00');

-- A pre-existing draft counts as an existing submission and must not be called missing.
insert into public.statistic_submissions(
  id, church_id, period_id, ou_id, status
) values (
  'e9000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001',
  'e8000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000003', 'draft'
);

select public.run_missing_submission_reminders(
  '2026-08-16 01:59:00+00', array['e1000000-0000-4000-8000-000000000001'::uuid], 9
);
select pg_temp.assert_true(
  (select count(*) = 0 from public.notifications where event_type = 'missing_submission_reminder'),
  '08:59 Asia/Bangkok is before the local reminder window'
);

select public.run_missing_submission_reminders(
  '2026-08-16 02:00:00+00', array['eeeeeeee-0000-4000-8000-000000000001'::uuid], 9
);
select pg_temp.assert_true(
  (select count(*) = 0 from public.notifications where event_type = 'missing_submission_reminder'),
  'Tenant outside the schedule canary is excluded'
);

select public.run_missing_submission_reminders(
  '2026-08-16 02:00:00+00', array['e1000000-0000-4000-8000-000000000001'::uuid], 9
);
select pg_temp.assert_true(
  (select count(*) = 2 from public.notifications
   where event_type = 'missing_submission_reminder'
     and ou_id = 'e6000000-0000-4000-8000-000000000002'),
  'missing OU notifies its exact data-entry member and ancestor manager'
);
select pg_temp.assert_true(
  (select count(*) = 0 from public.notifications
   where event_type = 'missing_submission_reminder'
     and recipient_user_id = 'e2000000-0000-4000-8000-000000000005'),
  'sibling data-entry member and OU with a draft are skipped'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.notification_deliveries delivery
   join public.notifications notification on notification.id = delivery.notification_id
   where notification.event_type = 'missing_submission_reminder'),
  'notify_missing opt-out keeps In-app but suppresses optional LINE delivery'
);

select public.run_missing_submission_reminders(
  '2026-08-16 10:00:00+00', array['e1000000-0000-4000-8000-000000000001'::uuid], 9
);
select pg_temp.assert_true(
  (select count(*) = 2 from public.notifications where event_type = 'missing_submission_reminder'),
  'repeated same-local-day scan is idempotent'
);

-- Convert both current-period OUs to submitted so they feed the approval digest.
insert into public.statistic_submissions(
  id, church_id, period_id, ou_id, status, submitted_by, submitted_at
) values (
  'e9000000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000001',
  'e8000000-0000-4000-8000-000000000001', 'e6000000-0000-4000-8000-000000000002',
  'submitted', 'e2000000-0000-4000-8000-000000000001', '2026-08-16 01:00:00+00'
);
update public.statistic_submissions
set status = 'submitted',
    submitted_by = 'e2000000-0000-4000-8000-000000000005',
    submitted_at = '2026-08-16 01:00:00+00'
where id = 'e9000000-0000-4000-8000-000000000001';

select public.run_pending_approval_digests(
  '2026-08-16 02:00:00+00', array['e1000000-0000-4000-8000-000000000001'::uuid], 9
);
select pg_temp.assert_true(
  (select count(*) = 2 from public.notifications where event_type = 'pending_approval_digest'),
  'one daily digest is created for each actionable approver'
);
select pg_temp.assert_true(
  (select payload ->> 'pendingCount' = '1'
   from public.notifications
   where event_type = 'pending_approval_digest'
     and recipient_user_id = 'e2000000-0000-4000-8000-000000000004'),
  'nearest child approver receives only the child-scope pending count'
);
select pg_temp.assert_true(
  (select payload ->> 'pendingCount' = '1'
   from public.notifications
   where event_type = 'pending_approval_digest'
     and recipient_user_id = 'e2000000-0000-4000-8000-000000000003'),
  'root approver receives the sibling pending count but not the nearer approver item'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.notification_deliveries delivery
   join public.notifications notification on notification.id = delivery.notification_id
   where notification.event_type = 'pending_approval_digest'),
  'notify_approval opt-out suppresses only the digest LINE outbox row'
);

select public.run_pending_approval_digests(
  '2026-08-16 15:00:00+00', array['e1000000-0000-4000-8000-000000000001'::uuid], 9
);
select pg_temp.assert_true(
  (select count(*) = 2 from public.notifications where event_type = 'pending_approval_digest'),
  'daily digest rerun does not create message spam'
);

select public.run_pending_approval_digests(
  '2026-08-17 02:00:00+00', array['e1000000-0000-4000-8000-000000000001'::uuid], 9
);
select pg_temp.assert_true(
  (select count(*) = 4 from public.notifications where event_type = 'pending_approval_digest'),
  'next local day creates one new digest per actionable recipient'
);

update public.statistic_periods set status = 'closed'
where id = 'e8000000-0000-4000-8000-000000000001';
select public.run_missing_submission_reminders(
  '2026-08-17 02:00:00+00', array['e1000000-0000-4000-8000-000000000001'::uuid], 9
);
select pg_temp.assert_true(
  (select count(*) = 2 from public.notifications where event_type = 'missing_submission_reminder'),
  'closed current period creates no new missing reminder'
);

select pg_temp.assert_true(
  (select count(*) >= 1 from public.audit_logs
   where church_id = 'e1000000-0000-4000-8000-000000000001'
     and entity_type = 'notification_schedule'
     and metadata::text !~* '(line_user_id|U-stage-e|body|token|secret|authorization)'),
  'schedule audit contains only non-sensitive window metadata'
);
select pg_temp.assert_true(
  not has_function_privilege('authenticated', 'public.run_missing_submission_reminders(timestamptz,uuid[],integer)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.run_pending_approval_digests(timestamptz,uuid[],integer)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'app_security.notification_can_approve_for_ou(uuid,uuid)', 'EXECUTE'),
  'browser role cannot run schedules or inspect internal approval resolution'
);

rollback;
select 'ok 1 - BE-029 scheduled notifications are timezone-aware, scoped, preference-safe, and idempotent';
