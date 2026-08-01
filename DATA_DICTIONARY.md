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

## organization_units

| Field | Description |
|---|---|
| parent_id | Parent OU |
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
