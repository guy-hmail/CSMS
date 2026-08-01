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
select * from public.ensure_recent_sunday_periods();

reset role;

select pg_temp.assert_true(
    (select count(*) = 5 from recent_periods),
    'returns the upcoming Sunday and four previous Sundays'
);

select pg_temp.assert_true(
    (
        select max(period_end)
            = current_date + ((7 - extract(dow from current_date)::integer) % 7)
          and min(period_end)
            = current_date + ((7 - extract(dow from current_date)::integer) % 7) - 28
          and bool_and(period_end - period_start = 6)
        from recent_periods
    ),
    'reporting window is Monday through Sunday and spans four weeks back'
);

select 'ok 1 - BE-014 rolling Sunday reporting periods';
rollback;
