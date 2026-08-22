# Production setup

Status: **Production Live since 8 August 2026**

This repository is deployed with a Vercel frontend and a hosted Supabase backend. The instructions below are retained as the setup and repeatable release runbook. Do not use the local `.env`, local certificates, or `supabase/seed.sql` in production.

## Current production record

- Go-Live: confirmed 8 August 2026
- Frontend platform: Vercel
- Backend platform: Hosted Supabase
- Production URL: `https://csms-rouge.vercel.app/`
- Release identifier: Git `297ec64`, Vercel `dpl_5qe33Qg2mZaFh2BjaTYkjyTdzm5g`
- Post-deployment smoke-test: passed 8 August 2026; `/`, `/app`, and `/app/help` returned HTTP 200 and no production 5xx logs were present immediately after deployment

For every subsequent release, follow `doc/17_Production_Release_and_Rollback_Plan.md`. The release must have a verified backup/PITR checkpoint and a recorded last-known-good Vercel deployment before production migration begins.

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
npx supabase secrets set LINE_CHANNEL_ID=YOUR_CHANNEL_ID ALLOWED_ORIGINS=https://YOUR_APP_DOMAIN WORKER_SERVICE_ROLE_KEY=YOUR_CURRENT_SERVICE_ROLE_KEY
npx supabase secrets set LINE_MESSAGING_CHANNEL_ACCESS_TOKEN=YOUR_TOKEN LINE_MESSAGING_CHANNEL_SECRET=YOUR_SECRET LINE_DELIVERY_ENABLED=false LINE_DELIVERY_CANARY_CHURCH_IDS=YOUR_TEST_TENANT_UUID LINE_DELIVERY_APP_BASE_URL=https://YOUR_APP_DOMAIN/
npx supabase functions deploy line-auth
npx supabase functions deploy switch-active-tenant
npx supabase functions deploy report-export
npx supabase functions deploy send-line-notification --no-verify-jwt
npx supabase functions deploy scan-missing-submissions --no-verify-jwt
npx supabase functions deploy send-pending-approval-digest --no-verify-jwt
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
npx vercel env add PUBLIC_LINE_MESSAGING_OA_BASIC_ID production
npx vercel env add PUBLIC_PRODUCTION_APP_URL production
npx vercel env add PUBLIC_APP_ENV production
npx vercel
npx vercel --prod
```

Use `.env.production.example` as the variable checklist. Deploy a Preview first, then update `ALLOWED_ORIGINS`, Supabase Auth URLs, and the LINE LIFF Endpoint URL to the final production domain before promoting.

LIFF applications are platform-managed and cannot be changed by a tenant. `PUBLIC_LINE_LIFF_ID` selects the LIFF application for the deployed environment. `PUBLIC_LINE_LIFF_PRODUCTION_ID` and `PUBLIC_PRODUCTION_APP_URL` are displayed read-only in **Tenant Settings → ทั่วไป → LINE OA & Rich Menu**, so a tenant administrator can copy the correct production link into their LINE OA Rich Menu. Keep the production and development LIFF applications under the LINE Login channel represented by the Edge Function `LINE_CHANNEL_ID`, because the backend validates ID tokens against that channel.

Tenant LINE OAs are entry points only. Outbound LINE notification delivery must use the central CSMS LINE OA, while Messaging API credentials for that OA remain in Supabase Edge Function secrets and are never stored in tenant settings. Notification preferences already persist, but the Messaging API delivery Edge Function is a separate rollout item and must be deployed and verified before LINE delivery is considered active.

### Central OA notification configuration contract

The platform owner must confirm the central OA Basic ID, Messaging API Channel ID, quota owner, and incident owner outside Tenant configuration. The OA Basic ID is non-secret and must be exposed to the Notification Center as `PUBLIC_LINE_MESSAGING_OA_BASIC_ID`; configure `LINE_MESSAGING_CHANNEL_ID`, `LINE_MESSAGING_CHANNEL_ACCESS_TOKEN`, and `LINE_MESSAGING_CHANNEL_SECRET` only with `supabase secrets set`. Never place the access token or channel secret in Vercel variables, database Tenant settings, notification payloads, or audit logs.

Keep `LINE_DELIVERY_ENABLED=false` through Stage A–C. `LINE_DELIVERY_CANARY_CHURCH_IDS` must initially contain only the approved test Tenant when the Stage D worker is deployed. The existing `LINE_CHANNEL_ID` is the LINE Login channel and is deliberately separate from the central OA Messaging API Channel ID.

Stage D is implemented but must remain disabled on first deployment. Invoke the worker only from a protected scheduler using the service-role credential. After verifying the approved canary Tenant, set `LINE_DELIVERY_ENABLED=true`; keep its UUID as the only `LINE_DELIVERY_CANARY_CHURCH_IDS` value. Use `*` only after the canary evidence and quota/incident ownership are recorded. To stop outbound delivery immediately, restore `LINE_DELIVERY_ENABLED=false`; pending In-app notifications and outbox rows remain intact. Replay a dead letter only after correcting its cause by calling `replay_line_notification_delivery` with the service role, then record the operator/change ticket separately.

### Stage E scheduled notifications

Deploy both scheduled functions with `NOTIFICATION_SCHEDULE_ENABLED=false`. Set `NOTIFICATION_SCHEDULE_CANARY_CHURCH_IDS` to one approved test Tenant UUID and confirm its IANA timezone. Each Tenant's direct Root OU Admin configures the enabled state, active weekdays, missing-reminder hour, and approval-digest hour from Tenant Settings. New and existing Tenants default to disabled, all weekdays selected, and 09:00 for both event types.

Create two hourly Supabase Cron jobs, one POSTing to `/functions/v1/scan-missing-submissions` and one to `/functions/v1/send-pending-approval-digest`. Store the scheduler credential in Supabase Vault and send it as the `apikey` or Bearer credential; never embed it directly in migration SQL or source control. First verify that disabled invocations return zero counts. Then enable the approved test Tenant in Tenant Settings and set `NOTIFICATION_SCHEDULE_ENABLED=true` while retaining the single-Tenant canary. Run each function twice on the same selected local day and confirm the second run creates zero notifications. Inspect Cron run history, In-app recipients, outbox rows, and sanitized audit metadata before considering `*`.

The schedule kill switch is independent from `LINE_DELIVERY_ENABLED`: disabling schedules stops creation of future reminder/digest records, while disabling LINE delivery preserves new In-app records and queues their optional outbox rows. Hosted Supabase Cron uses `pg_cron`; Edge Function HTTP scheduling can use `pg_net`, with credentials stored in Vault.

### Notification incident operations

The Tenant Detail page in the System Admin control plane provides aggregate queue depth, delivery rates, stale leases, event counts, and sanitized dead-letter correlations. It never displays recipients or notification bodies. Use correlation UUID/error code to investigate server-side, maintaining least access.

- Provider outage or quota exhaustion: set `LINE_DELIVERY_ENABLED=false`, leave In-app and schedules available, record queue depth, and re-enable a single Tenant after provider recovery.
- Recipient/permanent 4xx: correct membership/OA friendship or invalid-recipient cause before audited manual replay. Do not bulk replay unknown failures.
- Secret rotation: disable delivery, rotate the central OA token/secret through Supabase secrets, redeploy/restart the function if required, test one dedicated recipient, revoke the old credential, then restore the canary.
- Schedule incident: set `NOTIFICATION_SCHEDULE_ENABLED=false` and disable both Cron jobs. Do not delete deterministic notifications already created.
- Stale worker: verify provider acceptance with the correlation/retry key before intervention; retain the stable delivery UUID.

Complete `doc/18_Notifications_Production_Evidence.md` for every production rollout. Repository tests and local simulation do not substitute for Preview/canary evidence.

Vercel automatically sets `VERCEL=1`, which enables the Vercel adapter. Local Windows builds use the auto adapter because the Vercel adapter requires symlink privileges; CI validates the Vercel adapter on Linux.

## Release gate

- `npm run preflight:production` passes.
- CI database tests pass against a clean local Supabase instance.
- LINE login, invite acceptance, tenant switching, submission, approval, edit request, dashboard, and export pass on Preview.
- Backup and restore ownership is documented.
- The release record and rollback decision matrix in `doc/17_Production_Release_and_Rollback_Plan.md` are completed.
