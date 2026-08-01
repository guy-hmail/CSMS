# Church Statistics Management System (CSMS)
## API Design Specification

Version: 1.0  
Status: Production Blueprint  
Target Platform: Supabase PostgreSQL + Supabase Edge Functions  
Frontend: SvelteKit + LINE LIFF  
Architecture Style: Thin Frontend, RPC-Centered Backend, RLS-Protected API

---

# 1. Document Purpose

This document defines the API architecture, RPC contracts, Edge Function contracts, request/response structures, validation rules, error model, and frontend integration rules for the Church Statistics Management System (CSMS).

This document is the authoritative reference for:

- Supabase RPC function design
- Supabase Edge Function design
- Frontend API service calls
- Request and response contracts
- Workflow execution rules
- Permission validation rules
- Error handling
- Audit behavior
- API naming conventions

This document must be followed when implementing backend functions, SvelteKit services, and AI-generated application code.

---

# 2. Design Principles

CSMS uses a database-first backend design.

Core principles:

1. Frontend must be thin.
2. Frontend must not contain critical business logic.
3. Critical workflows must use PostgreSQL RPC or trusted Edge Functions.
4. RLS must protect all direct table access.
5. RPC functions must validate authorization internally.
6. All tenant-owned operations must include or resolve `church_id`.
7. API functions must use dynamic metrics.
8. API must never create fixed attendance fields.
9. Reports and dashboards must aggregate recursively from descendant OUs.
10. Approved submissions only are counted in official reports.
11. Submission behavior is selected by the current tenant's persisted `approval_mode`.
12. `auto_approve` approves on submit; `approval_required` enters the approval workflow without a schema change.
13. Every critical mutation must create audit logs.

---

# 3. API Architecture

```text
SvelteKit Frontend
      │
      │ Supabase JS Client
      ▼
Supabase API
      │
      ├── Direct SELECT for safe read models protected by RLS
      │
      ├── PostgreSQL RPC for business workflows
      │
      └── Edge Functions for external integrations
              │
              ├── LINE LIFF profile verification
              ├── Notifications
              ├── Export generation
              └── Scheduled jobs
```

---

# 4. API Layers

## 4.1 Direct Table Access

Allowed only for simple read operations protected by RLS.

Examples:

- Read accessible Organization Units
- Read metric definitions
- Read reporting periods
- Read dashboard views
- Read submission status views

Authenticated frontend insert/update/delete to business tables is prohibited. Business mutations use permission-validating, audited RPCs; platform administration uses separately authorized and audited backend/Edge Function operations.

---

## 4.2 PostgreSQL RPC

Use RPC for critical business actions.

Examples:

- Create or update user profile
- Submit statistics
- Save draft
- Approve submission
- Reject submission
- Return submission to draft
- Get recursive dashboard summary
- Create child OU
- Assign OU permission

RPC functions must:

- Resolve current user from `auth.uid()`.
- Validate tenant access.
- Validate OU permission.
- Validate input data.
- Execute transactionally.
- Write audit logs.
- Return structured JSON.

---

## 4.3 Edge Functions

Use Edge Functions when the operation requires:

- External service integration
- Secret keys not allowed in frontend
- File generation
- Notification delivery
- Scheduled jobs
- Webhook handling

Examples:

- LINE profile sync
- LINE notification
- Excel export
- PDF export
- Reminder job
- Missing submission scan

Edge Functions may call RPC functions for business logic.

---

# 5. Naming Convention

## 5.1 PostgreSQL RPC

Use snake_case.

Examples:

```text
submit_statistics
save_statistics_draft
approve_statistics
get_recursive_summary
```

## 5.2 SvelteKit API Service Functions

Use camelCase.

Examples:

```ts
submitStatistics()
saveStatisticsDraft()
approveStatistics()
getRecursiveSummary()
```

## 5.3 Edge Functions

Use kebab-case folder names.

Examples:

```text
sync-line-profile
send-line-notification
export-report-excel
export-report-pdf
```

---

# 6. Common API Response Format

All RPC functions should return a consistent JSON shape.

## 6.1 Success Response

```json
{
  "success": true,
  "data": {},
  "message": "Operation completed successfully"
}
```

## 6.2 Error Response

```json
{
  "success": false,
  "error": {
    "code": "PERMISSION_DENIED",
    "message": "You do not have permission to perform this action",
    "details": {}
  }
}
```

## 6.3 List Response

```json
{
  "success": true,
  "data": {
    "items": [],
    "total": 0,
    "page": 1,
    "pageSize": 20
  }
}
```

## 6.1 Mutation concurrency and retry contract

Every retryable critical mutation accepts `clientRequestId` (UUID). A request with the same authenticated actor, tenant, operation, key, and payload hash returns the stored response without executing twice; the same key with a different payload returns `IDEMPOTENCY_KEY_REUSED`.

Mutations of an existing versioned record also accept `expectedRevision`. The RPC locks the row and returns `REVISION_CONFLICT` with the current revision when it does not match. A successful content or workflow mutation increments `revisionNo` exactly once and writes the matching immutable revision snapshot in the same transaction. Creation uses `expectedRevision: null`.

---

# 7. Standard Error Codes

| Code | Meaning |
|---|---|
| `AUTH_REQUIRED` | User is not authenticated |
| `USER_NOT_FOUND` | Authenticated user has no CSMS user profile |
| `USER_INACTIVE` | User profile is inactive |
| `TENANT_NOT_FOUND` | Church does not exist or is inactive |
| `PERMISSION_DENIED` | User lacks required permission |
| `OU_NOT_FOUND` | Organization Unit not found or inaccessible |
| `OU_NOT_DATA_ENTRY` | OU does not allow direct data entry |
| `PERIOD_NOT_FOUND` | Reporting period not found |
| `PERIOD_LOCKED` | Period is locked |
| `METRIC_NOT_FOUND` | Metric not found or inactive |
| `INVALID_METRIC_VALUE` | Metric value does not match metric data type or validation |
| `SUBMISSION_NOT_FOUND` | Submission not found |
| `SUBMISSION_ALREADY_APPROVED` | Approved submission cannot be modified by current user |
| `INVALID_STATUS_TRANSITION` | Workflow transition is not allowed |
| `DUPLICATE_SUBMISSION` | Submission already exists for OU and period |
| `VALIDATION_ERROR` | Input validation failed |
| `INTERNAL_ERROR` | Unexpected server error |

---

# 8. Authentication Context

Every RPC function must resolve the current user by Supabase Auth.

Recommended helper function:

```sql
current_app_user_id()
```

Expected behavior:

```text
1. Read auth.uid().
2. Find active users.auth_user_id = auth.uid().
3. Return users.id.
4. Raise AUTH_REQUIRED or USER_NOT_FOUND if missing.
```

Recommended `users` table field:

```sql
users.auth_user_id uuid unique
```

---

# 9. Authorization Helpers

RPC functions should rely on shared helper functions instead of duplicating permission logic.

Recommended helpers:

```sql
current_app_user_id() returns uuid
current_church_id() returns uuid
user_has_permission(p_ou_id uuid, p_permissions text[]) returns boolean
user_has_subtree_permission(p_ou_id uuid, p_permissions text[]) returns boolean
user_can_view_ou(p_ou_id uuid) returns boolean
user_can_manage_ou(p_ou_id uuid) returns boolean
user_can_submit_for_ou(p_ou_id uuid) returns boolean
user_can_approve_submission(p_submission_id uuid) returns boolean
user_can_override_submission(p_submission_id uuid) returns boolean
```

---

# 10. API Module Catalog

| Module | API Type | Purpose |
|---|---|---|
| Identity | RPC / Edge Function | LINE login profile sync and user profile |
| Church | RPC / Direct Read | Tenant context |
| Organization | RPC / Direct Read | OU tree and OU management |
| Permission | RPC / Direct Read | OU member assignment |
| Period | RPC / Direct Read | Reporting period management |
| Metric | RPC / Direct Read | Dynamic KPI configuration |
| Submission | RPC | Draft, submit, edit workflow |
| Approval | RPC | Approve, reject, return, override |
| Dashboard | RPC / View | Recursive aggregation |
| Report | RPC / Edge Function | Report data and exports |
| Audit | Direct Read / RPC | Audit log visibility |
| Notification | Edge Function | LINE notification and reminders |

---

# 11. Identity APIs

## 11.0 Platform Tenant Provisioning

Platform tenant operations run through a trusted Edge Function/backend service. They are not callable as direct table mutations or ordinary tenant RPCs.

### `provision_tenant`

```json
{
  "name": "Hope Church",
  "slug": "hope-church",
  "rootOuName": "คริสตจักรหลัก",
  "initialAdmin": {
    "displayName": "Tenant Admin",
    "email": "admin@example.org"
  },
  "timezone": "Asia/Bangkok",
  "reportingWeekEndsOn": 0,
  "approvalMode": "auto_approve",
  "trialDays": 30
}
```

Rules:

1. Require an active platform `system_admin` through the platform service path.
2. Generate tenant/root/type IDs server-side.
3. In one database transaction create the `churches` row in `provisioning`, initial OU types, tenant-owned metric definitions copied from the current versioned platform template, the Root OU at Level 1, and a pending Root OU `admin` invitation.
4. Generate the raw invitation token in the service, persist only its hash, and deliver the raw token once.
5. Commit before sending email; if delivery fails, retain the pending invitation and return a resend-required state.
6. Set tenant status to `trial` only after the provisioning transaction completes. No partially created tenant may become selectable.
7. Write a platform audit event containing IDs and safe metadata, never the raw token.

Response:

```json
{
  "tenantId": "uuid",
  "rootOuId": "uuid",
  "invitationId": "uuid",
  "status": "trial",
  "invitationDelivery": "sent"
}
```

### `accept_tenant_invitation`

Requires a validated LINE/Supabase session.

```json
{
  "token": "one-time-raw-token"
}
```

The trusted operation hashes the token, locks the pending invitation, verifies expiry/status, creates or reactivates `church_members`, creates the intended `ou_members` assignment, records the authenticated user as `accepted_by`, marks the invitation accepted, and writes an audit log in one transaction. Acceptance is idempotent for the same authenticated user and rejected for a different user after use.

The invitation token proves possession; LINE email matching is not required. The invitation email is a delivery address, not an identity key.

### `change_tenant_status`

```json
{
  "tenantId": "uuid",
  "status": "active",
  "reason": "Trial converted"
}
```

Allowed transitions:

```text
provisioning → trial
trial → active | suspended | closed
active → suspended | closed
suspended → active | closed
closed → no transition
```

Every transition is platform-authorized and audited. `is_active` is maintained transactionally from status.

### `set_tenant_approval_mode`

Tenant RPC restricted to an active direct Root OU admin.

```json
{
  "approvalMode": "approval_required",
  "reason": "เริ่มใช้งานกระบวนการอนุมัติ"
}
```

The change affects only submissions performed after it commits. Existing `submitted`, `approved`, `returned`, or `rejected` records keep their state. Enabling `approval_required` should warn when no active approver exists, but direct Root Admin fallback prevents a dead queue. Write a tenant-wide audit event.

---

## 11.1 `sync_user_profile`

Synchronizes authenticated LINE user profile into CSMS `users` table.

Type: PostgreSQL RPC or Edge Function-backed RPC  
Phase: 1  
Critical: Yes

### Request

```json
{
  "lineUserId": "Uxxxxxxxx",
  "displayName": "John",
  "pictureUrl": "https://...",
  "email": "john@example.com",
  "phone": "0812345678"
}
```

### Internal Rules

1. Validate Supabase authentication.
2. Validate LINE identity through trusted LIFF/Edge Function flow if required.
3. If `line_user_id` exists, update profile fields.
4. If not exists, create inactive or active user according to tenant onboarding policy.
5. Set `auth_user_id = auth.uid()`.
6. Update `last_login_at`.
7. Write audit log.

### Response

```json
{
  "success": true,
  "data": {
    "userId": "uuid",
    "currentTenantId": "uuid-or-null",
    "displayName": "John",
    "globalRole": "user",
    "isActive": true
  }
}
```

---

## 11.2 `get_my_profile`

Returns current CSMS user profile and accessible OU permissions.

Type: PostgreSQL RPC  
Phase: 1

### Request

```json
{}
```

### Response

```json
{
  "success": true,
  "data": {
    "user": {
      "id": "uuid",
      "displayName": "John",
      "pictureUrl": "https://...",
      "globalRole": "user"
    },
    "currentTenant": {
      "id": "uuid",
      "slug": "main-church",
      "name": "Main Church",
      "status": "active"
    },
    "permissions": [
      {
        "ouId": "uuid",
        "ouName": "Group A",
        "permission": "data_entry",
        "canOverride": false
      }
    ]
  }
}
```

---

## 11.3 `list_my_tenants`

Returns active tenant memberships for the authenticated global user without requiring an already selected tenant.

Type: Security-definer RPC  
Phase: 1

```json
{}
```

Response:

```json
{
  "items": [
    {
      "tenantId": "uuid",
      "slug": "main-church",
      "name": "Main Church",
      "status": "active",
      "membershipStatus": "active",
      "isCurrent": true,
      "isLastActive": true
    }
  ]
}
```

The function resolves the user from `auth.uid()` and returns only that user's active `church_members` joined to selectable tenants in `trial` or `active` status. It never accepts a user ID.

## 11.4 `switch_active_tenant`

Type: Trusted Edge Function/backend endpoint  
Phase: 1  
Critical: Yes

```json
{
  "tenantId": "uuid"
}
```

Rules:

1. Validate the Supabase session and resolve the global user.
2. Lock/read an active `church_members` row for the requested tenant.
3. Require tenant status `trial` or `active`.
4. Update server-managed Supabase Auth `app_metadata.active_church_id`; never use `user_metadata`.
5. Update `users.last_active_church_id` as a preference only.
6. Write an audit event without exposing other memberships.
7. Return a refreshed session/token, or an explicit `sessionRefreshRequired` result.

```json
{
  "tenantId": "uuid",
  "sessionRefreshRequired": true,
  "redirectTo": "/app/dashboard"
}
```

The frontend must not change its current-tenant store until the refreshed JWT contains the new `active_church_id`. It then clears OU, permission, period, submission, dashboard, report, and query caches before navigating.

Login bootstrap:

- No selectable tenant: show access/invitation state.
- Exactly one selectable tenant: select it automatically through the same trusted operation.
- More than one tenant and no valid current claim: show tenant selection.
- A stale claim for a revoked membership or suspended/closed tenant is rejected and cleared.

---

## 11.5 Profile and preference APIs

### `update_my_profile`

```json
{
  "displayName": "สมชาย ใจดี",
  "email": "somchai@example.org",
  "phone": "0812345678"
}
```

Updates only the authenticated user's permitted profile fields. LINE/auth identity, `global_role`, and active state are immutable through this RPC.

### `get_my_preferences`

Returns the selected tenant's preference row or server defaults.

### `update_my_preferences`

```json
{
  "defaultOuId": "uuid-or-null",
  "language": "th",
  "landingPage": "/app/dashboard",
  "notifyMissing": true,
  "notifySubmitted": true,
  "notifyApproval": false,
  "notifyEmail": false
}
```

The RPC derives the current church membership, validates that `defaultOuId` belongs to the selected tenant and is currently visible, and upserts one preference row. Preferences never grant access. Email notification delivery may remain disabled until Phase 3 while the preference is retained.

### `get_tenant_settings`

Returns `name`, `slug`, `timezone`, `reportingWeekEndsOn`, `approvalMode`, and `primaryMetricId`. Any active tenant member may read the values needed for UI behavior.

### `update_tenant_settings`

```json
{
  "name": "Main Church",
  "timezone": "Asia/Bangkok",
  "reportingWeekEndsOn": 0,
  "approvalMode": "auto_approve",
  "primaryMetricId": "uuid"
}
```

Requires an active direct Root OU admin. Validate the primary metric belongs to the tenant, week-end range is 0–6, timezone is supported, and approval-mode rules from `set_tenant_approval_mode`. Slug changes use a separate platform-controlled operation. Write one tenant-wide audit event with old/new values.

---

# 12. Organization APIs

## 12.A OU Type APIs

### `list_organization_unit_types`

Returns all OU types in the selected tenant for Root Admin settings, or active types only for ordinary OU creation.

```json
{
  "includeInactive": false
}
```

Each item returns `id`, `code`, `name`, `description`, `sortOrder`, `defaultAllowDataEntry`, `isActive`, `usageCount`, and derived `canDeactivate`. `canDeactivate` is false for the type currently used by the active Root OU.

### `create_organization_unit_type`

```json
{
  "code": "DISTRICT",
  "name": "เขต",
  "description": "หน่วยงานระดับเขต",
  "sortOrder": 30,
  "defaultAllowDataEntry": false
}
```

### `update_organization_unit_type`

```json
{
  "ouTypeId": "uuid",
  "name": "เขตพื้นที่",
  "description": "ชื่อใหม่",
  "sortOrder": 30,
  "defaultAllowDataEntry": false,
  "isActive": true
}
```

Rules for all OU Type mutations:

- Require an active direct `admin` assignment on the selected Tenant Root OU Level 1.
- Derive `church_id` from the validated tenant context.
- Type code is immutable after any OU has used the type.
- A type used by non-root OUs may be deactivated and remains visible on existing records, but cannot be selected for new OUs or type changes.
- The type used by the active Root OU cannot be deactivated.
- Hard delete is prohibited.
- OU types are not tied to a fixed level.
- Write a tenant-wide audit event.

---

## 12.1 `get_accessible_ou_tree`

Returns OU tree visible to the current user.

Type: PostgreSQL RPC or RLS-protected view  
Phase: 1

### Request

```json
{}
```

### Response

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "parentId": null,
        "code": "MAIN",
        "name": "Main Church",
        "ouTypeId": "uuid",
        "ouTypeName": "คริสตจักร",
        "level": 1,
        "path": "/root-id",
        "allowDataEntry": false,
        "children": []
      }
    ]
  }
}
```

### Rules

- Return only OUs inside the user's authorized subtree.
- `level` is the absolute persisted tree level: the tenant Root OU is always Level 1 and each child is `parent.level + 1`.
- Do not renumber an authorized subtree when its actual tenant root is outside the response.
- Admin, manager, approver, and viewer permissions can view descendant OUs.
- Data entry users can view directly assigned OUs.

---

## 12.2 `create_organization_unit`

Creates child OU under an accessible parent OU.

Type: PostgreSQL RPC  
Phase: 1  
Critical: Yes

### Request

```json
{
  "parentOuId": "uuid",
  "ouTypeId": "uuid",
  "code": "GROUP-A",
  "name": "Group A",
  "description": "Cell group A",
  "allowDataEntry": true,
  "sortOrder": 10
}
```

### Permission

Allowed permissions on parent OU subtree:

- `admin`
- `manager`

### Internal Rules

1. Validate parent OU exists and is active.
2. Validate current user can manage parent OU.
3. Inherit `church_id` from parent OU.
4. Validate `ouTypeId` is active and belongs to the same tenant.
5. Copy the type's `default_allow_data_entry` only when `allowDataEntry` is omitted; an explicit OU value overrides it.
6. Calculate `level = parent.level + 1`.
7. Generate `path` after insert using parent path + new OU id.
8. Enforce unique `(church_id, code)`.
9. Write audit log.

### Response

```json
{
  "success": true,
  "data": {
    "ouId": "uuid"
  }
}
```

---

## 12.3 `update_organization_unit`

Updates OU metadata.

Type: PostgreSQL RPC  
Phase: 1  
Critical: Yes

### Request

```json
{
  "ouId": "uuid",
  "parentOuId": "uuid",
  "ouTypeId": "uuid",
  "code": "GROUP-A",
  "name": "Group A Updated",
  "description": "Updated description",
  "allowDataEntry": true,
  "confirmAdditiveParentEntry": true,
  "sortOrder": 20
}
```

### Permission

- `admin`
- `manager`

### Rules

- Cannot change `church_id`.
- A changed `ouTypeId` must be active and belong to the same tenant. Keeping the OU's existing inactive type is allowed.
- Enabling data entry on an OU with active descendants requires `confirmAdditiveParentEntry = true`.
- A direct submission represents this OU's own activity and is additive to descendant submissions.
- `parentOuId` may move a non-root OU only when the actor can manage both the current OU and the new parent.
- A move must reject self/descendant cycles and cross-tenant parents, then recalculate `parent_id`, `path`, and absolute `level` for the complete moved subtree in the same transaction.
- Root OU movement is prohibited.
- Write audit log.

---

## 12.4 `soft_delete_organization_unit`

Soft deletes an OU.

Type: PostgreSQL RPC  
Phase: 1  
Critical: Yes

### Request

```json
{
  "ouId": "uuid",
  "reason": "Created by mistake"
}
```

### Rules

Deletion is prohibited when:

- Active child OU exists.
- Submission history exists.

Soft delete fields:

```text
is_active = false
deleted_at = now()
deleted_by = current_app_user_id()
```

---

# 13. Permission APIs

## 13.1 `assign_ou_member`

Assigns permission to a user for an OU.

Type: PostgreSQL RPC  
Phase: 1  
Critical: Yes

### Request

```json
{
  "ouId": "uuid",
  "churchMemberId": "uuid",
  "permission": "data_entry",
  "canOverride": false,
  "clientRequestId": "uuid"
}
```

### Permission

The RPC must resolve the actor's effective authorization source on the target OU:

- An active `admin` on the target OU or an ancestor uses the admin assignment path.
- An active `manager` on the target OU or an ancestor uses the manager assignment path and remains subject to the restricted rules below.

### Rules

1. Assigner must manage the target OU through an active assignment in the current tenant.
2. Target user must belong to same church.
3. An admin assigner may assign `admin`, `manager`, `data_entry`, `approver`, or `viewer`.
4. A manager assigner may assign only `manager`, `data_entry`, `approver`, or `viewer`; assigning `admin` must be rejected.
5. A manager assigner must always submit `canOverride = false`. Only an authorized admin assigner may grant `canOverride = true`, and only to an `approver` assignment; `admin` has override authority by role.
6. A manager may not modify their own source assignment or an existing assignment whose permission is `admin` or whose `can_override` is true.
7. The RPC must not trust actor role, source OU, or inherited capability supplied by the client.
8. Write an audit log containing the acting member, authorization source assignment, target OU, old values, and new values.

---

## 13.2 `remove_ou_member`

Soft deletes or deactivates a user permission assignment.

Type: PostgreSQL RPC  
Phase: 1  
Critical: Yes

### Request

```json
{
  "ouMemberId": "uuid",
  "reason": "Role changed"
}
```

### Rules

- Set `is_active = false`.
- Set `deleted_at` and `deleted_by`.
- Apply the same admin-versus-manager authorization rules as `assign_ou_member`.
- A manager may not remove their own source assignment, an `admin` assignment, or an assignment with `can_override = true`.
- Write an audit log containing the authorization source assignment.

## 13.2A `update_ou_member_assignment`

Updates one active assignment's permission and `canOverride` flag without replacing the tenant membership or other OU assignments.

Rules:

- Apply the same admin-versus-manager authorization-source rules as `assign_ou_member`.
- A manager cannot update their source assignment, an `admin` assignment, or an assignment that already grants override.
- Only an admin may grant `canOverride`, and only to an `approver` assignment.
- Prevent removal or downgrade of the final active direct Root OU admin.
- Write before/after audit data and return the persisted assignment ID.

---

## 13.3 `list_ou_assignments`

Returns active and optionally inactive assignments for one visible OU. Each item includes assignment ID, church member ID, display name, LINE picture, permission, override flag, active state, and whether the actor may edit/remove it. The server derives these capability flags from the authorization source.

## 13.4 `search_assignable_members`

```json
{
  "ouId": "uuid",
  "query": "สมชาย",
  "cursor": null,
  "limit": 20
}
```

Searches active `church_members` in the current tenant after verifying that the actor may manage the target OU. It returns only safe assignment fields and never exposes users from another tenant. Results indicate existing assignments for that OU.

## 13.5 Tenant member invitation APIs

OU invitation management includes `list_ou_invitations`, `revoke_ou_invitation`, and `reissue_ou_invitation`.

- Listing derives `expired` when a pending invitation is past `expires_at` and returns pending, accepted, expired, and revoked history for the selected OU.
- Revocation requires a reason, invalidates the pending link, and writes an audit event.
- Reissue replaces the token hash, returns the new raw token once, resets the invitation to pending, and audits the operation; an accepted invitation cannot be reissued.
- Manager restrictions for `admin` and `can_override` invitations are identical to assignment restrictions.

`invite_tenant_member` accepts `email`, `displayName`, `targetOuId`, `permission`, `canOverride`, `expiresInDays`, and `clientRequestId`. Authorization follows `assign_ou_member`: managers cannot invite an admin or grant override; only a direct Root Admin may invite another direct Root Admin. The service stores only a token hash and delivers the raw token once.

`resend_tenant_invitation` rotates the token/expiry for a still-pending invitation and invalidates the previous token. `revoke_tenant_invitation` marks it revoked. Both require a reason, `clientRequestId`, equivalent assignment authority, and an audit event.

---

# 14. Reporting Period APIs

## 14.1 `create_statistic_period`

Creates a reporting period.

Type: PostgreSQL RPC  
Phase: 1

### Request

```json
{
  "periodStart": "2026-07-06",
  "periodEnd": "2026-07-12"
}
```

### Permission

- Active `admin` assigned directly to the current tenant's Root OU Level 1.
- System administrator through the separately audited platform service path.
- Reject managers, inherited administrators, and admins assigned only to non-root OUs.

### Rules

- Derive the tenant from the authenticated active membership.
- Create only `period_type = 'week'` for submission periods.
- Require exactly seven inclusive days and require `period_end` weekday to match the tenant setting.
- Derive ISO `year`, `week_no`, and canonical label from `period_end`; set `month_no = null`.
- Prevent duplicate `(church_id, period_start)`.
- Write an audit log.

---

## 14.2 `close_statistic_period`

Changes period status to `closed` or `locked`.

Type: PostgreSQL RPC  
Phase: 1 Tenant Admin Feature

### Permission

- Active `admin` assigned directly to the current tenant's Root OU Level 1.
- System administrator through the separately audited platform service path.
- Reject managers, inherited administrators, and admins assigned only to non-root OUs.

### Request

```json
{
  "periodId": "uuid",
  "status": "locked",
  "reason": "Finalized monthly report"
}
```

### Rules

- The period must belong to the authenticated current tenant.
- `locked` periods cannot accept normal submissions.
- Validate the requested status transition server-side.
- Unlock requires the same direct Root OU admin permission and a reason.
- Write an audit log containing the previous status, new status, reason, and actor.

---

## 14.3 `list_statistic_periods`

Read-only tenant RPC used by submission, dashboard, and report selectors.

```json
{
  "status": "open-or-null",
  "from": "2026-01-01",
  "to": "2026-12-31"
}
```

Returns `id`, `periodStart`, `periodEnd`, ISO year/week, canonical label, status, and a server-generated localized display label. The Thai UI uses the reporting date from `periodEnd`, for example `อา. 12 ก.ค. 2026`.

---

# 15. Metric APIs

## 15.1 `get_active_metrics`

Returns active tenant-owned metrics.

Type: Direct RLS Read or PostgreSQL RPC  
Phase: 1

### Request

```json
{
  "churchId": "uuid",
  "category": "attendance"
}
```

### Response

```json
{
  "success": true,
  "data": {
    "items": [
      {
        "id": "uuid",
        "code": "ATTENDANCE",
        "name": "Worship Attendance",
        "category": "attendance",
        "unit": "person",
        "dataType": "number",
        "inputType": "number",
        "aggregation": "sum",
        "isRequired": true,
        "sortOrder": 10
      }
    ]
  }
}
```

### Rules

- Return only metrics where `church_id` equals the validated current tenant.
- Return active metrics only.
- Sort by `sort_order`, then `name`.

---

## 15.2 `create_statistic_metric`

Creates a church-specific metric.

Type: PostgreSQL RPC  
Phase: 2 or Admin Feature

### Permission

- Active `admin` assigned directly to the current tenant's Root OU Level 1.
- System administrator through the separately audited platform service path.
- Reject managers, inherited administrators, and admins assigned only to non-root OUs.

### Request

```json
{
  "churchId": "uuid",
  "code": "YOUTH",
  "name": "Youth Attendance",
  "description": "Youth group attendance",
  "category": "attendance",
  "unit": "person",
  "dataType": "number",
  "aggregation": "sum",
  "defaultValue": 0,
  "minValue": 0,
  "maxValue": null,
  "isRequired": false,
  "sortOrder": 70
}
```

### Rules

- Derive the tenant from the authenticated active membership; do not authorize from request `churchId`.
- Do not create fixed columns.
- Enforce unique metric code per church.
- Derive `inputType` from `dataType` (`number`, `text`, or `checkbox`) and validate `aggregation`.
- Require `aggregation = none` for text/boolean metrics and validate `minValue <= defaultValue <= maxValue` when provided.
- Tenant RPCs always create a non-null tenant `church_id`.
- Write audit log.

---

## 15.3 `update_statistic_metric`

Updates or deactivates a church-specific metric.

Type: PostgreSQL RPC  
Phase: 1 Tenant Admin Feature

### Permission

- Same permission contract as `create_statistic_metric`.

### Request

```json
{
  "metricId": "uuid",
  "name": "Youth Attendance",
  "description": "Updated description",
  "category": "attendance",
  "unit": "person",
  "aggregation": "sum",
  "defaultValue": 0,
  "minValue": 0,
  "maxValue": null,
  "isRequired": false,
  "sortOrder": 70,
  "isActive": true
}
```

### Rules

- Metric must have a non-null `church_id` equal to the authenticated current tenant.
- Reject changing `church_id` or template provenance fields.
- Metric `code` and `dataType` are immutable after values exist; use a new metric when semantics change.
- Deactivate used metrics instead of deleting them.
- Validate the complete resulting configuration and write an audit log with old and new values.

---

# 16. Submission APIs

## 16.0 `list_submissions`

OU-scoped paginated query used by the submissions page.

```json
{
  "ouId": "uuid-or-null",
  "periodId": "uuid-or-null",
  "status": ["draft", "submitted", "approved"],
  "cursor": null,
  "limit": 50
}
```

Returns only submissions inside the actor's visible OU scopes, including OU and period display data, status timestamps, revision number, and permitted actions. `ouId: null` means all visible scopes, never all tenant rows.

## 16.1 `save_statistics_draft`

Creates or updates a draft submission for an OU and period.

Type: PostgreSQL RPC  
Phase: 1  
Critical: Yes

### Request

```json
{
  "clientRequestId": "uuid",
  "expectedRevision": null,
  "ouId": "uuid",
  "periodId": "uuid",
  "remarks": "Weekly note",
  "values": [
    {
      "metricId": "uuid",
      "numericValue": 120,
      "textValue": null,
      "booleanValue": null
    },
    {
      "metricId": "uuid",
      "numericValue": 5,
      "textValue": null,
      "booleanValue": null
    }
  ]
}
```

### Permission

Allowed if user can submit for OU:

- Direct `data_entry` on OU
- `manager` on OU or ancestor
- `admin` on OU or ancestor

### Validation Rules

1. OU must be active.
2. OU must belong to current user's church.
3. OU must have `allow_data_entry = true`.
4. A direct submission represents only the selected OU's own activity; clients must not send a pre-aggregated descendant total.
5. Period must be open.
6. Metrics must be active and available to church.
7. Required metrics must be present.
8. Numeric values must respect min/max.
9. Number values cannot be negative unless metric allows it.
10. Only one value field should be populated according to metric `data_type`.
11. Approved submission cannot be modified; it must be returned first.
12. For an existing row, `expectedRevision` is required and must match after row lock.

### Draft Behavior

New and existing draft submissions remain:

```text
status = draft
```

Saving corrections to a returned submission keeps `status = returned` and its return audit fields until `submit_statistics` performs the resubmission transition. It must not erase prior workflow history merely to save edits.

### Response

```json
{
  "success": true,
  "data": {
    "submissionId": "uuid",
    "status": "draft",
    "revisionNo": 1
  }
}
```

---

## 16.2 `submit_statistics`

Submits statistics for official reporting.

Type: PostgreSQL RPC  
Phase: 1  
Critical: Yes

### Request

```json
{
  "clientRequestId": "uuid",
  "expectedRevision": 1,
  "ouId": "uuid",
  "periodId": "uuid",
  "remarks": "Weekly submission",
  "values": [
    {
      "metricId": "uuid",
      "numericValue": 120,
      "textValue": null,
      "booleanValue": null
    }
  ]
}
```

### Permission

Allowed if user can submit for OU.

### Internal Workflow

```text
Validate authenticated user
↓
Validate OU access and data-entry permission
↓
Validate period status
↓
Validate metric values
↓
Create or update statistic_submissions
↓
Upsert statistic_values
↓
Apply Phase-specific status
↓
Write approval_logs
↓
Write audit_logs
↓
Return submission result
```

The submit RPC is idempotent, locks the submission, validates `expectedRevision`, increments the revision once, and writes the value snapshot before returning.

### `approval_mode = auto_approve`

The submission is auto-approved.

```text
status = approved
submitted_by = current_user
submitted_at = now()
approved_by = current_user
approved_at = now()
```

Approval log:

```text
action = submit
to_status = approved
is_override = false
```

### `approval_mode = approval_required`

The submission waits for approval.

```text
status = submitted
submitted_by = current_user
submitted_at = now()
approved_by = null
approved_at = null
```

Approval log:

```text
action = submit
to_status = submitted
```

### Response

```json
{
  "success": true,
  "data": {
    "submissionId": "uuid",
    "status": "approved-or-submitted",
    "submittedAt": "2026-07-05T10:00:00+07:00",
    "approvedAt": "timestamp-or-null"
  },
  "message": "Statistics submitted successfully"
}
```

---

## 16.3 `get_submission_detail`

Returns submission header and metric values.

Type: PostgreSQL RPC or RLS-protected read  
Phase: 1

### Request

```json
{
  "submissionId": "uuid"
}
```

### Response

```json
{
  "success": true,
  "data": {
    "submission": {
      "id": "uuid",
      "churchId": "uuid",
      "periodId": "uuid",
      "ouId": "uuid",
      "status": "approved",
      "remarks": "Weekly note",
      "revisionNo": 1,
      "submittedBy": "uuid",
      "submittedAt": "2026-07-05T10:00:00+07:00",
      "approvedBy": "uuid",
      "approvedAt": "2026-07-05T10:00:00+07:00"
    },
    "values": [
      {
        "metricId": "uuid",
        "metricCode": "ATTENDANCE",
        "metricName": "Worship Attendance",
        "dataType": "number",
        "numericValue": 120,
        "textValue": null,
        "booleanValue": null
      }
    ]
  }
}
```

---

## 16.4 `get_submission_revision_history`

```json
{
  "submissionId": "uuid"
}
```

After checking visibility of the submission OU, returns revision metadata newest first. An optional `revisionNo` detail request returns that revision's immutable value snapshot. Revision history is read-only and cannot be used to bypass current metric or workflow validation.

---

# 17. Approval APIs

## 17.1 `get_pending_approval_list`

Returns submissions awaiting approval for the current approver.

Type: PostgreSQL RPC  
Phase: 2

### Request

```json
{
  "periodId": "uuid",
  "ouId": "uuid"
}
```

### Rules

- Return submissions with `status = submitted`.
- Return only submissions inside approver's authorized subtree.
- If `ouId` is provided, filter to that OU subtree.

---

## 17.2 `approve_statistics`

Approves a submitted record.

Type: PostgreSQL RPC  
Phase: 2  
Critical: Yes

### Request

```json
{
  "submissionId": "uuid",
  "approvalNote": "Checked and approved"
}
```

### Permission

Allowed if:

- User has `approver` permission on the same OU or ancestor OU.
- User has `admin` permission on same OU or ancestor OU.

### Rules

1. Submission must be `submitted`.
2. Any active approver at the nearest responsible OU may act; the first committed valid transition wins. Otherwise the actor must be a valid senior override.
3. Set `status = approved`.
4. Set `approved_by` and `approved_at`.
5. Write approval log.
6. Write audit log.

### Response

```json
{
  "success": true,
  "data": {
    "submissionId": "uuid",
    "status": "approved",
    "approvedAt": "2026-07-05T11:00:00+07:00"
  }
}
```

---

## 17.3 `reject_statistics`

Rejects a submitted record.

Type: PostgreSQL RPC  
Phase: 2  
Critical: Yes

### Request

```json
{
  "submissionId": "uuid",
  "reason": "Incorrect value"
}
```

### Rules

- Submission must be `submitted`.
- Reason is required.
- Set `status = rejected`.
- Rejected submissions are not included in reports.
- Rejection is terminal for normal submitters. Use Return for correctable data.
- Reopening requires `reopen_rejected_submission`.
- Write approval log and audit log.

---

## 17.4 `return_statistics_to_draft`

Returns a submission for correction.

Type: PostgreSQL RPC  
Phase: 2  
Critical: Yes

### Request

```json
{
  "submissionId": "uuid",
  "reason": "Please correct Sunday School number"
}
```

### Rules

- Submission status may be `submitted` or `approved` if approver has edit/return permission.
- Reason is required.
- Set status to `returned`.
- Data entry can edit and resubmit returned records.
- Increment `revision_no` on resubmission.
- Approved values cannot be edited before this transition commits.

---

## 17.5 `override_approve_statistics`

Higher-level approver approves by override.

Type: PostgreSQL RPC  
Phase: 2  
Critical: Yes

### Request

```json
{
  "submissionId": "uuid",
  "reason": "District approver unavailable"
}
```

### Rules

- User must have an ancestor `approver` assignment with `can_override = true`, or an ancestor `admin` assignment.
- Reason is required.
- `approval_logs.is_override = true`.
- Write audit log with reason.

---

## 17.6 `reopen_rejected_submission`

Transitions a terminal rejection back to `returned` for correction.

```json
{
  "submissionId": "uuid",
  "reason": "อนุญาตให้แก้ไขและส่งใหม่"
}
```

Only an authorized responsible approver or ancestor admin may reopen it. Reason is required. The RPC locks the submission, writes approval/audit logs, and makes it editable only after status becomes `returned`.

---

# 18. Dashboard APIs

## 18.1 `get_recursive_summary`

Returns aggregated metric summary for an OU subtree and period.

Type: PostgreSQL RPC  
Phase: 1

### Request

```json
{
  "ouId": "uuid",
  "periodId": "uuid",
  "comparePeriodId": "uuid-or-null"
}
```

### Rules

- User must be able to view OU.
- Include descendant OUs recursively.
- Include approved submissions only.
- Aggregate by metric according to `statistic_metrics.aggregation`.
- Ignore soft-deleted submissions.

### Response

```json
{
  "success": true,
  "data": {
    "ou": { "id": "uuid", "name": "Main Church", "path": "/root" },
    "period": { "id": "uuid", "periodEnd": "2026-07-12", "displayLabel": "อา. 12 ก.ค. 2026" },
    "metrics": [
      {
        "metricCode": "ATTENDANCE",
        "metricName": "Worship Attendance",
        "unit": "person",
        "aggregation": "sum",
        "currentValue": 520,
        "compareValue": 500,
        "growthPercent": 4
      }
    ]
  }
}
```

---

## 18.2 `get_dashboard_trend`

Returns trend data for dashboard chart.

Type: PostgreSQL RPC  
Phase: 1

### Request

```json
{
  "ouId": "uuid",
  "metricCodes": ["ATTENDANCE", "SUNDAY_SCHOOL"],
  "periodType": "week",
  "fromDate": "2026-01-01",
  "toDate": "2026-12-31"
}
```

### Response

```json
{
  "success": true,
  "data": {
    "series": [
      {
        "metricCode": "ATTENDANCE",
        "metricName": "Worship Attendance",
        "points": [
          {
            "periodId": "uuid",
            "label": "Week 1 / 2026",
            "periodStart": "2026-01-05",
            "value": 480
          }
        ]
      }
    ]
  }
}
```

---

## 18.3 `get_child_ou_summary`

Returns summary grouped by direct child OU.

Type: PostgreSQL RPC  
Phase: 1

### Request

```json
{
  "parentOuId": "uuid",
  "periodId": "uuid",
  "metricCodes": ["ATTENDANCE", "NEW_VISITOR"]
}
```

### Rules

- For each direct child OU, aggregate that child's full subtree.
- Use approved submissions only.
- Respect permission visibility.

### Response

```json
{
  "success": true,
  "data": {
    "children": [
      {
        "ouId": "uuid",
        "ouName": "เขต 1",
        "metrics": [
          { "metricCode": "ATTENDANCE", "metricName": "ผู้ใหญ่มาคจ.", "value": 230 }
        ],
        "submissionStatus": "complete"
      }
    ]
  }
}
```

---

## 18.4 `get_submission_status_summary`

Returns submission progress for an OU subtree.

Type: PostgreSQL RPC  
Phase: 1

### Request

```json
{
  "ouId": "uuid",
  "periodId": "uuid"
}
```

### Response

```json
{
  "success": true,
  "data": {
    "totalDataEntryOus": 10,
    "draft": 1,
    "submitted": 2,
    "approved": 6,
    "missing": 1,
    "rejected": 0,
    "returned": 0,
    "items": [
      {
        "ouId": "uuid",
        "ouName": "กลุ่ม A",
        "expected": true,
        "status": "approved",
        "submittedAt": "timestamp",
        "approvedAt": "timestamp"
      }
    ]
  }
}
```

---

# 19. Report APIs

## 19.1 `get_report_data`

Returns report-ready data for weekly/monthly/yearly reports.

Type: PostgreSQL RPC  
Phase: 1

### Request

```json
{
  "ouId": "uuid",
  "periodType": "week",
  "fromDate": "2026-07-01",
  "toDate": "2026-07-31",
  "metricCodes": ["ATTENDANCE", "SUNDAY_SCHOOL", "NEW_VISITOR"]
}
```

### Rules

- User must be able to view OU.
- Include approved submissions only.
- Aggregate recursively.
- Return normalized rows suitable for Excel/PDF generation.

### Response

```json
{
  "success": true,
  "data": {
    "columns": ["Period", "OU", "Attendance", "Sunday School", "New Visitors"],
    "rows": [
      {
        "periodLabel": "Week 27 / 2026",
        "ouId": "uuid",
        "ouName": "Group A",
        "values": {
          "ATTENDANCE": 120,
          "SUNDAY_SCHOOL": 30,
          "NEW_VISITOR": 4
        }
      }
    ]
  }
}
```

---

## 19.2 `export-report-excel`

Generates Excel export.

Type: Supabase Edge Function  
Phase: 1

### Request

```json
{
  "ouId": "uuid",
  "periodType": "month",
  "fromDate": "2026-07-01",
  "toDate": "2026-07-31",
  "metricCodes": ["ATTENDANCE", "SUNDAY_SCHOOL"],
  "format": "xlsx"
}
```

### Rules

- Edge Function validates user JWT.
- Edge Function calls `get_report_data` RPC.
- Generate `.xlsx` using server-side library.
- Store generated file in Supabase Storage or return signed URL.

### Response

```json
{
  "success": true,
  "data": {
    "fileName": "csms-report-2026-07.xlsx",
    "downloadUrl": "signed-url",
    "expiresIn": 3600
  }
}
```

---

## 19.3 `export-report-pdf`

Generates PDF export.

Type: Supabase Edge Function  
Phase: 1 or 2

### Rules

- Same authorization as report data.
- Use approved submissions only.
- PDF layout is defined in `07_Reports_Dashboard.md`.

---

# 20. Audit APIs

## 20.1 `get_audit_logs`

Returns audit logs visible to authorized users.

Type: PostgreSQL RPC  
Phase: 2 (audit writing remains mandatory for critical mutations from Phase 1)

### Request

```json
{
  "ouId": "uuid-or-null",
  "entityType": "statistic_submissions",
  "entityId": "uuid",
  "actorUserId": "uuid-or-null",
  "action": "submit",
  "fromDate": "2026-07-01",
  "toDate": "2026-07-31",
  "page": 1,
  "pageSize": 20
}
```

### Permission

- Direct Root OU `admin`: All tenant audit events, including tenant-wide events without `ouId`.
- Non-root `admin`: Full audit visibility for events tied to an OU inside the assigned subtree.
- `manager`: OU/member-management and submission audit events inside the managed subtree.
- `approver`: Approval-related audit events inside the approval subtree.
- `data_entry`: No general audit access.
- `viewer`: No general audit access.
- System administrator: Separate platform audit API/service path.

### Response

```json
{
  "items": [
    {
      "id": "uuid",
      "churchId": "uuid",
      "ouId": "uuid-or-null",
      "userId": "uuid-or-null",
      "actorChurchMemberId": "uuid-or-null",
      "sourceOuMemberId": "uuid-or-null",
      "entityType": "statistic_submissions",
      "entityId": "uuid",
      "action": "submit",
      "beforeData": {},
      "afterData": {},
      "metadata": {},
      "requestId": "uuid",
      "createdAt": "2026-07-05T10:30:00Z"
    }
  ],
  "page": 1,
  "pageSize": 20,
  "total": 1
}
```

### Rules

- Derive the tenant from the validated session; the request does not accept `churchId`.
- Apply role, OU-subtree, entity-type, and action authorization before filters, pagination, or counts.
- Reject an `ouId` outside the caller's audit-visible scope instead of revealing whether it exists.
- Redact secrets, tokens, and sensitive personal fields from `beforeData`, `afterData`, and `metadata`.
- Audit rows are append-only; this API is read-only.

---

# 21. Notification APIs

## 21.1 `send-line-notification`

Sends LINE notification to users.

Type: Supabase Edge Function  
Phase: 3

### Use Cases

- Pending approval notification
- Returned submission notification
- Missing submission reminder
- Weekly submission reminder

### Request

```json
{
  "userIds": ["uuid"],
  "templateCode": "PENDING_APPROVAL",
  "payload": {
    "ouName": "Group A",
    "periodLabel": "Week 27 / 2026"
  }
}
```

### Rules

- Service role can be used only inside Edge Function.
- Notification event must be logged.
- Do not expose LINE secret to frontend.

---

# 22. Scheduled Job APIs

## 22.1 `scan-missing-submissions`

Finds data-entry OUs with missing submissions for an open period.

Type: Scheduled Supabase Edge Function  
Phase: 3

### Rules

- Identify active OUs where `allow_data_entry = true`.
- Check if submission exists for target period.
- Create reminder notification records or send LINE notifications.

---

# 23. Frontend Service Structure

Recommended SvelteKit API service structure:

```text
src/lib/server/
  supabaseAdmin.ts

src/lib/supabase/
  client.ts
  types.ts

src/lib/api/
  identityApi.ts
  organizationApi.ts
  permissionApi.ts
  periodApi.ts
  metricApi.ts
  submissionApi.ts
  approvalApi.ts
  dashboardApi.ts
  reportApi.ts
  auditApi.ts

src/lib/types/
  api.ts
  organization.ts
  submission.ts
  dashboard.ts
```

---

# 24. Frontend API Function Examples

## 24.1 Submit Statistics

```ts
export async function submitStatistics(payload: SubmitStatisticsRequest) {
  const { data, error } = await supabase.rpc('submit_statistics', {
    p_payload: payload
  });

  if (error) throw error;
  return data as ApiResponse<SubmitStatisticsResponse>;
}
```

## 24.2 Get Recursive Summary

```ts
export async function getRecursiveSummary(payload: GetRecursiveSummaryRequest) {
  const { data, error } = await supabase.rpc('get_recursive_summary', {
    p_ou_id: payload.ouId,
    p_period_id: payload.periodId
  });

  if (error) throw error;
  return data as ApiResponse<RecursiveSummaryResponse>;
}
```

---

# 25. TypeScript Shared Types

## 25.1 Base Response

```ts
export type ApiResponse<T> =
  | {
      success: true;
      data: T;
      message?: string;
    }
  | {
      success: false;
      error: ApiError;
    };

export type ApiError = {
  code: string;
  message: string;
  details?: Record<string, unknown>;
};
```

## 25.2 Metric Value Input

```ts
export type StatisticValueInput = {
  metricId: string;
  numericValue?: number | null;
  textValue?: string | null;
  booleanValue?: boolean | null;
};
```

## 25.3 Submit Statistics Request

```ts
export type SubmitStatisticsRequest = {
  ouId: string;
  periodId: string;
  remarks?: string | null;
  values: StatisticValueInput[];
};
```

---

# 26. RPC Implementation Pattern

Recommended RPC signature pattern:

```sql
create or replace function submit_statistics(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
    v_user_id uuid;
    v_ou_id uuid;
    v_period_id uuid;
    v_submission_id uuid;
begin
    v_user_id := current_app_user_id();

    -- validate payload
    -- validate permission
    -- validate metrics
    -- upsert submission
    -- upsert values
    -- write logs

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'submissionId', v_submission_id,
            'status', 'approved'
        )
    );
exception
    when others then
        return jsonb_build_object(
            'success', false,
            'error', jsonb_build_object(
                'code', 'INTERNAL_ERROR',
                'message', sqlerrm
            )
        );
end;
$$;
```

Important:

- `security definer` must be used carefully.
- Function must validate permission internally.
- Function owner should be controlled.
- `search_path` must be explicitly set.
- Do not use service role from frontend.

---

# 27. Validation Rules by Data Type

## 27.1 Number Metric

Required field:

```text
numeric_value
```

Rules:

- Must be numeric.
- Must be greater than or equal to `min_value` if defined.
- Must be less than or equal to `max_value` if defined.
- Default minimum should be 0 for count/person metrics.

## 27.2 Text Metric

Required field:

```text
text_value
```

Rules:

- Trim text.
- Maximum length should be enforced in application or RPC.
- Empty text is invalid if metric is required.

## 27.3 Boolean Metric

Required field:

```text
boolean_value
```

Rules:

- Must be true or false.
- Null is invalid if metric is required.

---

# 28. Workflow Status Transitions

## 28.1 Phase 1

```text
draft
  └── submit_statistics → approved
```

## 28.2 Phase 2

```text
draft
  └── submit_statistics → submitted

submitted
  ├── approve_statistics → approved
  ├── reject_statistics → rejected
  └── return_statistics_to_draft → returned

returned
  └── submit_statistics → submitted

approved
  └── return_statistics_to_draft → returned  [approver/admin only]

rejected
  └── reopen_rejected_submission → returned  [responsible approver/admin only]
```

Invalid transitions must return:

```text
INVALID_STATUS_TRANSITION
```

Transition RPCs lock the submission row. Before changing state they copy the prior state to approval/audit history, then clear header actor/timestamp fields that are incompatible with the new current state. Historical actors and values are read from append-only logs/revisions, not stale header columns.

---

# 29. Pagination and Filtering

List APIs should support:

```json
{
  "page": 1,
  "pageSize": 20,
  "search": "Group A",
  "sortBy": "name",
  "sortDirection": "asc"
}
```

Default rules:

- Default `page = 1`.
- Default `pageSize = 20`.
- Maximum `pageSize = 100`.
- Sort fields must be allowlisted.

---

# 30. Security Requirements

1. All RPC functions must check `auth.uid()`.
2. All RPC functions must resolve internal `users.id`.
3. Never accept `userId` from frontend as actor identity.
4. `churchId` from frontend must be validated against user access.
5. RLS must be enabled on all business tables.
6. Service role key must be used only in backend/Edge Functions.
7. Edge Functions must validate JWT unless intentionally public.
8. Public endpoints must not expose tenant data.
9. Audit logs must be append-only from application perspective.
10. Error messages must not leak sensitive SQL details in production.

---

# 31. Minimum Phase 1 API Set

Phase 1 MVP should implement these APIs first:

## Identity

- `sync_user_profile`
- `get_my_profile`

## Organization

- `get_accessible_ou_tree`
- `create_organization_unit`
- `update_organization_unit`
- `soft_delete_organization_unit`

## Permission

- `assign_ou_member`
- `remove_ou_member`

## Period

- `create_statistic_period`
- Direct read `statistic_periods`

## Metric

- `get_active_metrics`

## Submission

- `save_statistics_draft`
- `submit_statistics`
- `get_submission_detail`

## Dashboard

- `get_recursive_summary`
- `get_dashboard_trend`
- `get_child_ou_summary`
- `get_submission_status_summary`

## Report

- `get_report_data`
- `export-report-excel`

---

# 32. Deferred APIs

These APIs should be deferred until Phase 2 or later:

## Phase 2

- `get_pending_approval_list`
- `approve_statistics`
- `reject_statistics`
- `return_statistics_to_draft`
- `override_approve_statistics`
- `close_statistic_period`

## Phase 3

- `send-line-notification`
- `scan-missing-submissions`
- `unlock_submission`
- `create_notification_template`

## Phase 4

- `get_growth_ranking`
- `get_kpi_insights`
- `get_forecast_summary`
- `generate_ai_summary`

---

# 33. AI Implementation Notes

When generating API code:

1. Do not create fixed attendance APIs with hard-coded attendance fields.
2. Use dynamic metric arrays for all statistic input.
3. Always validate `church_id` through current user context.
4. Never trust frontend-provided actor user ID.
5. Use RPC for submit and approval workflows.
6. Use direct table read only when RLS is sufficient.
7. Keep SvelteKit UI logic thin.
8. Create typed API wrappers in `src/lib/api`.
9. Return consistent `ApiResponse<T>` objects.
10. Use audit logs for all critical mutations.
11. Follow ADR decisions unless explicitly superseded.
12. Do not bypass RLS.

---

# 34. Open Implementation Decisions

The following items should be decided before backend coding:

| Decision | Recommendation |
|---|---|
| Add `users.auth_user_id` | Yes, required for clean Supabase RLS/RPC |
| Tenant submission mode | Persist `approval_mode`; default `auto_approve`, optional `approval_required` (Resolved) |
| Draft save allowed? | Yes |
| Parent OU direct entry | Only if `allow_data_entry = true` |
| OU move support | Defer after Phase 1 |
| Metric customization UI | Phase 1 Direct Root OU Admin feature (Resolved) |
| PDF export | Can defer after Excel export |
| Notification | Phase 3 |

---

# 35. Next Documents

Continue with:

- `05_Frontend_Design.md`
- `06_UI_Wireframe.md`
- `07_Reports_Dashboard.md`
