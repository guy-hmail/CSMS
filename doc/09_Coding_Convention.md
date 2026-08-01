# Church Statistics Management System (CSMS)

# 09_Coding_Convention.md

Version: 1.0\
Status: Project Standard

------------------------------------------------------------------------

# 1. Purpose

This document defines coding standards for the CSMS project to ensure
consistency, maintainability, readability, and AI-assisted development.

------------------------------------------------------------------------

# 2. General Principles

-   Documentation before implementation.
-   Follow ADR decisions.
-   Thin frontend.
-   Business logic belongs in PostgreSQL RPC or Edge Functions.
-   Never bypass Row Level Security (RLS).
-   Keep code simple and modular.

------------------------------------------------------------------------

# 3. Technology Standards

  Layer      Standard
  ---------- ------------------------
  Frontend   SvelteKit + TypeScript
  Backend    Supabase
  Database   PostgreSQL
  Styling    Skeleton UI
  Charts     Chart.js

------------------------------------------------------------------------

# 4. Naming Conventions

## Database

-   snake_case
-   UUID primary keys
-   Foreign keys end with `_id`

Example:

``` text
organization_units
statistic_submissions
created_at
church_id
```

## TypeScript

-   camelCase for variables/functions
-   PascalCase for classes/components
-   UPPER_SNAKE_CASE for constants

------------------------------------------------------------------------

# 5. Folder Structure

``` text
src/
  lib/
  routes/
  features/
  components/
  services/
  stores/
  types/
```

Feature-first organization is preferred.

------------------------------------------------------------------------

# 6. TypeScript Rules

-   Enable strict mode.
-   Avoid `any`.
-   Share generated database types.
-   Prefer interfaces for API contracts.

------------------------------------------------------------------------

# 7. Svelte Guidelines

-   One responsibility per component.
-   Keep page components lightweight.
-   Move reusable logic into lib/services.
-   Avoid business logic inside UI.

------------------------------------------------------------------------

# 8. Database Rules

-   Use migrations only.
-   Soft delete business entities.
-   Dynamic metrics only.
-   Never create fixed attendance columns.
-   Always include `church_id` on tenant-owned tables.

------------------------------------------------------------------------

# 9. RPC & API

-   Validation occurs in RPC.
-   Authorization enforced by RLS.
-   Return consistent response objects.
-   Use transactions for multi-table updates.

------------------------------------------------------------------------

# 10. Error Handling

Standard response:

``` json
{
  "success": false,
  "code": "VALIDATION_ERROR",
  "message": "Human readable message"
}
```

Never expose internal errors to users.

------------------------------------------------------------------------

# 11. Git Convention

Branches

-   main
-   develop
-   feature/\*
-   hotfix/\*
-   release/\*

Commit format

``` text
feat:
fix:
docs:
refactor:
test:
chore:
```

------------------------------------------------------------------------

# 12. Documentation Rules

-   Update documentation before architecture changes.
-   Update ADR for architectural decisions.
-   Keep Data Dictionary synchronized with schema.

------------------------------------------------------------------------

# 13. Security

-   Never expose service role keys.
-   Never disable RLS.
-   Validate all inputs.
-   Use HTTPS only.

------------------------------------------------------------------------

# 14. AI Coding Rules

AI assistants must:

-   Read README and blueprint documents first.
-   Follow ADR decisions.
-   Preserve architecture.
-   Do not invent new database patterns.
-   Generate strongly typed code.
-   Keep frontend thin.

------------------------------------------------------------------------

# 15. Code Review Checklist

-   Naming conventions followed
-   Types are strict
-   RLS respected
-   Tests updated
-   Documentation updated
-   No duplicated business logic
-   No secrets committed

------------------------------------------------------------------------

# References

-   README.md
-   AI_STYLE_GUIDE.md
-   ARCHITECTURE_DECISIONS.md
-   02_Database_Design.md
-   03_RLS_and_Permissions.md
-   04_API_Design.md
