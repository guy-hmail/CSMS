\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-031 assertion: %', message; end if;
end;
$$;

insert into public.churches(
  id, code, slug, name, timezone, status, approval_mode,
  notification_schedule_enabled, notification_schedule_days,
  missing_reminder_local_hour, approval_digest_local_hour
) values
  (
    'f1100000-0000-4000-8000-000000000001', 'NTS1', 'tenant-schedule-one',
    'Tenant Schedule One', 'Asia/Bangkok', 'active', 'approval_required',
    true, array['SUN'], 9, 17
  ),
  (
    'f1100000-0000-4000-8000-000000000002', 'NTS2', 'tenant-schedule-two',
    'Tenant Schedule Two', 'UTC', 'active', 'approval_required',
    false, array['SUN'], 0, 0
  ),
  (
    'f1100000-0000-4000-8000-000000000003', 'NTS3', 'tenant-schedule-three',
    'Tenant Schedule Three', 'Asia/Bangkok', 'active', 'approval_required',
    true, array['MON'], 8, 10
  );

select pg_temp.assert_true(
  (public.run_tenant_missing_submission_reminders(
    '2026-08-16 01:59:00+00',
    array['f1100000-0000-4000-8000-000000000001'::uuid]
  ) #>> '{data,tenantsScanned}')::integer = 0,
  'Tenant local time before the configured hour is skipped'
);

select pg_temp.assert_true(
  (public.run_tenant_missing_submission_reminders(
    '2026-08-16 02:00:00+00',
    array['f1100000-0000-4000-8000-000000000001'::uuid]
  ) #>> '{data,tenantsScanned}')::integer = 1,
  'Tenant runs on its configured local day and hour'
);

select pg_temp.assert_true(
  (public.run_tenant_missing_submission_reminders(
    '2026-08-17 02:00:00+00',
    array['f1100000-0000-4000-8000-000000000001'::uuid]
  ) #>> '{data,tenantsScanned}')::integer = 0,
  'Tenant is skipped on a local weekday it did not select'
);

select pg_temp.assert_true(
  (public.run_tenant_missing_submission_reminders(
    '2026-08-16 02:00:00+00',
    array['f1100000-0000-4000-8000-000000000002'::uuid]
  ) #>> '{data,tenantsScanned}')::integer = 0,
  'Tenant-owned disabled switch prevents scheduled execution'
);

select pg_temp.assert_true(
  (public.run_tenant_pending_approval_digests(
    '2026-08-17 02:59:00+00',
    array['f1100000-0000-4000-8000-000000000003'::uuid]
  ) #>> '{data,tenantsScanned}')::integer = 0,
  'Approval digest respects its independent Tenant hour'
);

select pg_temp.assert_true(
  (public.run_tenant_pending_approval_digests(
    '2026-08-17 03:00:00+00',
    array['f1100000-0000-4000-8000-000000000003'::uuid]
  ) #>> '{data,tenantsScanned}')::integer = 1,
  'Approval digest starts at its configured Tenant-local hour'
);

do $$
begin
  begin
    update public.churches
    set notification_schedule_days = array['SAI']
    where id = 'f1100000-0000-4000-8000-000000000001';
    raise exception 'Invalid weekday code was accepted';
  exception when check_violation then
    null;
  end;
end;
$$;

select pg_temp.assert_true(
  not has_function_privilege(
    'authenticated',
    'public.run_tenant_missing_submission_reminders(timestamptz,uuid[])',
    'EXECUTE'
  )
  and not has_function_privilege(
    'authenticated',
    'public.run_tenant_pending_approval_digests(timestamptz,uuid[])',
    'EXECUTE'
  ),
  'Browser roles cannot invoke Tenant schedule workers'
);

rollback;
select 'ok 1 - BE-031 Tenant notification schedules enforce enabled state, local day, local hour, and worker isolation';
