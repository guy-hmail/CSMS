\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
    if condition is not true then
        raise exception 'BE-013 assertion: %', message;
    end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config(
    'request.jwt.claims',
    '{"sub":"80000000-0000-4000-8000-000000000002","role":"authenticated"}',
    true
);

create temporary table created_tenant as
select public.create_platform_tenant(jsonb_build_object(
    'name', 'Default Metrics Test',
    'slug', 'default-metrics-test',
    'rootOuName', 'Test Root',
    'adminName', 'Test Admin',
    'adminEmail', 'admin@default-metrics.test',
    'timezone', 'Asia/Bangkok',
    'weekEndsOn', 'sunday',
    'approvalMode', 'auto_approve'
)) as id;

reset role;

select pg_temp.assert_true(
    (
        select array_agg(metric.code::text order by metric.sort_order) = array[
            'ATTENDANCE',
            'CHILD_ATTENDANCE',
            'ONLINE',
            'PASTOR_ATTENDANCE',
            'ELDER_ATTENDANCE',
            'CARE_MEETING',
            'CARE_ONLINE',
            'LUNCH',
            'SUNDAY_SCHOOL'
        ]::text[]
        from public.statistic_metrics as metric
        where metric.church_id = (select id from created_tenant)
          and metric.is_active = true
    ),
    'new tenant receives the nine ordered default metrics'
);

select pg_temp.assert_true(
    (
        select count(*) filter (where metric.is_required) = 1
           and bool_and(not metric.is_required or metric.code = 'ATTENDANCE')
           and count(distinct metric.source_template_set_id) = 1
           and count(*) filter (where metric.source_template_code = metric.code) = 9
        from public.statistic_metrics as metric
        where metric.church_id = (select id from created_tenant)
          and metric.is_active = true
    ),
    'only adult attendance is required and template provenance is retained'
);

select pg_temp.assert_true(
    (
        select metric.code = 'ATTENDANCE'
        from public.churches as church
        join public.statistic_metrics as metric
          on metric.church_id = church.id
         and metric.id = church.primary_metric_id
        where church.id = (select id from created_tenant)
    ),
    'adult attendance is the primary metric'
);

select pg_temp.assert_true(
    (
        select array_agg(ou_type.code::text order by ou_type.sort_order) = array[
            'CHURCH',
            'REGION',
            'DISTRICT',
            'GROUP',
            'CARE'
        ]::text[]
        from public.organization_unit_types as ou_type
        where ou_type.church_id = (select id from created_tenant)
          and ou_type.is_active = true
    ),
    'new tenant receives CARE as the fifth ordered OU type'
);

update public.statistic_metrics
set name = 'Tenant-specific child attendance'
where church_id = (select id from created_tenant)
  and code = 'CHILD_ATTENDANCE';

select pg_temp.assert_true(
    (
        select definition ->> 'name' = 'เด็กมาคจ.'
        from public.metric_template_sets as template
        cross join lateral jsonb_array_elements(template.metric_definitions) as definition
        where template.code = 'CSMS_DEFAULT'
          and template.is_active = true
          and definition ->> 'code' = 'CHILD_ATTENDANCE'
        order by template.version desc
        limit 1
    ),
    'tenant metric edits do not mutate the default template'
);

select 'ok 1 - BE-013 tenant default metric snapshot';
rollback;
