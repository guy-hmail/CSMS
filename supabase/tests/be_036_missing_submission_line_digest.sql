\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-036 assertion: %', message; end if;
end;
$$;

insert into public.churches(
  id, code, slug, name, timezone, status, approval_mode, reporting_week_ends_on
) values (
  'f1000000-0000-4000-8000-000000000001', 'NLD', 'notification-line-digest',
  'Notification LINE Digest', 'Asia/Bangkok', 'active', 'auto_approve', 0
);

insert into public.users(id, auth_user_id, line_user_id, display_name)
values (
  'f2000000-0000-4000-8000-000000000001',
  'f3000000-0000-4000-8000-000000000001',
  'U-line-digest-manager',
  'LINE Digest Manager'
);

insert into public.church_members(id, church_id, user_id, status)
values (
  'f4000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f2000000-0000-4000-8000-000000000001',
  'active'
);

insert into public.organization_unit_types(id, church_id, code, name)
values (
  'f5000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'GROUP',
  'Group'
);

insert into public.organization_units(
  id, church_id, structure_root_id, parent_id, ou_type_id,
  code, name, path, level, allow_data_entry, is_active
) values
  (
    'f6000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001',
    'f6000000-0000-4000-8000-000000000001', null,
    'f5000000-0000-4000-8000-000000000001', 'ROOT', 'Root', '/root', 1, false, true
  ),
  (
    'f6000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000001',
    'f6000000-0000-4000-8000-000000000001', 'f6000000-0000-4000-8000-000000000001',
    'f5000000-0000-4000-8000-000000000001', 'A', 'Group A', '/root/a', 2, true, true
  ),
  (
    'f6000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000001',
    'f6000000-0000-4000-8000-000000000001', 'f6000000-0000-4000-8000-000000000001',
    'f5000000-0000-4000-8000-000000000001', 'B', 'Group B', '/root/b', 2, true, true
  );

insert into public.ou_members(
  id, church_id, ou_id, church_member_id, permission, can_override
) values (
  'f7000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  'f6000000-0000-4000-8000-000000000001',
  'f4000000-0000-4000-8000-000000000001',
  'manager',
  false
);

insert into public.user_preferences(
  church_id, church_member_id, notify_missing, notify_submitted, notify_approval
) values (
  'f1000000-0000-4000-8000-000000000001',
  'f4000000-0000-4000-8000-000000000001',
  true, true, true
);

insert into public.statistic_periods(
  id, church_id, year, week_no, period_start, period_end, label, status,
  submission_opens_at, submission_due_at
) values (
  'f8000000-0000-4000-8000-000000000001',
  'f1000000-0000-4000-8000-000000000001',
  2026, 33, '2026-08-10', '2026-08-16', '2026-W33', 'open',
  '2026-08-15 17:00:00+00', '2026-08-17 16:59:59.999999+00'
);

select public.run_missing_submission_reminders(
  '2026-08-16 02:00:00+00',
  array['f1000000-0000-4000-8000-000000000001'::uuid],
  9
);

select pg_temp.assert_true(
  (select count(*) = 2
   from public.notifications
   where event_key like 'missing:period:%'),
  'each missing OU remains visible as a separate In-app notification'
);

select pg_temp.assert_true(
  (select count(*) = 1
   from public.notifications
   where event_key like 'missing-digest:%'
     and payload ->> 'missingOuCount' = '2'
     and payload ->> 'deliveryMode' = 'digest'),
  'multiple missing OUs create one daily recipient digest'
);

select pg_temp.assert_true(
  (select count(*) = 1
   from public.notification_deliveries delivery
   join public.notifications notification on notification.id = delivery.notification_id
   where delivery.channel = 'line'
     and notification.event_key like 'missing-digest:%'),
  'only the consolidated digest enters the LINE outbox'
);

select pg_temp.assert_true(
  (select count(*) = 0
   from public.notification_deliveries delivery
   join public.notifications notification on notification.id = delivery.notification_id
   where notification.event_key like 'missing:period:%'),
  'per-OU details do not fan out into LINE messages'
);

select public.run_missing_submission_reminders(
  '2026-08-16 10:00:00+00',
  array['f1000000-0000-4000-8000-000000000001'::uuid],
  9
);

select pg_temp.assert_true(
  (select count(*) = 3
   from public.notifications
   where event_type = 'missing_submission_reminder')
  and (select count(*) = 1 from public.notification_deliveries),
  'same-local-day reruns are idempotent for both In-app and LINE'
);

rollback;
select 'ok 1 - BE-036 missing reminders consolidate LINE delivery per recipient and day';
