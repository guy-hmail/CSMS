\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is not true then raise exception 'BE-019 assertion: %', message; end if; end; $$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);

create temporary table report_result as
select public.get_report_table('84000000-0000-4000-8000-000000000001', '2026-07-20', '2026-07-26') response;
select pg_temp.assert_true((select (response #>> '{data,totals,ATTENDANCE}')::numeric = 175 from report_result), 'weekly report total is 175');
select pg_temp.assert_true((select jsonb_array_length(response #> '{data,rows}') = 2 from report_result), 'report compares two reporting OUs');
select pg_temp.assert_true((
  select (response #>> '{data,totals,ATTENDANCE}')::numeric =
    (public.get_recursive_summary('84000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002', null) #>> '{data,metrics,0,currentValue}')::numeric
  from report_result
), 'report total matches dashboard for the same OU and week');

create temporary table trend_result as
select public.get_report_trend('84000000-0000-4000-8000-000000000001', 'ATTENDANCE', '2026-07-13', '2026-07-26') response;
select pg_temp.assert_true((
  select count(*) = 2 from trend_result, lateral jsonb_array_elements(response #> '{data,points}') point
  where (point ->> 'value')::numeric in (90, 175)
), 'report trend contains approved weekly totals');

create temporary table completeness_result as
select public.get_submission_completeness('84000000-0000-4000-8000-000000000001', '2026-07-20', '2026-07-26') response;
select pg_temp.assert_true((select response #>> '{data,summary,expected}' = '2' and response #>> '{data,summary,approved}' = '2' from completeness_result), 'weekly completeness is correct');

reset role;
insert into public.users (id, auth_user_id, line_user_id, display_name)
values ('80000000-0000-4000-8000-000000000099', '80000000-0000-4000-8000-000000000099', 'report-limited', 'Report Limited');
insert into public.church_members (id, church_id, user_id, status)
values ('82000000-0000-4000-8000-000000000099', '81000000-0000-4000-8000-000000000001', '80000000-0000-4000-8000-000000000099', 'active');
insert into public.ou_members (church_id, ou_id, church_member_id, permission)
values ('81000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000004', '82000000-0000-4000-8000-000000000099', 'viewer');

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000099', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000099","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);
select pg_temp.assert_true(jsonb_array_length(public.get_report_table('84000000-0000-4000-8000-000000000004', '2026-07-20', '2026-07-26') #> '{data,rows}') = 1, 'limited viewer exports only assigned OU');

do $$ begin
  perform public.get_report_table('84000000-0000-4000-8000-000000000001', '2026-07-20', '2026-07-26');
  raise exception 'BE-019 assertion: inaccessible root report should fail';
exception when others then
  if sqlerrm <> 'REPORT_FORBIDDEN' then raise; end if;
end $$;

select pg_temp.assert_true(not has_function_privilege('anon', 'public.get_report_table(uuid,date,date)', 'EXECUTE'), 'anonymous report execution revoked');
select pg_temp.assert_true(not has_function_privilege('anon', 'public.get_report_trend(uuid,text,date,date)', 'EXECUTE'), 'anonymous trend execution revoked');
select pg_temp.assert_true(not has_function_privilege('anon', 'public.get_submission_completeness(uuid,date,date)', 'EXECUTE'), 'anonymous completeness execution revoked');

select 'ok 1 - Task 6 reports, dashboard parity and export permission scope';
rollback;
