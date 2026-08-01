\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.churches (id, code, slug, name, status, approval_mode)
values
('00000000-0000-0000-0000-000000000161', 'T3A', 'task3-a', 'Task 3 A', 'active', 'approval_required'),
('00000000-0000-0000-0000-000000000162', 'T3B', 'task3-b', 'Task 3 B', 'active', 'auto_approve');
insert into public.users (id, auth_user_id, line_user_id, display_name)
values ('10000000-0000-0000-0000-000000000161', 'a6000000-0000-4000-8000-000000000161', 'task3-user', 'Task 3 User');
insert into public.church_members (id, church_id, user_id, status)
values ('20000000-0000-0000-0000-000000000161', '00000000-0000-0000-0000-000000000161', '10000000-0000-0000-0000-000000000161', 'active');
insert into public.organization_unit_types (id, church_id, code, name)
values
('30000000-0000-0000-0000-000000000161', '00000000-0000-0000-0000-000000000161', 'GROUP', 'Group'),
('30000000-0000-0000-0000-000000000162', '00000000-0000-0000-0000-000000000162', 'GROUP', 'Group');
insert into public.organization_units (id, church_id, structure_root_id, ou_type_id, code, name, path, level, allow_data_entry)
values
('40000000-0000-0000-0000-000000000161', '00000000-0000-0000-0000-000000000161', '40000000-0000-0000-0000-000000000161', '30000000-0000-0000-0000-000000000161', 'A', 'Visible A', '/a', 1, true),
('40000000-0000-0000-0000-000000000162', '00000000-0000-0000-0000-000000000162', '40000000-0000-0000-0000-000000000162', '30000000-0000-0000-0000-000000000162', 'B', 'Hidden B', '/b', 1, true);
insert into public.ou_members (id, church_id, ou_id, church_member_id, permission)
values ('41000000-0000-0000-0000-000000000161', '00000000-0000-0000-0000-000000000161', '40000000-0000-0000-0000-000000000161', '20000000-0000-0000-0000-000000000161', 'data_entry');
insert into public.statistic_metrics (id, church_id, code, name, category, unit, min_value, max_value, is_required)
values
('60000000-0000-0000-0000-000000000161', '00000000-0000-0000-0000-000000000161', 'A', 'Metric A', 'test', 'count', 0, 10, true),
('60000000-0000-0000-0000-000000000162', '00000000-0000-0000-0000-000000000162', 'B', 'Metric B', 'test', 'count', 0, 10, true);

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-016 assertion: %', message; end if; end; $$;
create function pg_temp.cross_tenant_lookup_is_denied()
returns boolean language plpgsql as $$
begin
  perform public.get_submission_by_context(
    '40000000-0000-0000-0000-000000000162',
    ((select response #>> '{data,periods,0,id}' from context_result))::uuid
  );
  return false;
exception when insufficient_privilege then return true;
end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000161', true);
select set_config('request.jwt.claims', '{"sub":"a6000000-0000-4000-8000-000000000161","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000161"}}', true);

create temporary table context_result as select public.get_weekly_submission_context() response;
select pg_temp.assert_true((select jsonb_array_length(response #> '{data,periods}') = 5 from context_result), 'five recent Sunday periods');
select pg_temp.assert_true((select response #>> '{data,organizationUnits,0,name}' = 'Visible A' from context_result), 'only submit-capable OU');
select pg_temp.assert_true((select jsonb_array_length(response #> '{data,metrics}') = 1 from context_result), 'metrics are tenant isolated');
select pg_temp.assert_true((select (response #>> '{data,metrics,0,maxValue}')::numeric = 10 from context_result), 'metric validation metadata is returned');
select pg_temp.assert_true(
  public.get_submission_by_context('40000000-0000-0000-0000-000000000161', ((select response #>> '{data,periods,0,id}' from context_result))::uuid) #> '{data}' = 'null'::jsonb,
  'lookup returns null before first draft'
);
select pg_temp.assert_true(pg_temp.cross_tenant_lookup_is_denied(), 'cross-tenant lookup is denied');
select pg_temp.assert_true(not has_function_privilege('anon', 'public.get_weekly_submission_context()', 'EXECUTE'), 'anonymous context execution revoked');

select public.save_statistics_draft(jsonb_build_object(
  'clientRequestId', '70000000-0000-4000-8000-000000000161',
  'expectedRevision', null,
  'ouId', '40000000-0000-0000-0000-000000000161',
  'periodId', ((select response #>> '{data,periods,0,id}' from context_result))::uuid,
  'values', jsonb_build_array(jsonb_build_object(
    'metricId', '60000000-0000-0000-0000-000000000161',
    'numericValue', 7, 'textValue', null, 'booleanValue', null
  ))
));
select pg_temp.assert_true(
  public.get_submission_by_context('40000000-0000-0000-0000-000000000161', ((select response #>> '{data,periods,0,id}' from context_result))::uuid) #>> '{data,submission,status}' = 'draft',
  'lookup returns the persisted draft by OU and period'
);

select 'ok 1 - Task 3 submission page context is permission and tenant scoped';
rollback;
