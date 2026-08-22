\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
    if condition is not true then
        raise exception 'BE-014 assertion: %', message;
    end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config(
    'request.jwt.claims',
    '{"sub":"80000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}',
    true
);

create temporary table recent_periods as
select * from public.ensure_recent_reporting_periods();

reset role;

select pg_temp.assert_true(
    (select count(*) = 5 from recent_periods),
    'returns the latest completed calculation date and four prior periods'
);

select pg_temp.assert_true(
    (
        select max(period_end)
            = (now() at time zone 'Asia/Bangkok')::date
              - ((extract(dow from (now() at time zone 'Asia/Bangkok')::date)::integer - 0 + 7) % 7)
          and min(period_end)
            = (now() at time zone 'Asia/Bangkok')::date
              - ((extract(dow from (now() at time zone 'Asia/Bangkok')::date)::integer - 0 + 7) % 7) - 28
          and bool_and(period_end - period_start = 6)
          and bool_and(submission_opens_at is not null and submission_due_at is not null)
        from recent_periods
    ),
    'calculation window is Monday through Sunday and each period snapshots a submission window'
);

select 'ok 1 - BE-014 Tenant-configured reporting periods';
rollback;
