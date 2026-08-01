-- BE-002: Row Level Security and permission helpers.
-- Source of truth: doc/03_RLS_and_Permissions.md.
-- Authorized mutation RPCs are implemented in BE-004 through BE-007.

create schema if not exists app_security;

revoke all on schema app_security from public;
grant usage on schema app_security to authenticated;

create or replace function app_security.jwt_subject()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select coalesce(
        auth.uid(),
        nullif(
            nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub',
            ''
        )::uuid
    );
$$;

create or replace function app_security.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select app_user.id
    from public.users as app_user
    where app_user.auth_user_id = app_security.jwt_subject()
      and app_user.is_active = true
      and app_user.deleted_at is null
    limit 1;
$$;

create or replace function app_security.current_church_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select membership.church_id
    from public.users as app_user
    join public.church_members as membership
      on membership.user_id = app_user.id
    where app_user.auth_user_id = app_security.jwt_subject()
      and app_user.is_active = true
      and app_user.deleted_at is null
      and membership.status = 'active'
      and membership.church_id = nullif(
          nullif(
              current_setting('request.jwt.claims', true),
              ''
          )::jsonb -> 'app_metadata' ->> 'active_church_id',
          ''
      )::uuid
    limit 1;
$$;

create or replace function app_security.current_church_member_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
    select membership.id
    from public.church_members as membership
    join public.users as app_user
      on app_user.id = membership.user_id
    where app_user.auth_user_id = app_security.jwt_subject()
      and membership.church_id = app_security.current_church_id()
      and membership.status = 'active'
      and app_user.is_active = true
      and app_user.deleted_at is null
    limit 1;
$$;

create or replace function app_security.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.users as app_user
        where app_user.auth_user_id = app_security.jwt_subject()
          and app_user.global_role = 'system_admin'
          and app_user.is_active = true
          and app_user.deleted_at is null
    );
$$;

create or replace function app_security.has_permission_on_ou(
    target_ou_id uuid,
    required_permissions text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.organization_units as target_ou
        join public.ou_members as assignment
          on assignment.ou_id = target_ou.id
         and assignment.church_id = target_ou.church_id
        join public.church_members as membership
          on membership.id = assignment.church_member_id
         and membership.church_id = target_ou.church_id
        join public.users as app_user
          on app_user.id = membership.user_id
        where target_ou.id = target_ou_id
          and target_ou.church_id = app_security.current_church_id()
          and target_ou.is_active = true
          and target_ou.deleted_at is null
          and membership.status = 'active'
          and app_user.auth_user_id = app_security.jwt_subject()
          and app_user.is_active = true
          and app_user.deleted_at is null
          and assignment.permission = any(required_permissions)
          and assignment.is_active = true
          and assignment.deleted_at is null
    );
$$;

create or replace function app_security.has_subtree_permission(
    target_ou_id uuid,
    required_permissions text[]
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select exists (
        select 1
        from public.organization_units as target_ou
        join public.organization_units as assigned_ou
          on target_ou.church_id = assigned_ou.church_id
         and target_ou.structure_root_id = assigned_ou.structure_root_id
         and (
             target_ou.path = assigned_ou.path
             or target_ou.path like assigned_ou.path || '/%'
         )
        join public.ou_members as assignment
          on assignment.ou_id = assigned_ou.id
         and assignment.church_id = assigned_ou.church_id
        join public.church_members as membership
          on membership.id = assignment.church_member_id
         and membership.church_id = assignment.church_id
        join public.users as app_user
          on app_user.id = membership.user_id
        where target_ou.id = target_ou_id
          and target_ou.church_id = app_security.current_church_id()
          and target_ou.is_active = true
          and target_ou.deleted_at is null
          and assigned_ou.is_active = true
          and assigned_ou.deleted_at is null
          and membership.status = 'active'
          and app_user.auth_user_id = app_security.jwt_subject()
          and app_user.is_active = true
          and app_user.deleted_at is null
          and assignment.permission = any(required_permissions)
          and assignment.is_active = true
          and assignment.deleted_at is null
    );
$$;

create or replace function app_security.can_view_ou(target_ou_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        app_security.has_subtree_permission(
            target_ou_id,
            array['admin', 'manager', 'approver', 'viewer']
        )
        or app_security.has_permission_on_ou(
            target_ou_id,
            array['data_entry']
        );
$$;

create or replace function app_security.can_manage_ou(target_ou_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select app_security.has_subtree_permission(
        target_ou_id,
        array['admin', 'manager']
    );
$$;

create or replace function app_security.can_submit_for_ou(target_ou_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        app_security.has_permission_on_ou(
            target_ou_id,
            array['data_entry']
        )
        or app_security.has_subtree_permission(
            target_ou_id,
            array['admin', 'manager']
        );
$$;

create or replace function app_security.can_approve_for_ou(target_ou_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select app_security.has_subtree_permission(
        target_ou_id,
        array['admin', 'approver']
    );
$$;

create or replace function app_security.can_view_audit_log(
    target_church_id uuid,
    target_ou_id uuid,
    target_entity_type text,
    target_action text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
    select
        target_church_id = app_security.current_church_id()
        and not app_security.is_system_admin()
        and (
            exists (
                select 1
                from public.organization_units as root_ou
                join public.ou_members as assignment
                  on assignment.church_id = root_ou.church_id
                 and assignment.ou_id = root_ou.id
                join public.church_members as membership
                  on membership.church_id = assignment.church_id
                 and membership.id = assignment.church_member_id
                join public.users as app_user
                  on app_user.id = membership.user_id
                where root_ou.church_id = target_church_id
                  and root_ou.parent_id is null
                  and root_ou.level = 1
                  and root_ou.is_active = true
                  and root_ou.deleted_at is null
                  and assignment.permission = 'admin'
                  and assignment.is_active = true
                  and assignment.deleted_at is null
                  and membership.status = 'active'
                  and app_user.auth_user_id = app_security.jwt_subject()
                  and app_user.is_active = true
                  and app_user.deleted_at is null
            )
            or (
                target_ou_id is not null
                and (
                    app_security.has_subtree_permission(
                        target_ou_id,
                        array['admin']
                    )
                    or (
                        app_security.has_subtree_permission(
                            target_ou_id,
                            array['manager']
                        )
                        and target_entity_type = any(array[
                            'organization_units',
                            'ou_members',
                            'statistic_submissions',
                            'statistic_values'
                        ])
                    )
                    or (
                        app_security.has_subtree_permission(
                            target_ou_id,
                            array['approver']
                        )
                        and target_entity_type = any(array[
                            'statistic_submissions',
                            'approval_logs'
                        ])
                        and target_action = any(array[
                            'approve',
                            'reject',
                            'return_draft',
                            'override_approve'
                        ])
                    )
                )
            )
        );
$$;

revoke all on all functions in schema app_security from public;
grant execute on all functions in schema app_security to authenticated;

alter table public.churches enable row level security;
alter table public.users enable row level security;
alter table public.church_members enable row level security;
alter table public.tenant_invitations enable row level security;
alter table public.user_preferences enable row level security;
alter table public.organization_unit_types enable row level security;
alter table public.organization_units enable row level security;
alter table public.ou_members enable row level security;
alter table public.statistic_periods enable row level security;
alter table public.metric_template_sets enable row level security;
alter table public.statistic_metrics enable row level security;
alter table public.statistic_submissions enable row level security;
alter table public.statistic_values enable row level security;
alter table public.submission_revisions enable row level security;
alter table public.api_idempotency_keys enable row level security;
alter table public.approval_logs enable row level security;
alter table public.audit_logs enable row level security;

alter table public.churches force row level security;
alter table public.users force row level security;
alter table public.church_members force row level security;
alter table public.tenant_invitations force row level security;
alter table public.user_preferences force row level security;
alter table public.organization_unit_types force row level security;
alter table public.organization_units force row level security;
alter table public.ou_members force row level security;
alter table public.statistic_periods force row level security;
alter table public.metric_template_sets force row level security;
alter table public.statistic_metrics force row level security;
alter table public.statistic_submissions force row level security;
alter table public.statistic_values force row level security;
alter table public.submission_revisions force row level security;
alter table public.api_idempotency_keys force row level security;
alter table public.approval_logs force row level security;
alter table public.audit_logs force row level security;

create policy churches_select_policy
on public.churches
for select
to authenticated
using (id = app_security.current_church_id());

create policy churches_insert_policy
on public.churches
for insert
to authenticated
with check (false);

create policy churches_update_policy
on public.churches
for update
to authenticated
using (false)
with check (false);

create policy churches_delete_policy
on public.churches
for delete
to authenticated
using (false);

create policy users_select_policy
on public.users
for select
to authenticated
using (id = app_security.current_user_id());

create policy users_insert_policy
on public.users
for insert
to authenticated
with check (false);

create policy users_update_policy
on public.users
for update
to authenticated
using (false)
with check (false);

create policy users_delete_policy
on public.users
for delete
to authenticated
using (false);

create policy church_members_select_policy
on public.church_members
for select
to authenticated
using (
    church_id = app_security.current_church_id()
    and user_id = app_security.current_user_id()
);

create policy church_members_insert_policy
on public.church_members
for insert
to authenticated
with check (false);

create policy church_members_update_policy
on public.church_members
for update
to authenticated
using (false)
with check (false);

create policy church_members_delete_policy
on public.church_members
for delete
to authenticated
using (false);

create policy tenant_invitations_select_policy
on public.tenant_invitations
for select
to authenticated
using (false);

create policy tenant_invitations_insert_policy
on public.tenant_invitations
for insert
to authenticated
with check (false);

create policy tenant_invitations_update_policy
on public.tenant_invitations
for update
to authenticated
using (false)
with check (false);

create policy tenant_invitations_delete_policy
on public.tenant_invitations
for delete
to authenticated
using (false);

create policy user_preferences_select_policy
on public.user_preferences
for select
to authenticated
using (
    church_id = app_security.current_church_id()
    and church_member_id = app_security.current_church_member_id()
);

create policy user_preferences_insert_policy
on public.user_preferences
for insert
to authenticated
with check (false);

create policy user_preferences_update_policy
on public.user_preferences
for update
to authenticated
using (false)
with check (false);

create policy user_preferences_delete_policy
on public.user_preferences
for delete
to authenticated
using (false);

create policy ou_types_select_policy
on public.organization_unit_types
for select
to authenticated
using (church_id = app_security.current_church_id());

create policy ou_types_insert_policy
on public.organization_unit_types
for insert
to authenticated
with check (false);

create policy ou_types_update_policy
on public.organization_unit_types
for update
to authenticated
using (false)
with check (false);

create policy ou_types_delete_policy
on public.organization_unit_types
for delete
to authenticated
using (false);

create policy ou_select_policy
on public.organization_units
for select
to authenticated
using (app_security.can_view_ou(id));

create policy ou_insert_policy
on public.organization_units
for insert
to authenticated
with check (false);

create policy ou_update_policy
on public.organization_units
for update
to authenticated
using (false)
with check (false);

create policy ou_delete_policy
on public.organization_units
for delete
to authenticated
using (false);

create policy ou_members_select_policy
on public.ou_members
for select
to authenticated
using (app_security.can_view_ou(ou_id));

create policy ou_members_insert_policy
on public.ou_members
for insert
to authenticated
with check (false);

create policy ou_members_update_policy
on public.ou_members
for update
to authenticated
using (false)
with check (false);

create policy ou_members_delete_policy
on public.ou_members
for delete
to authenticated
using (false);

create policy periods_select_policy
on public.statistic_periods
for select
to authenticated
using (church_id = app_security.current_church_id());

create policy periods_insert_policy
on public.statistic_periods
for insert
to authenticated
with check (false);

create policy periods_update_policy
on public.statistic_periods
for update
to authenticated
using (false)
with check (false);

create policy periods_delete_policy
on public.statistic_periods
for delete
to authenticated
using (false);

-- metric_template_sets intentionally has no authenticated-client policy.

create policy metrics_select_policy
on public.statistic_metrics
for select
to authenticated
using (church_id = app_security.current_church_id());

create policy metrics_insert_policy
on public.statistic_metrics
for insert
to authenticated
with check (false);

create policy metrics_update_policy
on public.statistic_metrics
for update
to authenticated
using (false)
with check (false);

create policy metrics_delete_policy
on public.statistic_metrics
for delete
to authenticated
using (false);

create policy submissions_select_policy
on public.statistic_submissions
for select
to authenticated
using (app_security.can_view_ou(ou_id));

create policy submissions_insert_policy
on public.statistic_submissions
for insert
to authenticated
with check (false);

create policy submissions_update_policy
on public.statistic_submissions
for update
to authenticated
using (false)
with check (false);

create policy submissions_delete_policy
on public.statistic_submissions
for delete
to authenticated
using (false);

create policy statistic_values_select_policy
on public.statistic_values
for select
to authenticated
using (
    exists (
        select 1
        from public.statistic_submissions as submission
        where submission.id = statistic_values.submission_id
          and submission.church_id = statistic_values.church_id
          and app_security.can_view_ou(submission.ou_id)
    )
);

create policy statistic_values_insert_policy
on public.statistic_values
for insert
to authenticated
with check (false);

create policy statistic_values_update_policy
on public.statistic_values
for update
to authenticated
using (false)
with check (false);

create policy statistic_values_delete_policy
on public.statistic_values
for delete
to authenticated
using (false);

-- submission_revisions intentionally has no authenticated-client policy.
-- api_idempotency_keys intentionally has no authenticated-client policy.

create policy approval_logs_select_policy
on public.approval_logs
for select
to authenticated
using (
    exists (
        select 1
        from public.statistic_submissions as submission
        where submission.id = approval_logs.submission_id
          and submission.church_id = approval_logs.church_id
          and app_security.can_view_ou(submission.ou_id)
    )
);

create policy approval_logs_insert_policy
on public.approval_logs
for insert
to authenticated
with check (false);

create policy approval_logs_update_policy
on public.approval_logs
for update
to authenticated
using (false)
with check (false);

create policy approval_logs_delete_policy
on public.approval_logs
for delete
to authenticated
using (false);

create policy audit_logs_select_policy
on public.audit_logs
for select
to authenticated
using (
    app_security.can_view_audit_log(
        church_id,
        ou_id,
        entity_type,
        action
    )
);

create policy audit_logs_insert_policy
on public.audit_logs
for insert
to authenticated
with check (false);

create policy audit_logs_update_policy
on public.audit_logs
for update
to authenticated
using (false)
with check (false);

create policy audit_logs_delete_policy
on public.audit_logs
for delete
to authenticated
using (false);
