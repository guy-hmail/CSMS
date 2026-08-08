\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-025 assertion: %', message; end if; end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);

create temporary table generated_ou as
select public.create_organization_unit(jsonb_build_object(
  'parentOuId', '84000000-0000-4000-8000-000000000001',
  'ouTypeId', '83000000-0000-4000-8000-000000000004',
  'name', 'กลุ่มภาษาไทย',
  'code', ' ภาษาไทย / invalid code ',
  'allowDataEntry', false
)) response;

select pg_temp.assert_true((
  select response #>> '{data,ouCode}' ~ '^GROUP-[A-F0-9]{12}$'
    and response #>> '{data,ouCode}' = (
      select code from public.organization_units where id = (response #>> '{data,ouId}')::uuid
    )
  from generated_ou
), 'backend ignores user code and generates an ASCII-safe code from OU Type');

select public.update_organization_unit(jsonb_build_object(
  'ouId', (select (response #>> '{data,ouId}')::uuid from generated_ou),
  'ouTypeId', '83000000-0000-4000-8000-000000000004',
  'name', 'กลุ่มภาษาไทยแก้ไข',
  'code', 'HACKED-CODE',
  'allowDataEntry', false
));

select pg_temp.assert_true((
  select code = response #>> '{data,ouCode}'
  from public.organization_units, generated_ou
  where id = (response #>> '{data,ouId}')::uuid
), 'system-generated OU code is immutable during update');

select 'ok 1 - system-generated immutable OU codes';
rollback;
