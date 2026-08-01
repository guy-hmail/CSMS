# Church Statistics Management System (CSMS)
## UI Wireframe Specification

Version: 1.0  
Status: Production Blueprint  
Target Platform: SvelteKit + Skeleton UI + Tailwind CSS  
Backend: Supabase PostgreSQL + RPC + RLS  
Authentication: LINE LIFF + Supabase Auth Bridge  
Architecture Style: Thin Frontend, Permission-Aware UI, Dynamic Metric Forms

---

# 1. Document Purpose

This document defines the UI wireframe, screen structure, user flows, component layout, and interaction behavior for the Church Statistics Management System (CSMS).

This document is intended for:

- UI/UX design
- SvelteKit frontend implementation
- Component planning
- AI coding assistants
- User acceptance testing
- Future feature expansion

This document must be used together with:

- `00_Project_Overview.md`
- `01_Business_Requirements.md`
- `02_Database_Design.md`
- `03_RLS_and_Permissions.md`
- `04_API_Design.md`
- `05_Frontend_Design.md`
- `ARCHITECTURE_DECISIONS.md`
- `AI_STYLE_GUIDE.md`

---

# 2. UI Design Principles

The CSMS UI follows these principles:

1. Simple enough for non-technical church users.
2. Mobile-first because many users may submit reports from mobile LINE LIFF.
3. Dashboard-first after login.
4. Permission-aware, but not permission-authoritative.
5. Dynamic metrics drive forms and dashboard cards.
6. Parent OUs show aggregated data.
7. Leaf OUs focus on submission.
8. Critical actions must be explicit and confirmed.
9. Every mutation must show clear success or error feedback.
10. Avoid clutter in Phase 1.
11. Approval UI must be ready for Phase 2 without redesign.
12. Do not hard-code fixed attendance fields in UI logic.

---

# 3. Target Devices

| Device | Priority | Notes |
|---|---:|---|
| Mobile phone | High | Main device for LINE LIFF users and data entry users |
| Tablet | Medium | Useful for leaders and approvers |
| Desktop | High | Used by admins, managers, and report users |

---

# 4. Global Layout

## 4.1 Desktop Layout

```text
+--------------------------------------------------------------------------------+
| Top Bar                                                                        |
| [☰] CSMS                         [Church Selector] [Period] [User Profile]     |
+----------------------+---------------------------------------------------------+
| Sidebar              | Main Content                                            |
|                      |                                                         |
| Dashboard            | Page Header                                             |
| Organization         | Breadcrumb                                              |
| Submission           | Content Cards / Tables / Forms                          |
| Approval             |                                                         |
| Reports              |                                                         |
| Settings             |                                                         |
+----------------------+---------------------------------------------------------+
```

## 4.2 Mobile Layout

```text
+--------------------------------+
| Top Bar                        |
| [☰] CSMS          [Profile]    |
+--------------------------------+
| Page Header                    |
| Breadcrumb / Context           |
|                                |
| Content Cards                  |
| Forms                          |
| Tables as cards                |
|                                |
+--------------------------------+
| Bottom Navigation              |
| Home | Submit | Reports | More |
+--------------------------------+
```

## 4.3 Layout Rules

- Desktop uses sidebar navigation.
- Mobile uses hamburger menu and optional bottom navigation.
- Top bar always shows the current tenant context.
- Show a tenant switcher only when the user has multiple active tenant memberships.
- Switching tenant navigates to a safe landing page, clears OU/report/permission state, and reloads authorized data.
- UI lists, counts, searches, notifications, exports, and cached state must never combine tenants.
- Page header must clearly show the current OU and period.
- Breadcrumb must be used for hierarchy navigation.

---

# 5. Navigation Structure

```text
/app
├── Dashboard
├── Organization
├── Weekly Submission
├── Approval Queue
├── Reports
├── Users & Permissions
├── Metrics Setup
├── Audit Logs
└── Settings
```

## 5.1 Role-Based Navigation Visibility

| Menu | Admin | Manager | Data Entry | Approver | Viewer |
|---|---:|---:|---:|---:|---:|
| Dashboard | Yes | Yes | Yes | Yes | Yes |
| Organization | Yes | Yes | No | View only | View only |
| Weekly Submission | Yes | Yes | Yes | Yes | View only |
| Approval Queue | Yes | Optional | No | Yes | No |
| Reports | Yes | Yes | Own subtree | Yes | Yes |
| Users & Permissions | Yes | Yes for subtree | No | No | No |
| Metrics Setup | Yes | No | No | No | No |
| Audit Logs | Yes | Limited subtree | No | Approval events | No |
| Settings | Yes | Limited | Limited | Limited | Limited |

Important:

UI visibility is only for user experience. Real authorization is enforced by Supabase RLS and RPC.

---

# 6. Main User Flows

## 6.1 Login Flow

```text
Open LINE LIFF URL
        ↓
Initialize LIFF
        ↓
LINE Login
        ↓
Get LINE Profile
        ↓
Call Auth Bridge / Sync User Profile
        ↓
Create or update user record
        ↓
Load user permissions
        ↓
Redirect to Dashboard
```

## 6.2 Weekly Submission Flow — Phase 1

```text
Dashboard / Submission Menu
        ↓
Select OU
        ↓
Select Reporting Period
        ↓
Load active metrics
        ↓
Display dynamic metric form
        ↓
User enters values
        ↓
Validate values
        ↓
Submit
        ↓
Call submit_statistics RPC
        ↓
Auto Approved
        ↓
Show success
        ↓
Dashboard refresh
```

## 6.3 Approval Flow — Phase 2

```text
Approver opens Approval Queue
        ↓
System lists submitted records in approver subtree
        ↓
Approver opens submission detail
        ↓
Review metric values and history
        ↓
Approve / Reject / Return to Draft
        ↓
Call approval RPC
        ↓
Show result
        ↓
Queue refresh
```

## 6.4 Organization Management Flow

```text
Admin / Manager opens Organization page
        ↓
View hierarchy tree
        ↓
Select OU
        ↓
View OU details
        ↓
Create / Edit / Deactivate child OU
        ↓
Call organization RPC or protected mutation
        ↓
Tree refresh
```

## 6.5 Report Flow

```text
Reports Menu
        ↓
Select OU
        ↓
Select period range
        ↓
Select report type
        ↓
Load recursive summary
        ↓
Display table and charts
        ↓
Export Excel / PDF
```

---

# 7. Screen Catalog

| Screen ID | Screen Name | Route | Phase | Primary Users |
|---|---|---|---|---|
| UI-001 | Login / LIFF Loading | `/login` | Phase 1 | All users |
| UI-002 | Dashboard | `/app/dashboard` | Phase 1 | All users |
| UI-003 | Organization Tree | `/app/organization` | Phase 1 | Admin, Manager |
| UI-004 | Organization Detail | `/app/organization/[ouId]` | Phase 1 | Admin, Manager, Viewer |
| UI-005 | Weekly Submission List | `/app/submissions` | Phase 1 | Data Entry, Manager, Admin |
| UI-006 | Weekly Submission Form | `/app/submissions/[periodId]/[ouId]` | Phase 1 | Data Entry, Manager, Admin |
| UI-007 | Submission Detail | `/app/submissions/[submissionId]` | Phase 1 | Authorized users |
| UI-008 | Approval Queue | `/app/approval` | Approval mode | Approver, Admin |
| UI-009 | Approval Detail | `/app/approval/[submissionId]` | Approval mode | Approver, Admin |
| UI-010 | Reports | `/app/reports` | Phase 1 | Authorized users |
| UI-011 | Report Detail | `/app/reports/detail` | Phase 1 | Authorized users |
| UI-012 | Users & Permissions | `/app/users` | Phase 1 | Admin, Manager |
| UI-013 | User Permission Detail | `/app/users/[userId]` | Phase 1 | Admin, Manager |
| UI-014 | Metric Setup | `/app/settings/metrics` | Phase 1 | Direct Root OU Admin |
| UI-015 | Period Setup | `/app/settings/periods` | Phase 1 | Direct Root OU Admin |
| UI-016 | Audit Logs | `/app/audit-logs` | Phase 2 | Admin, Manager (limited), Approver (approval events) |
| UI-017 | Profile | `/app/profile` | Phase 1 | All users |
| UI-018 | Access Denied | `/app/access-denied` | Phase 1 | All users |
| UI-019 | Not Found | `/404` | Phase 1 | All users |

---

# 8. UI-001 Login / LIFF Loading

## Purpose

Authenticate users using LINE LIFF and synchronize the LINE profile with the CSMS user profile.

## Wireframe

```text
+--------------------------------+
|                                |
|            CSMS                |
| Church Statistics System       |
|                                |
|      [ LINE Login Button ]     |
|                                |
|  Loading your profile...       |
|                                |
+--------------------------------+
```

## UI Elements

| Element | Type | Notes |
|---|---|---|
| App logo/name | Text/Icon | Phase 1 can use text only |
| LINE login button | Button | Hidden if LIFF auto-login succeeds |
| Loading state | Spinner | During LIFF initialization |
| Error message | Alert | Shown if LIFF or auth bridge fails |

## Actions

| Action | Backend |
|---|---|
| Login with LINE | LINE LIFF SDK |
| Sync profile | Auth bridge / Supabase user sync |
| Load permissions | Permission RPC or RLS-protected query |

## Error States

- LINE login failed.
- User is inactive.
- User has no assigned OU.
- Auth bridge failed.

---

# 9. UI-002 Dashboard

## Purpose

Show a summary of statistics and submission status for the current user's accessible OU context.

## Wireframe — Desktop

```text
+--------------------------------------------------------------------------------+
| Dashboard                                                                       |
| Church > Region > District                         [Period: Week 27, 2026 ▼]    |
+--------------------------------------------------------------------------------+
| [OU Selector ▼] [Refresh]                                                       |
+---------------------+---------------------+---------------------+--------------+
| Worship Attendance  | Sunday School       | New Visitors        | New Believers |
| 1,250               | 350                 | 42                  | 12            |
+---------------------+---------------------+---------------------+--------------+
| Trend Chart                                                                    |
| +----------------------------------------------------------------------------+ |
| |                                                                            | |
| +----------------------------------------------------------------------------+ |
|                                                                                |
| Child OU Summary                                                               |
| +----------------+------------+------------+--------------+------------------+ |
| | OU             | Attendance | Visitors   | Status       | Action           | |
| +----------------+------------+------------+--------------+------------------+ |
| | Group A        | 120        | 5          | Submitted    | View             | |
| | Group B        | 85         | 2          | Missing      | Remind           | |
| +----------------+------------+------------+--------------+------------------+ |
```

## Wireframe — Mobile

```text
+--------------------------------+
| Dashboard              [👤]    |
| Church > District              |
| [Week 27, 2026 ▼]              |
+--------------------------------+
| [OU Selector ▼]                |
+--------------------------------+
| Worship Attendance             |
| 1,250                          |
+--------------------------------+
| Sunday School                  |
| 350                            |
+--------------------------------+
| New Visitors                   |
| 42                             |
+--------------------------------+
| Trend Chart                    |
| [chart]                        |
+--------------------------------+
| Child Summary                  |
| Group A | 120 | Submitted      |
| Group B | 85  | Missing        |
+--------------------------------+
```

## Data Sources

- `get_recursive_summary` RPC
- `get_submission_status` RPC or view
- RLS-protected OU list

## UI Rules

- Summary cards are generated from active metrics.
- Do not hard-code metric cards.
- Only numeric metrics with `aggregation != none` appear in summary cards.
- Missing submissions should be highlighted.
- Parent OU dashboard uses recursive aggregation.
- Leaf OU dashboard may show direct submission status.

## Empty States

| Condition | Message |
|---|---|
| No accessible OU | No organization has been assigned to your account. |
| No data for period | No statistics have been submitted for this period. |
| No metrics configured | No active metrics are configured. |

---

# 10. UI-003 Organization Tree

## Purpose

Allow authorized users to view and manage hierarchical Organization Units.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Organization Management                                                        |
| [Create Root OU] [Expand All] [Collapse All]                                   |
+-----------------------------+--------------------------------------------------+
| Organization Tree           | Selected OU                                      |
|                             |                                                  |
| ▼ Main Church               | Name: Group A                                    |
|   ▼ Region 1                | Code: G-A                                        |
|     ▼ District 1            | Parent: District 1                               |
|       • Group A             | Level: 3                                         |
|       • Group B             | Allow Data Entry: Yes                            |
|   ▼ Region 2                | Active: Yes                                      |
|                             |                                                  |
|                             | [Edit] [Create Child OU] [Deactivate]           |
+-----------------------------+--------------------------------------------------+
```

## UI Elements

| Element | Type | Notes |
|---|---|---|
| Tree view | Recursive component | Supports unlimited levels |
| OU detail panel | Card | Shows selected OU |
| Create child button | Button | Manager/Admin only |
| Edit button | Button | Manager/Admin only |
| Deactivate button | Button | Disabled if child/data exists |

## UI Rules

- Tree must support unlimited depth.
- Tree roots must be the current user's directly assigned OU or OUs.
- Show only the assigned OU and authorized descendants; do not show ancestors, siblings, or unrelated branches.
- If the user has multiple assignments, merge the authorized subtrees and remove duplicate OU nodes.
- `data_entry` users see only directly assigned OUs unless another role grants descendant visibility.
- `admin` sees the full tenant tree only when assigned to the church root OU; otherwise admin remains scoped to the assigned subtree.
- Tree search, expand/lazy-load, counts, OU selectors, create-child actions, and member assignment must use only the backend-authorized OU dataset.
- The backend/RLS must filter OUs before returning them; client-side hiding is not an authorization control.
- A manager on a parent OU is shown as an inherited administrator on child and descendant OUs.
- Inherited administration must be labelled with its source, for example `Inherited from District 1 · manager`.
- The UI must not create a duplicate `admin` assignment for inherited access.
- Inherited managers can manage descendant OU structure and LINE assignments, but admin-only, override, workflow, and OU Type Setting actions remain hidden or disabled.
- Use lazy loading if OU count becomes large.
- Deactivate is preferred over hard delete.
- Show `allow_data_entry` clearly.
- If OU has child OUs, default `allow_data_entry = false`.
- If OU has no child OUs, default `allow_data_entry = true` unless overridden.

---

# 11. UI-004 Organization Detail

## Purpose

Display and edit one Organization Unit.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Organization Detail                                                            |
| Church > Region 1 > District 1 > Group A                                       |
+--------------------------------------------------------------------------------+
| General Information                                                            |
| Name                 [ Group A                         ]                       |
| Code                 [ G-A                             ]                       |
| Description          [                               ]                         |
| Allow Data Entry     [x]                                                       |
| Sort Order           [ 10                              ]                       |
| Status               Active                                                    |
|                                                                                |
| [Save] [Cancel]                                                                |
+--------------------------------------------------------------------------------+
| Assigned Users                                                                  |
| +------------+-------------+----------------+--------------+----------------+   |
| | User       | Permission  | Override       | Active       | Action         |   |
| +------------+-------------+----------------+--------------+----------------+   |
| | John       | data_entry  | No             | Yes          | Remove         |   |
| | Peter      | approver    | Yes            | Yes          | Remove         |   |
+--------------------------------------------------------------------------------+
| [Assign User]                                                                  |
+--------------------------------------------------------------------------------+
```

## Validation

- Name is required.
- Code is required and unique per church.
- Parent OU must belong to the same church.
- Cannot move OU under itself or descendant.
- Cannot deactivate OU if active child OU exists unless backend allows cascading deactivation.

---

# 12. UI-005 Weekly Submission List

## Purpose

Show weekly submission status for accessible OUs and periods.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Weekly Submissions                                                             |
| [Period: Week 27, 2026 ▼] [OU Filter ▼] [Status ▼] [Search]                    |
+--------------------------------------------------------------------------------+
| +----------------+----------------+------------+--------------+--------------+ |
| | OU             | Period         | Status     | Updated At   | Action       | |
| +----------------+----------------+------------+--------------+--------------+ |
| | Group A        | Week 27        | Approved   | 2026-07-05   | View         | |
| | Group B        | Week 27        | Draft      | 2026-07-05   | Continue     | |
| | Group C        | Week 27        | Missing    | -            | Create       | |
| +----------------+----------------+------------+--------------+--------------+ |
```

## Status Badges

| Status | Badge Label | Meaning |
|---|---|---|
| missing | Missing | No submission exists |
| draft | Draft | Editable |
| submitted | Submitted | Waiting for approval in Phase 2 |
| approved | Approved | Included in reports |
| rejected | Rejected | Not included |
| returned | Returned | Needs correction |

## Actions

| Status | Action |
|---|---|
| missing | Create |
| draft | Continue |
| returned | Edit |
| submitted | View |
| approved | View |
| rejected | View |

---

# 13. UI-006 Weekly Submission Form

## Purpose

Allow authorized users to submit weekly statistics using dynamic metrics.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Weekly Submission                                                              |
| OU: Group A                                      Period: Week 27, 2026          |
| Status: Draft                                                                  |
+--------------------------------------------------------------------------------+
| Statistics                                                                     |
| Worship Attendance *        [ 120                         ] person             |
| Sunday School              [ 35                          ] person             |
| New Visitors               [ 5                           ] person             |
| New Believers              [ 1                           ] person             |
| Online Attendance          [ 22                          ] person             |
| Remarks                    [ text area                                      ] |
|                                                                                |
| [Save Draft] [Submit]                                                          |
+--------------------------------------------------------------------------------+
```

## Dynamic Metric Rendering

| Metric `data_type` | Metric `input_type` | UI Control |
|---|---|---|
| number | number | Number input |
| text | text | Text input or textarea |
| boolean | checkbox | Checkbox |

## Validation Rules

- Required metrics must be filled.
- Numeric values must not be negative unless metric configuration allows it.
- Numeric value must respect `min_value` and `max_value` if set.
- Only one value type is submitted per metric.
- OU must allow data entry.
- Period must be open unless backend allows late submission.

## Phase 1 Submit Behavior

```text
Click Submit
    ↓
Confirm submit dialog
    ↓
Call submit_statistics RPC
    ↓
Backend sets status = approved
    ↓
Show success
```

## Confirmation Dialog

```text
Submit weekly statistics?

After submission, this report will be recorded as Approved for Phase 1.

[Cancel] [Submit]
```

---

# 14. UI-007 Submission Detail

## Purpose

Read-only or permission-based detail view for a submission.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Submission Detail                                                              |
| OU: Group A | Period: Week 27, 2026 | Status: Approved                         |
+--------------------------------------------------------------------------------+
| Summary                                                                        |
| Submitted By: John                                                             |
| Submitted At: 2026-07-05 10:30                                                 |
| Approved By: John                                                              |
| Approved At: 2026-07-05 10:30                                                  |
+--------------------------------------------------------------------------------+
| Metric Values                                                                  |
| +-------------------------+-------------+------+                               |
| | Metric                  | Value       | Unit |                               |
| +-------------------------+-------------+------+                               |
| | Worship Attendance      | 120         | person |                             |
| | Sunday School           | 35          | person |                             |
| | New Visitors            | 5           | person |                             |
| +-------------------------+-------------+------+                               |
+--------------------------------------------------------------------------------+
| Remarks                                                                        |
| ...                                                                            |
+--------------------------------------------------------------------------------+
| [Edit Draft] [Return]                                                          |
```

## UI Rules

- Approved records are read-only for normal data entry users.
- Admin/Approver may see edit/return controls depending on Phase 2 permission.
- Metric display is generated from `statistic_values` + `statistic_metrics`.

---

# 15. UI-008 Approval Queue — Phase 2

## Purpose

Show pending submissions that an approver can approve.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Approval Queue                                                                 |
| [Period ▼] [OU Filter ▼] [Search]                                              |
+--------------------------------------------------------------------------------+
| Pending Approval: 12                                                           |
+--------------------------------------------------------------------------------+
| +----------------+----------------+--------------+-------------+-------------+ |
| | OU             | Period         | Submitted By | Submitted At| Action      | |
| +----------------+----------------+--------------+-------------+-------------+ |
| | Group A        | Week 27        | John         | 2026-07-05  | Review      | |
| | Group B        | Week 27        | Mary         | 2026-07-05  | Review      | |
| +----------------+----------------+--------------+-------------+-------------+ |
```

## UI Rules

- Shows only submissions accessible to the current approver.
- Backend determines actual accessibility.
- Queue should support period and OU filtering.
- Higher-level approvers may see descendant OU submissions.

---

# 16. UI-009 Approval Detail — Phase 2

## Purpose

Allow approver to review and act on a submitted report.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Approval Detail                                                                |
| OU: Group A | Period: Week 27, 2026 | Status: Submitted                        |
+--------------------------------------------------------------------------------+
| Metric Values                                                                  |
| Worship Attendance        120 person                                           |
| Sunday School             35 person                                            |
| New Visitors              5 person                                             |
| New Believers             1 person                                             |
+--------------------------------------------------------------------------------+
| Submission Remarks                                                             |
| ...                                                                            |
+--------------------------------------------------------------------------------+
| Approval Note                                                                  |
| [ text area                                                                  ] |
|                                                                                |
| [Approve] [Reject] [Return to Draft]                                           |
+--------------------------------------------------------------------------------+
| Approval History                                                               |
| +-------------+----------+----------+----------------+                         |
| | Time        | Action   | User     | Reason         |                         |
| +-------------+----------+----------+----------------+                         |
```

## Confirmation Dialogs

### Approve

```text
Approve this submission?

Approved records will be included in official reports.

[Cancel] [Approve]
```

### Reject

```text
Reject this submission?

Please provide a reason.

Reason: [ textarea ]

[Cancel] [Reject]
```

### Return to Draft

```text
Return this submission to draft?

The data entry user must correct and resubmit it.

Reason: [ textarea ]

[Cancel] [Return]
```

---

# 17. UI-010 Reports

## Purpose

Allow authorized users to generate weekly, monthly, quarterly, and yearly reports.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Reports                                                                        |
+--------------------------------------------------------------------------------+
| Report Type       [Weekly ▼]                                                   |
| Organization Unit [District 1 ▼]                                               |
| Period From       [Week 01, 2026 ▼]                                            |
| Period To         [Week 27, 2026 ▼]                                            |
| Metric Category   [All ▼]                                                      |
|                                                                                |
| [Generate Report]                                                              |
+--------------------------------------------------------------------------------+
| Recent Reports                                                                 |
| +----------------+--------------+-------------+----------------+              |
| | Type           | OU           | Period      | Action         |              |
| +----------------+--------------+-------------+----------------+              |
| | Weekly         | District 1   | Week 27     | View           |              |
+--------------------------------------------------------------------------------+
```

## Report Types

| Report Type | Description |
|---|---|
| Weekly | One week or week range |
| Monthly | Month summary |
| Quarterly | Quarter summary |
| Yearly | Year summary |
| Custom | Custom date/period range |

---

# 18. UI-011 Report Detail

## Purpose

Display generated report results with table, charts, and export actions.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Report Detail                                                                  |
| District 1 | Weekly Report | Week 01 - Week 27, 2026                           |
| [Export Excel] [Export PDF]                                                    |
+--------------------------------------------------------------------------------+
| Summary Cards                                                                  |
| Attendance Total | Average | Growth % | Missing Submissions                     |
+--------------------------------------------------------------------------------+
| Trend Chart                                                                    |
| [chart]                                                                        |
+--------------------------------------------------------------------------------+
| Metric Table                                                                   |
| +----------+--------------+---------------+--------------+-------------+       |
| | Period   | Attendance   | Sunday School | Visitors     | Believers   |       |
| +----------+--------------+---------------+--------------+-------------+       |
| | Week 01  | 1,000        | 300           | 20           | 3           |       |
| | Week 02  | 1,050        | 310           | 25           | 5           |       |
| +----------+--------------+---------------+--------------+-------------+       |
+--------------------------------------------------------------------------------+
| Child OU Breakdown                                                             |
| +------------+------------+------------+------------+                          |
| | OU         | Attendance | Visitors   | Status     |                          |
| +------------+------------+------------+------------+                          |
```

## UI Rules

- Report metrics are dynamic.
- Table columns are generated from selected metrics.
- Export must match visible filters.
- Reports include approved records only.
- In `auto_approve`, submission is immediately reportable; in `approval_required`, it remains pending until approved.

---

# 19. UI-012 Users & Permissions

## Purpose

Allow Admin/Manager to manage user assignments and OU-specific permissions.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Users & Permissions                                                            |
| [Search User] [Permission Filter ▼] [OU Filter ▼] [Assign User]                |
+--------------------------------------------------------------------------------+
| +-------------+----------------+----------------+------------+----------------+|
| | User        | Default Church | Assigned OU    | Permission | Action         ||
| +-------------+----------------+----------------+------------+----------------+|
| | John        | Main Church    | Group A        | data_entry | Edit           ||
| | Peter       | Main Church    | District 1     | approver   | Edit           ||
| +-------------+----------------+----------------+------------+----------------+|
```

## Assign User Modal

```text
Assign User

User              [Search LINE user/profile ▼]
Organization Unit [OU Selector ▼]
Permission        [admin/manager/data_entry/approver/viewer ▼]
Can Override      [ ]

[Cancel] [Assign]
```

## UI Rules

- A user may have multiple permissions across multiple OUs.
- Permission names must match database values.
- Manager can assign users only within authorized subtree if backend permits.
- Admin can assign any user in the tenant.

---

# 20. UI-013 User Permission Detail

## Purpose

Display one user's profile and permissions.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| User Detail                                                                    |
| [Profile Image] John                                                           |
| LINE User ID: xxxxx                                                            |
| Email: john@example.com                                                        |
| Status: Active                                                                 |
+--------------------------------------------------------------------------------+
| Permissions                                                                    |
| +----------------+-------------+--------------+----------------+              |
| | OU             | Permission  | Override     | Action         |              |
| +----------------+-------------+--------------+----------------+              |
| | Group A        | data_entry  | No           | Remove         |              |
| | District 1     | approver    | Yes          | Remove         |              |
+--------------------------------------------------------------------------------+
| [Add Permission] [Deactivate User]                                             |
```

---

# 21. UI-014 Metric Setup

## Purpose

Allow Admin to configure dynamic metrics.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Metric Setup                                                                   |
| [Create Metric] [Category Filter ▼]                                            |
+--------------------------------------------------------------------------------+
| +------------+---------------------+------------+----------+----------+--------+|
| | Code       | Name                | Category   | Unit     | Required | Active ||
| +------------+---------------------+------------+----------+----------+--------+|
| | ATTENDANCE | Worship Attendance  | attendance | person   | Yes      | Yes    ||
| | VISITOR    | New Visitors        | attendance | person   | No       | Yes    ||
| +------------+---------------------+------------+----------+----------+--------+|
```

## Metric Form

```text
Metric

Code              [ ATTENDANCE ]
Name              [ Worship Attendance ]
Category          [ attendance ]
Unit              [ person ]
Data Type         [ number ▼]
Input Type        [ number ▼]
Aggregation       [ sum ▼]
Default Value     [ 0 ]
Min Value         [ 0 ]
Max Value         [   ]
Required          [x]
Sort Order        [ 10 ]
Active            [x]

[Cancel] [Save]
```

## UI Rules

- Do not create fixed frontend fields from metrics.
- Metrics drive forms, dashboards, and report columns.
- Deactivate metrics instead of deleting if already used.
- Provisioned metrics are tenant-owned and editable by a direct Root OU admin; template updates never silently alter the tenant form.

---

# 22. UI-015 Period Setup

## Purpose

Allow Admin to manage reporting periods.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Reporting Periods                                                              |
| [Generate Weekly Periods] [Create Period] [Year ▼]                             |
+--------------------------------------------------------------------------------+
| +----------+------------+------------+------------+------------+--------------+|
| | Type     | Label      | Start      | End        | Status     | Action       ||
| +----------+------------+------------+------------+------------+--------------+|
| | week     | Week 27    | 2026-06-29 | 2026-07-05 | open       | Edit         ||
| | week     | Week 28    | 2026-07-06 | 2026-07-12 | open       | Edit         ||
| +----------+------------+------------+------------+------------+--------------+|
```

## Status Behavior

| Status | Behavior |
|---|---|
| open | Normal submission allowed |
| closed | Late submission may require permission |
| locked | No normal editing allowed |

Backend determines final behavior.

---

# 23. UI-016 Audit Logs

## Purpose

Allow authorized users to inspect critical actions.

## Wireframe

```text
+--------------------------------------------------------------------------------+
| Audit Logs                                                                     |
| [OU ▼] [Entity Type ▼] [Action ▼] [Actor ▼] [Date From] [Date To] [Search]    |
+--------------------------------------------------------------------------------+
| +---------------------+-------------+-------------+----------------+----------+|
| | Time                | User        | Entity      | Action         | Details  ||
| +---------------------+-------------+-------------+----------------+----------+|
| | 2026-07-05 10:30    | John        | submission  | submit         | View     ||
| | 2026-07-05 10:32    | Peter       | approval    | approve        | View     ||
| +---------------------+-------------+-------------+----------------+----------+|
```

## UI Rules

- Audit log is read-only.
- The OU filter contains only OUs within the caller's audit-visible scope.
- Direct Root OU admins can inspect tenant-wide events; non-root admins see only their assigned subtree.
- Managers see only OU/member-management and submission events in their managed subtree.
- Approvers see only approval-related events in their approval subtree.
- Data-entry and viewer roles do not see the Audit Logs navigation item.
- Tenant-wide events without an OU are visible only to a direct Root OU admin.
- Expandable details show redacted structured data and the request ID; secrets and tokens are never displayed.
- The source assignment is shown when inherited OU administration authorized the action.

---

# 24. UI-017 Profile

## Purpose

Show the current user's LINE profile, assigned OUs, and permissions.

## Wireframe

```text
+--------------------------------+
| Profile                        |
| [Profile Image]                |
| Display Name                   |
| LINE User ID                   |
+--------------------------------+
| My Permissions                 |
| Main Church / Group A          |
| data_entry                     |
|                                |
| Main Church / District 1       |
| viewer                         |
+--------------------------------+
| [Logout]                       |
+--------------------------------+
```

---

# 25. UI-018 Access Denied

## Wireframe

```text
+--------------------------------+
| Access Denied                  |
| You do not have permission to  |
| access this page or action.    |
|                                |
| [Back to Dashboard]            |
+--------------------------------+
```

## Usage

Show this page when:

- User has no permission for route.
- RPC returns authorization error.
- RLS blocks required data.

---

# 26. UI-019 Not Found

## Wireframe

```text
+--------------------------------+
| Page Not Found                 |
| The page you requested does    |
| not exist.                     |
|                                |
| [Back to Dashboard]            |
+--------------------------------+
```

---

# 27. Shared Components

| Component | Purpose |
|---|---|
| `AppShell` | Main layout wrapper |
| `TopBar` | Header navigation |
| `SideNav` | Desktop navigation |
| `BottomNav` | Mobile navigation |
| `Breadcrumb` | OU path display |
| `OuSelector` | Select accessible OU |
| `PeriodSelector` | Select reporting period |
| `MetricInput` | Render dynamic metric input |
| `MetricSummaryCard` | Dashboard metric card |
| `StatusBadge` | Submission/period status badge |
| `ConfirmDialog` | Confirm critical actions |
| `ErrorAlert` | Standard error message |
| `EmptyState` | Standard empty state |
| `LoadingState` | Spinner/skeleton loading |
| `PermissionGuard` | UI-level visibility helper |
| `SubmissionStatusTable` | Submission status list |
| `ApprovalHistoryTable` | Approval log display |
| `ReportTable` | Dynamic report table |
| `TrendChart` | Chart.js trend chart |
| `AuditLogViewer` | Expandable audit log details |

---

# 28. Standard UI States

Every data screen must handle:

```text
loading
loaded
empty
validation_error
authorization_error
server_error
network_error
success
```

## Error Display Rules

| Error Type | UI Behavior |
|---|---|
| Validation | Inline field error and top alert |
| Authorization | Access denied message or disabled action |
| Network | Retry option |
| Server | Friendly error with technical detail hidden by default |
| Unknown | Generic error message |

---

# 29. Form UX Rules

1. Required fields show `*`.
2. Numeric metric fields use numeric keyboard on mobile.
3. Save buttons must show loading state while submitting.
4. Submit buttons must prevent double-click submission.
5. Dirty forms must warn before navigation.
6. Confirmation dialogs are required for submit, approve, reject, return, deactivate, and delete-like actions.
7. Backend validation errors must be mapped to user-friendly messages.

---

# 30. Status Badge Design

| Status | Label | Suggested Tone |
|---|---|---|
| draft | Draft | Neutral |
| submitted | Submitted | Info |
| approved | Approved | Success |
| rejected | Rejected | Error |
| returned | Returned | Warning |
| missing | Missing | Warning |
| open | Open | Success |
| closed | Closed | Neutral |
| locked | Locked | Error |

Do not rely only on color. Always include text label.

---

# 31. Permission-Aware UI Behavior

## 31.1 Data Entry User

Visible focus:

- Dashboard
- My weekly submissions
- Own reports
- Profile

Hidden by default:

- Organization management
- User management
- Metric setup
- Audit logs

## 31.2 Manager

Visible focus:

- Dashboard for assigned OU subtree
- Organization subtree management
- Submission monitoring
- Reports
- User assignment within subtree, if allowed

## 31.3 Approver

Visible focus:

- Dashboard
- Approval queue
- Submission detail
- Reports

## 31.4 Admin

Visible focus:

- All tenant management features
- User permissions
- Metrics
- Periods
- Audit logs

---

# 32. Responsive Behavior

## Desktop

- Use tables for list views.
- Sidebar is visible.
- Detail pages may use two-column layout.
- Dashboard cards can show 3–4 per row.

## Tablet

- Sidebar may collapse.
- Dashboard cards show 2 per row.
- Forms remain single column or two columns depending on width.

## Mobile

- Tables become cards.
- Main actions appear as full-width buttons.
- Bottom navigation may be used.
- Dashboard cards stack vertically.
- Organization tree should use expandable accordion.

---

# 33. Accessibility Rules

- All buttons must have clear labels.
- Forms must have labels, not only placeholders.
- Error messages must be text, not color only.
- Keyboard navigation should work on desktop.
- Use sufficient contrast.
- Icons must not be the only indication of meaning.

---

# 34. Page-Level Acceptance Criteria

## Dashboard

- User can see aggregated statistics for accessible OU.
- User can change period.
- User can change OU if multiple OUs are accessible.
- Metric cards are dynamic.
- Missing submissions are visible for parent OU.

## Submission Form

- User can input all active metrics.
- Required metric validation works.
- Submit calls backend RPC.
- Phase 1 submit results in approved status.
- Unauthorized submit is blocked by backend and shown clearly.

## Organization

- Admin/Manager can view tree.
- Admin/Manager can create child OU.
- Tree supports unlimited hierarchy.
- Tree displays only directly assigned OU roots and their authorized descendants.
- Tree never displays ancestor, sibling, or unrelated OU branches outside the user's assignment scope.
- Multiple assigned subtrees are merged without duplicate OU nodes.
- Full tenant tree visibility requires a church-root assignment or system-administrator authority.
- Parent OU managers automatically receive inherited OU-administration capabilities on child and descendant OUs.
- Inherited administration does not grant approval, override, `admin` assignment, or OU Type Setting permissions.
- Detail panel shows users and permissions.

## Reports

- User can select OU and period.
- Report respects accessible subtree.
- Export buttons are available.
- Report uses approved submissions only.

## Approval — Phase 2

- Approver can see pending queue.
- Approver can approve, reject, or return submission.
- Approval history is visible.
- Override action is clearly logged.

---

# 35. AI Implementation Instructions

When generating frontend code from this document:

1. Follow `05_Frontend_Design.md` for folder structure.
2. Use this document for page layout and component behavior.
3. Do not implement final authorization in frontend.
4. Use frontend permission checks only for UI visibility.
5. Always call RPC for critical workflows.
6. Do not hard-code fixed attendance fields.
7. Generate forms from `statistic_metrics`.
8. Generate dashboard cards from metric summary responses.
9. Generate report columns dynamically from selected metrics.
10. Use reusable components for status badges, metric inputs, selectors, and dialogs.
11. Keep route files small.
12. Put service calls in service modules.
13. Handle loading, empty, success, and error states on every page.
14. Use TypeScript strict mode.
15. Use database-generated types where available.

---

# 36. Phase 1 MVP Screens

Phase 1 must implement:

```text
UI-001 Login / LIFF Loading
UI-002 Dashboard
UI-003 Organization Tree
UI-004 Organization Detail
UI-005 Weekly Submission List
UI-006 Weekly Submission Form
UI-007 Submission Detail
UI-010 Reports
UI-011 Report Detail
UI-012 Users & Permissions
UI-014 Metric Setup
UI-015 Period Setup
UI-017 Profile
UI-018 Access Denied
UI-019 Not Found
```

Phase 1 may hide approval queue from navigation, but the UI structure should not conflict with Phase 2.

---

# 37. Phase 2 Screens

Phase 2 adds or enables:

```text
UI-008 Approval Queue
UI-009 Approval Detail
UI-016 Audit Logs
Approval History panels
Reject / Return workflow
Override workflow
```

---

# 38. Next Document

Continue with:

`07_Reports_Dashboard.md`

This next document should define KPI logic, dashboard aggregation behavior, chart definitions, report formats, export layouts, and reporting acceptance criteria.
