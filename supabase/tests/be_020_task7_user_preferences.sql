\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-020 assertion: %', message; end if; end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);

select pg_temp.assert_true(
  public.get_my_preferences() #>> '{data,landingPage}' = '/app/dashboard'
  and public.get_my_preferences() #>> '{data,language}' = 'th',
  'server defaults are returned before first save'
);

select public.update_my_preferences(jsonb_build_object(
  'defaultOuId', '84000000-0000-4000-8000-000000000003',
  'language', 'en', 'landingPage', '/app/reports',
  'notifyMissing', false, 'notifySubmitted', true,
  'notifyApproval', false, 'notifyEmail', true
));
select pg_temp.assert_true(
  public.get_my_preferences() #>> '{data,defaultOuId}' = '84000000-0000-4000-8000-000000000003'
  and public.get_my_preferences() #>> '{data,language}' = 'en'
  and public.get_my_preferences() #>> '{data,notifyEmail}' = 'true',
  'preferences persist across independent RPC calls'
);

do $$ begin
  perform public.update_my_preferences('{"landingPage":"/app/admin","language":"th"}'::jsonb);
  raise exception 'BE-020 assertion: invalid landing page should fail';
exception when others then if sqlerrm <> 'INVALID_LANDING_PAGE' then raise; end if; end $$;

reset role;
insert into public.churches (id, code, slug, name, status)
values ('81000000-0000-4000-8000-000000000099', 'PREF2', 'preference-two', 'Preference Two', 'active');
insert into public.church_members (id, church_id, user_id, status)
values ('82000000-0000-4000-8000-000000000099', '81000000-0000-4000-8000-000000000099', '80000000-0000-4000-8000-000000000001', 'active');
insert into public.organization_unit_types (id, church_id, code, name)
values ('83000000-0000-4000-8000-000000000099', '81000000-0000-4000-8000-000000000099', 'ROOT', 'Root');
insert into public.organization_units (id, church_id, structure_root_id, ou_type_id, code, name, path, level)
values ('84000000-0000-4000-8000-000000000099', '81000000-0000-4000-8000-000000000099', '84000000-0000-4000-8000-000000000099', '83000000-0000-4000-8000-000000000099', 'ROOT', 'Preference Root', '/84000000-0000-4000-8000-000000000099', 1);
insert into public.ou_members (church_id, ou_id, church_member_id, permission)
values ('81000000-0000-4000-8000-000000000099', '84000000-0000-4000-8000-000000000099', '82000000-0000-4000-8000-000000000099', 'viewer');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000099"}}', true);
select pg_temp.assert_true(public.get_my_preferences() #>> '{data,language}' = 'th', 'second tenant starts with independent defaults');

do $$ begin
  perform public.update_my_preferences('{"defaultOuId":"84000000-0000-4000-8000-000000000003","language":"th","landingPage":"/app/dashboard"}'::jsonb);
  raise exception 'BE-020 assertion: cross-tenant default OU should fail';
exception when others then if sqlerrm <> 'INVALID_DEFAULT_OU' then raise; end if; end $$;

select public.update_my_preferences(jsonb_build_object(
  'defaultOuId', '84000000-0000-4000-8000-000000000099',
  'language', 'th', 'landingPage', '/app/organization',
  'notifyMissing', true, 'notifySubmitted', false,
  'notifyApproval', true, 'notifyEmail', false
));
select pg_temp.assert_true(public.get_my_preferences() #>> '{data,landingPage}' = '/app/organization', 'second tenant preference persists');

select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);
select pg_temp.assert_true(public.get_my_preferences() #>> '{data,landingPage}' = '/app/reports', 'switching back restores first tenant preference');

select public.update_my_profile('{"displayName":"Task 7 User","email":"task7@example.test","phone":"081-234-5678"}'::jsonb);
select pg_temp.assert_true((select display_name = 'Task 7 User' and email = 'task7@example.test' from public.users where auth_user_id = '80000000-0000-4000-8000-000000000002'), 'profile persists in the user identity');
reset role;
select pg_temp.assert_true((select count(*) >= 3 from public.audit_logs where user_id = '80000000-0000-4000-8000-000000000001' and action in ('update_my_preferences', 'update_my_profile')), 'profile and tenant preference mutations are audited');
select pg_temp.assert_true(not has_function_privilege('anon', 'public.update_my_preferences(jsonb)', 'EXECUTE'), 'anonymous preference mutation revoked');

select 'ok 1 - Task 7 tenant preferences, validation, persistence and profile';
rollback;
