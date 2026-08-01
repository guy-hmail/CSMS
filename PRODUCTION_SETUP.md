# Production setup

This repository is prepared for a Vercel frontend and a hosted Supabase backend. Do not use the local `.env`, local certificates, or `supabase/seed.sql` in production.

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
npx vercel env add PUBLIC_APP_ENV production
npx vercel
npx vercel --prod
```

Use `.env.production.example` as the variable checklist. Deploy a Preview first, then update `ALLOWED_ORIGINS`, Supabase Auth URLs, and the LINE LIFF Endpoint URL to the final production domain before promoting.

Vercel automatically sets `VERCEL=1`, which enables the Vercel adapter. Local Windows builds use the auto adapter because the Vercel adapter requires symlink privileges; CI validates the Vercel adapter on Linux.

## Release gate

- `npm run preflight:production` passes.
- CI database tests pass against a clean local Supabase instance.
- LINE login, invite acceptance, tenant switching, submission, approval, edit request, dashboard, and export pass on Preview.
- Backup and restore ownership is documented.
