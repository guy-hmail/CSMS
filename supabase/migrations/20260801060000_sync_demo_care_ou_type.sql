-- Keep an already-running local demo database in sync with seed.sql without
-- changing non-demo tenants. On a clean reset seed.sql creates this row.

insert into public.organization_unit_types (
    id, church_id, code, name, sort_order,
    default_allow_data_entry, is_active, created_by
)
select
    '83000000-0000-4000-8000-000000000005',
    church.id,
    'CARE',
    'แคร์',
    50,
    true,
    true,
    '80000000-0000-4000-8000-000000000001'
from public.churches as church
where church.id = '81000000-0000-4000-8000-000000000001'
  and exists (
      select 1
      from public.users as creator
      where creator.id = '80000000-0000-4000-8000-000000000001'
  )
on conflict (church_id, code) do update
set name = excluded.name,
    sort_order = excluded.sort_order,
    default_allow_data_entry = excluded.default_allow_data_entry,
    is_active = true,
    deleted_at = null,
    deleted_by = null;
