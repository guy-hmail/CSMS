-- Production reference data must not depend on the optional demo seed.
-- A null creator identifies a platform-owned template installed by migration.

alter table public.metric_template_sets
    alter column created_by drop not null;

comment on column public.metric_template_sets.created_by is
    'User who created the template; null for platform-owned templates installed by migration.';

insert into public.metric_template_sets (
    id,
    code,
    version,
    name,
    metric_definitions,
    is_active,
    created_by
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
    true,
    null
)
on conflict (code, version) do update
set name = excluded.name,
    metric_definitions = excluded.metric_definitions,
    is_active = true;
