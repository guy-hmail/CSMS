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

The central OA contract records `LINE_MESSAGING_OA_BASIC_ID` and uses `LINE_MESSAGING_CHANNEL_ID`, `LINE_MESSAGING_CHANNEL_ACCESS_TOKEN`, and `LINE_MESSAGING_CHANNEL_SECRET` only as Supabase Edge Function secrets. `LINE_DELIVERY_ENABLED=false` is the default kill switch and `LINE_DELIVERY_CANARY_CHURCH_IDS` limits the later Stage D rollout. Stage A does not read or send with these values.

## notifications

| Field | Type | Description |
|---|---|---|
| church_id | uuid | Server-resolved Tenant; part of recipient and OU foreign keys |
| recipient_user_id | uuid | Active Tenant member receiving the In-app record |
| ou_id | uuid nullable | Optional active OU inside the same Tenant and recipient scope |
| event_type | varchar(80) | Allowlisted notification event |
| event_key | varchar(255) | Deterministic deduplication key, unique per Tenant and recipient |
| title | text | In-app title; 1–200 characters |
| body | text | In-app body; 1–2,000 characters |
| deep_link | text nullable | Relative, server-created `/app/...` path; never an arbitrary host URL |
| payload | jsonb | Non-sensitive object for trusted UI context; token/secret-like keys are rejected recursively |
| read_at | timestamptz nullable | First read timestamp |
| archived_at | timestamptz nullable | User archive timestamp; archive also marks the row read |

The unique key `(church_id, recipient_user_id, event_key)` makes event replay idempotent. Stage C event keys include the submission revision or assignment grant timestamp, while recipient identity remains part of the unique key. Browser roles cannot insert, update, or delete notification rows directly; ownership mutations use audited RPCs.

## notification_deliveries

| Field | Type | Description |
|---|---|---|
| church_id | uuid | Tenant duplicated for strong composite ownership with the notification |
| notification_id | uuid | In-app source-of-truth record |
| channel | varchar(20) | Stage A allows only `line` |
| status | varchar(20) | `pending`, `processing`, `sent`, `failed`, or `dead_letter` |
| attempt_count | integer | Bounded delivery attempts, 0–3 |
| delivery_cycle | integer | Starts at 0 and increments for each operator-approved manual replay |
| next_attempt_at | timestamptz | Earliest claim time |
| processing_started_at | timestamptz nullable | Worker lease/recovery timestamp |
| sent_at | timestamptz nullable | Required only for `sent` |
| provider_message_id | varchar(255) nullable | Non-secret provider correlation value |
| last_error_code | varchar(100) nullable | Sanitized provider classification |
| last_error_message | text nullable | Sanitized error, maximum 1,000 characters |

Authenticated browser roles have no table privileges for delivery records. Stage C business RPCs request a pending row through the internal enqueue helper when the preference resolver permits it. The In-app record is still created when the relevant preference is disabled. Stage D claims these durable rows only from the protected worker, and rechecks membership, preference, OU scope, and LINE identity before returning recipient data.

## notification_delivery_attempts

| Field | Type | Description |
|---|---|---|
| church_id | uuid | Tenant-owned composite reference to the delivery |
| delivery_id | uuid | Parent delivery; cascades only when that delivery is removed |
| delivery_cycle | integer | Replay cycle copied from the parent delivery |
| attempt_no | integer | Attempt number 1–3, unique inside a delivery cycle |
| outcome | varchar(30) | `sent`, `retryable_failure`, `permanent_failure`, or `stale_recovered` |
| provider_message_id | varchar(255) nullable | Sanitized provider request/correlation ID |
| error_code | varchar(100) nullable | Sanitized provider or worker classification |
| error_message | text nullable | Redacted operational detail, maximum 1,000 characters |
| started_at / completed_at | timestamptz | Worker lease and finalization timestamps |

The table intentionally contains no LINE user ID, access token, channel secret, notification title, body, or deep link. Browser roles cannot read or mutate attempt history.

## Notification schedule windows

Tenant schedule settings are persisted on `churches`:

| Field | Type | Description |
|---|---|---|
| notification_schedule_enabled | boolean | Tenant-owned switch; defaults to `false` |
| notification_schedule_days | text[] | One or more unique weekday codes: `MON`, `TUE`, `WED`, `THU`, `FRI`, `SAT`, `SUN` |
| missing_reminder_local_hour | smallint | Missing-submission start hour, 0–23 in the Tenant timezone; default 9 |
| approval_digest_local_hour | smallint | Pending-approval digest start hour, 0–23 in the Tenant timezone; default 9 |

The hosted jobs invoke protected wrapper RPCs hourly. Each wrapper applies the platform kill switch/canary, then derives `localDate`, weekday, and local hour from `churches.timezone` and the Tenant-owned settings. Direct Root OU Admins mutate these fields through the audited `update_tenant_notification_schedule` RPC. Missing-reminder event keys are `missing:period:{periodId}:ou:{ouId}:window:{YYYY-MM-DD}` and digest keys are `approval-digest:window:{YYYY-MM-DD}`. Recipient identity is already part of the notification unique constraint, making each window idempotent per recipient.

Reminder payloads contain only `periodId`, `ouId`, and `reminderDate`. Digest payloads contain only `pendingCount` and `digestDate`. Schedule audit rows contain local window metadata and never copy message bodies, LINE identities, or credentials.

## Notification operations projection

`get_platform_notification_operations(tenant_id, window_hours)` is a System Admin-only projection rather than a table. It returns Tenant-scoped aggregate notification/delivery counts, queue status, stale processing count, oldest queued timestamp, sent/dead-letter rates, attempt outcome counts, event-type counts, and up to 20 recent dead-letter correlation records.

Recent dead-letter records expose only delivery UUID, notification UUID, event type, attempt/cycle numbers, sanitized error code, and update timestamp. The projection intentionally omits recipient identity, LINE user ID, title, body, deep link, payload, provider error message, provider response, and credentials.

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
| period_end | Tenant-configured calculation boundary; canonical date for ISO week and month/quarter/year aggregation |
| submission_opens_at | Snapshotted Tenant-local opening instant for normal entry; nullable only for legacy/manually managed periods |
| submission_due_at | Snapshotted inclusive Tenant-local deadline for normal submission; does not affect report aggregation |
| status | open/closed/locked |

Tenant schedule fields on `churches`:

| Field | Description |
|---|---|
| reporting_week_ends_on | Calculation period-end weekday, PostgreSQL DOW 0–6 |
| submission_deadline_days_after_period_end | Required 1–6 local calendar-day offset used when snapshotting each new period deadline |

`not_open`, `open`, `overdue`, and `locked` are derived workflow states, not stored submission statuses. Authorized `returned` corrections can be resubmitted outside the normal time window while the period remains administratively open.

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
