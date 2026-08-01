\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.churches (id, code, slug, name, status)
values ('00000000-0000-0000-0000-000000000061', 'SUM', 'sum', 'Summary Test', 'active');
insert into public.users (id, auth_user_id, line_user_id, display_name)
values ('10000000-0000-0000-0000-000000000061', 'a6000000-0000-4000-8000-000000000061', 'summary-viewer', 'Summary Viewer');
insert into public.church_members (id, church_id, user_id, status)
values ('20000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000061', '10000000-0000-0000-0000-000000000061', 'active');
insert into public.organization_unit_types (id, church_id, code, name)
values ('30000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000061', 'GENERIC', 'Generic');
insert into public.organization_units (
    id, church_id, structure_root_id, parent_id, ou_type_id, code, name, path, level, allow_data_entry
)
values
('40000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000061', null, '30000000-0000-0000-0000-000000000061', 'ROOT', 'Root', '/sum-root', 1, false),
('40000000-0000-0000-0000-000000000062', '00000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000061', '30000000-0000-0000-0000-000000000061', 'LEAF1', 'Leaf 1', '/sum-root/leaf-1', 2, true),
('40000000-0000-0000-0000-000000000063', '00000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000061', '30000000-0000-0000-0000-000000000061', 'LEAF2', 'Leaf 2', '/sum-root/leaf-2', 2, true);
insert into public.ou_members (church_id, ou_id, church_member_id, permission)
values ('00000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000061', '20000000-0000-0000-0000-000000000061', 'viewer');
insert into public.statistic_periods (id, church_id, year, week_no, period_start, period_end, label)
values
('50000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000061', 2026, 30, '2026-07-20', '2026-07-26', '2026-W30'),
('50000000-0000-0000-0000-000000000062', '00000000-0000-0000-0000-000000000061', 2026, 29, '2026-07-13', '2026-07-19', '2026-W29');
insert into public.statistic_metrics (
    id, church_id, code, name, category, unit, aggregation
)
values ('60000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000061', 'ATTENDANCE', 'Attendance', 'attendance', 'person', 'sum');
insert into public.statistic_submissions (
    id, church_id, period_id, ou_id, status,
    submitted_by, submitted_at, approved_by, approved_at
)
values
('70000000-0000-0000-0000-000000000061', '00000000-0000-0000-0000-000000000061', '50000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000062', 'approved', '10000000-0000-0000-0000-000000000061', now(), '10000000-0000-0000-0000-000000000061', now()),
('70000000-0000-0000-0000-000000000062', '00000000-0000-0000-0000-000000000061', '50000000-0000-0000-0000-000000000061', '40000000-0000-0000-0000-000000000063', 'approved', '10000000-0000-0000-0000-000000000061', now(), '10000000-0000-0000-0000-000000000061', now()),
('70000000-0000-0000-0000-000000000063', '00000000-0000-0000-0000-000000000061', '50000000-0000-0000-0000-000000000062', '40000000-0000-0000-0000-000000000062', 'approved', '10000000-0000-0000-0000-000000000061', now(), '10000000-0000-0000-0000-000000000061', now());
insert into public.statistic_values (church_id, submission_id, metric_id, numeric_value)
values
('00000000-0000-0000-0000-000000000061', '70000000-0000-0000-0000-000000000061', '60000000-0000-0000-0000-000000000061', 100),
('00000000-0000-0000-0000-000000000061', '70000000-0000-0000-0000-000000000062', '60000000-0000-0000-0000-000000000061', 50),
('00000000-0000-0000-0000-000000000061', '70000000-0000-0000-0000-000000000063', '60000000-0000-0000-0000-000000000061', 120);

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin if condition is not true then raise exception 'BE-006 assertion: %', message; end if; end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a6000000-0000-4000-8000-000000000061', true);
select set_config('request.jwt.claims', '{"sub":"a6000000-0000-4000-8000-000000000061","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000061"}}', true);
create temporary table summary_result as
select public.get_recursive_summary(
    '40000000-0000-0000-0000-000000000061',
    '50000000-0000-0000-0000-000000000061',
    '50000000-0000-0000-0000-000000000062'
) as response;
select pg_temp.assert_true(
    ((select response #>> '{data,metrics,0,currentValue}' from summary_result))::numeric = 150,
    'subtree current sum'
);
select pg_temp.assert_true(
    ((select response #>> '{data,metrics,0,compareValue}' from summary_result))::numeric = 120,
    'compare sum'
);
select pg_temp.assert_true(
    ((select response #>> '{data,metrics,0,growthPercent}' from summary_result))::numeric = 25,
    'growth percent'
);
reset role;
select 'ok 1 - BE-006 recursive summary';
rollback;
