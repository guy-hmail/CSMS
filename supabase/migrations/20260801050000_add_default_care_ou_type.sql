-- Keep the existing tenant provisioning implementation intact and extend it
-- with the CARE OU type. Existing tenants are intentionally not modified;
-- this default applies to tenants created after this migration.

alter function public.create_platform_tenant(jsonb)
rename to create_platform_tenant_base;

revoke all on function public.create_platform_tenant_base(jsonb) from public;
revoke all on function public.create_platform_tenant_base(jsonb) from authenticated;

create or replace function public.create_platform_tenant(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
    actor_user_id uuid;
    tenant_id uuid;
begin
    actor_user_id := app_security.require_system_admin();
    tenant_id := public.create_platform_tenant_base(payload);

    insert into public.organization_unit_types (
        id, church_id, code, name, sort_order,
        default_allow_data_entry, is_active, created_by
    )
    values (
        gen_random_uuid(), tenant_id, 'CARE', 'แคร์', 50,
        true, true, actor_user_id
    );

    return tenant_id;
end;
$$;

revoke all on function public.create_platform_tenant(jsonb) from public;
grant execute on function public.create_platform_tenant(jsonb) to authenticated;
