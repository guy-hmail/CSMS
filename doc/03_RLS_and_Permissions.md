# Church Statistics Management System (CSMS)
## Row Level Security and Permissions Specification

Version: 1.0  
Status: Production Blueprint  
Target Platform: Supabase PostgreSQL  
Frontend: SvelteKit + LINE LIFF  
Architecture Style: Multi-Tenant SaaS, Database-First Security, OU-Based Authorization

---

# 1. Document Purpose

This document defines the Row Level Security (RLS), permission model, authorization rules, and security functions for the Church Statistics Management System (CSMS).

This document is the authoritative reference for:

- Supabase Row Level Security
- Organization Unit permission model
- Multi-tenant data isolation
- User access control
- Submission authorization
- Approval authorization
- Dashboard and report visibility
- Security helper functions
- RPC authorization rules

This document must be followed when implementing database policies, RPC functions, Edge Functions, and frontend access behavior.

---

# 2. Security Principles

CSMS follows database-first security.

The frontend must never be trusted to decide authorization.

Core principles:

1. Every tenant-owned table must be filtered by `church_id`.
2. Every business table must have Row Level Security enabled.
3. Users can only access Organization Units within their permitted subtree.
4. Permissions are assigned per Organization Unit through `ou_members`.
5. Position titles such as Pastor, Leader, Elder, or Staff are informational only.
6. Critical workflows must be executed through PostgreSQL RPC or trusted Edge Functions.
7. RLS must protect direct client-side Supabase access.
8. RPC functions must still validate permission internally.
9. Audit logs must be written for critical actions.
10. Service role key must never be exposed to the frontend.

---

# 3. Authorization Architecture

```text
LINE LIFF Login
      │
      ▼
Supabase Auth User
      │
      ▼
users table
      │
      ▼
ou_members
      │
      ▼
Permission on Organization Unit
      │
      ▼
Subtree Access
      │
      ▼
RLS Policies + RPC Validation
```

---

# 4. Authentication Model

## 4.1 LINE LIFF Authentication

Users authenticate through LINE LIFF.

After login, the system synchronizes the LINE profile to the `users` table.

The application must map the authenticated Supabase user to an internal CSMS user record.

Recommended mapping:

```text
Supabase auth.uid()
        ↓
users.auth_user_id or users.line_user_id mapping
        ↓
users.id
```

## 4.2 Recommended Database Adjustment

The current database design stores `line_user_id`, but RLS works best when there is a direct link to Supabase Auth.

Recommended additional field:

```sql
alter table users add column auth_user_id uuid unique;
```

Reason:

- `auth.uid()` returns Supabase Auth user ID.
- RLS policies can directly identify the current user.
- Avoids relying on frontend-provided user IDs.

If this field is not added, every RLS function must resolve the user indirectly from JWT claims.

Recommended decision:

```text
Add users.auth_user_id uuid unique before implementing RLS.
```

---

## 4.3 Validated Tenant Context

The authenticated user may have multiple tenant memberships:

```text
auth.uid() -> users.auth_user_id -> active church_members -> selected church_id
```

- `users.church_id` must not be used as authorization; users are global identities.
- `current_church_id()` may return only a church with an active membership for the current user.
- Tenant IDs from routes, request bodies, headers, or client stores are untrusted until validated.
- `ou_members` references a `church_member_id` from the same tenant as the target OU.
- Every cross-table write rejects tenant mismatches, even when all UUIDs exist.
- Tenant switching invalidates tenant-scoped caches and triggers fresh permission evaluation.
- System administrator bypass uses a separate audited policy or service path.

---
# 5. Permission Model

Permissions are assigned per Organization Unit using `ou_members`.

A user may have multiple permissions in different Organization Units.

Example:

| User | Organization Unit | Permission |
|---|---|---|
| John | Group A | data_entry |
| John | District 1 | viewer |
| Peter | District 1 | approver |
| David | Church Root | admin |

---

# 6. Permission Types

| Permission | Scope | Description |
|---|---|---|
| `admin` | Assigned OU subtree | Full access within assigned OU and descendants |
| `manager` | Assigned OU subtree | Manage assigned OU and child OUs |
| `data_entry` | Assigned OU | Submit statistics for assigned OU |
| `approver` | Assigned OU subtree | Approve submissions from assigned OU and descendants |
| `viewer` | Assigned OU subtree | Read-only access |

---

# 7. Permission Inheritance

## 7.1 Subtree Permissions

The following permissions apply to the assigned OU and all descendant OUs:

- `admin`
- `manager`
- `approver`
- `viewer`

Example:

```text
Church Root  ← user has manager
│
├── Region A
│   └── District A
│       └── Group A
└── Region B
```

The user can manage Church Root, Region A, District A, Group A, and Region B.

## 7.2 Direct OU Permission

The following permission applies only to the assigned OU unless explicitly assigned elsewhere:

- `data_entry`

Reason:

Data entry should normally be controlled at the actual reporting OU to prevent accidental submission for the wrong OU.

Exception:

`admin` and `manager` may submit on behalf of descendant OUs if the workflow allows it.

## 7.3 Inherited OU Administration for Parent Managers

An active direct `manager` assignment on an OU grants effective OU-administration capabilities on all descendant OUs.

This is capability inheritance, not role duplication:

```text
Direct manager on Parent OU
    ↓
Effective OU administration on descendants
    ↓
No additional admin rows in ou_members
```

Inherited OU administration permits:

- create, edit, and deactivate descendant OUs
- assign or remove LINE accounts within descendants
- assign `manager`, `data_entry`, `approver`, and `viewer` within descendants

Inherited OU administration does not permit:

- assigning `admin`
- granting `can_override`
- approval, rejection, or workflow override unless separately assigned
- managing OU Type Setting or organization-wide settings
- modifying ancestors, the source manager assignment, or OUs outside the subtree

Permission checks must derive this capability from the target OU ancestry and the active source `ou_members` manager assignment. Revoking the source assignment or moving an OU must change effective access immediately.

Audit records for inherited administration must include the source assignment or source OU that granted access.

---

# 8. Permission Matrix

| Action | admin | manager | approver | data_entry | viewer |
|---|---:|---:|---:|---:|---:|
| View assigned OU | Yes | Yes | Yes | Yes | Yes |
| View descendant OU | Yes | Yes | Yes | No | Yes |
| Create child OU | Yes | Yes | No | No | No |
| Edit OU | Yes | Yes | No | No | No |
| Soft delete OU | Yes | Yes | No | No | No |
| Assign users | Yes | Yes | No | No | No |
| View submissions | Yes | Yes | Yes | Own/Assigned OU | Yes |
| Create draft submission | Yes | Yes | No | Yes | No |
| Edit draft submission | Yes | Yes | No | Yes | No |
| Submit statistics | Yes | Yes | No | Yes | No |
| Approve submission | Yes | No | Yes | No | No |
| Reject submission | Yes | No | Yes | No | No |
| Return to draft | Yes | No | Yes | No | No |
| Override approval | Yes | No | Conditional (`can_override`) | No | No |
| View dashboard | Yes | Yes | Yes | Assigned OU | Yes |
| Export reports | Yes | Yes | Yes | Assigned OU | Yes |
| View audit logs | Yes | Limited | Limited | No | No |

---

# 9. Tenant Isolation Rules

## 9.1 Tenant Boundary

A user can access data only if:

```text
active church_members.church_id = target_table.church_id
```

Platform system administrators do not bypass tenant RLS through the normal application client. They use a separately authorized service path whose reads and writes are explicitly scoped and audited.

## 9.2 System Administrator

A system administrator has:

```text
users.global_role = 'system_admin'
```

`global_role` is the persisted field. `app_security.is_system_admin()` is a helper function derived from that field, not a boolean column on `users`.

System administrator access is used only for platform-level maintenance through trusted Edge Functions/backend services. `app_security.is_system_admin()` may authorize entry to that service path, but tenant RLS policies and tenant permission helpers must not use it as a blanket bypass. System administrator actions must be logged.

---

# 10. Organization Subtree Access

A user has access to an OU if:

1. The OU is directly assigned to the user in `ou_members`, or
2. The OU is a descendant of an assigned OU with an inheritable permission.

Recommended subtree check uses `organization_units.path`.

Example logic:

```text
Target OU path starts with Assigned OU path
```
## 10.1 Organization Tree Visibility

The Organization Tree query must return only OUs authorized by the current user's active `ou_members` assignments.

1. A directly assigned OU is a visible tree root.
2. Descendants are included only when the assigned permission is inheritable.
3. Ancestors above an assigned OU, siblings, and unrelated branches are excluded.
4. Multiple assignments produce the union of authorized subtrees and duplicate OU rows must be removed.
5. `data_entry` exposes only the directly assigned OU unless another assignment grants subtree access.
6. `admin` remains scoped to the assigned OU subtree. Tenant-wide tree visibility requires assignment on the church root OU; system administrators follow separately audited platform rules.
7. Search, lazy loading, counts, OU selectors, member assignment, and child creation must all use the same authorized OU dataset.
8. Filtering must be enforced by RLS or a permission-validating RPC before data reaches the frontend.

The frontend must never fetch the complete tenant OU tree and rely on client-side hiding as the security boundary.

---

# 11. Security Helper Functions

Security helper functions should be placed in a dedicated schema.

Recommended schema:

```sql
create schema if not exists app_security;
```

Important:

Use `security definer` carefully.
Always set `search_path`.
Do not expose unnecessary functions to public users.

---

# 12. Current User Helper

## 12.1 `current_user_id()`

Returns the internal CSMS user ID of the currently authenticated user.

```sql
create or replace function app_security.current_user_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select u.id
    from users u
    where u.auth_user_id = auth.uid()
      and u.is_active = true
      and u.deleted_at is null
    limit 1;
$$;
```

## 12.2 `current_church_id()`

Returns the server-selected tenant only when the current user has an active membership. `active_church_id` is a server-managed Supabase Auth `app_metadata` claim; tenant switching must update the claim through a trusted RPC/Edge Function and refresh the session.

```sql
create or replace function app_security.current_church_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select cm.church_id
    from users u
    join church_members cm on cm.user_id = u.id
    where u.auth_user_id = auth.uid()
      and u.is_active = true
      and u.deleted_at is null
      and cm.status = 'active'
      and cm.church_id = nullif(auth.jwt() -> 'app_metadata' ->> 'active_church_id', '')::uuid
    limit 1;
$$;
```
## 12.2A `current_church_member_id()`

Returns the active membership for the validated current tenant.

```sql
create or replace function app_security.current_church_member_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
    select cm.id
    from church_members cm
    join users u on u.id = cm.user_id
    where u.auth_user_id = auth.uid()
      and cm.church_id = app_security.current_church_id()
      and cm.status = 'active'
    limit 1;
$$;
```

## 12.3 `is_system_admin()`

```sql
create or replace function app_security.is_system_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
        select 1
        from users u
        where u.auth_user_id = auth.uid()
          and u.global_role = 'system_admin'
          and u.is_active = true
          and u.deleted_at is null
    );
$$;
```

---

# 13. Permission Helper Functions

## 13.1 `has_permission_on_ou()`

Checks whether an active tenant member has a direct permission on an OU in the selected tenant.

```sql
create or replace function app_security.has_permission_on_ou(
    target_ou_id uuid,
    required_permissions text[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
            select 1
            from organization_units target_ou
            join ou_members om on om.ou_id = target_ou.id
            join church_members cm on cm.id = om.church_member_id
            join users u on u.id = cm.user_id
            where target_ou.id = target_ou_id
              and target_ou.church_id = app_security.current_church_id()
              and om.church_id = target_ou.church_id
              and cm.church_id = target_ou.church_id
              and cm.status = 'active'
              and u.auth_user_id = auth.uid()
              and u.is_active = true
              and u.deleted_at is null
              and om.permission = any(required_permissions)
              and om.is_active = true
              and om.deleted_at is null
        );
$$;
```
## 13.2 `has_subtree_permission()`

Checks whether an active tenant member has an inheritable permission on the target OU or an ancestor within the same tenant root.

```sql
create or replace function app_security.has_subtree_permission(
    target_ou_id uuid,
    required_permissions text[]
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select exists (
            select 1
            from organization_units target_ou
            join organization_units assigned_ou
              on target_ou.path like assigned_ou.path || '%'
             and target_ou.church_id = assigned_ou.church_id
             and target_ou.structure_root_id = assigned_ou.structure_root_id
            join ou_members om on om.ou_id = assigned_ou.id
            join church_members cm on cm.id = om.church_member_id
            join users u on u.id = cm.user_id
            where target_ou.id = target_ou_id
              and target_ou.church_id = app_security.current_church_id()
              and om.church_id = target_ou.church_id
              and cm.church_id = target_ou.church_id
              and cm.status = 'active'
              and u.auth_user_id = auth.uid()
              and u.is_active = true
              and u.deleted_at is null
              and om.permission = any(required_permissions)
              and om.is_active = true
              and om.deleted_at is null
              and assigned_ou.is_active = true
              and assigned_ou.deleted_at is null
              and target_ou.is_active = true
              and target_ou.deleted_at is null
        );
$$;
```
## 13.3 `can_view_ou()`

```sql
create or replace function app_security.can_view_ou(target_ou_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
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
```

## 13.4 `can_manage_ou()`

```sql
create or replace function app_security.can_manage_ou(target_ou_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select app_security.has_subtree_permission(
        target_ou_id,
        array['admin', 'manager']
    );
$$;
```

## 13.5 `can_submit_for_ou()`

```sql
create or replace function app_security.can_submit_for_ou(target_ou_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
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
```

## 13.6 `can_approve_for_ou()`

```sql
create or replace function app_security.can_approve_for_ou(target_ou_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
    select app_security.has_subtree_permission(
        target_ou_id,
        array['admin', 'approver']
    );
$$;
```

---

# 14. RLS Enablement

Enable RLS on all business tables.

```sql
alter table churches enable row level security;
alter table users enable row level security;
alter table church_members enable row level security;
alter table tenant_invitations enable row level security;
alter table user_preferences enable row level security;
alter table organization_unit_types enable row level security;
alter table organization_units enable row level security;
alter table ou_members enable row level security;
alter table statistic_periods enable row level security;
alter table metric_template_sets enable row level security;
alter table statistic_metrics enable row level security;
alter table statistic_submissions enable row level security;
alter table statistic_values enable row level security;
alter table submission_revisions enable row level security;
alter table api_idempotency_keys enable row level security;
alter table approval_logs enable row level security;
alter table audit_logs enable row level security;
```

Recommended:

```sql
alter table churches force row level security;
alter table users force row level security;
alter table church_members force row level security;
alter table tenant_invitations force row level security;
alter table user_preferences force row level security;
alter table organization_unit_types force row level security;
alter table organization_units force row level security;
alter table ou_members force row level security;
alter table statistic_periods force row level security;
alter table metric_template_sets force row level security;
alter table statistic_metrics force row level security;
alter table statistic_submissions force row level security;
alter table statistic_values force row level security;
alter table submission_revisions force row level security;
alter table api_idempotency_keys force row level security;
alter table approval_logs force row level security;
alter table audit_logs force row level security;
```

---

# 15. RLS Policy Design by Table

## 15.1 `churches`

### Select Policy

Tenant clients can view only the server-selected church. Platform administration uses a separate service path.

```sql
create policy churches_select_policy
on churches
for select
using (
    id = app_security.current_church_id()
);
```

### Insert / Update / Delete

Authenticated clients cannot mutate churches directly. Tenant provisioning and status changes use separately authorized and audited platform operations.

```sql
create policy churches_insert_policy
on churches
for insert
to authenticated
with check (false);

create policy churches_update_policy
on churches
for update
to authenticated
using (false)
with check (false);

create policy churches_delete_policy
on churches
for delete
to authenticated
using (false);
```

Hard delete should normally be disabled.

---

## 15.2 `users`

### Select Policy

Users can read only their own global profile directly. Searching or listing assignable tenant members must use an OU-scoped RPC that joins `church_members` after authorization.

```sql
create policy users_select_policy
on users
for select
using (
    id = app_security.current_user_id()
);
```

### Update Policy

Direct updates are blocked because a row policy cannot provide column-level protection for `global_role`, identity mapping, or active state. Use `update_my_profile` or the trusted LINE profile-sync operation.

```sql
create policy users_update_policy
on users
for update
to authenticated
using (false)
with check (false);
```

Important:

Do not allow frontend users to change `global_role`, identity fields, or `is_active` directly.
Profile-sync RPCs must exclude `global_role` from client-controlled fields. System-admin promotion or demotion requires a separate platform-only operation with actor, target user, previous role, new role, reason, and timestamp in the audit log.

---

## 15.3 `church_members`

Users can read only their own membership in the selected tenant directly. OU-scoped member lists and assignment searches use authorized RPCs.

```sql
create policy church_members_select_policy
on church_members
for select
using (
    church_id = app_security.current_church_id()
    and user_id = app_security.current_user_id()
);

create policy church_members_insert_policy
on church_members
for insert
to authenticated
with check (false);

create policy church_members_update_policy
on church_members
for update
to authenticated
using (false)
with check (false);

create policy church_members_delete_policy
on church_members
for delete
to authenticated
using (false);
```

Membership invitation, activation, suspension, and revocation use audited RPCs or the platform onboarding service.

---

## 15.3A `tenant_invitations`

Invitation tokens and invitee details are never directly readable or mutable by authenticated clients. The acceptance endpoint receives the raw token, hashes it server-side, locks the matching pending row, and returns only the result of the transaction.

```sql
create policy tenant_invitations_select_policy
on tenant_invitations
for select
to authenticated
using (false);

create policy tenant_invitations_insert_policy
on tenant_invitations
for insert
to authenticated
with check (false);

create policy tenant_invitations_update_policy
on tenant_invitations
for update
to authenticated
using (false)
with check (false);

create policy tenant_invitations_delete_policy
on tenant_invitations
for delete
to authenticated
using (false);
```

Creation, resend, revocation, and acceptance use separately authorized and audited RPC/backend operations.

---

## 15.3B `user_preferences`

```sql
create policy user_preferences_select_policy
on user_preferences
for select
using (
    church_id = app_security.current_church_id()
    and church_member_id = app_security.current_church_member_id()
);

create policy user_preferences_insert_policy
on user_preferences
for insert
to authenticated
with check (false);

create policy user_preferences_update_policy
on user_preferences
for update
to authenticated
using (false)
with check (false);
```

Preferences are created/updated through `update_my_preferences`, which validates default-OU visibility and never changes authorization.

---

## 15.4 `organization_unit_types`

Active members may read OU types in the selected tenant. Mutations are RPC-only and require a direct Root OU admin.

```sql
create policy ou_types_select_policy
on organization_unit_types
for select
using (
    church_id = app_security.current_church_id()
);

create policy ou_types_insert_policy
on organization_unit_types
for insert
to authenticated
with check (false);

create policy ou_types_update_policy
on organization_unit_types
for update
to authenticated
using (false)
with check (false);

create policy ou_types_delete_policy
on organization_unit_types
for delete
to authenticated
using (false);
```

---

## 15.5 `organization_units`

### Select Policy

Users can view OUs inside permitted subtree.

```sql
create policy ou_select_policy
on organization_units
for select
using (
    app_security.can_view_ou(id)
);
```

### Mutation Policies

OU creation, editing, movement, and soft deletion are RPC-only so path/level/root invariants and audit logging cannot be bypassed.

```sql
create policy ou_insert_policy
on organization_units
for insert
to authenticated
with check (false);
```

### Update Policy

Users can update OUs they can manage.

```sql
create policy ou_update_policy
on organization_units
for update
to authenticated
using (false)
with check (false);
```

### Delete Policy

Hard delete should be disabled.
Use soft delete through RPC.

---

## 15.6 `ou_members`

### Select Policy

Users can see membership assignments for OUs they can view.

```sql
create policy ou_members_select_policy
on ou_members
for select
using (
    app_security.can_view_ou(ou_id)
);
```

### Insert Policy

Tenant clients must not insert assignments directly. Assignment validation requires comparing the actor's authorization source with the requested permission and `can_override`, which must be performed by `assign_ou_member`.

```sql
create policy ou_members_insert_policy
on ou_members
for insert
with check (
    false
);
```

### Update Policy

```sql
create policy ou_members_update_policy
on ou_members
for update
using (
    false
)
with check (
    false
);
```

Hard delete should be disabled.
Tenant assignment changes must use audited `assign_ou_member` and `remove_ou_member` security-definer RPCs. Those RPCs must validate the current tenant, target membership, target OU, actor's active source assignment, restricted manager role list, self/source-assignment protection, and `can_override`.

---

## 15.7 `statistic_periods`

### Select Policy

Users can view periods in their church.

```sql
create policy periods_select_policy
on statistic_periods
for select
using (
    church_id = app_security.current_church_id()
);
```

### Insert / Update Policy

Authenticated clients must not insert or update reporting periods directly. Tenant mutations use audited security-definer RPCs restricted to an active admin assigned directly to the tenant Root OU Level 1.

```sql
create policy periods_insert_policy
on statistic_periods
for insert
to authenticated
with check (false);

create policy periods_update_policy
on statistic_periods
for update
to authenticated
using (false)
with check (false);
```

Use `create_statistic_period` and `close_statistic_period` for tenant operations. The RPC must derive the current tenant from authenticated membership, validate a direct Root OU admin assignment, preserve `church_id`, validate the status transition, and write an audit log. System-administrator changes use the separately audited platform service path.

---

## 15.8 `statistic_metrics`

`metric_template_sets` has no authenticated-client policy. Only the platform provisioning/template service can read or mutate it.

### Select Policy

Users can view tenant-owned metrics for the selected tenant. Platform metric templates are not runtime form rows.

```sql
create policy metrics_select_policy
on statistic_metrics
for select
using (
    church_id = app_security.current_church_id()
);
```

### Insert / Update Policy

Authenticated clients must not insert or update metrics directly. Tenant metric mutations use audited security-definer RPCs restricted to an active admin assigned directly to the tenant Root OU Level 1.

```sql
create policy metrics_insert_policy
on statistic_metrics
for insert
to authenticated
with check (false);

create policy metrics_update_policy
on statistic_metrics
for update
to authenticated
using (false)
with check (false);
```

Use `create_statistic_metric` and `update_statistic_metric` for tenant operations. Each RPC validates the direct Root OU admin assignment, preserves `church_id`, validates configuration, and writes an audit log. Platform template changes use the separately audited platform service path and never mutate existing tenant metrics.

---

## 15.9 `statistic_submissions`

### Select Policy

Users can view submissions for OUs they can view.

```sql
create policy submissions_select_policy
on statistic_submissions
for select
using (
    app_security.can_view_ou(ou_id)
);
```

### Mutation Policies

Draft creation, value changes, submission, and workflow transitions are RPC-only.

```sql
create policy submissions_insert_policy
on statistic_submissions
for insert
to authenticated
with check (false);
```

### Update Policy

```sql
create policy submissions_update_draft_policy
on statistic_submissions
for update
to authenticated
using (false)
with check (false);
```

---

## 15.10 `statistic_values`

### Select Policy

Users can view values if they can view the parent submission OU.

```sql
create policy statistic_values_select_policy
on statistic_values
for select
using (
    exists (
        select 1
        from statistic_submissions s
        where s.id = statistic_values.submission_id
          and app_security.can_view_ou(s.ou_id)
    )
);
```

### Insert / Update Policy

Value mutations are performed transactionally by submission RPCs only.

```sql
create policy statistic_values_insert_policy
on statistic_values
for insert
to authenticated
with check (false);

create policy statistic_values_update_policy
on statistic_values
for update
to authenticated
using (false)
with check (false);
```

Hard delete is also unavailable to authenticated clients.

---

## 15.10A `submission_revisions`

Revision snapshots are returned only through `get_submission_revision_history`, which first checks visibility of the parent submission OU. Authenticated clients have no direct select or mutation policy; the security-definer workflow owns all writes.

## 15.10B `api_idempotency_keys`

Idempotency rows are internal workflow state. Authenticated clients have no direct table policy. Security-definer RPCs derive the tenant and actor, lock the key, compare the request hash, and persist the final response.

---

## 15.11 `approval_logs`

### Select Policy

Users can view approval logs for submissions they can view.

```sql
create policy approval_logs_select_policy
on approval_logs
for select
using (
    exists (
        select 1
        from statistic_submissions s
        where s.id = approval_logs.submission_id
          and app_security.can_view_ou(s.ou_id)
    )
);
```

### Insert Policy

Only RPC should insert approval logs.

Direct insert should normally be blocked for authenticated users.

```sql
create policy approval_logs_insert_policy
on approval_logs
for insert
with check (false);
```

Approval logs are inserted by security-definer RPC functions.

---

## 15.12 `audit_logs`

### Select Policy

Audit visibility is tenant- and OU-scoped. It is not enough to match only `church_id`.

```sql
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
set search_path = public
as $$
    select
        target_church_id = app_security.current_church_id()
        and not app_security.is_system_admin()
        and (
            -- A direct Root OU admin can see tenant-wide and OU-scoped events.
            exists (
                select 1
                from organization_units root_ou
                join ou_members om
                  on om.church_id = root_ou.church_id
                 and om.ou_id = root_ou.id
                join church_members cm
                  on cm.church_id = om.church_id
                 and cm.id = om.church_member_id
                join users u on u.id = cm.user_id
                where root_ou.church_id = target_church_id
                  and root_ou.parent_id is null
                  and root_ou.level = 1
                  and root_ou.is_active = true
                  and root_ou.deleted_at is null
                  and om.permission = 'admin'
                  and om.is_active = true
                  and om.deleted_at is null
                  and cm.status = 'active'
                  and u.auth_user_id = auth.uid()
                  and u.is_active = true
                  and u.deleted_at is null
            )
            or (
                target_ou_id is not null
                and (
                    app_security.has_subtree_permission(target_ou_id, array['admin'])
                    or (
                        app_security.has_subtree_permission(target_ou_id, array['manager'])
                        and target_entity_type = any(array[
                            'organization_units',
                            'ou_members',
                            'statistic_submissions',
                            'statistic_values'
                        ])
                    )
                    or (
                        app_security.has_subtree_permission(target_ou_id, array['approver'])
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
```

```sql
create policy audit_logs_select_policy
on audit_logs
for select
using (
    app_security.can_view_audit_log(
        church_id,
        ou_id,
        entity_type,
        action
    )
);
```

Platform-wide audit logs where `church_id is null` and system-admin reads are available only through the separately authorized and audited platform service path, not this tenant policy.

### Mutation Policies

Only RPC or backend trusted processes should insert audit logs.

```sql
create policy audit_logs_insert_policy
on audit_logs
for insert
with check (false);
```

```sql
create policy audit_logs_update_policy
on audit_logs
for update
using (false)
with check (false);

create policy audit_logs_delete_policy
on audit_logs
for delete
using (false);
```

The trusted writer derives `church_id`, `ou_id`, actor membership, and authorization-source assignment from validated records. These scope fields must not be accepted as authoritative client input.

---

# 16. RPC Authorization Rules

Even with RLS, all critical RPC functions must validate permissions internally.

RLS protects table access.
RPC protects business workflows.

---

## 16.1 `submit_statistics`

User can submit statistics if:

1. User is authenticated.
2. User is active.
3. Target OU belongs to user's church.
4. User has `data_entry` directly on OU, or `manager/admin` on OU subtree.
5. OU has `allow_data_entry = true`.
6. Period is open.
7. Values pass metric validation.
8. Submission is not approved, unless user has edit-approved permission.

Submission behavior is selected from the persisted tenant mode:

```text
auto_approve       → submit_statistics() writes approved
approval_required  → submit_statistics() writes submitted
```

Required audit:

- create submission
- save draft
- submit
- auto approve when the tenant uses `auto_approve`

---

## 16.2 `approve_statistics`

User can approve if:

1. User is authenticated.
2. User is active.
3. User has `approver` or `admin` on the submitted OU or ancestor OU.
4. Submission status is `submitted`.
5. Submission belongs to the same church.

Required audit:

- approve action
- approval log
- previous status
- new status

---

## 16.3 `reject_statistics`

User can reject if:

1. User can approve the submission.
2. Submission status is `submitted`.
3. Rejection reason is provided.

Required audit:

- reject action
- rejection reason

---

## 16.4 `return_to_draft`

User can return to draft if:

1. User can approve the submission.
2. Submission status is `submitted` or `approved`.
3. Reason is provided.

Required audit:

- return action
- reason
- revision update if applicable

---

## 16.5 `get_recursive_summary`

User can request dashboard summary if:

1. User can view the requested root OU.
2. Requested period belongs to the same church.
3. Query includes only approved submissions.

---

# 17. Approval Permission Algorithm

## 17.1 Nearest Ancestor Approver

When a submission is submitted:

```text
1. Start from submitted OU.
2. Check active approver on the same OU.
3. If not found, move to parent OU.
4. Repeat until root OU.
5. If multiple active approvers exist at the nearest OU, any one may act; lock the submission so the first committed transition wins.
6. If no approver is found, only a direct Root OU admin can approve.
```

## 17.2 Override Approval

A user can override approval if:

1. User has an ancestor `admin` assignment, or
2. User has an ancestor `approver` assignment with `ou_members.can_override = true`.

Override actions must be logged with:

- override flag
- actor
- timestamp
- reason
- from status
- to status

---

# 18. Data Visibility Rules

## 18.1 Dashboard

Dashboard data must:

- include only visible OUs
- include only approved submissions
- aggregate recursively
- filter by `church_id`
- ignore soft-deleted records

## 18.2 Reports

Reports must:

- respect OU subtree visibility
- include approved submissions only
- use dynamic metrics
- never use fixed attendance columns
- support global and church-specific metrics

## 18.3 Submission Status

Parent OUs can see submission status of descendant OUs if they have:

- `admin`
- `manager`
- `approver`
- `viewer`

Data entry users can see only their assigned OU submissions.

---

# 19. Soft Delete Rules

Hard delete is not allowed for important business records.

Soft delete fields:

```text
is_active = false
deleted_at = now()
deleted_by = current_user_id()
```

Tables requiring soft delete:

- churches
- users
- organization_units
- ou_members
- statistic_metrics
- statistic_submissions

Deletion restrictions:

| Entity | Restriction |
|---|---|
| Organization Unit | Cannot delete if active child OU exists |
| Organization Unit | Cannot delete if attendance/submission exists |
| Metric | Cannot delete if used in statistic_values |
| User | Should deactivate instead of delete |
| Submission | Should soft delete only with audit log |

---

# 20. RLS Testing Checklist

Every implementation must pass the following tests.

## 20.1 Tenant Isolation

- User from Church A cannot read Church B data.
- User from Church A cannot insert data into Church B.
- User from Church A cannot update Church B records.

## 20.2 OU Visibility

- Viewer on parent OU can see descendant OUs.
- Data entry on leaf OU cannot see sibling OU.
- Manager on district can see child groups.
- Approver on region can see pending submissions from descendants.

## 20.3 Submission Security

- Data entry can create a draft for an assigned OU through the authorized RPC.
- Data entry cannot submit for unrelated OU.
- Authenticated clients cannot directly insert or update submission headers or values.
- Authenticated clients cannot directly mutate churches, memberships, OU types, OUs, assignments, periods, metrics, approval logs, or audit logs.
- A system administrator using the normal tenant client receives no blanket RLS bypass.
- Viewer cannot submit.
- Data entry cannot approve.
- Approver cannot modify metric values directly unless workflow allows.

## 20.4 Approval Security

- Approver can approve descendant submission.
- Approver cannot approve unrelated church submission.
- Higher approver with override can override.
- Higher approver without override cannot override unless admin.

## 20.5 Audit Security

- Normal user cannot insert audit log directly.
- Audit log is created by RPC.
- Audit log records correct actor.

---

# 21. Recommended Implementation Order

Implement RLS in this order:

```text
1. Add users.auth_user_id
2. Create app_security schema
3. Create current user helper functions
4. Create permission helper functions
5. Enable RLS on all tables
6. Add SELECT policies
7. Add explicit deny-direct mutation policies for authenticated clients
8. Disable hard delete
9. Implement authorized, audited mutation RPCs and the separate platform service path
10. Test RLS with multiple users and churches
```

---

# 22. Important Implementation Notes for AI Coding Tools

When generating code:

- Do not bypass RLS.
- Do not use frontend-only permission checks.
- Do not create fixed attendance columns.
- Always use `statistic_metrics` and `statistic_values`.
- Always filter tenant data by `church_id`.
- Use `auth.uid()` to identify the current authenticated user.
- Use `users.auth_user_id` to map Supabase Auth to internal users.
- Use RPC for submit, approve, reject, return, and override.
- Insert audit logs inside RPC functions.
- Approval is per submission, not per metric.
- Reports include approved submissions only.
- Data entry is normally leaf OU only.
- Parent dashboards aggregate recursively from descendant OUs.

---

# 23. Open Design Notes

## 23.1 `users.auth_user_id`

This document recommends adding:

```sql
users.auth_user_id uuid unique
```

This is required for clean Supabase RLS implementation.

## 23.2 Direct Table Mutation vs RPC-only

Production uses RPC-only or separately trusted service mutation for:

- churches
- users
- church_members
- tenant_invitations
- user_preferences
- organization_unit_types
- organization_units
- ou_members
- statistic_periods
- statistic_metrics
- statistic_submissions
- statistic_values
- approval_logs
- audit_logs

Authenticated frontend access to business tables is read-only where a select policy is explicitly defined. Critical mutations must validate authorization, preserve tenant ownership, maintain derived fields, and write audit records in one transaction.

## 23.3 Audit Log Visibility

Audit-log visibility follows Section 15.12 from the first release:

- Direct Root OU admin: every tenant event.
- Non-root admin: events tied to an OU in the assigned subtree.
- Manager: OU/member-management and submission events in the managed subtree.
- Approver: approval events in the approval subtree.
- Data entry and viewer: no general audit-log access.
- System administrator: separate authorized and audited platform service path.

An event without `ou_id` is tenant-wide and is visible only to a direct Root OU admin. Audit rows are append-only.

---

# 24. Acceptance Criteria

This RLS and Permission design is accepted when:

- Every business table has RLS enabled.
- Every tenant-owned table is isolated by `church_id`.
- OU subtree access works correctly.
- Data entry can submit only authorized OU statistics.
- Approvers can approve only authorized submissions.
- Parent dashboards cannot leak unrelated OU data.
- Users cannot bypass workflows with direct table updates.
- Audit logs are created for critical actions.
- Audit-log reads are filtered by tenant, OU subtree, entity type, and action before pagination and counts.
- Direct Root admins, non-root admins, managers, approvers, data-entry users, viewers, and system administrators each pass their documented positive and negative audit-visibility tests.
- Authenticated clients cannot insert, update, or delete audit rows directly.
- Both tenant modes, `auto_approve` and `approval_required`, work without a schema change.

---

# 25. Next Document

Continue with:

**04_API_Design.md**
