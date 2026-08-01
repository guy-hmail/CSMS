\set ON_ERROR_STOP on

select '1..1';

do $$
begin
    if (select count(*) from public.churches where code = 'DEMO') <> 1 then
        raise exception 'BE-008: expected demo tenant';
    end if;
    if (select count(*) from public.organization_units where church_id = '81000000-0000-4000-8000-000000000001') <> 5 then
        raise exception 'BE-008: expected five demo OUs';
    end if;
    if not exists (
        select 1
        from public.organization_unit_types
        where church_id = '81000000-0000-4000-8000-000000000001'
          and code = 'CARE'
          and name = 'แคร์'
          and sort_order = 50
          and default_allow_data_entry = true
          and is_active = true
    ) then
        raise exception 'BE-008: expected CARE demo OU type at sort order 50';
    end if;
    if (
        select count(*)
        from public.statistic_metrics
        where church_id = '81000000-0000-4000-8000-000000000001'
          and is_active = true
    ) <> 9 then
        raise exception 'BE-008: expected nine active metrics';
    end if;
    if (select count(*) from public.statistic_submissions where church_id = '81000000-0000-4000-8000-000000000001' and status = 'approved') <> 3 then
        raise exception 'BE-008: expected three approved submissions';
    end if;
end;
$$;

begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);
do $$
declare
    response jsonb;
begin
    response := public.get_recursive_summary(
        '84000000-0000-4000-8000-000000000001',
        '88000000-0000-4000-8000-000000000002',
        '88000000-0000-4000-8000-000000000001'
    );
    if (response #>> '{data,metrics,0,currentValue}')::numeric <> 175 then
        raise exception 'BE-008: expected current attendance 175';
    end if;
end;
$$;
reset role;
select 'ok 1 - BE-008 seed data';
rollback;
