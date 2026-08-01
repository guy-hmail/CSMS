\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.churches (id, code, slug, name, status, approval_mode)
values ('00000000-0000-0000-0000-000000000051', 'SUB', 'sub', 'Submission Test', 'active', 'auto_approve');
insert into public.users (id, auth_user_id, line_user_id, display_name)
values ('10000000-0000-0000-0000-000000000051', 'a5000000-0000-4000-8000-000000000051', 'submission-user', 'Submission User');
insert into public.church_members (id, church_id, user_id, status)
values ('20000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000051', '10000000-0000-0000-0000-000000000051', 'active');
insert into public.organization_unit_types (id, church_id, code, name)
values ('30000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000051', 'GROUP', 'Group');
insert into public.organization_units (
    id, church_id, structure_root_id, ou_type_id, code, name, path, level, allow_data_entry
)
values ('40000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000051', '40000000-0000-0000-0000-000000000051', '30000000-0000-0000-0000-000000000051', 'ROOT', 'Root', '/sub-root', 1, true);
insert into public.ou_members (id, church_id, ou_id, church_member_id, permission)
values ('41000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000051', '40000000-0000-0000-0000-000000000051', '20000000-0000-0000-0000-000000000051', 'data_entry');
insert into public.statistic_periods (
    id, church_id, year, week_no, period_start, period_end, label
)
values ('50000000-0000-0000-0000-000000000051', '00000000-0000-0000-0000-000000000051', 2026, 30, '2026-07-20', '2026-07-26', '2026-W30');
insert into public.statistic_metrics (
    id, church_id, code, name, category, unit, data_type,
    input_type, aggregation, min_value, is_required
)
values (
    '60000000-0000-0000-0000-000000000051',
    '00000000-0000-0000-0000-000000000051',
    'ATTENDANCE', 'Attendance', 'attendance', 'person',
    'number', 'number', 'sum', 0, true
);

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin if condition is not true then raise exception 'BE-005 assertion: %', message; end if; end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a5000000-0000-4000-8000-000000000051', true);
select set_config('request.jwt.claims', '{"sub":"a5000000-0000-4000-8000-000000000051","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000051"}}', true);

create temporary table draft_result as
select public.save_statistics_draft(jsonb_build_object(
    'clientRequestId', '70000000-0000-4000-8000-000000000051',
    'expectedRevision', null,
    'ouId', '40000000-0000-0000-0000-000000000051',
    'periodId', '50000000-0000-0000-0000-000000000051',
    'remarks', 'Draft',
    'values', jsonb_build_array(jsonb_build_object(
        'metricId', '60000000-0000-0000-0000-000000000051',
        'numericValue', 42, 'textValue', null, 'booleanValue', null
    ))
)) as response;

select pg_temp.assert_true(
    (select response #>> '{data,status}' = 'draft' and response #>> '{data,revisionNo}' = '1' from draft_result),
    'new draft status and revision'
);
select pg_temp.assert_true(
    public.save_statistics_draft(jsonb_build_object(
        'clientRequestId', '70000000-0000-4000-8000-000000000051',
        'expectedRevision', null,
        'ouId', '40000000-0000-0000-0000-000000000051',
        'periodId', '50000000-0000-0000-0000-000000000051',
        'remarks', 'Draft',
        'values', jsonb_build_array(jsonb_build_object(
            'metricId', '60000000-0000-0000-0000-000000000051',
            'numericValue', 42, 'textValue', null, 'booleanValue', null
        ))
    )) = (select response from draft_result),
    'idempotent draft replay'
);

create temporary table submit_result as
select public.submit_statistics(jsonb_build_object(
    'clientRequestId', '70000000-0000-4000-8000-000000000052',
    'expectedRevision', 1,
    'ouId', '40000000-0000-0000-0000-000000000051',
    'periodId', '50000000-0000-0000-0000-000000000051',
    'remarks', 'Submit',
    'values', jsonb_build_array(jsonb_build_object(
        'metricId', '60000000-0000-0000-0000-000000000051',
        'numericValue', 50, 'textValue', null, 'booleanValue', null
    ))
)) as response;

select pg_temp.assert_true(
    (select response #>> '{data,status}' = 'approved' and response #>> '{data,revisionNo}' = '2' from submit_result),
    'auto-approved submit'
);
select pg_temp.assert_true(
    (public.get_submission_detail(
        ((select response #>> '{data,submissionId}' from submit_result))::uuid
    ) #>> '{data,values,0,numericValue}')::numeric = 50,
    'submission detail'
);

reset role;
select pg_temp.assert_true((select count(*) = 2 from public.submission_revisions), 'immutable revision snapshots');
select pg_temp.assert_true((select count(*) = 1 from public.approval_logs), 'approval log');
select pg_temp.assert_true(
    (
        select count(*) = 2
        from public.audit_logs
        where church_id = '00000000-0000-0000-0000-000000000051'
    ),
    'draft and submit audit logs'
);
select pg_temp.assert_true((select count(*) = 2 from public.api_idempotency_keys), 'idempotency records');

select 'ok 1 - BE-005 weekly submissions';
rollback;
