\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin if condition is not true then raise exception 'BE-021 assertion: %', message; end if; end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', '80000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"80000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"active_church_id":"81000000-0000-4000-8000-000000000001"}}', true);

select pg_temp.assert_true(
  (public.get_platform_tenant_detail('81000000-0000-4000-8000-000000000001') #>> '{provisioning,ready}')::boolean,
  'detail exposes a ready provisioning state'
);

select public.update_platform_tenant('81000000-0000-4000-8000-000000000001', jsonb_build_object(
  'name', 'Tenant Task 8', 'slug', 'tenant-task-8', 'description', 'control plane test',
  'timezone', 'Asia/Bangkok', 'approvalMode', 'approval_required', 'weekEndsOn', 'saturday',
  'submissionDeadlineDaysAfterPeriodEnd', 2
));
select pg_temp.assert_true(
  (public.get_platform_tenant_detail('81000000-0000-4000-8000-000000000001') #>> '{name}') = 'Tenant Task 8'
  and (public.get_platform_tenant_detail('81000000-0000-4000-8000-000000000001') #>> '{weekEndsOn}') = 'saturday'
  and (public.get_platform_tenant_detail('81000000-0000-4000-8000-000000000001') #>> '{submissionDeadlineDaysAfterPeriodEnd}') = '2',
  'tenant detail/update round-trips configuration'
);

create temporary table issued as select public.create_platform_admin_invite_link('81000000-0000-4000-8000-000000000001', 7) result;
select pg_temp.assert_true(
  exists(select 1 from public.list_platform_tenant_invitations('81000000-0000-4000-8000-000000000001') where status = 'pending'),
  'platform invitation list returns pending invite'
);
select public.revoke_platform_tenant_invitation(
  '81000000-0000-4000-8000-000000000001', (select (result ->> 'invitationId')::uuid from issued)
);
select pg_temp.assert_true(
  exists(select 1 from public.list_platform_tenant_invitations('81000000-0000-4000-8000-000000000001') where status = 'revoked'),
  'platform invite can be revoked'
);

select public.set_platform_tenant_status('81000000-0000-4000-8000-000000000001', 'suspended');
select pg_temp.assert_true(app_security.current_church_id() is null, 'suspended tenant is rejected by the central RPC/RLS scope');
select pg_temp.assert_true((select count(*) = 0 from public.organization_units), 'RLS hides tenant rows while suspended');
do $$ begin
  begin perform public.get_accessible_ou_tree(); raise exception 'tenant RPC remained usable while suspended';
  exception when raise_exception then
    if sqlerrm <> 'TENANT_CONTEXT_REQUIRED' then raise; end if;
  end;
end $$;

select public.set_platform_tenant_status('81000000-0000-4000-8000-000000000001', 'active');
select pg_temp.assert_true(app_security.current_church_id() = '81000000-0000-4000-8000-000000000001', 'reactivation restores tenant scope');

select pg_temp.assert_true(
  exists(select 1 from public.list_platform_tenant_activity('81000000-0000-4000-8000-000000000001', 100) where action = 'update_platform_tenant')
  and exists(select 1 from public.list_platform_tenant_activity('81000000-0000-4000-8000-000000000001', 100) where action = 'revoke_platform_tenant_invitation')
  and (select count(*) >= 2 from public.list_platform_tenant_activity('81000000-0000-4000-8000-000000000001', 100) where action = 'update_tenant_status'),
  'all Task 8 platform mutations are searchable in audit activity'
);

select public.set_platform_tenant_status('81000000-0000-4000-8000-000000000001', 'closed');
select pg_temp.assert_true(
  (public.get_platform_tenant_detail('81000000-0000-4000-8000-000000000001') #>> '{status}') = 'closed',
  'closed lifecycle retains tenant data without hard delete'
);
do $$ begin
  begin perform public.set_platform_tenant_status('81000000-0000-4000-8000-000000000001', 'active'); raise exception 'closed tenant was reopened';
  exception when object_not_in_prerequisite_state then
    if sqlerrm <> 'TENANT_CLOSED' then raise; end if;
  end;
end $$;

reset role;
insert into public.users(id, auth_user_id, line_user_id, display_name, global_role)
values ('10000000-0000-0000-0000-000000000121', 'a1000000-0000-4000-8000-000000000121', 'task8-user', 'Task 8 User', 'user');
set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000121', true);
select set_config('request.jwt.claims', '{"sub":"a1000000-0000-4000-8000-000000000121","role":"authenticated"}', true);
do $$ begin
  begin perform public.get_platform_tenant_detail('81000000-0000-4000-8000-000000000001'); raise exception 'non-admin read control plane';
  exception when insufficient_privilege then if sqlerrm <> 'SYSTEM_ADMIN_REQUIRED' then raise; end if; end;
end $$;

reset role;
select 'ok 1 - BE-021 Task 8 Super Admin tenant detail, lifecycle, permission and audit';
rollback;
