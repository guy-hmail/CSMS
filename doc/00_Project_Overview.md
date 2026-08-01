# 00_Project_Overview.md

# Church Statistics Management System (CSMS)

Version: 1.0

Status: Draft

---

# 1. Introduction

Church Statistics Management System (CSMS) is a web-based application developed to digitize weekly church statistical reporting.

The system replaces Excel-based reporting with a centralized platform that supports hierarchical organization management, attendance collection, reporting, dashboards, and future approval workflow.

The system is designed using modern cloud-native architecture with **SvelteKit**, **Supabase**, and **LINE LIFF Authentication**.

---

# 2. Project Objectives

The primary objectives are:

* Replace manual Excel reporting
* Provide real-time church statistics
* Reduce duplicated data entry
* Support unlimited organization hierarchy
* Allow each organization unit to access its own statistics
* Automatically aggregate statistics to upper organizational levels
* Support future approval workflow without redesigning the database
* Minimize operational cost using free/open-source technologies

---

# 3. Business Problems

Current challenges include:

* Manual data collection through Excel or chat applications
* Difficult report consolidation
* Duplicate data
* Late submissions
* No audit trail
* Difficult historical comparison
* No centralized dashboard
* No standardized organizational management

---

# 4. Project Scope

## In Scope

### Authentication

* LINE LIFF Login
* User Profile Synchronization

### Organization

* Unlimited Organization Hierarchy
* Organization Management
* User Assignment
* Organization Permission

### Attendance

* Weekly Attendance
* Sunday School
* New Visitors
* New Believers
* Remarks

### Dashboard

* My Organization Dashboard
* Parent Organization Dashboard
* Trend Charts
* Summary Cards

### Reports

* Weekly
* Monthly
* Yearly
* Excel Export
* PDF Export

### Security

* Row Level Security
* Audit Log

---

## Out of Scope (Version 1)

* Financial Reporting
* Donation Management
* Membership Management
* Event Registration
* QR Check-in
* Mobile Native Application
* AI Analytics
* Multi-language UI

---

# 5. System Vision

The system should become the single source of truth for church statistical reporting.

Every organization unit should:

* Enter data once
* View its own statistics
* View historical trends
* Compare previous periods

Every upper-level organization should:

* View all child organizations
* Monitor submission status
* Monitor growth
* Generate reports

---

# 6. Organization Hierarchy

The system supports unlimited hierarchy depth.

Example

```text
Church
│
├── Region
│
├── District
│
├── Zone
│
├── Cell Group
│
└── Team
```

Different churches may have completely different structures.

The system **must not assume fixed organization levels.**

Hierarchy depth is unlimited.

---

# 7. Organization Unit (OU)

An Organization Unit (OU) represents any organizational structure.

Examples:

* Church
* Region
* District
* Ministry
* Cell Group
* Team

Every OU contains:

* Parent OU
* Child OU
* Assigned Users
* Reports
* Dashboard

---

# 8. Data Entry Principle

To avoid duplicate counting, only **Leaf Organization Units** should submit attendance data.

A Leaf Organization Unit is defined as an organization that has no child organizations.

Example

```text
Church

└── District

     ├── Group A   ← Data Entry

     ├── Group B   ← Data Entry

     └── Group C   ← Data Entry
```

Statistics for parent organizations are calculated automatically by aggregating approved records from descendant leaf nodes.

Future versions may allow manual override if required.

---

# 9. User Roles

The system separates organizational structure from permissions.

Users may have different permissions in different Organization Units.

Typical permissions include:

* Organization Administrator
* Organization Manager
* Data Entry
* Approver
* Viewer

Permissions are assigned per Organization Unit.

Position names (Leader, Pastor, Elder, etc.) are informational only and do not determine system permissions.

---

# 10. Approval Strategy

Version 1 (MVP)

Attendance submission is automatically considered Approved.

Workflow

```text
Draft

↓

Submit

↓

Approved
```

Version 2

Approval workflow will be enabled.

```text
Draft

↓

Submit

↓

Pending Approval

↓

Approved
```

Approvers are determined dynamically based on the nearest ancestor Organization Unit with an assigned approver.

Higher-level approvers may override lower-level approvals.

---

# 11. Dashboard Concept

Each Organization Unit has its own dashboard.

Dashboard contains:

* Attendance
* Sunday School
* New Visitors
* New Believers
* Historical Trend
* Growth Comparison

Upper Organization Units additionally see:

* Child Organization Summary
* Submission Status
* Approval Status
* Drill-down Reports

---

# 12. Reporting Strategy

Reports are available by:

* Week
* Month
* Quarter
* Year

Export formats:

* Excel
* PDF

Reports are generated recursively from descendant Organization Units.

---

# 13. Security Principles

The system follows Zero Trust principles.

Security is enforced primarily at the database layer using Supabase Row Level Security (RLS).

The frontend never determines data access permissions.

---

# 14. High-Level Architecture

```text
LINE LIFF
      │
      ▼
Authentication
      │
      ▼
SvelteKit Frontend
      │
      ▼
Supabase API
      │
 ┌────┴────────────┐
 │                 │
 ▼                 ▼
PostgreSQL     Storage
      │
      ▼
Row Level Security
```

---

# 15. Technology Stack

| Layer          | Technology       |
| -------------- | ---------------- |
| Frontend       | SvelteKit        |
| Language       | TypeScript       |
| UI             | Skeleton UI      |
| Backend        | Supabase         |
| Database       | PostgreSQL       |
| Authentication | LINE LIFF        |
| Authorization  | Supabase RLS     |
| Storage        | Supabase Storage |
| Hosting        | Vercel           |
| Charts         | Chart.js         |
| Export         | SheetJS, pdf-lib |

---

# 16. Development Phases

## Phase 1

Minimum Viable Product

Features

* Authentication
* Organization Management
* Attendance Entry
* Dashboard
* Reports

---

## Phase 2

Approval Workflow

* Submit
* Approve
* Reject
* Return to Draft
* Approval Queue

---

## Phase 3

Workflow Enhancement

* Notifications
* Revision History
* Unlock
* Reminder

---

## Phase 4

Analytics

* KPI
* Trend Analysis
* Ranking
* AI Summary
* Forecast

---

# 17. Design Principles

The following principles guide system development:

1. Unlimited organization hierarchy
2. Recursive data aggregation
3. Role-based permission per Organization Unit
4. Business logic centralized in backend
5. Thin frontend
6. Audit every critical action
7. Future-proof database schema
8. Approval workflow can be enabled without schema redesign

---

# 18. Success Criteria

The project will be considered successful when:

* All weekly statistics are submitted through the system.
* Manual Excel consolidation is eliminated.
* Reports are generated automatically.
* Organization leaders can monitor attendance in real time.
* Historical trends are available for every Organization Unit.
* The approval workflow can be enabled without database migration.

---

# Next Document

Continue with:

**01_Business_Requirements.md**
