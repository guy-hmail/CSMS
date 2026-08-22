-- BE-008: Deterministic local/demo seed. Safe to run repeatedly.
begin;

-- Local-only Supabase Auth account for the deterministic system administrator
-- below. Production identities are provisioned through the configured auth
-- provider and must not reuse these credentials.
insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
)
values (
    '00000000-0000-0000-0000-000000000000',
    '80000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'admin@csms.local',
    extensions.crypt('CsmsLocal!2026', extensions.gen_salt('bf')),
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"email_verified":true}'::jsonb,
    now(),
    now()
)
on conflict (id) do update
set email = excluded.email,
    encrypted_password = excluded.encrypted_password,
    email_confirmed_at = excluded.email_confirmed_at,
    confirmation_token = excluded.confirmation_token,
    recovery_token = excluded.recovery_token,
    email_change_token_new = excluded.email_change_token_new,
    email_change = excluded.email_change,
    raw_app_meta_data = excluded.raw_app_meta_data,
    raw_user_meta_data = excluded.raw_user_meta_data,
    updated_at = now(),
    deleted_at = null;

insert into auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    created_at,
    updated_at
)
values (
    '80000000-0000-4000-8000-000000000002',
    '80000000-0000-4000-8000-000000000002',
    '80000000-0000-4000-8000-000000000002',
    '{"sub":"80000000-0000-4000-8000-000000000002","email":"admin@csms.local","email_verified":true,"phone_verified":false}'::jsonb,
    'email',
    now(),
    now()
)
on conflict (provider_id, provider) do update
set user_id = excluded.user_id,
    identity_data = excluded.identity_data,
    updated_at = now();

-- Local Auth identity for the Demo Church LINE tenant administrator imported
-- from users_rows.csv. The email is local-only and exists so LINE auth can
-- issue the magic-link session exchange for the pre-linked auth user.
insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    confirmation_token,
    recovery_token,
    email_change_token_new,
    email_change,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at
)
values (
    '00000000-0000-0000-0000-000000000000',
    'b5985c41-e895-469b-8d7e-361be6f267e2',
    'authenticated',
    'authenticated',
    'line-demo-admin@csms.local',
    '',
    now(),
    '',
    '',
    '',
    '',
    '{"provider":"email","providers":["email"],"auth_provider":"line","active_church_id":"81000000-0000-4000-8000-000000000001"}'::jsonb,
    '{"email_verified":true,"auth_provider":"line"}'::jsonb,
    now(),
    now()
)
on conflict (id) do update
set email = excluded.email,
    email_confirmed_at = excluded.email_confirmed_at,
    confirmation_token = excluded.confirmation_token,
    recovery_token = excluded.recovery_token,
    email_change_token_new = excluded.email_change_token_new,
    email_change = excluded.email_change,
    raw_app_meta_data = excluded.raw_app_meta_data,
    raw_user_meta_data = excluded.raw_user_meta_data,
    updated_at = now(),
    deleted_at = null;

insert into auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    created_at,
    updated_at
)
values (
    'b5985c41-e895-469b-8d7e-361be6f267e2',
    'b5985c41-e895-469b-8d7e-361be6f267e2',
    'b5985c41-e895-469b-8d7e-361be6f267e2',
    '{"sub":"b5985c41-e895-469b-8d7e-361be6f267e2","email":"line-demo-admin@csms.local","email_verified":true,"phone_verified":false}'::jsonb,
    'email',
    now(),
    now()
)
on conflict (provider_id, provider) do update
set user_id = excluded.user_id,
    identity_data = excluded.identity_data,
    updated_at = now();

insert into public.users (
    id, auth_user_id, line_user_id, display_name, global_role, is_active
)
values (
    '80000000-0000-4000-8000-000000000001',
    '80000000-0000-4000-8000-000000000002',
    'local-demo-admin',
    'ผู้ดูแลระบบตัวอย่าง',
    'system_admin',
    true
)
on conflict (auth_user_id) do update
set display_name = excluded.display_name,
    global_role = excluded.global_role,
    is_active = true,
    deleted_at = null;

insert into public.churches (
    id, code, slug, name, description, status, approval_mode, is_active,
    reporting_week_ends_on, submission_deadline_days_after_period_end
)
values (
    '81000000-0000-4000-8000-000000000001',
    'DEMO',
    'demo-church',
    'คริสตจักรตัวอย่าง',
    'ข้อมูลตัวอย่างสำหรับ local development',
    'active',
    'auto_approve',
    true,
    0, -- Sunday (PostgreSQL DOW)
    1  -- submission deadline is one day after period end
)
on conflict (id) do update
set name = excluded.name,
    description = excluded.description,
    status = 'active',
    is_active = true,
    reporting_week_ends_on = excluded.reporting_week_ends_on,
    submission_deadline_days_after_period_end = excluded.submission_deadline_days_after_period_end,
    deleted_at = null;

insert into public.users (
    id, auth_user_id, last_active_church_id, line_user_id, display_name,
    picture_url, global_role, is_active
)
values (
    '54c9f932-8b50-4845-87e8-d949ff99c7b5',
    'b5985c41-e895-469b-8d7e-361be6f267e2',
    '81000000-0000-4000-8000-000000000001',
    'U3a58a17bfa7d286fba62bd02c81a9311',
    'Guyus',
    'https://profile.line-scdn.net/0h62HQk-lCaR11KH-KQiAWSkltZ3ACBm9VDR12fAMvMCQMHX0YTRp0KVguMSRQSCtISR4lK1AqNSRY',
    'user',
    true
)
on conflict (auth_user_id) do update
set last_active_church_id = excluded.last_active_church_id,
    line_user_id = excluded.line_user_id,
    display_name = excluded.display_name,
    picture_url = excluded.picture_url,
    global_role = 'user',
    is_active = true,
    deleted_at = null;

update public.users
set last_active_church_id = '81000000-0000-4000-8000-000000000001'
where id = '80000000-0000-4000-8000-000000000001';

insert into public.church_members (
    id, church_id, user_id, status, joined_at, created_by
)
values (
    '82000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    '80000000-0000-4000-8000-000000000001',
    'active',
    now(),
    '80000000-0000-4000-8000-000000000001'
)
on conflict (church_id, user_id) do update
set status = 'active';

insert into public.church_members (
    id, church_id, user_id, status, joined_at, created_by
)
values (
    '82000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000001',
    '54c9f932-8b50-4845-87e8-d949ff99c7b5',
    'active',
    now(),
    '80000000-0000-4000-8000-000000000001'
)
on conflict (church_id, user_id) do update
set status = 'active';

insert into public.organization_unit_types (
    id, church_id, code, name, sort_order,
    default_allow_data_entry, is_active, created_by
)
values
('83000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 'CHURCH', 'คริสตจักร', 10, false, true, '80000000-0000-4000-8000-000000000001'),
('83000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001', 'REGION', 'ภาค', 20, false, true, '80000000-0000-4000-8000-000000000001'),
('83000000-0000-4000-8000-000000000003', '81000000-0000-4000-8000-000000000001', 'DISTRICT', 'เขต', 30, false, true, '80000000-0000-4000-8000-000000000001'),
('83000000-0000-4000-8000-000000000004', '81000000-0000-4000-8000-000000000001', 'GROUP', 'กลุ่ม', 40, true, true, '80000000-0000-4000-8000-000000000001'),
('83000000-0000-4000-8000-000000000005', '81000000-0000-4000-8000-000000000001', 'CARE', 'แคร์', 50, true, true, '80000000-0000-4000-8000-000000000001')
on conflict (church_id, code) do update
set name = excluded.name,
    sort_order = excluded.sort_order,
    default_allow_data_entry = excluded.default_allow_data_entry,
    is_active = true,
    deleted_at = null;

insert into public.organization_units (
    id, church_id, structure_root_id, parent_id, ou_type_id,
    code, name, path, level, sort_order, allow_data_entry, created_by
)
values
('84000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000001', null, '83000000-0000-4000-8000-000000000001', 'ROOT', 'คริสตจักรตัวอย่าง', '/84000000-0000-4000-8000-000000000001', 1, 10, false, '80000000-0000-4000-8000-000000000001'),
('84000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000001', '83000000-0000-4000-8000-000000000002', 'REGION-A', 'ภาคกลาง', '/84000000-0000-4000-8000-000000000001/84000000-0000-4000-8000-000000000002', 2, 10, false, '80000000-0000-4000-8000-000000000001'),
('84000000-0000-4000-8000-000000000003', '81000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000002', '83000000-0000-4000-8000-000000000003', 'DISTRICT-1', 'เขต 1', '/84000000-0000-4000-8000-000000000001/84000000-0000-4000-8000-000000000002/84000000-0000-4000-8000-000000000003', 3, 10, false, '80000000-0000-4000-8000-000000000001'),
('84000000-0000-4000-8000-000000000004', '81000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000003', '83000000-0000-4000-8000-000000000004', 'GROUP-A', 'กลุ่ม A', '/84000000-0000-4000-8000-000000000001/84000000-0000-4000-8000-000000000002/84000000-0000-4000-8000-000000000003/84000000-0000-4000-8000-000000000004', 4, 10, true, '80000000-0000-4000-8000-000000000001'),
('84000000-0000-4000-8000-000000000005', '81000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000003', '83000000-0000-4000-8000-000000000004', 'GROUP-B', 'กลุ่ม B', '/84000000-0000-4000-8000-000000000001/84000000-0000-4000-8000-000000000002/84000000-0000-4000-8000-000000000003/84000000-0000-4000-8000-000000000005', 4, 20, true, '80000000-0000-4000-8000-000000000001')
on conflict (church_id, code) do update
set name = excluded.name,
    is_active = true,
    deleted_at = null;

insert into public.ou_members (
    id, church_id, ou_id, church_member_id, permission, is_active, assigned_by
)
values (
    '85000000-0000-4000-8000-000000000001',
    '81000000-0000-4000-8000-000000000001',
    '84000000-0000-4000-8000-000000000001',
    '82000000-0000-4000-8000-000000000001',
    'admin',
    true,
    '80000000-0000-4000-8000-000000000001'
)
on conflict (church_id, ou_id, church_member_id, permission) do update
set is_active = true, deleted_at = null;

insert into public.ou_members (
    id, church_id, ou_id, church_member_id, permission, is_active, assigned_by
)
values (
    '85000000-0000-4000-8000-000000000002',
    '81000000-0000-4000-8000-000000000001',
    '84000000-0000-4000-8000-000000000001',
    '82000000-0000-4000-8000-000000000002',
    'admin',
    true,
    '80000000-0000-4000-8000-000000000001'
)
on conflict (church_id, ou_id, church_member_id, permission) do update
set is_active = true, deleted_at = null;

insert into public.metric_template_sets (
    id, code, version, name, metric_definitions, created_by
)
values (
    '86000000-0000-4000-8000-000000000001',
    'CSMS_DEFAULT',
    1,
    'CSMS Default Metrics',
    '[
      {"code":"ATTENDANCE","name":"ผู้ใหญ่มาคจ.","category":"attendance","unit":"คน","required":true},
      {"code":"CHILD_ATTENDANCE","name":"เด็กมาคจ.","category":"attendance","unit":"คน"},
      {"code":"ONLINE","name":"ออนไลน์","category":"attendance","unit":"คน"},
      {"code":"PASTOR_ATTENDANCE","name":"ผจ.มาคจ.","category":"attendance","unit":"คน"},
      {"code":"ELDER_ATTENDANCE","name":"ผส.มาคจ.","category":"attendance","unit":"คน"},
      {"code":"CARE_MEETING","name":"แคร์พบปะกัน","category":"care","unit":"คน"},
      {"code":"CARE_ONLINE","name":"แคร์ออนไลน์","category":"care","unit":"คน"},
      {"code":"LUNCH","name":"อาหารกลางวัน","category":"hospitality","unit":"คน"},
      {"code":"SUNDAY_SCHOOL","name":"รวีวารศึกษา","category":"education","unit":"คน"}
    ]'::jsonb,
    '80000000-0000-4000-8000-000000000001'
)
on conflict (code, version) do update
set metric_definitions = excluded.metric_definitions,
    is_active = true;

insert into public.statistic_metrics (
    id, church_id, source_template_set_id, source_template_code,
    code, name, category, unit, aggregation, min_value,
    is_required, sort_order, is_active
)
values
('87000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000001', 'ATTENDANCE', 'ATTENDANCE', 'ผู้ใหญ่มาคจ.', 'attendance', 'คน', 'sum', 0, true, 10, true),
('87000000-0000-4000-8000-000000000008', '81000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000001', 'CHILD_ATTENDANCE', 'CHILD_ATTENDANCE', 'เด็กมาคจ.', 'attendance', 'คน', 'sum', 0, false, 20, true),
('87000000-0000-4000-8000-000000000005', '81000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000001', 'ONLINE', 'ONLINE', 'ออนไลน์', 'attendance', 'คน', 'sum', 0, false, 30, true),
('87000000-0000-4000-8000-000000000009', '81000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000001', 'PASTOR_ATTENDANCE', 'PASTOR_ATTENDANCE', 'ผจ.มาคจ.', 'attendance', 'คน', 'sum', 0, false, 40, true),
('87000000-0000-4000-8000-000000000010', '81000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000001', 'ELDER_ATTENDANCE', 'ELDER_ATTENDANCE', 'ผส.มาคจ.', 'attendance', 'คน', 'sum', 0, false, 50, true),
('87000000-0000-4000-8000-000000000011', '81000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000001', 'CARE_MEETING', 'CARE_MEETING', 'แคร์พบปะกัน', 'care', 'คน', 'sum', 0, false, 60, true),
('87000000-0000-4000-8000-000000000012', '81000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000001', 'CARE_ONLINE', 'CARE_ONLINE', 'แคร์ออนไลน์', 'care', 'คน', 'sum', 0, false, 70, true),
('87000000-0000-4000-8000-000000000013', '81000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000001', 'LUNCH', 'LUNCH', 'อาหารกลางวัน', 'hospitality', 'คน', 'sum', 0, false, 80, true),
('87000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001', '86000000-0000-4000-8000-000000000001', 'SUNDAY_SCHOOL', 'SUNDAY_SCHOOL', 'รวีวารศึกษา', 'education', 'คน', 'sum', 0, false, 90, true)
on conflict (church_id, code) do update
set name = excluded.name, category = excluded.category, unit = excluded.unit,
    min_value = excluded.min_value, is_required = excluded.is_required,
    sort_order = excluded.sort_order, is_active = true, deleted_at = null;

update public.statistic_metrics
set is_active = false
where church_id = '81000000-0000-4000-8000-000000000001'
  and source_template_set_id = '86000000-0000-4000-8000-000000000001'
  and code not in (
      'ATTENDANCE', 'CHILD_ATTENDANCE', 'ONLINE', 'PASTOR_ATTENDANCE',
      'ELDER_ATTENDANCE', 'CARE_MEETING', 'CARE_ONLINE', 'LUNCH',
      'SUNDAY_SCHOOL'
  );

update public.churches
set primary_metric_id = '87000000-0000-4000-8000-000000000001'
where id = '81000000-0000-4000-8000-000000000001';

insert into public.statistic_periods (
    id, church_id, year, week_no, period_start, period_end, label, status
)
values
('88000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', 2026, 29, '2026-07-13', '2026-07-19', '2026-W29', 'open'),
('88000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001', 2026, 30, '2026-07-20', '2026-07-26', '2026-W30', 'open')
on conflict (church_id, period_start) do update
set status = excluded.status, label = excluded.label;

insert into public.statistic_submissions (
    id, church_id, period_id, ou_id, status, submitted_by,
    submitted_at, approved_by, approved_at, revision_no, remarks
)
values
('89000000-0000-4000-8000-000000000001', '81000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000001', '84000000-0000-4000-8000-000000000004', 'approved', '80000000-0000-4000-8000-000000000001', now(), '80000000-0000-4000-8000-000000000001', now(), 1, 'ข้อมูลตัวอย่างสัปดาห์ก่อน'),
('89000000-0000-4000-8000-000000000002', '81000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002', '84000000-0000-4000-8000-000000000004', 'approved', '80000000-0000-4000-8000-000000000001', now(), '80000000-0000-4000-8000-000000000001', now(), 1, 'ข้อมูลตัวอย่างสัปดาห์ปัจจุบัน'),
('89000000-0000-4000-8000-000000000003', '81000000-0000-4000-8000-000000000001', '88000000-0000-4000-8000-000000000002', '84000000-0000-4000-8000-000000000005', 'approved', '80000000-0000-4000-8000-000000000001', now(), '80000000-0000-4000-8000-000000000001', now(), 1, 'ข้อมูลตัวอย่างกลุ่ม B')
on conflict (church_id, period_id, ou_id) do nothing;

insert into public.statistic_values (
    church_id, submission_id, metric_id, numeric_value
)
values
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000001', 90),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000008', 20),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000005', 12),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000009', 1),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000010', 3),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000011', 40),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000012', 8),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000013', 75),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000001', '87000000-0000-4000-8000-000000000002', 25),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000001', 100),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000008', 24),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000005', 18),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000009', 1),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000010', 4),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000011', 45),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000012', 10),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000013', 82),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000002', '87000000-0000-4000-8000-000000000002', 30),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000001', 75),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000008', 15),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000005', 10),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000009', 1),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000010', 2),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000011', 35),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000012', 6),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000013', 60),
('81000000-0000-4000-8000-000000000001', '89000000-0000-4000-8000-000000000003', '87000000-0000-4000-8000-000000000002', 20)
on conflict (church_id, submission_id, metric_id) do update
set numeric_value = excluded.numeric_value,
    text_value = null,
    boolean_value = null;

commit;
