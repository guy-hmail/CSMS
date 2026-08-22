\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-033 assertion: %', message; end if;
end;
$$;

update public.churches
set reporting_week_ends_on = 0,
    submission_deadline_days_after_period_end = 1,
    timezone = 'Asia/Bangkok'
where id = '81000000-0000-4000-8000-000000000001';

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config(
  'request.jwt.claims',
  '{"sub":"80000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}',
  true
);

create temporary table initial_completed_periods as
select * from public.ensure_recent_reporting_periods();

reset role;

update public.statistic_periods period
set submission_due_at = now() - interval '1 microsecond'
where period.id = (
  select completed.period_id
  from initial_completed_periods completed
  order by completed.period_end desc
  limit 1
);

set local role authenticated;
create temporary table rollover_context as
select public.get_weekly_submission_context() #> '{data}' response;
create temporary table dashboard_periods_after_rollover as
select * from public.ensure_recent_reporting_periods();
reset role;

select pg_temp.assert_true(
  (select
    jsonb_array_length(response -> 'periods') = 5
    and response ->> 'defaultPeriodId' = response #>> '{periods,0,id}'
    and (response #>> '{periods,0,periodEnd}')::date
      = (response #>> '{periods,1,periodEnd}')::date + 7
    and (response #>> '{periods,0,periodStart}')::date
      = (response #>> '{periods,1,periodEnd}')::date + 1
    and response #>> '{periods,0,submissionState}' = 'open'
   from rollover_context),
  'submission context rolls to the next week immediately after the previous deadline'
);

select pg_temp.assert_true(
  (select max(period_end) = (select max(period_end) from initial_completed_periods)
   from dashboard_periods_after_rollover),
  'completed-period consumers used by dashboard and reports remain on the previous week'
);

select 'ok 1 - BE-033 submission rollover is isolated from dashboard and report periods';
rollback;
