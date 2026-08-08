# Church Statistics Management System (CSMS)

# 08_Deployment.md

Version: 1.0\
Status: Production Live / Operational Runbook

Last updated: 8 August 2026

Go-Live: ✅ Production deployment completed on 8 August 2026

## 1. Purpose

This document defines the deployment architecture, environments, CI/CD
strategy, security hardening, monitoring, backup, disaster recovery, and
production deployment process for CSMS.

The initial production deployment is complete. This document now also serves as the operational runbook for subsequent releases, rollback, monitoring, backup, and disaster recovery.

## 2. Deployment Philosophy

-   Infrastructure as Code whenever possible
-   Documentation first
-   Immutable deployments
-   Database migration before application deployment
-   Zero Trust security
-   Rollback must always be possible

## 3. Environment Architecture

Local → Development → Staging → Production

## 4. Production Architecture

``` text
Users
   │
LINE LIFF
   │
Vercel (SvelteKit)
   │
Supabase API
 ├── PostgreSQL
 ├── Storage
 └── Edge Functions
        │
 Row Level Security
```

## 5. Infrastructure

  Layer        Technology
  ------------ ----------------------
  Frontend     Vercel
  Backend      Supabase
  Database     PostgreSQL
  Auth         LINE LIFF + Supabase
  Storage      Supabase Storage
  Serverless   Edge Functions

## 6. Environment Variables

### Frontend

-   PUBLIC_SUPABASE_URL
-   PUBLIC_SUPABASE_ANON_KEY
-   PUBLIC_LINE_LIFF_ID
-   PUBLIC_APP_ENV

### Backend

-   SUPABASE_SERVICE_ROLE_KEY
-   LINE_CHANNEL_SECRET
-   LINE_CHANNEL_ID
-   JWT_SECRET

Never expose service_role keys to the frontend.

## 7. Git Strategy

-   main
-   develop
-   feature/\*
-   release/\*
-   hotfix/\*

## 8. CI/CD

Developer → Pull Request → Review → Staging → Production

## 9. Database Migration

Deployment order:

1.  Database Migration
2.  Seed Data (optional)
3.  RPC
4.  RLS
5.  Edge Functions
6.  Frontend

## 10. Security

-   HTTPS only
-   CSP
-   HSTS
-   Secure cookies
-   Verify RLS before deployment
-   Rotate secrets

## 11. Monitoring

-   Vercel Logs
-   Supabase Logs
-   Edge Function Logs
-   Optional Sentry

## 12. Backup

-   Daily PostgreSQL backup
-   Weekly Storage backup
-   Git repository backup

Target: - RPO: 24 hours - RTO: 4 hours

## 13. Scaling

Current target:

-   20 churches
-   1,000 users
-   2,000 OUs

Future:

-   Materialized Views
-   Read Replicas
-   Partitioned Tables

## 14. Production Checklist

Deployment record:

-   [x] Production release promoted and Go-Live confirmed on 8 August 2026
-   [ ] Record the production URL and release identifier in the repository
-   [ ] Attach post-deployment smoke-test evidence
-   [ ] Record monitoring and alert ownership
-   [ ] Record the latest successful backup/restore drill

The repeatable release sequence, rollback decision matrix, Vercel Instant Rollback procedure, and production-safe Supabase recovery policy are maintained in `17_Production_Release_and_Rollback_Plan.md`.

Before each deployment:

-   Tests passed
-   Migration reviewed
-   RLS verified
-   API verified

After each deployment:

-   Login works
-   Dashboard works
-   Reports work
-   Audit logs verified

## 15. AI Deployment Rules

-   Read all blueprint documents first.
-   Never bypass RLS.
-   Keep business logic in RPC/Edge Functions.
-   Never expose secrets.
-   Update documentation before architectural changes.

## References

-   README.md
-   00_Project_Overview.md
-   01_Business_Requirements.md
-   02_Database_Design.md
-   03_RLS_and_Permissions.md
-   04_API_Design.md
-   05_Frontend_Design.md
-   06_UI_Wireframe.md
-   07_Reports_Dashboard.md
-   AI_STYLE_GUIDE.md
-   ARCHITECTURE_DECISIONS.md
-   PROJECT_ROADMAP.md
