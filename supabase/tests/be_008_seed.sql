\set ON_ERROR_STOP on

select '1..1';

do $$
begin
    if (select count(*) from public.churches where code = 'DEMO') <> 1 then
        raise exception 'BE-008: expected demo tenant';
    end if;
    if not exists (
        select 1
        from public.churches
        where id = '81000000-0000-4000-8000-000000000001'
          and reporting_week_ends_on = 0
          and submission_deadline_days_after_period_end = 1
    ) then
        raise exception 'BE-008: expected Sunday calculation end and +1 day submission deadline';
    end if;
    if not exists (
        select 1
        from public.users u
        join auth.users au on au.id = u.auth_user_id
        join public.church_members cm
          on cm.church_id = '81000000-0000-4000-8000-000000000001'
         and cm.user_id = u.id
         and cm.status = 'active'
        join public.ou_members om
          on om.church_id = cm.church_id
         and om.church_member_id = cm.id
         and om.ou_id = '84000000-0000-4000-8000-000000000001'
         and om.permission = 'admin'
         and om.is_active = true
         and om.deleted_at is null
        where u.line_user_id = 'U3a58a17bfa7d286fba62bd02c81a9311'
          and u.last_active_church_id = cm.church_id
          and u.global_role = 'user'
          and u.is_active = true
    ) then
        raise exception 'BE-008: expected seeded LINE user to be an active Demo Church tenant admin';
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
