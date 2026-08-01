# Church Statistics Management System (CSMS)

# 10_AI_Context.md

Version: 1.0\
Status: AI Development Blueprint

------------------------------------------------------------------------

# Purpose

This document provides permanent implementation context for AI coding
assistants (Cursor, Codex, Claude Code, Gemini CLI, ChatGPT) working on
the CSMS project.

AI should treat this document as the primary implementation guide
together with the project blueprint.

------------------------------------------------------------------------

# Documents To Read First (Priority)

1.  README.md
2.  AI_STYLE_GUIDE.md
3.  ARCHITECTURE_DECISIONS.md
4.  00_Project_Overview.md
5.  01_Business_Requirements.md
6.  02_Database_Design.md
7.  03_RLS_and_Permissions.md
8.  04_API_Design.md
9.  05_Frontend_Design.md
10. 06_UI_Wireframe.md
11. 07_Reports_Dashboard.md
12. 08_Deployment.md
13. 09_Coding_Convention.md

Never implement code without understanding these documents.

------------------------------------------------------------------------

# Project Summary

CSMS is a multi-tenant church statistics management system.

Core characteristics:

-   Shared database using church_id
-   Unlimited organization hierarchy
-   Dynamic KPI model
-   Recursive aggregation
-   LINE LIFF authentication
-   Supabase RLS
-   Thin frontend
-   Business logic in RPC / Edge Functions

------------------------------------------------------------------------

# Frozen Architecture

Do NOT change without explicit request.

-   Multi-Tenant using shared tables
-   parent_id + path + level hierarchy
-   statistic_metrics + statistic_values
-   OU-based permissions
-   Approval per submission
-   Soft delete
-   PostgreSQL RPC
-   Supabase RLS

------------------------------------------------------------------------

# Coding Rules

Always:

-   Use TypeScript strict mode
-   Generate reusable code
-   Respect naming conventions
-   Use transactions where appropriate
-   Keep components small
-   Reuse shared types

Never:

-   Create fixed attendance columns
-   Bypass RLS
-   Put business logic in UI
-   Expose service keys
-   Duplicate validation logic

------------------------------------------------------------------------

# Backend Rules

-   Validate in RPC
-   Authorize using RLS
-   Audit critical operations
-   Use church_id filters
-   Use recursive SQL for hierarchy

------------------------------------------------------------------------

# Frontend Rules

-   SvelteKit
-   Skeleton UI
-   Feature-based folders
-   Services call RPC
-   UI displays permission state only

------------------------------------------------------------------------

# Database Rules

-   UUID primary keys
-   snake_case
-   Soft delete
-   Dynamic metrics
-   Migrations only

------------------------------------------------------------------------

# Development Workflow

1.  Read blueprint
2.  Confirm architecture
3.  Implement feature
4.  Update tests
5.  Update documentation
6.  Submit for review

------------------------------------------------------------------------

# AI Review Checklist

Before finishing, verify:

-   Architecture unchanged
-   RLS respected
-   church_id enforced
-   Types are strict
-   No duplicated business logic
-   Documentation still accurate

------------------------------------------------------------------------

# Expected Output Style

AI should produce:

-   Production-ready code
-   Clear comments only where needed
-   Small focused commits
-   Consistent naming
-   No unnecessary abstractions

------------------------------------------------------------------------

# References

All project blueprint documents and ADRs are normative.
