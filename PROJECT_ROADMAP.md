# PROJECT_ROADMAP.md

# Project Roadmap

Last updated: 8 August 2026

Current status: **Production Live — Continuous Improvement**

CSMS has completed its first production go-live. Core backend, frontend, testing, and production deployment milestones are complete. Open Tenant Settings items and operational improvements remain active backlog work and do not change the production deployment status.

## Phase A — Blueprint

| Task | Status |
|---|---|
| README | ✅ |
| PROJECT_CONTEXT | ✅ |
| 00 Project Overview | ✅ |
| 01 Business Requirements | ✅ |
| 02 Database Design | ✅ |
| 03 RLS & Permissions | ✅ |
| 04 API Design | ✅ |
| 05 Frontend Design | ✅ |
| 06 UI Wireframe | ✅ |
| 07 Reports & Dashboard | ✅ |
| 08 Deployment | ✅ |
| 09 Coding Convention | ✅ |
| 10 AI Context | ✅ |

Goal: Blueprint and deployment documentation are established. Operational details must continue to be updated after each production change.

---

## Phase B — Backend

Status: ✅ Complete for the current production baseline

- Database schema and migrations
- RLS and security helpers
- RPC and Edge Functions
- Seed/reference data
- Audit logging
- Database and integration tests

Deliverable: Functional backend API.

---

## Phase C — Frontend

Status: ✅ Complete for the current production baseline

- Authentication
- Organization Management
- Weekly Submission
- Approval
- Dashboard
- Reports
- Settings

Deliverable: Production-ready SvelteKit application.

---

## Phase D — Testing

Status: ✅ Release validation completed before go-live; regression testing remains continuous

- Unit Tests — ✅
- Integration Tests — ✅
- RLS Verification — ✅ automated regression coverage
- Performance Testing — 🔄 ongoing production validation
- UAT — ✅ pre-go-live routes validated

---

## Phase E — Deployment

Status: ✅ Production Go-Live completed on 8 August 2026

- Vercel production deployment — ✅
- Supabase production deployment — ✅
- Monitoring and alerting — 🔄 operational follow-up
- Backup/restore verification — 🔄 operational follow-up
- Documentation — 🔄 maintained continuously

Operational follow-up: monitoring, alerting, backup/restore drills, performance validation, and security review remain continuous production responsibilities.

---

## Phase F — Continuous Improvement

Status: 🔄 Active

- Complete remaining Tenant Settings and Reporting Period management work
- Notification Center and LINE notifications
- Performance and scalability improvements
- Security, observability, backup, and accessibility improvements
- Advanced analytics, forecasting, and mobile support

---

## Milestones

1. Blueprint Frozen — ✅
2. Database Ready — ✅
3. Backend Complete — ✅
4. Frontend Complete — ✅
5. UAT Passed — ✅
6. Production Go-Live — ✅ 8 August 2026
7. Continuous Improvement — 🔄 Active

---

## Working Rules

1. Update documentation first.
2. Freeze design before implementation.
3. Code follows documentation.
4. Review before merge.
5. Keep ADR updated whenever architecture changes.
