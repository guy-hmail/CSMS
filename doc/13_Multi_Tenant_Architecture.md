# Multi-Tenant Architecture

Version: 1.0  
Status: Accepted  
Scope: Tenant, identity, organization hierarchy, permission, RLS, and tenant switching

---

# 1. Source of Truth

This document is the canonical multi-tenant model for CSMS. If an older document implies that a user belongs to only one church, that assumption is superseded by this document.

`churches` is the tenant master. One church record represents one isolated customer organization.

```text
Global LINE / Supabase User
          |
          +-- Church Membership (Tenant A) -- OU Memberships
          |
          +-- Church Membership (Tenant B) -- OU Memberships
```

# 2. Core Invariants

1. Every tenant-owned business row contains a non-null `church_id`.
2. `users` is a global identity table and is not owned by one tenant.
3. A user can enter a tenant only through an active `church_members` row.
4. A client-provided `church_id` is context, not authorization. The backend must validate it against `auth.uid()` and `church_members`.
5. Foreign keys and RPC validation must prevent references across tenants.
6. Every tenant has exactly one active Root OU with `parent_id IS NULL` and `level = 1`.
7. Every descendant OU has the same `church_id` and `structure_root_id` as its parent.
8. OU types belong to one tenant and are used consistently from Root OU Level 1 downward.
9. `admin` is scoped to the assigned OU subtree. Only a direct `admin` assignment on the tenant Root OU has tenant-wide administration authority.
10. System administrators are platform-level actors and must use a separately audited service path.
11. Every reference between tenant-owned rows is protected by a composite foreign key containing `church_id`; RLS alone is not the referential-integrity boundary.
12. Global user identities are the intentional ownership exception. Runtime metrics are tenant-owned copies of versioned platform templates.
13. Tenant audit events carry an explicit OU scope and authorization source when applicable; audit visibility is filtered by tenant, subtree, entity type, and action.

# 3. Canonical Data Model

## 3.1 `churches`

Tenant master table.

Required fields: `id`, `code`, `slug`, `name`, `timezone`, `status`, `approval_mode`, `is_active`, and audit timestamps.

## 3.2 `users`

Global LINE/Supabase identity.

Required fields:

- `id`
- `auth_user_id` — unique Supabase Auth identity
- `line_user_id` — unique LINE identity
- profile fields
- `last_active_church_id` — optional UI preference only; never grants access
- `global_role` — `user` or `system_admin`
- audit timestamps

Rules:

- `global_role` is the canonical persisted platform-role field.
- `is_system_admin` is not a `users` column; it is a security helper or derived API/UI boolean computed from `global_role = 'system_admin'`.
- Frontend profile updates must never change `global_role`.
- Promotion or demotion of a system administrator must use a separately authorized and audited platform operation.

## 3.3 `church_members`

Connects a global user to a tenant.

Required fields: `id`, `church_id`, `user_id`, `status`, `joined_at`, `created_by`, and audit timestamps.

Rules:

- `status` is `invited`, `active`, `suspended`, or `revoked`
- unique `(church_id, user_id)`
- access requires `status = 'active'`
- a membership cannot be moved to another tenant

## 3.3A `tenant_invitations`

One-time onboarding record for a future authenticated LINE identity.

Rules:

- no placeholder `users` row is created
- only a token hash is stored
- acceptance atomically creates/reactivates tenant membership and the intended OU assignment
- the invitation email is for delivery and is not treated as the LINE identity
- Root Admin onboarding is created as part of the platform tenant-provisioning transaction

## 3.4 `organization_unit_types`

Tenant-wide OU type setting.

Required fields: `id`, `church_id`, `code`, `name`, `description`, `sort_order`, `default_allow_data_entry`, `is_active`, and audit fields.

Rules:

- unique `(church_id, code)`
- only a direct Root OU Level 1 admin can create, rename, reorder, or deactivate types
- used types are deactivated instead of deleted
- all OUs can select only active types from their own tenant
- OU types are not bound to a fixed tree level; `sort_order` controls display order only
- `default_allow_data_entry` is copied as the initial value when an OU is created and may be overridden on that OU

## 3.5 `organization_units`

Tenant hierarchy with `church_id`, `structure_root_id`, `parent_id`, `ou_type_id`, `level` starting at 1, and `path`.

Root rules:

- exactly one active root per tenant
- `parent_id IS NULL`
- `level = 1`
- `structure_root_id = id`

Child rules:

- parent, type, and child share the same `church_id`
- `structure_root_id = parent.structure_root_id`
- `level = parent.level + 1`
- reparenting recalculates path and level for the moved subtree in one transaction
- moving an OU across tenants is prohibited

## 3.6 `ou_members`

OU-scoped permissions for a tenant member. It contains `church_id`, `ou_id`, `church_member_id`, permission fields, active state, and assignment audit fields.

Constraints:

- the OU and church membership belong to the same `church_id`
- unique active assignment per `(ou_id, church_member_id, permission)`
- inherited administration is computed from a parent `manager` assignment and does not create duplicate rows

# 4. Tenant Context Flow

1. Authenticate with LINE LIFF and Supabase Auth.
2. Resolve the global user using `auth.uid()`.
3. Load active `church_members` rows for that user.
4. If there is one tenant, select it automatically.
5. If there are multiple tenants, require an explicit tenant selection.
6. Store the selected tenant as short-lived server-validated session context.
7. Every query and RPC revalidates the selected tenant membership.
8. Switching tenant clears cached OU, period, report, and permission state before loading the new context.
9. The frontend changes tenant state only after a refreshed JWT contains the server-validated `active_church_id`.
10. Selectable tenants must have an active membership and tenant status `trial` or `active`.

# 5. RLS Requirements

- Enable RLS on every business table.
- Enable and force RLS on `church_members` and `organization_unit_types` as well as the original business tables.
- Tenant-owned reads and writes require `church_id = current_church_id()`.
- `current_church_id()` returns only a tenant for which the authenticated user has an active `church_members` row.
- OU policies additionally enforce authorized subtree access.
- Inserts validate every referenced row belongs to the same tenant.
- Tenant-owned relationships use composite `(church_id, ..._id)` foreign keys so cross-tenant references fail even when RLS is bypassed.
- Runtime metrics must match the target row's `church_id`; platform template rows are never referenced by submissions.
- Global-user actor fields require RPC validation against an active membership in the target tenant, except for a separately authorized and audited system-admin path.
- Updates may not change `church_id`, `structure_root_id`, or membership ownership directly.
- Cross-tenant joins, IDs, paths, counts, search results, exports, and error details must not leak.
- Service-role operations bypassing RLS are isolated and audited.
- Authenticated application clients have no direct insert, update, or delete policy on business tables; mutations use authorized transactional RPCs.
- System administrators do not receive a blanket bypass in tenant RLS or tenant permission helpers and must use the separately authorized platform service path.

# 6. Permission Rules

- Root OU Level 1 `admin`: tenant-wide OU administration, tenant settings, and OU Type Setting.
- Non-root `admin`: full administration only inside the assigned subtree.
- Parent OU `manager`: manager on its own OU and inherited OU administration on descendants, subject to the permission specification.
- No OU role grants access to another tenant.
- Platform system administrator is separate from tenant roles.

# 7. UI Requirements

- Always display the current tenant in the application shell.
- Show a tenant switcher only when the user has more than one active tenant membership.
- Never combine OU trees, reports, notifications, search results, or counts from different tenants.
- On tenant switch, navigate to a safe tenant landing page and reload authorization context.
- URLs may contain a tenant identifier for navigation, but the backend remains the authority.

# 8. Acceptance Criteria

- One LINE account can belong to two tenants and switch between them.
- The same user can hold different OU roles in each tenant.
- A revoked membership immediately loses all access in that tenant while other tenant access remains intact.
- Supplying another tenant's OU ID, member ID, period ID, submission ID, or tenant-owned metric ID is rejected by a database constraint or trigger even when a privileged path bypasses RLS.
- Normal client requests with a mismatched tenant context are rejected by RLS/RPC before the database constraint is reached.
- Each tenant has exactly one active Root OU Level 1.
- Root OU types and settings never affect another tenant.
- Root admin sees the full tree only for their own tenant.
- No API response exposes ancestor, sibling, unrelated, or cross-tenant OU data.
- A non-root audit reader cannot see tenant-wide events, events from an unauthorized subtree, or counts that reveal those events.
- Audit rows cannot be inserted, updated, or deleted directly by authenticated clients.

# 9. Implementation Order

1. Add global identity mapping and `church_members`.
2. Migrate existing `users.church_id` relationships into tenant memberships.
3. Add `structure_root_id`, Level 1 root constraints, and tenant OU types.
4. Migrate `ou_members` to `church_member_id`.
5. Implement validated tenant-context helpers and RLS.
6. Add tenant switcher and tenant-scoped client stores.
7. Add negative database tests for every composite foreign key, including rejected cross-tenant metric references.
8. Run cross-tenant isolation and permission regression tests before production data migration.
