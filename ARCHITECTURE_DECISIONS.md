# ARCHITECTURE_DECISIONS.md

# Architecture Decision Records (ADR)

Project: Church Statistics Management System (CSMS)

This document records architectural decisions. These decisions are considered frozen unless explicitly superseded.

---

## ADR-001 — Multi-Tenant

**Decision:** Shared database with `church_id` on every tenant-owned table. `users` is a global identity table; access to a tenant is granted only through an active `church_members` record.

**Why:** Simpler operations, Supabase-compatible, scalable with Row Level Security.

**Invariant:** Tenant context must be validated on the server from `auth.uid()` and `church_members`. A client-provided `church_id` is never sufficient authorization.

**Platform role field:** `users.global_role` is the persisted source of truth. System-admin checks and UI booleans are derived from `global_role = 'system_admin'`; there is no separate `users.is_system_admin` column.

---

## ADR-002 — Organization Hierarchy

**Decision:** Every tenant has exactly one active Root OU at Level 1. Unlimited descendants use `parent_id + structure_root_id + path + level`.

**Why:** Flexible church structures without fixed levels.

---

## ADR-003 — Data Entry

**Decision:** Leaf OU submits statistics by default. `allow_data_entry` can override.

**Why:** Prevent duplicate counting while allowing exceptional structures.

---

## ADR-004 — Dynamic Metrics

**Decision:** Statistics are stored using `statistic_metrics` and `statistic_values`.

**Why:** New KPIs require no schema migration.

---

## ADR-005 — Permission Model

**Decision:** Permissions are assigned to tenant members per OU via `ou_members`. `admin` is scoped to the assigned subtree; tenant-wide administration requires direct assignment to the tenant Root OU.

**Why:** Position titles differ between churches and cannot determine authorization.

---

## ADR-006 — Approval

**Decision:** Approval is per submission. Nearest ancestor approver is responsible. Higher approvers may override.

---

## ADR-007 — Security

**Decision:** Database-first security using Supabase RLS and RPC for workflow.

---

## ADR-008 — Soft Delete

**Decision:** Business records use soft delete (`deleted_at`, `deleted_by`, `is_active`).

---

## ADR-009 — Reporting

**Decision:** Parent dashboards aggregate recursively from descendant OUs. Phase 2 reports include approved submissions only.

---

## ADR-010 — Technology Stack

Frontend: SvelteKit + TypeScript  
Backend: Supabase + PostgreSQL + Edge Functions  
Authentication: LINE LIFF + Supabase Auth bridge  
Hosting: Vercel

---

## ADR-011 — Tenant Membership

**Decision:** A LINE/Supabase identity may belong to multiple tenants through `church_members`. `ou_members` references a tenant membership rather than treating a global user as tenant-owned.

**Why:** Supports one LINE account in multiple organizations without duplicating identity data or weakening tenant isolation.

---

## ADR-012 — Tenant OU Type Settings

**Decision:** OU types are configurable per tenant through `organization_unit_types`. Only an active `admin` directly assigned to the tenant Root OU Level 1 may manage this setting.

OU types are a tenant-wide catalog, not a fixed level schema. `sort_order` affects selection-list ordering only, while `default_allow_data_entry` supplies the initial value for newly created OUs.

**Why:** Each tenant can name its hierarchy types without hardcoded labels while keeping one consistent type catalog across its entire structure.
