\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.churches (id, code, slug, name, status)
values
('00000000-0000-0000-0000-000000000121', 'SETTINGS', 'settings', 'Settings Test', 'active'),
('00000000-0000-0000-0000-000000000122', 'SETTINGS-OTHER', 'settings-other', 'Other Settings Tenant', 'active');

insert into public.users (id, auth_user_id, line_user_id, display_name)
values
('10000000-0000-0000-0000-000000000121', 'a1200000-0000-4000-8000-000000000121', 'settings-root-admin', 'Root Admin'),
('10000000-0000-0000-0000-000000000122', 'a1200000-0000-4000-8000-000000000122', 'settings-manager', 'Root Manager'),
('10000000-0000-0000-0000-000000000123', 'a1200000-0000-4000-8000-000000000123', 'settings-child-admin', 'Child Admin');

insert into public.church_members (id, church_id, user_id, status)
values
('20000000-0000-0000-0000-000000000121', '00000000-0000-0000-0000-000000000121', '10000000-0000-0000-0000-000000000121', 'active'),
('20000000-0000-0000-0000-000000000122', '00000000-0000-0000-0000-000000000121', '10000000-0000-0000-0000-000000000122', 'active'),
('20000000-0000-0000-0000-000000000123', '00000000-0000-0000-0000-000000000121', '10000000-0000-0000-0000-000000000123', 'active');

insert into public.organization_unit_types (
    id, church_id, code, name, sort_order
)
values
('30000000-0000-0000-0000-000000000121', '00000000-0000-0000-0000-000000000121', 'CHURCH', 'Church', 10),
('30000000-0000-0000-0000-000000000122', '00000000-0000-0000-0000-000000000122', 'OTHER', 'Other', 10);

insert into public.organization_units (
    id, church_id, structure_root_id, parent_id, ou_type_id,
    code, name, path, level
)
values
(
    '40000000-0000-0000-0000-000000000121',
    '00000000-0000-0000-0000-000000000121',
    '40000000-0000-0000-0000-000000000121',
    null,
    '30000000-0000-0000-0000-000000000121',
    'ROOT', 'Root', '/settings-root', 1
),
(
    '40000000-0000-0000-0000-000000000123',
    '00000000-0000-0000-0000-000000000121',
    '40000000-0000-0000-0000-000000000121',
    '40000000-0000-0000-0000-000000000121',
    '30000000-0000-0000-0000-000000000121',
    'CHILD', 'Child', '/settings-root/child', 2
);

insert into public.ou_members (
    id, church_id, ou_id, church_member_id, permission
)
values
(
    '50000000-0000-0000-0000-000000000121',
    '00000000-0000-0000-0000-000000000121',
    '40000000-0000-0000-0000-000000000121',
    '20000000-0000-0000-0000-000000000121',
    'admin'
),
(
    '50000000-0000-0000-0000-000000000122',
    '00000000-0000-0000-0000-000000000121',
    '40000000-0000-0000-0000-000000000121',
    '20000000-0000-0000-0000-000000000122',
    'manager'
),
(
    '50000000-0000-0000-0000-000000000123',
    '00000000-0000-0000-0000-000000000121',
    '40000000-0000-0000-0000-000000000123',
    '20000000-0000-0000-0000-000000000123',
    'admin'
);

insert into public.statistic_metrics (
    id, church_id, code, name, category, unit, data_type,
    input_type, aggregation, default_value, min_value, sort_order
)
values (
    '60000000-0000-0000-0000-000000000121',
    '00000000-0000-0000-0000-000000000121',
    'ATTENDANCE', 'Attendance', 'attendance', 'person',
    'number', 'number', 'sum', 0, 0, 10
);

update public.churches
set primary_metric_id = '60000000-0000-0000-0000-000000000121'
where id = '00000000-0000-0000-0000-000000000121';

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
    if condition is not true then
        raise exception 'BE-012 assertion: %', message;
    end if;
end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1200000-0000-4000-8000-000000000121', true);
select set_config(
    'request.jwt.claims',
    '{"sub":"a1200000-0000-4000-8000-000000000121","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000121"}}',
    true
);

select public.update_tenant_settings(jsonb_build_object(
    'name', 'Settings Updated',
    'timezone', 'Asia/Bangkok',
    'approvalMode', 'approval_required',
    'reportingWeekEndsOn', 6,
    'submissionDeadlineDaysAfterPeriodEnd', 2,
    'primaryMetricId', '60000000-0000-0000-0000-000000000121'
));

select public.update_tenant_notification_schedule(jsonb_build_object(
    'enabled', true,
    'scheduleDays', jsonb_build_array('MON', 'WED', 'SAT'),
    'missingReminderLocalHour', 8,
    'approvalDigestLocalHour', 17
));

create temporary table created_ou_types as
select (public.create_organization_unit_type(jsonb_build_object(
    'code', 'DISTRICT',
    'name', 'District',
    'description', 'District type',
    'sortOrder', 20,
    'defaultAllowDataEntry', false
)) #>> '{data,ouTypeId}')::uuid as id;

select public.update_organization_unit_type(jsonb_build_object(
    'ouTypeId', (select id from created_ou_types),
    'name', 'District Updated',
    'description', 'Updated type',
    'sortOrder', 30,
    'defaultAllowDataEntry', true,
    'isActive', true
));

create temporary table created_metrics as
select (public.create_statistic_metric(jsonb_build_object(
    'code', 'YOUTH',
    'name', 'Youth Attendance',
    'description', 'Youth',
    'category', 'attendance',
    'unit', 'person',
    'dataType', 'number',
    'aggregation', 'sum',
    'defaultValue', 0,
    'minValue', 0,
    'maxValue', null,
    'isRequired', false,
    'sortOrder', 20
)) #>> '{data,metricId}')::uuid as id;

select public.update_statistic_metric(jsonb_build_object(
    'metricId', (select id from created_metrics),
    'name', 'Youth Attendance Updated',
    'description', 'Updated metric',
    'category', 'attendance',
    'unit', 'people',
    'aggregation', 'avg',
    'defaultValue', 1,
    'minValue', 0,
    'maxValue', 100,
    'isRequired', true,
    'sortOrder', 30,
    'isActive', true
));

select pg_temp.assert_true(
    (select name = 'Settings Updated'
        and approval_mode = 'approval_required'
        and reporting_week_ends_on = 6
        and submission_deadline_days_after_period_end = 2
        and notification_schedule_enabled
        and notification_schedule_days = array['MON', 'WED', 'SAT']::text[]
        and missing_reminder_local_hour = 8
        and approval_digest_local_hour = 17
     from public.churches
     where id = '00000000-0000-0000-0000-000000000121'),
    'direct Root Admin updates tenant settings'
);
select pg_temp.assert_true(
    (select name = 'District Updated'
        and sort_order = 30
        and default_allow_data_entry
     from public.organization_unit_types
     where id = (select id from created_ou_types)),
    'OU Type create and update'
);
select pg_temp.assert_true(
    (select name = 'Youth Attendance Updated'
        and aggregation = 'avg'
        and is_required
     from public.statistic_metrics
     where id = (select id from created_metrics)),
    'metric create and update'
);

do $$
begin
    begin
        perform public.update_organization_unit_type(jsonb_build_object(
            'ouTypeId', '30000000-0000-0000-0000-000000000121',
            'isActive', false
        ));
        raise exception 'Root OU type deactivation was accepted';
    exception when others then
        if sqlerrm <> 'ROOT_OU_TYPE_DEACTIVATION_FORBIDDEN' then raise; end if;
    end;

    begin
        perform public.update_statistic_metric(jsonb_build_object(
            'metricId', '60000000-0000-0000-0000-000000000121',
            'isActive', false
        ));
        raise exception 'Primary metric deactivation was accepted';
    exception when others then
        if sqlerrm <> 'PRIMARY_METRIC_DEACTIVATION_FORBIDDEN' then raise; end if;
    end;

    begin
        perform public.update_organization_unit_type(jsonb_build_object(
            'ouTypeId', '30000000-0000-0000-0000-000000000122',
            'name', 'Cross tenant'
        ));
        raise exception 'Cross-tenant OU Type update was accepted';
    exception when others then
        if sqlerrm <> 'OU_TYPE_NOT_FOUND' then raise; end if;
    end;
end;
$$;

reset role;
select pg_temp.assert_true(
    (select count(*) = 6
     from public.audit_logs
     where church_id = '00000000-0000-0000-0000-000000000121'),
    'all successful settings mutations are audited'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1200000-0000-4000-8000-000000000122', true);
select set_config(
    'request.jwt.claims',
    '{"sub":"a1200000-0000-4000-8000-000000000122","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000121"}}',
    true
);
do $$
begin
    begin
        perform public.update_tenant_settings(jsonb_build_object('name', 'Manager Denied'));
        raise exception 'Root manager mutation was accepted';
    exception when others then
        if sqlerrm <> 'DIRECT_ROOT_ADMIN_REQUIRED' then raise; end if;
    end;
    begin
        perform public.update_tenant_notification_schedule(jsonb_build_object(
            'enabled', true,
            'scheduleDays', jsonb_build_array('SUN'),
            'missingReminderLocalHour', 9,
            'approvalDigestLocalHour', 9
        ));
        raise exception 'Root manager notification schedule mutation was accepted';
    exception when others then
        if sqlerrm <> 'DIRECT_ROOT_ADMIN_REQUIRED' then raise; end if;
    end;
end;
$$;

select set_config('request.jwt.claim.sub', 'a1200000-0000-4000-8000-000000000123', true);
select set_config(
    'request.jwt.claims',
    '{"sub":"a1200000-0000-4000-8000-000000000123","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000121"}}',
    true
);
do $$
begin
    begin
        perform public.create_organization_unit_type(jsonb_build_object(
            'code', 'DENIED',
            'name', 'Denied'
        ));
        raise exception 'Non-root admin mutation was accepted';
    exception when others then
        if sqlerrm <> 'DIRECT_ROOT_ADMIN_REQUIRED' then raise; end if;
    end;
end;
$$;

reset role;
select 'ok 1 - BE-012 tenant settings';
rollback;
