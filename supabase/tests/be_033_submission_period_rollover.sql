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

insert into public.statistic_periods (
  church_id, year, week_no, period_start, period_end, label, status,
  submission_opens_at, submission_due_at
)
select
  '81000000-0000-4000-8000-000000000001',
  extract(isoyear from completed.period_end + 7)::integer,
  extract(week from completed.period_end + 7)::integer,
  completed.period_end + 1,
  completed.period_end + 7,
  to_char(completed.period_end + 7, 'YYYY-MM-DD'),
  'open',
  (completed.period_end + 7)::timestamp at time zone 'Asia/Bangkok',
  ((completed.period_end + 9)::timestamp at time zone 'Asia/Bangkok') - interval '1 microsecond'
from initial_completed_periods completed
order by completed.period_end desc
limit 1
on conflict on constraint uq_period_per_church do update
set submission_opens_at = excluded.submission_opens_at,
    submission_due_at = excluded.submission_due_at;

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
    and (response #>> '{periods,0,submissionOpensAt}')::timestamptz <= now()
   from rollover_context),
  'submission context moves a pre-created next week earlier and opens it immediately after the previous deadline'
);

select pg_temp.assert_true(
  (select max(period_end) = (select max(period_end) from initial_completed_periods)
   from dashboard_periods_after_rollover),
  'completed-period consumers used by dashboard and reports remain on the previous week'
);

select 'ok 1 - BE-033 submission rollover is isolated from dashboard and report periods';
rollback;
