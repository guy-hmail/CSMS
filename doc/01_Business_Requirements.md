# 01_Business_Requirements.md

# Business Requirements Specification (BRS)

Project: Church Statistics Management System (CSMS)

Version: 1.0

---

# 1. Purpose

This document defines the business requirements, functional requirements, business rules, and user permissions for the Church Statistics Management System.

This document serves as the primary functional reference for software development.

---

# 2. Business Objectives

The system shall:

* Centralize weekly church statistics.
* Replace Excel-based reporting.
* Support unlimited organizational hierarchy.
* Reduce duplicate data entry.
* Allow each Organization Unit (OU) to manage its own statistics.
* Automatically aggregate child statistics to parent organizations.
* Provide dashboards and reports.
* Support approval workflow in future versions without redesign.

---

# 2.1 Multi-Tenant Requirements

* One `church` record represents one isolated tenant.
* A LINE/Supabase user is a global identity and may belong to multiple tenants through active `church_members` records.
* The same user may have different OU roles in each tenant.
* Every tenant has exactly one active Root OU at Level 1; all descendant OUs belong to that root and tenant.
* Every tenant-owned query, mutation, report, export, search, and count must be isolated by server-validated tenant context.
* Tenant selection never grants access by itself; the backend must verify active membership from the authenticated identity.
* Switching tenant must clear OU, report-period, permission, and cached business state before loading the new tenant.
* Tenant-wide OU Type Setting is independent per tenant and may be changed only by a direct admin of that tenant's Root OU Level 1.
* Every tenant-wide settings page and mutation must require an active `admin` assignment directly on that tenant's Root OU Level 1. A manager, a non-root admin, or an inherited administration capability is not sufficient.
* OU Types are a tenant-wide catalog and are not permanently bound to a tree level. Any active type may be selected for an OU at any descendant level, subject to tenant validation.
* `sort_order` controls how OU Types are displayed in selection lists; it does not define or restrict the OU tree level.
* Each OU Type may define `default_allow_data_entry` as the initial value when a new OU is created. The OU record may override that default.
* Revoking one tenant membership must not affect the user's valid memberships in other tenants.
* Platform system administration is separate from tenant roles and must be audited.

---
# 3. Organization Structure

The system supports unlimited hierarchy depth.

Example

```text
Church
│
├── Region
│   ├── District
│   │   ├── Group A
│   │   └── Group B
│   └── District
└── Ministry
```

The system must **not assume fixed hierarchy levels**.

Each church may have different structures.

---

# 4. Organization Unit (OU)

Every OU consists of

* Parent OU
* Child OU
* Assigned Users
* Dashboard
* Reports

An OU may represent

* Church
* Region
* District
* Ministry
* Cell Group
* Team

---

# 5. User Assignment

Users are assigned directly to Organization Units.

Permissions are OU-specific.

Example

| User  | OU         | Permission    |
| ----- | ---------- | ------------- |
| John  | Group A    | Data Entry    |
| Peter | District 1 | Approver      |
| David | Church     | Administrator |

The same user may have different permissions in different Organization Units.

---

# 6. User Permissions

The system supports permission-based authorization.

## Administrator

Permissions

* Full access
* Manage Organization
* Manage Users
* Assign Permissions
* View All Reports
* Override Approval

---

## Organization Manager

Permissions

* Manage assigned OU
* Create Child OU
* Delete Child OU
* Assign Users
* View Reports
* Manage Dashboard

---

## Data Entry

Permissions

* Enter attendance
* Edit own draft
* View own reports

---

## Approver (`approval_required`)

Permissions

* Approve submissions
* Reject submissions
* Return submitted/approved records for correction
* Reopen rejected records when correction is explicitly allowed

---

## Viewer

Permissions

* Read-only access

---

# 7. Attendance Management

Each attendance record contains

* Attendance
* Sunday School
* New Visitors
* New Believers
* Remarks

Attendance is submitted weekly.

Only one attendance record is allowed per OU per week.

---

# 8. Data Entry Rules

Primary Rule

Only **Leaf Organization Units** should submit attendance.

Leaf OU

= Organization Unit without child OU.

Reason

* Prevent duplicate counting.
* Simplify aggregation.
* Simplify reporting.

Future versions may allow manual override.

Canonical override rule:

- `allow_data_entry = true` means the OU submits statistics for that OU's own activity only.
- A non-leaf OU may be enabled explicitly, but its direct submission must not repeat totals already submitted by descendants.
- Dashboard/report aggregation sums approved direct submissions from every enabled reporting OU in the selected subtree exactly once.
- Parent dashboards never persist a pre-aggregated attendance row.
- Enabling direct entry on a non-leaf OU requires a warning/confirmation because incorrect use can double-count business data.

---

# 9. Weekly Workflow

## 9.1 Calculation period and submission window

The weekly calculation boundary and the submission deadline are independent Tenant settings:

- `reporting_week_ends_on` defines the last date included in calculations. A Sunday boundary produces a Monday–Sunday seven-day period.
- `submission_deadline_days_after_period_end` defines how many local calendar days after `period_end` remain available for normal submission. It must be 1–6.
- The submission window opens at 00:00 on `period_end` and closes at 23:59:59.999999 on `period_end + submission_deadline_days_after_period_end`, evaluated in the Tenant timezone.
- Dashboard/report aggregation, ISO week, and month/quarter/year assignment always use `period_end`; a submission deadline must never move business data into another reporting period.
- Submission, approval, dashboard, report selectors, and missing-submission reminders must use the same server-generated canonical period/window.
- New drafts and normal submissions are rejected before opening and after the deadline. A specific submission returned through the authorized edit-request workflow may be corrected and resubmitted after the normal deadline while the period remains administratively open.
- Each period snapshots `submission_opens_at` and `submission_due_at`; later Tenant-setting changes do not rewrite historical deadlines.

## Tenant mode: `auto_approve` (initial MVP default)

Workflow

```text
Draft

↓

Submit

↓

Approved
```

Submit immediately becomes Approved.

No manual approval step is used.

---

## Tenant mode: `approval_required`

Workflow

```text
Draft

↓

Submit

↓

Pending Approval

↓

Approved
```

---

# 10. Approval Workflow

Approvers are assigned per Organization Unit.

If an OU has no approver

↓

The system automatically searches parent Organization Units.

Nearest ancestor approver becomes responsible.

If multiple active approvers exist at that nearest OU, any one may act and the first committed transition wins. If none exists through the Root OU, only a direct Root OU admin may act.

Example

```text
Church (Approver)

│

Region (No Approver)

│

District (No Approver)

│

Group A (Submit)
```

The Church approver receives the approval request.

---

# 11. Approval Override

Higher-level approvers may override lower-level approvals.

Override actions must be logged.

Audit includes

* Override By
* Override Time
* Reason

---

# 12. Edit After Approval

Approved values are never edited in place. An authorized approver/admin must return the submission for correction first.

Workflow

```text
Approved

↓

Returned

↓

Edit

↓

Submit

↓

Approve
```

The previous approved state and values remain traceable through audit/revision history.

---

# 13. Dashboard Requirements

Every Organization Unit can view

* Own attendance
* Weekly summary
* Monthly summary
* Yearly summary
* Trend chart

Parent Organization Units additionally view

* Child summary
* Submission status
* Approval status

---

# 14. Report Requirements

Reports

* Weekly
* Monthly
* Quarterly
* Yearly

Filters

* Organization Unit
* Week
* Month
* Year

Export

* Excel
* PDF

---

# 15. Organization Management

Organization Managers may

* Create child OU
* Edit child OU
* Delete child OU
* Assign users

## OU Tree Visibility

The Organization Tree must display only Organization Units inside the current user's authorized scope.

* Each directly assigned OU is a visible root.
* Inheritable permissions (`admin`, `manager`, `approver`, `viewer`) may include descendants of the assigned OU.
* Direct-only permissions such as `data_entry` show only the directly assigned OU unless another assignment grants wider access.
* Ancestors above the assigned OU, sibling OUs, and unrelated OUs must not be displayed.
* If a user has multiple OU assignments, the UI displays the union of the authorized subtrees without duplicate OUs.
* An `admin` does not automatically see the entire tenant. Full-tree visibility requires an assignment on the church root OU or system-administrator authority.
* The backend/RLS must filter accessible OUs before returning them. The frontend must not load the full tenant tree and hide unauthorized nodes only in the UI.

## Inherited OU Administration

An active `manager` assigned directly to a parent OU automatically receives inherited OU-administration capabilities on every descendant OU.

* The manager remains `manager` on the directly assigned OU.
* On child and deeper descendant OUs, the manager can create/edit/deactivate child OUs and manage LINE account assignments.
* Inherited administration is an effective permission and must not create duplicate `admin` rows in `ou_members`.
* The inherited manager may assign `manager`, `data_entry`, `approver`, and `viewer` within descendants, but may not assign `admin` or grant `can_override`.
* Inherited administration does not grant approval, rejection, workflow override, tenant-wide audit administration/export, OU Type Setting, or organization-wide setting permissions. A manager may still read the limited operational audit events allowed for the managed subtree.
* The manager cannot edit the parent/ancestor OU, change their own assignment, or act outside the assigned subtree.
* Removing/deactivating the source manager assignment immediately removes inherited administration.
* Moving an OU to another parent must recalculate inherited administration from the new ancestry.
* Audit logs must record both the acting user and the source manager assignment that granted inherited administration.

Deletion is prohibited when

* Child OU exists
* Attendance exists

---

# 16. User Management

Users authenticate through LINE LIFF.

The system automatically creates user profiles on first login.

Administrators may

* Activate user
* Deactivate user
* Assign Organization Unit
* Change permissions

---

# 17. Business Rules

## BR-001

Every Organization Unit has only one parent.

---

## BR-002

Hierarchy depth is unlimited.

---

## BR-003

One attendance record per OU per week.

---

## BR-004

Attendance values cannot be negative.

---

## BR-005

Only authorized users may submit attendance.

---

## BR-006

Statistics shown on parent dashboards are aggregated recursively from descendant Organization Units.

---

## BR-007

Approval is performed by the nearest available ancestor approver.

---

## BR-008

Higher-level approvers may override approvals.

---

## BR-009

Every critical action must generate an audit log.

Audit requirements:

- Audit logs are append-only and cannot be created, edited, or deleted directly by an authenticated client.
- Tenant audit events record the tenant, affected OU when applicable, actor, actor's tenant membership, authorization-source assignment when inherited authority was used, action, affected entity, before/after state, request ID, and timestamp.
- A direct Root OU admin can view all audit events in the tenant.
- A non-root admin can view audit events only in the assigned OU subtree.
- A manager can view only OU/member-management and submission events in the managed subtree.
- An approver can view only approval-related events in the approval subtree.
- Data-entry and viewer roles have no general audit-log access.
- Platform audit events and system-admin access use a separate audited service path.
- Secrets, authentication tokens, and unredacted sensitive personal data must not be written to an audit payload.

---

## BR-010

Reports only include Approved records.

For an `auto_approve` tenant, submission becomes Approved in the same transaction. For an `approval_required` tenant, it is excluded until an approver approves it.

---

## BR-011

Each Organization Unit can only access statistics within its own subtree.

---

## BR-012

Permissions are assigned per Organization Unit, not by position title.

---

# 18. Non-Functional Requirements

Performance

* Dashboard < 3 seconds
* Attendance Save < 2 seconds

Availability

* 99.5%

Security

* Row Level Security
* HTTPS
* Audit Logging

Scalability

* Unlimited hierarchy depth
* Support 10,000+ attendance records

Maintainability

* Modular architecture
* TypeScript
* Feature-based structure

---

# 19. Acceptance Criteria

Phase 1 is accepted when

* Users authenticate using LINE.
* Organization hierarchy can be managed.
* Users submit weekly attendance.
* Dashboards display aggregated statistics.
* Reports export successfully.
* Audit logs are generated.

Phase 2 is accepted when

* Approval workflow operates correctly.
* Override approvals are supported.
* Approval history is retained.
* Pending approvals appear in approval queues.

---

# Next Document

Continue with:

**02_Database_Design.md**
