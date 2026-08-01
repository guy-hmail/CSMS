# AI_STYLE_GUIDE.md

# AI Style Guide

## Purpose
Rules that every AI coding assistant must follow.

## Architecture
- Follow PROJECT_CONTEXT.md first.
- Do not change ADR decisions unless requested.
- Keep backend business logic in PostgreSQL RPC/Edge Functions.
- Frontend must remain thin.

## Database
- UUID primary keys.
- snake_case names.
- Soft delete for business entities.
- Dynamic metrics only (never fixed attendance columns).
- Always include church_id on tenant-owned tables.

## Security
- Enforce authorization with Supabase RLS.
- Never bypass RLS.
- Use RPC for submit/approve workflows.

## TypeScript
- Strict mode.
- Shared types generated from database.
- camelCase functions.
- PascalCase Svelte components.

## Git
- Update docs before changing architecture.
- One feature per commit.
