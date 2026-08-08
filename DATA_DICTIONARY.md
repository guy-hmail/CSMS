# DATA_DICTIONARY.md

## Overview

Canonical field dictionary shared by Database, API and Frontend.

### Common Fields

| Field | Type | Description |
|---|---|---|
| id | uuid | Primary key |
| church_id | uuid | Tenant identifier |
| created_at | timestamptz | Creation timestamp |
| updated_at | timestamptz | Last update |
| deleted_at | timestamptz | Soft delete timestamp |
| deleted_by | uuid | User who soft deleted |
| is_active | boolean | Active flag |

## users

| Field | Type | Description |
|---|---|---|
| auth_user_id | uuid | Unique Supabase Auth identity |
| line_user_id | varchar(150) | Unique LINE identity |
| last_active_church_id | uuid | Optional UI preference; never grants tenant access |
| global_role | varchar(30) | Persisted platform role: `user` or `system_admin` |

`is_system_admin` is not a database field. `app_security.is_system_admin()` and frontend `isSystemAdmin` values are derived from `users.global_role = 'system_admin'`.

## Platform LINE configuration

LIFF configuration is deployment-level configuration, not tenant data. `PUBLIC_LINE_LIFF_ID` selects the LIFF application used by the running environment, while `PUBLIC_LINE_LIFF_PRODUCTION_ID` and `PUBLIC_PRODUCTION_APP_URL` provide the read-only production links shown in Tenant Settings for LINE OA Rich Menu setup.

Tenant tables do not store editable LIFF IDs. `LINE_CHANNEL_ID`, channel secrets, messaging credentials, and provider credentials remain server-side Edge Function secrets and are never exposed as tenant-editable fields.

## organization_units

| Field | Description |
|---|---|
| parent_id | Parent OU |
| code | Immutable system-generated ASCII identifier based on OU Type code plus UUID suffix; retained for internal API, audit, search, and export use but hidden from application screens |
| path | Materialized hierarchy path |
| level | Hierarchy depth |
| allow_data_entry | Allows direct submission |

## statistic_periods

| Field | Description |
|---|---|
| period_type | Canonical value `week` |
| year | ISO year derived from `period_end` |
| week_no | ISO week derived from `period_end` |
| month_no | Always null for canonical weekly periods |
| period_start | First day of the seven-day reporting interval |
| period_end | Tenant-configured reporting date and UI display date |
| status | open/closed/locked |

## statistic_metrics

| Field | Description |
|---|---|
| code | Unique KPI code |
| category | Attendance/Finance/etc |
| unit | person/THB/% |
| data_type | number/text/boolean |
| input_type | UI control |
| aggregation | sum/avg/max/min/none |
| default_value | Optional numeric default within min/max |
| source_template_set_id | Provisioning template provenance only |
| metric_kind | `input` for submission values or `calculated` for report-only fields |
| calculation_operator | Calculation operator; v1 supports `sum` |
| calculation_source_metric_ids | Tenant-owned active numeric input metrics used by the formula |
| show_on_dashboard | Whether the active numeric Raw/Calculated metric is shown on Dashboard |
| dashboard_order | Tenant-configured display order for Dashboard cards and selectors |

Calculated metrics never store rows in `statistic_values`. Report RPCs calculate them from approved source values for the requested OU scope and date range.

## statistic_submissions

| Field | Description |
|---|---|
| status | draft/submitted/approved/rejected/returned |
| submitted_by | Submitter |
| approved_by | Approver |
| revision_no | Revision counter |

## submission_revisions

| Field | Description |
|---|---|
| submission_id | Versioned submission |
| revision_no | Immutable version number |
| values_snapshot | JSON array of metric values at that revision |
| changed_by | Authenticated actor |

## api_idempotency_keys

| Field | Description |
|---|---|
| client_request_id | Client-generated retry UUID |
| operation | Mutation name |
| request_hash | Canonical payload hash |
| response_body | Stored response returned for a safe retry |
| expires_at | Cleanup/retention boundary |

## statistic_values

| Field | Description |
|---|---|
| numeric_value | Numeric KPI value |
| text_value | Text KPI value |
| boolean_value | Boolean KPI value |

## ou_members

| Field | Description |
|---|---|
| permission | admin/manager/data_entry/approver/viewer |
| can_override | Approval override permission |
