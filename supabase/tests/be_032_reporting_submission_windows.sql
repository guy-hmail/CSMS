\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-032 assertion: %', message; end if;
end;
$$;

update public.churches
set reporting_week_ends_on = 6,
    submission_deadline_days_after_period_end = 2,
    timezone = 'Asia/Bangkok'
where id = '81000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"80000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}',
  true
);

create temporary table configured_periods as
select * from public.ensure_recent_reporting_periods();

reset role;

select pg_temp.assert_true(
  (select count(*) = 5
      and bool_and(extract(dow from period_end)::integer = 6)
      and bool_and(period_end - period_start = 6)
      and bool_and((submission_due_at at time zone 'Asia/Bangkok')::date = period_end + 2)
      and bool_and((submission_due_at at time zone 'Asia/Bangkok')::time > time '23:59:59')
   from configured_periods),
  'Saturday calculation boundaries create five seven-day periods with a two-day local deadline snapshot'
);

select pg_temp.assert_true(
  app_security.reporting_submission_state(
    'open', '2026-08-16 00:00:00+07', '2026-08-17 23:59:59.999999+07', '2026-08-15 23:59:59+07'
  ) = 'not_open'
  and app_security.reporting_submission_state(
    'open', '2026-08-16 00:00:00+07', '2026-08-17 23:59:59.999999+07', '2026-08-17 09:00:00+07'
  ) = 'open'
  and app_security.reporting_submission_state(
    'open', '2026-08-16 00:00:00+07', '2026-08-17 23:59:59.999999+07', '2026-08-18 00:00:00+07'
  ) = 'overdue'
  and app_security.reporting_submission_state(
    'closed', '2026-08-16 00:00:00+07', '2026-08-17 23:59:59.999999+07', '2026-08-17 09:00:00+07'
  ) = 'locked',
  'submission state distinguishes not-open, open, overdue and administratively locked periods'
);

insert into public.statistic_periods(
  id, church_id, year, week_no, period_start, period_end, label,
  submission_opens_at, submission_due_at
) values
  ('f3200000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 2020, 2, '2020-01-06', '2020-01-12', 'BE-032-overdue', '2020-01-12 00:00:00+07', '2020-01-13 23:59:59.999999+07'),
  ('f3200000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001', 2030, 2, '2030-01-07', '2030-01-13', 'BE-032-future', '2030-01-13 00:00:00+07', '2030-01-14 23:59:59.999999+07');

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"80000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}',
  true
);

do $$
begin
  begin
    perform public.save_statistics_draft(jsonb_build_object(
      'periodId', 'f3200000-0000-4000-8000-000000000001',
      'ouId', '84000000-0000-4000-8000-000000000004'
    ));
    raise exception 'overdue period accepted a normal draft';
  exception when others then
    if sqlerrm <> 'SUBMISSION_DEADLINE_PASSED' then raise; end if;
  end;

  begin
    perform public.save_statistics_draft(jsonb_build_object(
      'periodId', 'f3200000-0000-4000-8000-000000000002',
      'ouId', '84000000-0000-4000-8000-000000000004'
    ));
    raise exception 'future period accepted a normal draft';
  exception when others then
    if sqlerrm <> 'SUBMISSION_WINDOW_NOT_OPEN' then raise; end if;
  end;
end;
$$;

reset role;

select 'ok 1 - BE-032 calculation periods and submission deadlines are independent';
rollback;
