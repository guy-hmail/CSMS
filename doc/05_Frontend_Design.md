# Church Statistics Management System (CSMS)
## Frontend Design Specification

Version: 1.0  
Status: Production Blueprint  
Target Platform: SvelteKit + TypeScript  
Backend: Supabase PostgreSQL + RPC + Edge Functions  
Authentication: LINE LIFF + Supabase Auth Bridge  
Architecture Style: Thin Frontend, Feature-Based Structure, RLS-Protected Data Access

---

# 1. Document Purpose

This document defines the frontend architecture for the Church Statistics Management System (CSMS).

It provides the implementation blueprint for:

- SvelteKit project structure
- Route design
- Layout hierarchy
- Component strategy
- Authentication flow
- Permission-aware UI rendering
- Supabase client integration
- API service layer
- Form handling
- Dashboard and reporting UI
- Error handling
- TypeScript conventions
- AI coding assistant implementation rules

This document must be followed when implementing the SvelteKit frontend.

---

# 2. Frontend Design Principles

CSMS frontend follows a thin-client architecture.

Core principles:

1. Frontend must not enforce final authorization.
2. Supabase RLS and RPC functions are the source of truth for permission checks.
3. Frontend may hide or show UI actions based on permissions for user experience only.
4. Critical workflows must call RPC functions.
5. Direct table access is allowed only for safe read operations protected by RLS.
6. Dynamic metrics must drive forms and dashboards.
7. Never hard-code attendance fields such as `attendance`, `sunday_school`, `new_visitor`, or `new_believer` as database columns.
8. Use generated database types wherever possible.
9. Keep page components small.
10. Move data access to service modules.
11. Move reusable UI to components.
12. Move shared business display rules to helper modules.
13. Keep route files focused on orchestration.
14. Every mutation must handle success, validation error, authorization error, and unexpected error.

---

# 3. Technology Stack

| Layer | Technology |
|---|---|
| Framework | SvelteKit |
| Language | TypeScript |
| UI Framework | Skeleton UI |
| Styling | Tailwind CSS |
| Backend Client | Supabase JS |
| Authentication | LINE LIFF + Supabase Auth bridge |
| Charts | Chart.js |
| Excel Export | SheetJS |
| PDF Export | pdf-lib or server-generated PDF |
| Forms | Svelte forms + validation helpers |
| State | Svelte stores |
| Hosting | Vercel |

---

# 4. Frontend Architecture Overview

```text
Browser
  │
  ▼
LINE LIFF
  │
  ▼
SvelteKit App
  │
  ├── Routes
  │     ├── Login
  │     ├── Dashboard
  │     ├── Organization
  │     ├── Submissions
  │     ├── Approval
  │     ├── Reports
  │     └── Settings
  │
  ├── Services
  │     ├── Supabase client
  │     ├── Auth service
  │     ├── Organization service
  │     ├── Submission service
  │     ├── Dashboard service
  │     └── Report service
  │
  ├── Stores
  │     ├── session
  │     ├── current church
  │     ├── current OU
  │     ├── permission context
  │     └── UI state
  │
  ▼
Supabase
  │
  ├── RLS-protected reads
  ├── RPC workflow calls
  └── Edge Functions
```

---

# 5. Repository Structure

Recommended SvelteKit structure:

```text
src/
│
├── app.css
├── app.d.ts
├── hooks.server.ts
├── hooks.client.ts
│
├── lib/
│   │
│   ├── components/
│   │   ├── common/
│   │   ├── layout/
│   │   ├── organization/
│   │   ├── submissions/
│   │   ├── approval/
│   │   ├── dashboard/
│   │   ├── reports/
│   │   └── forms/
│   │
│   ├── services/
│   │   ├── supabase.client.ts
│   │   ├── auth.service.ts
│   │   ├── church.service.ts
│   │   ├── organization.service.ts
│   │   ├── permission.service.ts
│   │   ├── metric.service.ts
│   │   ├── period.service.ts
│   │   ├── submission.service.ts
│   │   ├── approval.service.ts
│   │   ├── dashboard.service.ts
│   │   ├── report.service.ts
│   │   └── export.service.ts
│   │
│   ├── stores/
│   │   ├── session.store.ts
│   │   ├── church.store.ts
│   │   ├── organization.store.ts
│   │   ├── permission.store.ts
│   │   ├── notification.store.ts
│   │   └── ui.store.ts
│   │
│   ├── types/
│   │   ├── database.types.ts
│   │   ├── api.types.ts
│   │   ├── auth.types.ts
│   │   ├── permission.types.ts
│   │   ├── organization.types.ts
│   │   ├── metric.types.ts
│   │   ├── submission.types.ts
│   │   ├── dashboard.types.ts
│   │   └── report.types.ts
│   │
│   ├── utils/
│   │   ├── date.util.ts
│   │   ├── number.util.ts
│   │   ├── tree.util.ts
│   │   ├── permission.util.ts
│   │   ├── validation.util.ts
│   │   ├── error.util.ts
│   │   └── export.util.ts
│   │
│   ├── constants/
│   │   ├── routes.ts
│   │   ├── permissions.ts
│   │   ├── statuses.ts
│   │   └── messages.ts
│   │
│   └── config/
│       ├── app.config.ts
│       ├── supabase.config.ts
│       └── line.config.ts
│
└── routes/
    │
    ├── +layout.svelte
    ├── +layout.ts
    ├── +page.svelte
    │
    ├── login/
    │   └── +page.svelte
    │
    ├── app/
    │   ├── +layout.svelte
    │   ├── +layout.ts
    │   │
    │   ├── dashboard/
    │   │   └── +page.svelte
    │   │
    │   ├── organization/
    │   │   ├── +page.svelte
    │   │   └── [ouId]/
    │   │       └── +page.svelte
    │   │
    │   ├── submissions/
    │   │   ├── +page.svelte
    │   │   ├── new/
    │   │   │   └── +page.svelte
    │   │   └── [submissionId]/
    │   │       └── +page.svelte
    │   │
    │   ├── approval/
    │   │   ├── +page.svelte
    │   │   └── [submissionId]/
    │   │       └── +page.svelte
    │   │
    │   ├── reports/
    │   │   ├── +page.svelte
    │   │   └── export/
    │   │       └── +page.svelte
    │   │
    │   └── settings/
    │       ├── profile/
    │       │   └── +page.svelte
    │       ├── users/
    │       │   └── +page.svelte
    │       ├── metrics/
    │       │   └── +page.svelte
    │       └── periods/
    │           └── +page.svelte
```

---

# 6. Routing Strategy

## 6.1 Public Routes

| Route | Purpose |
|---|---|
| `/` | Redirect to `/app/dashboard` if logged in, otherwise `/login` |
| `/login` | LINE LIFF login |

## 6.2 Protected App Routes

| Route | Purpose |
|---|---|
| `/app/dashboard` | Main dashboard |
| `/app/organization` | Organization tree and management |
| `/app/organization/[ouId]` | OU detail |
| `/app/submissions` | Submission list |
| `/app/submissions/new` | New weekly submission |
| `/app/submissions/[submissionId]` | Submission detail/edit |
| `/app/approval` | Pending approval queue |
| `/app/approval/[submissionId]` | Approval detail |
| `/app/reports` | Report viewer |
| `/app/reports/export` | Export options |
| `/app/settings/profile` | User profile |
| `/app/settings/users` | User management |
| `/app/settings/metrics` | Metric settings |
| `/app/settings/periods` | Reporting period settings |

---

# 7. Layout Design

## 7.1 Root Layout

Responsibilities:

- Load global CSS
- Initialize theme
- Initialize notification/toast container
- Provide app shell placeholder

## 7.2 App Layout

Responsibilities:

- Validate user session
- Load current user profile
- Load current church context
- Load accessible OUs
- Load permission context
- Render sidebar and top navigation
- Redirect unauthenticated users to `/login`
- Load selectable tenants before tenant-owned data.
- If multiple memberships exist, show a tenant switcher outside page-specific filters.
- After switching, refresh the JWT first, then clear all tenant-scoped stores/caches before navigation.

App layout should not load heavy dashboard data.

---

# 8. Authentication Flow

Authentication uses LINE LIFF and Supabase Auth bridge.

## 8.1 Login Flow

```text
User opens app
  │
  ▼
SvelteKit checks session
  │
  ├── Session exists → /app/dashboard
  │
  └── No session → /login
            │
            ▼
        Initialize LIFF
            │
            ▼
        LINE Login
            │
            ▼
        Get LINE profile / ID token
            │
            ▼
        Call Edge Function: line-auth
            │
            ▼
        Verify LINE token
            │
            ▼
        Create or update user profile
            │
            ▼
        Return Supabase session/custom token
            │
            ▼
        Store session
            │
            ▼
        Redirect to /app/dashboard
```

## 8.2 Auth Service Responsibilities

`auth.service.ts` should provide:

```ts
initializeLiff(): Promise<void>
loginWithLine(): Promise<void>
logout(): Promise<void>
getCurrentSession(): Promise<AuthSession | null>
getCurrentUserProfile(): Promise<UserProfile | null>
refreshProfile(): Promise<UserProfile>
listMyTenants(): Promise<TenantSummary[]>
switchActiveTenant(tenantId: string): Promise<void>
```

## 8.3 Frontend Auth Rules

- Do not trust LINE profile alone for authorization.
- Always resolve the application user from the backend.
- User activation status must be checked from the database/RPC.
- Deactivated users must be blocked after login.
- Session state should be stored in a Svelte store.

---

# 9. Permission-Aware UI

Frontend permission checks are for UX only.

Backend RLS and RPC remain authoritative.

## 9.1 Permission Store

`permission.store.ts` should maintain:

```ts
type PermissionContext = {
  userId: string;
  churchId: string;
  accessibleOuIds: string[];
  currentOuId: string | null;
  permissionsByOu: Record<string, string[]>;
  isSystemAdmin: boolean;
};
```

`isSystemAdmin` is a derived UI value populated from the trusted API `globalRole` claim (`globalRole === 'system_admin'`). It is not a database column and must never be accepted from client input as authorization.

## 9.2 UI Permission Helpers

```ts
canViewOu(ouId: string): boolean
canManageOu(ouId: string): boolean
canSubmitForOu(ouId: string): boolean
canApproveForOu(ouId: string): boolean
canOverrideForOu(ouId: string): boolean
canManageUsers(ouId: string): boolean
canManageMetrics(): boolean
```

## 9.3 UI Behavior by Permission

| Permission | UI Access |
|---|---|
| `admin` | All tenant screens |
| `manager` | OU management, child OU, users under assigned OU, reports |
| `data_entry` | Submission create/edit for assigned OU |
| `approver` | Approval queue and approval actions |
| `viewer` | Dashboard and reports only |

## 9.4 Important Rule

Even if UI hides an action, direct access must still be blocked by:

- Route guard
- Backend RLS
- RPC authorization

---

# 10. Supabase Client Strategy

## 10.1 Browser Client

Use browser Supabase client for:

- Current session
- RLS-protected SELECT queries
- RPC calls
- File download if needed

## 10.2 Server Client

Use server-side Supabase client only when required by SvelteKit load functions.

Rules:

- Never expose service role key to frontend.
- Never use service role key in client code.
- Server-side privileged actions should be implemented in Supabase Edge Functions, not SvelteKit route handlers, unless explicitly approved.

---

# 11. API Service Layer

All API calls should be wrapped in service modules.

Page components must not directly call Supabase except for very simple local reads during prototyping.

## 11.1 Service Pattern

Example:

```ts
export async function getDashboardSummary(params: DashboardSummaryRequest): Promise<DashboardSummaryResponse> {
  const { data, error } = await supabase.rpc('get_recursive_summary', params);

  if (error) {
    throw mapSupabaseError(error);
  }

  return data;
}
```

## 11.2 Required Services

| Service | Responsibilities |
|---|---|
| `auth.service.ts` | LINE login, logout, session, profile |
| `church.service.ts` | Current church context |
| `organization.service.ts` | OU tree, OU CRUD via RPC |
| `permission.service.ts` | Permission context |
| `metric.service.ts` | Metric list and metric settings |
| `period.service.ts` | Reporting periods |
| `submission.service.ts` | Submission create/update/submit |
| `approval.service.ts` | Approval queue and actions |
| `dashboard.service.ts` | Dashboard summary and trends |
| `report.service.ts` | Report data |
| `export.service.ts` | Excel/PDF export |

---

# 12. Data Loading Strategy

## 12.1 Load Functions

Use SvelteKit `load` functions for:

- Initial page data
- Route-level dependency data
- Data required before rendering

Use client-side calls for:

- User-triggered filtering
- Form submit
- Refresh after mutation
- Lazy dashboard widgets

## 12.2 Recommended Pattern

```text
+layout.ts
  ├── Load session
  ├── Load user profile
  ├── Load permission context
  └── Load accessible OU list

+page.ts
  ├── Load page-specific data
  └── Return typed props

+page.svelte
  ├── Render UI
  ├── Handle local form state
  └── Call service for user actions
```

---

# 13. State Management

Use Svelte stores for shared UI/application state.

Avoid storing server data globally unless reused across pages.

## 13.1 Required Stores

| Store | Purpose |
|---|---|
| `session.store.ts` | Current Supabase session |
| `church.store.ts` | Current church context |
| `organization.store.ts` | Accessible OU tree and selected OU |
| `permission.store.ts` | Permission context |
| `notification.store.ts` | Toast and alerts |
| `ui.store.ts` | Sidebar, loading, theme |

## 13.2 Store Rules

- Stores should not contain critical authorization logic.
- Stores may contain helper selectors.
- Stores should be reset on logout.
- Stores should avoid duplicating large report datasets.

---

# 14. Dynamic Metric Form Design

Submission forms must be generated from `statistic_metrics`.

## 14.1 Form Generation Flow

```text
Open submission page
  │
  ▼
Load active metrics
  │
  ▼
Load existing submission if available
  │
  ▼
Generate form fields by metric input_type
  │
  ▼
Validate required/min/max/data type
  │
  ▼
Submit values to submit_statistics RPC
```

## 14.2 Metric Input Mapping

| Metric `data_type` | Metric `input_type` | UI Control |
|---|---|---|
| `number` | `number` | Number input |
| `text` | `text` | Text input / textarea |
| `boolean` | `checkbox` | Checkbox |

## 14.3 Submission Payload Shape

Frontend should send metric values as array items.

```ts
type SubmitStatisticsRequest = {
  churchId: string;
  ouId: string;
  periodId: string;
  remarks?: string;
  values: Array<{
    metricId: string;
    numericValue?: number | null;
    textValue?: string | null;
    booleanValue?: boolean | null;
  }>;
};
```

Do not send fixed attendance field names.

---

# 15. Organization UI Design

## 15.1 Organization Tree

The organization page should display unlimited hierarchy using a tree component.

Features:

- Expand/collapse nodes
- Select OU
- View OU details
- Create child OU
- Edit OU
- Soft delete OU
- Assign users
- Show `allow_data_entry` flag

## 15.2 Tree Data Structure

```ts
type OrganizationTreeNode = {
  id: string;
  churchId: string;
  parentId: string | null;
  code: string;
  name: string;
  path: string;
  level: number;
  allowDataEntry: boolean;
  children: OrganizationTreeNode[];
};
```

## 15.3 Organization Rules in UI

- Root OU should be visually distinct.
- Leaf OU should show data entry eligibility.
- Parent OU should show aggregated dashboard behavior.
- Delete should be disabled if backend reports child OU or attendance exists.

Backend still validates all operations.

---

# 16. Dashboard UI Design

## 16.1 Dashboard Scope

Dashboard is always viewed by:

- Current church
- Selected OU
- Selected period or date range

## 16.2 Dashboard Components

| Component | Purpose |
|---|---|
| `DashboardHeader.svelte` | OU and period selector |
| `MetricSummaryCard.svelte` | KPI total |
| `MetricTrendChart.svelte` | Historical trend |
| `ChildOuSummaryTable.svelte` | Child OU comparison |
| `SubmissionStatusPanel.svelte` | Submitted/missing/approved status |
| `ApprovalStatusPanel.svelte` | Approval status summary |

## 16.3 Dashboard Rules

- Use approved submissions only for official totals.
- Parent OU dashboard aggregates descendant OUs.
- Viewer sees only accessible OU subtree.
- Dashboard service should call `get_recursive_summary` or dedicated dashboard RPC.
- Heavy dashboard aggregation should not be computed in the browser.

---

# 17. Approval UI Design

Phase 2 feature.

## 17.1 Approval Queue

Approval queue should show submissions where the user can approve.

Columns:

- Period
- OU
- Submitted by
- Submitted at
- Status
- Revision
- Action

## 17.2 Approval Detail

Approval detail should show:

- Submission header
- OU path
- Metric values
- Remarks
- Approval history
- Action buttons

Actions:

- Approve
- Reject
- Return to Draft
- Override Approve

## 17.3 Approval Rules

- UI should show only actions that match permission context.
- RPC must validate approver permission again.
- Reason should be required for reject, return, and override.

---

# 18. Reports UI Design

Reports should support:

- Weekly report
- Monthly report
- Quarterly report
- Yearly report
- OU filter
- Period filter
- Metric filter
- Excel export
- PDF export

## 18.1 Report Page Flow

```text
Select report type
  │
  ▼
Select OU
  │
  ▼
Select period/date range
  │
  ▼
Load report data
  │
  ▼
Preview table/chart
  │
  ▼
Export Excel/PDF
```

## 18.2 Export Rules

- Small exports may be generated client-side.
- Large exports should use Edge Functions.
- Report data must come from RLS/RPC-protected source.
- Export must respect user permission.

---

# 19. Error Handling

## 19.1 Error Categories

| Category | UI Behavior |
|---|---|
| Validation error | Show field-level or form-level message |
| Unauthorized | Show access denied and disable action |
| Not found | Show not found page or empty state |
| Conflict | Show duplicate/locked/submitted state message |
| Server error | Show generic error and log detail |
| Network error | Show retry option |

## 19.2 Standard Error Shape

Frontend services should normalize backend errors into:

```ts
type AppError = {
  code: string;
  message: string;
  details?: unknown;
  fieldErrors?: Record<string, string>;
};
```

## 19.3 Error Rule

Do not expose sensitive backend details to normal users.

Developer diagnostics may be logged to console only in development mode.

---

# 20. Loading and Empty States

Every page must handle:

- Loading
- Empty data
- Error
- Unauthorized
- Success

Examples:

| Page | Empty State |
|---|---|
| Dashboard | No approved statistics for selected period |
| Organization | No accessible organization units |
| Submissions | No submissions found |
| Approval | No pending approvals |
| Reports | Select filters to generate report |

---

# 21. Validation Strategy

Frontend validation improves user experience.

Backend validation remains authoritative.

Frontend should validate:

- Required fields
- Number format
- Non-negative numeric values
- Min/max metric constraints
- Required reason for reject/return/override
- Required OU and period selection

Backend/RPC must validate again.

---

# 22. TypeScript Rules

## 22.1 General Rules

- Enable strict mode.
- Avoid `any` unless documented.
- Use generated Supabase database types.
- Define API request/response types in `src/lib/types/api.types.ts`.
- Use camelCase in frontend types.
- Map database snake_case to frontend camelCase where appropriate.

## 22.2 Naming Rules

| Item | Convention | Example |
|---|---|---|
| Component | PascalCase | `SubmissionForm.svelte` |
| Function | camelCase | `submitStatistics()` |
| Store | camelCase + store suffix | `permissionStore` |
| Type | PascalCase | `SubmissionStatus` |
| Constants | UPPER_SNAKE_CASE | `SUBMISSION_STATUS` |
| Route folder | kebab-case or lowercase | `submissions` |

---

# 23. Component Design

## 23.1 Component Categories

| Category | Purpose |
|---|---|
| `common` | Buttons, cards, modals, badges |
| `layout` | Sidebar, header, app shell |
| `organization` | Tree, OU detail, OU form |
| `submissions` | Submission form, value table |
| `approval` | Queue, approval action panel |
| `dashboard` | KPI cards, charts, summaries |
| `reports` | Report filters, tables, export buttons |
| `forms` | Shared form controls |

## 23.2 Component Rules

- Components should receive data via props.
- Components should emit events for actions.
- Components should not directly perform critical API mutations unless they are feature-level smart components.
- Reusable components should be presentation-only.
- Avoid large all-in-one page components.

---

# 24. Route Guard Strategy

Protected routes under `/app` require a valid session.

Route guard checks:

1. Session exists.
2. User profile exists.
3. User is active.
4. User has at least one active OU permission or is system admin.

If failed:

| Condition | Redirect |
|---|---|
| No session | `/login` |
| Inactive user | `/login?error=inactive` |
| No permission | `/login?error=no-permission` or access denied page |

---

# 25. Page-Level Access Rules

| Page | Minimum UI Permission |
|---|---|
| Dashboard | viewer or above |
| Organization list | viewer or above |
| Organization management | manager or admin |
| Submission list | data_entry, manager, admin, approver, viewer |
| New submission | data_entry, manager, admin |
| Approval queue | approver, manager, admin |
| Reports | viewer or above |
| User settings | manager or admin |
| Tenant-wide settings | active `admin` assigned directly to Root OU Level 1 |
| Metric settings | active `admin` assigned directly to Root OU Level 1 |
| Period settings | active `admin` assigned directly to Root OU Level 1 |

Backend remains authoritative.

The route guard must validate the direct Root OU assignment from backend permission context. Hiding a menu or trusting an inherited/subtree `admin` flag is not authorization.

---

# 26. Internationalization

Version 1 is not required to support multi-language UI.

However, frontend text should be centralized enough to support future translation.

Recommended:

```text
src/lib/constants/messages.ts
```

Future languages:

- Thai
- English

---

# 27. Accessibility and Responsive Design

Frontend should support:

- Desktop browser
- Tablet browser
- Mobile browser through LINE LIFF

Minimum responsive rules:

- Sidebar collapses on mobile.
- Forms are single-column on mobile.
- Tables use horizontal scroll on small screens.
- Action buttons remain reachable on mobile.
- Color must not be the only status indicator.

---

# 28. Security Rules for Frontend

Frontend must not:

- Store service role key.
- Bypass RLS.
- Trust hidden form fields for permission.
- Trust URL `ouId` without backend validation.
- Build dashboard totals from unauthorized raw data.
- Create fixed metric columns.
- Expose sensitive debug details to users.

Frontend must:

- Use authenticated Supabase client.
- Use RPC for workflow mutations.
- Validate input before submit.
- Handle unauthorized responses gracefully.
- Clear stores on logout.

---

# 29. Environment Variables

Required frontend environment variables:

```text
PUBLIC_SUPABASE_URL=
PUBLIC_SUPABASE_ANON_KEY=
PUBLIC_LINE_LIFF_ID=
PUBLIC_APP_ENV=development|staging|production
```

Rules:

- `PUBLIC_*` variables are visible to browser.
- Never put secrets in `PUBLIC_*` variables.
- Service role key must not exist in frontend environment.

---

# 30. Testing Strategy

Recommended frontend tests:

| Test Type | Scope |
|---|---|
| Unit test | utilities, mappers, permission helpers |
| Component test | forms, tree, cards, tables |
| Integration test | login flow, submission flow, approval flow |
| E2E test | critical user journeys |

Critical test scenarios:

1. User without permission cannot see protected actions.
2. Data entry can submit for assigned OU.
3. Data entry cannot submit for unauthorized OU.
4. Manager can view descendant OU dashboard.
5. Approver sees approval queue.
6. Viewer cannot mutate data.
7. Dynamic metric form renders new metric without code change.
8. Logout clears session and stores.

---

# 31. MVP Page Scope

## Phase 1 Required Pages

| Page | Required in MVP |
|---|---:|
| Login | Yes |
| Dashboard | Yes |
| Organization Tree | Yes |
| Submission Form | Yes |
| Submission List | Yes |
| Reports | Yes |
| Profile | Yes |
| User Management | Basic |
| Metric Settings | Basic or seed-only |
| Approval Queue | No |

## Phase 2 Required Pages

| Page | Required in Phase 2 |
|---|---:|
| Approval Queue | Yes |
| Approval Detail | Yes |
| Approval History | Yes |
| Return/Reject Flow | Yes |
| Override Approval | Yes |

---

# 32. Frontend Implementation Order

Recommended order:

```text
1. Project setup
2. Supabase client setup
3. LINE LIFF login page
4. Session and profile store
5. Protected app layout
6. Organization tree service and UI
7. Metric service
8. Period service
9. Submission form
10. Submission list/detail
11. Dashboard summary
12. Reports
13. User management
14. Approval pages
15. Export functions
16. UI polish and testing
```

---

# 33. AI Coding Assistant Rules

When generating frontend code:

1. Read README, ADR, Database Design, RLS, API Design, and this document first.
2. Do not change architecture unless explicitly requested.
3. Do not create fixed attendance fields.
4. Use dynamic metrics from `statistic_metrics`.
5. Use RPC for submit, approve, reject, return, override, and critical mutations.
6. Do not bypass RLS.
7. Do not use service role key in frontend.
8. Keep pages thin.
9. Put Supabase calls in service modules.
10. Use TypeScript strict mode.
11. Use generated database types.
12. Use permission helpers only for UI rendering, not final authorization.
13. Handle loading, empty, error, and unauthorized states.
14. Keep components reusable and small.
15. Update documentation before changing architecture.

---

# 34. Acceptance Criteria

Frontend design is accepted when:

- SvelteKit folder structure is defined.
- Route structure is defined.
- Authentication flow is clear.
- Permission-aware UI rules are defined.
- Service layer pattern is defined.
- Dynamic metric form design is defined.
- Dashboard, submission, approval, reports, and organization UI rules are defined.
- Security constraints are clear.
- AI coding assistant rules are explicit.

---

# 35. Next Documents

Continue with:

- `06_UI_Wireframe.md`
- `07_Reports_Dashboard.md`
- `08_Deployment.md`
- `09_Coding_Convention.md`
- `10_Backlog.md`
- `11_Phase_Plan.md`
- `12_AI_Context.md`
