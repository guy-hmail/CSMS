# Production setup

Status: **Production Live since 8 August 2026**

This repository is deployed with a Vercel frontend and a hosted Supabase backend. The instructions below are retained as the setup and repeatable release runbook. Do not use the local `.env`, local certificates, or `supabase/seed.sql` in production.

## Current production record

- Go-Live: confirmed 8 August 2026
- Frontend platform: Vercel
- Backend platform: Hosted Supabase
- Production URL: not recorded in the repository
- Release identifier: not recorded in the repository
- Post-deployment smoke-test evidence: not yet recorded in the repository

## 1. Source control and CI

1. Create a private GitHub repository and add it as `origin`.
2. Commit the current code on `main` and push it.
3. Confirm all jobs in `.github/workflows/ci.yml` pass on a clean runner.
4. Protect `main` and require the CI checks before merge.

## 2. Supabase production

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push --dry-run
npx supabase db push
npx supabase secrets set LINE_CHANNEL_ID=YOUR_CHANNEL_ID ALLOWED_ORIGINS=https://YOUR_APP_DOMAIN
npx supabase functions deploy line-auth
npx supabase functions deploy switch-active-tenant
npx supabase functions deploy report-export
```

Before pushing migrations, confirm the remote database major version matches `supabase/config.toml`. Do not run `supabase db reset` or seed the production project.

In the hosted Supabase dashboard:

- set the production Site URL and exact redirect allow-list;
- keep anonymous sign-in disabled;
- disable unused email/password signup paths;
- enable backups and review Auth/API rate limits;
- verify that all three Edge Functions have the expected JWT setting from `supabase/config.toml`.

## 3. Vercel production

```powershell
npx vercel link
npx vercel env add PUBLIC_SUPABASE_URL production
npx vercel env add PUBLIC_SUPABASE_ANON_KEY production
npx vercel env add PUBLIC_LINE_LIFF_ID production
npx vercel env add PUBLIC_LINE_LIFF_PRODUCTION_ID production
npx vercel env add PUBLIC_PRODUCTION_APP_URL production
npx vercel env add PUBLIC_APP_ENV production
npx vercel
npx vercel --prod
```

Use `.env.production.example` as the variable checklist. Deploy a Preview first, then update `ALLOWED_ORIGINS`, Supabase Auth URLs, and the LINE LIFF Endpoint URL to the final production domain before promoting.

LIFF applications are platform-managed and cannot be changed by a tenant. `PUBLIC_LINE_LIFF_ID` selects the LIFF application for the deployed environment. `PUBLIC_LINE_LIFF_PRODUCTION_ID` and `PUBLIC_PRODUCTION_APP_URL` are displayed read-only in **Tenant Settings → ทั่วไป → LINE OA & Rich Menu**, so a tenant administrator can copy the correct production link into their LINE OA Rich Menu. Keep the production and development LIFF applications under the LINE Login channel represented by the Edge Function `LINE_CHANNEL_ID`, because the backend validates ID tokens against that channel.

Tenant LINE OAs are entry points only. Outbound LINE notification delivery must use the central CSMS LINE OA, while Messaging API credentials for that OA remain in Supabase Edge Function secrets and are never stored in tenant settings. Notification preferences already persist, but the Messaging API delivery Edge Function is a separate rollout item and must be deployed and verified before LINE delivery is considered active.

Vercel automatically sets `VERCEL=1`, which enables the Vercel adapter. Local Windows builds use the auto adapter because the Vercel adapter requires symlink privileges; CI validates the Vercel adapter on Linux.

## Release gate

- `npm run preflight:production` passes.
- CI database tests pass against a clean local Supabase instance.
- LINE login, invite acceptance, tenant switching, submission, approval, edit request, dashboard, and export pass on Preview.
- Backup and restore ownership is documented.
