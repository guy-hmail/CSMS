# Church Statistics Management System (CSMS)

> A hierarchical Church Attendance & Statistics Management System built with **SvelteKit + Supabase + LINE LIFF**, designed for multi-level church organizations with approval workflow, reporting, dashboards, and role-based access control.

**Production status:** Live since 8 August 2026. The current production baseline includes LINE authentication, multi-tenant organization management, weekly submissions, approval workflow, dashboards, reports/export, user settings, and super-admin tenant management. Remaining backlog items are tracked in `doc/11_backlog.md`.

---

# Overview

Church Statistics Management System (CSMS) is a web-based application for collecting, approving, and reporting weekly church statistics.

The system is designed for churches that have hierarchical organizational structures such as:

```text
Church
├── Region
│   ├── District A
│   │   ├── Group A
│   │   └── Group B
│   └── District B
└── Region B
```

Each Organization Unit (OU) can have its own users, permissions, reports, dashboards, and approval responsibilities.

The system uses **LINE LIFF** for authentication and **Supabase** as Backend-as-a-Service.

---

# Project Goals

* Replace Excel-based weekly reporting
* Support hierarchical church organizations
* Provide real-time attendance statistics
* Support approval workflow
* Provide dashboards for every organizational level
* Support future expansion without database redesign

---

# Key Features

## Organization Management

* Hierarchical Organization Units (Unlimited Levels)
* Tree View
* Parent / Child Relationship
* Organization Management

---

## User Management

* LINE LIFF Login
* Role-Based Access Control (RBAC)
* Assign User to Organization Unit
* Multiple Roles per User

---

## Attendance Management

* Weekly Attendance Entry
  * Tenant-configured calculation week boundary
  * Independent 1–6 day submission deadline with Tenant-timezone enforcement
* Sunday School Statistics
* New Visitor Statistics
* New Believer Statistics
* Remarks

---

## Approval Workflow (Phase 2)

* Submit
* Approve
* Reject
* Return to Draft
* Override Approval
* Approval History

---

## Dashboard

Every Organization Unit can view:

* Current Week Summary
* Monthly Summary
* Yearly Summary
* Trend Charts
* Growth Statistics

Parent Organization Units can view:

* Own Statistics
* Aggregated Child Statistics
* Pending Approval
* Submission Status

---

## Reports

* Weekly Report
* Monthly Report
* Quarterly Report
* Yearly Report
* Excel Export
* PDF Export

---

## Audit

* Login History
* Data Changes
* Approval History
* Organization Changes
* User Assignment History

---

# System Architecture

```text
                   LINE LIFF
                        │
                        │
                  Authentication
                        │
                        ▼
                 SvelteKit Frontend
                        │
        ┌───────────────┼────────────────┐
        │               │                │
        ▼               ▼                ▼
     Supabase      Edge Functions    Storage
        │
        ▼
 PostgreSQL Database
        │
        ▼
 Row Level Security (RLS)
```

---

# Technology Stack

| Layer           | Technology              |
| --------------- | ----------------------- |
| Frontend        | SvelteKit               |
| UI              | Skeleton UI             |
| Backend         | Supabase                |
| Database        | PostgreSQL              |
| Authentication  | LINE LIFF               |
| Authorization   | Supabase RLS            |
| Hosting         | Vercel                  |
| Storage         | Supabase Storage        |
| Background Jobs | Supabase Edge Functions |
| Charts          | Chart.js                |
| Export          | SheetJS / pdf-lib       |

---

# Project Phases

## Phase 1 — MVP ✅ Production

Goal:

Collect weekly statistics.

Features

* LINE Login
* Organization Tree
* Attendance Entry
* Dashboard
* Reports
* Excel Export

Tenants can use `auto_approve`, where submitted records are approved automatically.

---

## Phase 2 — Approval Workflow ✅ Production

Additional Features

* Submit
* Approve
* Reject
* Return to Draft
* Approval Queue
* Approval History

---

## Phase 3 — Notification & Workflow 🟡 Partial / Planned

Additional Features

* LINE Notification
* Reminder
* Missing Submission
* Unlock
* Revision

---

## Phase 4 — Analytics 🟡 Partial / Planned

Additional Features

* KPI Dashboard
* Trend Analysis
* Ranking
* Forecast
* AI Summary

---

# Repository Structure

```text
docs/
│
├── README.md
├── 00_Project_Overview.md
├── 01_Business_Requirements.md
├── 02_Database_Design.md
├── 03_RLS_and_Permissions.md
├── 04_API_Design.md
├── 05_Frontend_Design.md
├── 06_UI_Wireframe.md
├── 07_Reports_Dashboard.md
├── 08_Deployment.md
├── 09_Coding_Convention.md
├── 10_Backlog.md
├── 11_Phase_Plan.md
├── 12_AI_Context.md
└── 13_Multi_Tenant_Architecture.md
```

---

# Development Principles

* Keep business logic inside Supabase whenever possible.
* UI should remain thin.
* Use Row Level Security instead of frontend permission checks.
* Every operation must be auditable.
* Organization hierarchy must support unlimited depth.
* Statistics are always aggregated recursively.
* Leaf Organization Units are the primary data entry points.
* Parent Organization Units consume aggregated statistics.

---

# Coding Principles

* TypeScript Strict Mode
* SvelteKit Best Practices
* Feature-Based Folder Structure
* Repository Pattern
* Strong Typing
* No Business Logic inside UI Components

---

# Naming Convention

## Database

* snake_case

Example

```text
attendance_records
organization_units
```

---

## API

camelCase

Example

```text
getAttendance()
submitAttendance()
approveAttendance()
```

---

## Components

PascalCase

```text
AttendanceForm.svelte

DashboardCard.svelte

ApprovalQueue.svelte
```

---

# Documentation Index

| File                        | Description                                             |
| --------------------------- | ------------------------------------------------------- |
| 00_Project_Overview.md      | System overview, architecture, roadmap                  |
| 01_Business_Requirements.md | Functional requirements and business rules              |
| 02_Database_Design.md       | ERD, tables, relationships, indexes                     |
| 03_RLS_and_Permissions.md   | Permission model and Supabase RLS                       |
| 04_API_Design.md            | RPC, Edge Functions, API contracts                      |
| 05_Frontend_Design.md       | SvelteKit architecture and folder structure             |
| 06_UI_Wireframe.md          | Screen specifications and user flows                    |
| 07_Reports_Dashboard.md     | Reports, dashboards, KPIs, charts                       |
| 08_Deployment.md            | Vercel, Supabase, LINE LIFF deployment guide            |
| 09_Coding_Convention.md     | Coding standards and best practices                     |
| 10_Backlog.md               | Product backlog and future enhancements                 |
| 11_Phase_Plan.md            | Implementation phases and milestones                    |
| 12_AI_Context.md            | AI coding instructions for Cursor, Claude Code, and GPT |
| 13_Multi_Tenant_Architecture.md | Canonical tenant, membership, Root OU, and isolation model |

---

# License

Internal Use Only

Copyright © Church Statistics Management System Project
