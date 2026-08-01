# Church Statistics Management System (CSMS)
## Reports & Dashboard Specification

Version: 1.0  
Status: Production Blueprint  
Target Platform: SvelteKit + Supabase PostgreSQL + RPC + RLS  
Frontend: SvelteKit + Skeleton UI + Chart.js  
Architecture Style: Dynamic Metrics, Recursive Aggregation, Permission-Protected Reporting

---

# 1. Document Purpose

This document defines the reporting and dashboard design for the Church Statistics Management System (CSMS).

It covers:

- Dashboard structure
- KPI definitions
- Summary cards
- Chart specifications
- Report specifications
- Recursive aggregation rules
- Filter behavior
- Export behavior
- Permission rules
- SQL/RPC requirements
- Phase 1 and Phase 2 workflow differences
- Future analytics extensions

This document must be used together with:

- `00_Project_Overview.md`
- `01_Business_Requirements.md`
- `02_Database_Design.md`
- `03_RLS_and_Permissions.md`
- `04_API_Design.md`
- `05_Frontend_Design.md`
- `06_UI_Wireframe.md`
- `ARCHITECTURE_DECISIONS.md`
- `AI_STYLE_GUIDE.md`

---

# 2. Reporting Design Principles

CSMS reporting follows these principles:

1. Reports must use dynamic metrics.
2. Reports must never depend on fixed columns such as `attendance`, `sunday_school`, or `new_visitor`.
3. Parent OU reports must aggregate data recursively from descendant OUs.
4. Report data must respect Supabase RLS.
5. The frontend must not perform security-sensitive filtering.
6. Dashboard and reports must use approved submissions only.
7. Phase 1 submitted records are automatically approved.
8. Filters must use canonical reporting periods.
9. Export results must match on-screen report results.
10. All dashboard queries must be implemented through views or RPC functions.
11. Every report must be scoped by `church_id` and accessible OU subtree.
12. Reporting UI must be metric-aware and should render labels dynamically from `statistic_metrics`.

---

# 3. Report Data Model

The reporting model uses these tables:

| Table | Purpose |
|---|---|
| `churches` | Tenant scope |
| `organization_units` | OU hierarchy |
| `ou_members` | Permission and accessible subtree |
| `statistic_periods` | Week, month, quarter, year, custom periods |
| `statistic_metrics` | Dynamic KPI definitions |
| `statistic_submissions` | Submission header and approval status |
| `statistic_values` | Metric values |
| `approval_logs` | Approval workflow history |
| `audit_logs` | Audit trail |

Canonical reporting view:

```text
organization_units
    ↓
statistic_submissions
    ↓
statistic_values
    ↓
statistic_metrics
```

Parent OU reporting uses:

```text
selected_ou
    ↓
recursive descendants
    ↓
approved submissions
    ↓
metric aggregation
```

---

# 4. Dashboard Types

## 4.1 My Dashboard

Audience:

- Data Entry
- Viewer
- Manager
- Approver
- Admin

Purpose:

Show the user's assigned OU summary and quick actions.

Main content:

- Current reporting period
- Assigned OUs
- Submission status
- Key metric summary cards
- Weekly trend chart
- Recent submissions
- Pending action prompts

---

## 4.2 Organization Dashboard

Audience:

- Manager
- Approver
- Admin
- Viewer with access

Purpose:

Show summary for one selected OU and its subtree.

Main content:

- Selected OU name and hierarchy path
- Current week summary
- Monthly summary
- Year-to-date summary
- Child OU comparison
- Submission status by child OU
- Approval status by child OU
- Trend charts

---

## 4.3 Parent / Executive Dashboard

Audience:

- Church-level admin
- Senior manager
- Senior approver

Purpose:

Show high-level health of all child organizations under a selected root OU.

Main content:

- Total attendance or configured primary metric
- Growth comparison
- Missing submissions
- Top growth OUs
- Declining OUs
- Pending approvals
- Export shortcuts

---

## 4.4 Approval Dashboard

Audience:

- Approver
- Manager
- Admin

Purpose:

Monitor submission workflow.

Main content:

- Submitted / Pending approval count
- Approved count
- Rejected count
- Returned count
- Pending approval list
- Aging pending items
- Override indicators

Tenant-mode note:

The approval dashboard is empty/minimal for an `auto_approve` tenant and shows the active queue for an `approval_required` tenant.

---

# 5. Dashboard Navigation

Recommended route structure:

```text
/app/dashboard
/app/dashboard/[ouId]
/app/reports
/app/reports/weekly
/app/reports/monthly
/app/reports/yearly
/app/reports/submission-status
/app/reports/export
/app/approval
```

Navigation visibility depends on user permission:

| Route | Admin | Manager | Approver | Data Entry | Viewer |
|---|---:|---:|---:|---:|---:|
| `/app/dashboard` | Yes | Yes | Yes | Yes | Yes |
| `/app/dashboard/[ouId]` | Yes | Yes | Yes | Limited | Yes |
| `/app/reports` | Yes | Yes | Yes | Limited | Yes |
| `/app/approval` | Yes | Yes | Yes | No | No |
| `/app/reports/export` | Yes | Yes | Yes | Limited | Limited |

Limited means only accessible for assigned OU or permitted subtree.

---

# 6. KPI Framework

## 6.1 Dynamic KPI Source

All KPIs come from `statistic_metrics`.

Example metrics:

| Code | Name | Category | Unit | Aggregation |
|---|---|---|---|---|
| `ATTENDANCE` | Worship Attendance | attendance | person | sum |
| `SUNDAY_SCHOOL` | Sunday School | attendance | person | sum |
| `NEW_VISITOR` | New Visitors | attendance | person | sum |
| `NEW_BELIEVER` | New Believers | ministry | person | sum |
| `ONLINE` | Online Attendance | attendance | person | sum |
| `OFFERING` | Offering | finance | THB | sum |

Frontend must render KPI names dynamically from the `name` field.

Do not hardcode metric labels unless used only as default seed examples.

---

## 6.2 Primary KPI

Each church should have one primary dashboard KPI.

Default:

```text
ATTENDANCE
```

Future enhancement:

Add church setting:

```text
primary_metric_code
```

Until then, the frontend may treat `ATTENDANCE` as the default primary KPI when available.

---

## 6.3 KPI Aggregation Rules

The aggregation input set is approved direct submissions from active OUs with `allow_data_entry = true`. A parent OU direct submission represents parent-only activity and is additive to descendant submissions. Generated parent rollups are never stored or re-aggregated.

| Aggregation | Rule |
|---|---|
| `sum` | Sum numeric values |
| `avg` | Average numeric values |
| `max` | Maximum numeric value |
| `min` | Minimum numeric value |
| `none` | Do not aggregate; display only detail values |

Text and boolean metrics are not included in numeric summary cards unless explicitly designed.

---

## 6.4 KPI Comparison Rules

Supported comparisons:

| Comparison | Definition |
|---|---|
| Week-over-week | Current week vs previous week |
| Month-over-month | Current month vs previous month |
| Year-over-year | Current period vs same period previous year |
| Year-to-date | Sum from first period of year to selected period |

Formula:

```text
growth_percent = ((current_value - previous_value) / previous_value) * 100
```

If previous value is 0 or null:

```text
growth_percent = null
```

UI should display:

```text
N/A
```

---

# 7. Dashboard Summary Cards

## 7.1 Current Period Summary Card

Displays one card per important metric.

Fields:

| Field | Description |
|---|---|
| Metric name | From `statistic_metrics.name` |
| Current value | Aggregated metric value |
| Unit | From `statistic_metrics.unit` |
| Comparison value | Previous period comparison |
| Growth percent | Percentage change |
| Trend indicator | Up / down / stable |

Wireframe:

```text
┌────────────────────────────┐
│ Worship Attendance          │
│ 1,245 person                │
│ +8.4% vs previous week      │
└────────────────────────────┘
```

---

## 7.2 Submission Status Card

Displays status of child OU submissions.

Fields:

| Field | Description |
|---|---|
| Total expected OU | Leaf or data-entry enabled OUs |
| Submitted | OUs with submission |
| Approved | Approved submissions |
| Missing | Expected OU without submission |
| Pending | Submitted but not approved, Phase 2 |

Wireframe:

```text
┌────────────────────────────┐
│ Submission Status           │
│ Submitted: 18 / 22          │
│ Missing: 4                  │
│ Pending Approval: 3         │
└────────────────────────────┘
```

---

## 7.3 Approval Status Card

Phase 2 dashboard card.

Fields:

| Field | Description |
|---|---|
| Pending approval | Count of submitted records |
| Returned | Count of returned records |
| Rejected | Count of rejected records |
| Approved | Count of approved records |
| Oldest pending | Oldest pending submission age |

---

# 8. Chart Specifications

## 8.1 Weekly Trend Chart

Purpose:

Show selected metric trend over time.

Chart type:

```text
Line Chart
```

Default period range:

```text
Last 12 weeks
```

Data source:

```text
RPC get_dashboard_trend
```

Fields:

| Field | Description |
|---|---|
| period_label | X-axis label |
| metric_value | Y-axis value |
| metric_code | Selected metric |

Example:

```text
Week 01 → Week 12
```

---

## 8.2 Child OU Comparison Chart

Purpose:

Compare child OUs for selected period and metric.

Chart type:

```text
Bar Chart
```

Default metric:

```text
Primary KPI
```

Data source:

```text
RPC get_child_ou_summary
```

Sort options:

- Highest value first
- Lowest value first
- OU sort order
- Growth percent

---

## 8.3 Metric Breakdown Chart

Purpose:

Show multiple metric totals for selected OU and period.

Chart type:

```text
Bar Chart or Card Grid
```

Metric categories:

- attendance
- ministry
- finance
- custom

---

## 8.4 Submission Completion Chart

Purpose:

Show submitted vs missing OUs.

Chart type:

```text
Donut Chart
```

Data groups:

- Submitted
- Missing
- Pending Approval
- Returned

In `auto_approve`, Submitted and Approved complete in one transaction. In `approval_required`, they must remain separate workflow counts.

---

# 9. Report Types

## 9.1 Weekly Report

Route:

```text
/app/reports/weekly
```

Purpose:

Show all metrics for selected OU subtree in a selected week.

Filters:

| Filter | Required | Description |
|---|---:|---|
| OU | Yes | Selected root OU |
| Week | Yes | Reporting week |
| Metric category | No | attendance/ministry/finance/custom |
| Status | No | Phase 2 only |

Columns:

| Column | Description |
|---|---|
| OU Name | Reporting OU or child OU |
| Period | Week label |
| Metric columns | Dynamic metric values |
| Total | Optional row total for numeric metrics |
| Status | Submission status |
| Submitted By | Submitter |
| Submitted At | Submit time |
| Approved By | Approver |
| Approved At | Approval time |

Dynamic metric columns are generated from `statistic_metrics`.

---

## 9.2 Monthly Report

Route:

```text
/app/reports/monthly
```

Purpose:

Aggregate weekly approved submissions into a monthly summary.

Filters:

| Filter | Required |
|---|---:|
| OU | Yes |
| Month | Yes |
| Metric category | No |

Aggregation:

```text
All approved weekly periods whose `period_end` is inside the selected month
```

Weeks that overlap months are assigned by their reporting date:

```text
Assign week to month by period_end date.
```

This rule is canonical for monthly, quarterly, and yearly aggregation.

---

## 9.3 Quarterly Report

Route:

```text
/app/reports/quarterly
```

Purpose:

Aggregate approved submissions by quarter.

Quarter definition:

| Quarter | Months |
|---|---|
| Q1 | Jan-Mar |
| Q2 | Apr-Jun |
| Q3 | Jul-Sep |
| Q4 | Oct-Dec |

---

## 9.4 Yearly Report

Route:

```text
/app/reports/yearly
```

Purpose:

Show yearly summary and trend by month or week.

Filters:

| Filter | Required |
|---|---:|
| OU | Yes |
| Year | Yes |
| Metric | No |

Default display:

- Monthly summary table
- Annual total cards
- Trend chart
- Child OU ranking

---

## 9.5 Submission Status Report

Route:

```text
/app/reports/submission-status
```

Purpose:

Monitor which OUs submitted reports.

Filters:

| Filter | Required |
|---|---:|
| OU | Yes |
| Period | Yes |
| Status | No |

Columns:

| Column | Description |
|---|---|
| OU Name | Data-entry OU |
| Parent OU | Direct parent |
| Expected | Yes/No |
| Submitted | Yes/No |
| Status | draft/submitted/approved/rejected/returned/missing |
| Submitted At | Submit time |
| Approved At | Approval time |
| Last Updated | Last update time |

Expected OUs are:

```text
active OUs under selected subtree where allow_data_entry = true
```

---

## 9.6 Approval History Report

Route:

```text
/app/reports/approval-history
```

Phase:

```text
Phase 2+
```

Purpose:

Show workflow history for audit and management.

Columns:

| Column | Description |
|---|---|
| Submission | Submission reference |
| OU | Organization Unit |
| Period | Reporting period |
| Action | approve/reject/return/override |
| From Status | Previous status |
| To Status | New status |
| Action By | User |
| Reason | Approval reason/comment |
| Created At | Action time |

---

# 10. Drill-Down Design

Dashboard drill-down path:

```text
Church Dashboard
    ↓
Region Dashboard
    ↓
District Dashboard
    ↓
Cell Group Dashboard
    ↓
Submission Detail
```

Rules:

1. User can drill down only into permitted subtree.
2. Parent dashboard shows child OU summary.
3. Clicking child OU opens dashboard for that OU.
4. Clicking metric opens metric trend/details.
5. Clicking submission status opens submission detail or approval screen.

---

# 11. Filter Design

## 11.1 Common Filters

| Filter | Description |
|---|---|
| OU Selector | Tree-based selector limited by permission |
| Period Selector | Week/month/quarter/year/custom |
| Metric Selector | Active metrics visible to church |
| Metric Category | attendance/ministry/finance/custom |
| Status | submission status |
| Date Range | For trend reports |

---

## 11.2 OU Selector Rules

The OU selector must show only accessible OUs.

Accessible OUs are determined by:

```text
user assigned OU + descendant OUs
```

The frontend may render a filtered tree, but the backend/RLS must enforce final access.

---

## 11.3 Period Selector Rules

Period options come from `statistic_periods`.

Do not calculate reporting periods only in frontend.

Required fields:

- `period_id`
- `period_type`
- `label`
- `period_start`
- `period_end`
- `status`

---

## 11.4 Metric Selector Rules

Metric selector must include:

```text
church_id = current church OR church_id IS NULL
```

Only active metrics:

```text
is_active = true
```

Sort by:

```text
category, sort_order, name
```

---

# 12. Export Design

## 12.1 Supported Formats

| Format | Phase | Library |
|---|---|---|
| Excel `.xlsx` | Phase 1 | SheetJS |
| PDF | Phase 1/2 | pdf-lib or server-side generator |
| CSV | Optional | Native export |

---

## 12.2 Export Rules

1. Export must use the same RPC result as the on-screen report.
2. Export must respect RLS.
3. Export must include filter metadata.
4. Export must include generated timestamp.
5. Export must include church name and selected OU name.
6. Export must not expose inaccessible child OUs.
7. Export file names must be deterministic.

Example filename:

```text
CSMS_Weekly_Report_<OU_CODE>_<YEAR>_W<WEEK_NO>.xlsx
```

---

## 12.3 Excel Layout

Recommended worksheet structure:

```text
Sheet 1: Summary
Sheet 2: Detail
Sheet 3: Submission Status
```

Summary sheet:

| Field | Value |
|---|---|
| Church | Church name |
| Organization Unit | Selected OU |
| Period | Period label |
| Generated At | Timestamp |
| Generated By | User |

Detail sheet:

```text
OU rows + dynamic metric columns
```

---

## 12.4 PDF Layout

PDF should be used for official printable reports.

Sections:

1. Header
2. Filter summary
3. KPI summary cards
4. Main report table
5. Submission status
6. Footer with generated timestamp

PDF export should avoid overly wide dynamic metric tables.

If many metrics exist, use category sections:

```text
Attendance Metrics
Ministry Metrics
Finance Metrics
Custom Metrics
```

---

# 13. RPC Requirements

Reports and dashboards should use RPC functions.

The canonical callable request/response contract, casing, response envelope, and error behavior are defined in `04_API_Design.md`. The examples below describe report semantics only and must not be generated as a second incompatible API contract.

## 13.1 `get_recursive_summary`

Purpose:

Return summary cards for selected OU and period.

Input:

```json
{
  "p_ou_id": "uuid",
  "p_period_id": "uuid",
  "p_compare_period_id": "uuid | null"
}
```

Output:

```json
{
  "ou": {
    "id": "uuid",
    "name": "string",
    "path": "string"
  },
  "period": {
    "id": "uuid",
    "label": "string"
  },
  "metrics": [
    {
      "metric_id": "uuid",
      "metric_code": "ATTENDANCE",
      "metric_name": "Worship Attendance",
      "category": "attendance",
      "unit": "person",
      "aggregation": "sum",
      "current_value": 1245,
      "compare_value": 1148,
      "growth_percent": 8.45
    }
  ]
}
```

Authorization:

- User must have viewer or higher permission on selected OU or ancestor.
- RLS must restrict inaccessible data.

---

## 13.2 `get_dashboard_trend`

Purpose:

Return trend data for one metric across periods.

Input:

```json
{
  "p_ou_id": "uuid",
  "p_metric_code": "string",
  "p_period_type": "week",
  "p_start_date": "date",
  "p_end_date": "date"
}
```

Output:

```json
[
  {
    "period_id": "uuid",
    "period_label": "2026-W01",
    "period_start": "2026-01-01",
    "period_end": "2026-01-07",
    "value": 120
  }
]
```

---

## 13.3 `get_child_ou_summary`

Purpose:

Return child OU metric summary for selected parent OU.

Input:

```json
{
  "p_parent_ou_id": "uuid",
  "p_period_id": "uuid",
  "p_metric_code": "string | null"
}
```

Output:

```json
[
  {
    "ou_id": "uuid",
    "ou_name": "District A",
    "level": 2,
    "metric_code": "ATTENDANCE",
    "metric_name": "Worship Attendance",
    "value": 230,
    "submission_status": "complete"
  }
]
```

---

## 13.4 `get_submission_status_summary`

Purpose:

Return expected vs submitted OU list.

Input:

```json
{
  "p_root_ou_id": "uuid",
  "p_period_id": "uuid"
}
```

Output:

```json
[
  {
    "ou_id": "uuid",
    "ou_name": "Group A",
    "parent_ou_name": "District 1",
    "expected": true,
    "submitted": true,
    "status": "approved",
    "submitted_at": "timestamp",
    "approved_at": "timestamp"
  }
]
```

---

## 13.5 `get_report_flat_values`

Purpose:

Return normalized report values for frontend table pivot or export.

Input:

```json
{
  "p_root_ou_id": "uuid",
  "p_period_id": "uuid",
  "p_metric_category": "string | null"
}
```

Output:

```json
[
  {
    "ou_id": "uuid",
    "ou_name": "Group A",
    "period_id": "uuid",
    "period_label": "2026-W01",
    "metric_code": "ATTENDANCE",
    "metric_name": "Worship Attendance",
    "category": "attendance",
    "unit": "person",
    "numeric_value": 45,
    "text_value": null,
    "boolean_value": null,
    "status": "approved"
  }
]
```

Frontend may pivot this result into dynamic columns.

---

# 14. SQL Design Examples

## 14.1 Recursive Subtree Metric Summary

```sql
with recursive descendants as (
    select id
    from organization_units
    where id = p_ou_id
      and is_active = true
      and deleted_at is null

    union all

    select child.id
    from organization_units child
    join descendants d on child.parent_id = d.id
    where child.is_active = true
      and child.deleted_at is null
)
select
    m.id as metric_id,
    m.code as metric_code,
    m.name as metric_name,
    m.category,
    m.unit,
    m.aggregation,
    case m.aggregation
        when 'sum' then sum(v.numeric_value)
        when 'avg' then avg(v.numeric_value)
        when 'max' then max(v.numeric_value)
        when 'min' then min(v.numeric_value)
        else null
    end as value
from statistic_submissions s
join statistic_values v on v.submission_id = s.id
join statistic_metrics m on m.id = v.metric_id
where s.ou_id in (select id from descendants)
  and s.period_id = p_period_id
  and s.status = 'approved'
  and s.deleted_at is null
  and m.is_active = true
group by m.id, m.code, m.name, m.category, m.unit, m.aggregation
order by min(m.sort_order), m.name;
```

---

## 14.2 Expected Submission OUs

```sql
with recursive descendants as (
    select id, parent_id, name, allow_data_entry
    from organization_units
    where id = p_root_ou_id
      and is_active = true
      and deleted_at is null

    union all

    select child.id, child.parent_id, child.name, child.allow_data_entry
    from organization_units child
    join descendants d on child.parent_id = d.id
    where child.is_active = true
      and child.deleted_at is null
)
select d.*
from descendants d
where d.allow_data_entry = true;
```

---

# 15. Permission Rules

## 15.1 Dashboard Access

A user can view a dashboard if:

- User is active.
- User belongs to the same church.
- User has one of these permissions on selected OU or ancestor:
  - admin
  - manager
  - approver
  - data_entry
  - viewer

Data Entry users should normally see their assigned OU and not unrestricted parent summaries unless explicitly assigned.

---

## 15.2 Report Access

| Report | Required Permission |
|---|---|
| Weekly Report | viewer or higher |
| Monthly Report | viewer or higher |
| Yearly Report | viewer or higher |
| Submission Status | manager, approver, admin, or viewer if assigned |
| Approval History | approver, manager, admin |
| Export | viewer or higher, limited by accessible subtree |

---

## 15.3 Export Access

Export follows the same permission as the source report.

No separate export privilege is required in Phase 1.

Future enhancement:

Add permission:

```text
report_exporter
```

Do not add this prematurely.

---

# 16. Phase Behavior

## 16.1 Phase 1 MVP

Submission workflow:

```text
Draft → Submit → Approved
```

Dashboard behavior:

- Submitted records appear as approved immediately.
- Approval status charts are optional.
- Pending approval count should be zero.
- Reports include records where `status = approved`.

---

## 16.2 Phase 2 Approval Workflow

Submission workflow:

```text
Draft → Submitted → Approved
              ↓
          Rejected / Returned
```

Dashboard behavior:

- Official reports include only approved submissions.
- Submission status report shows pending, returned, rejected, missing.
- Approval dashboard becomes active.
- Parent dashboard may show pending approval warning.

---

# 17. UI Components

Recommended components:

```text
DashboardSummaryCard.svelte
MetricTrendChart.svelte
ChildOuComparisonChart.svelte
SubmissionStatusCard.svelte
ReportFilterPanel.svelte
ReportDataTable.svelte
MetricCategoryTabs.svelte
ExportButtonGroup.svelte
OuDrilldownBreadcrumb.svelte
PeriodSelector.svelte
MetricSelector.svelte
```

Component rules:

1. Components receive data from services.
2. Components do not call Supabase directly unless they are page-level load functions or service wrappers.
3. Components do not implement authorization logic.
4. Components may hide buttons based on permission metadata returned by backend.
5. Components must support dynamic metrics.

---

# 18. Frontend Service Design

Recommended service file:

```text
src/lib/features/reports/reportService.ts
src/lib/features/dashboard/dashboardService.ts
```

Example functions:

```ts
getDashboardSummary(ouId: string, periodId: string): Promise<DashboardSummary>
getMetricTrend(params: MetricTrendParams): Promise<MetricTrendPoint[]>
getChildOuSummary(params: ChildOuSummaryParams): Promise<ChildOuSummaryRow[]>
getSubmissionStatusReport(params: SubmissionStatusParams): Promise<SubmissionStatusRow[]>
getReportFlatValues(params: ReportFlatValuesParams): Promise<ReportFlatValueRow[]>
exportWeeklyReport(params: ExportReportParams): Promise<Blob>
```

Naming convention:

- TypeScript functions use camelCase.
- Types use PascalCase.
- Database fields remain snake_case at the API boundary unless explicitly mapped.

---

# 19. TypeScript Types

Recommended types:

```ts
export type MetricSummary = {
  metric_id: string;
  metric_code: string;
  metric_name: string;
  category: string;
  unit: string;
  aggregation: 'sum' | 'avg' | 'max' | 'min' | 'none';
  current_value: number | null;
  compare_value: number | null;
  growth_percent: number | null;
};

export type DashboardSummary = {
  ou: {
    id: string;
    name: string;
    path: string;
  };
  period: {
    id: string;
    label: string;
  };
  metrics: MetricSummary[];
};

export type ReportFlatValueRow = {
  ou_id: string;
  ou_name: string;
  period_id: string;
  period_label: string;
  metric_code: string;
  metric_name: string;
  category: string;
  unit: string;
  numeric_value: number | null;
  text_value: string | null;
  boolean_value: boolean | null;
  status: string;
};
```

---

# 20. Empty State Design

## 20.1 No Submission

Message:

```text
No statistics have been submitted for this period.
```

Action:

- Show `Submit Statistics` button if user has data_entry/manager/admin permission.
- Show `View other period` if read-only.

---

## 20.2 No Metrics Configured

Message:

```text
No active metrics are configured for this church.
```

Action:

- Admin: show `Configure Metrics`.
- Non-admin: show contact administrator message.

---

## 20.3 No Accessible OU

Message:

```text
You do not have access to any organization unit.
```

Action:

- Suggest contacting church administrator.

---

# 21. Performance Strategy

Expected first production scale:

- 1–20 churches
- 100–1,000 users
- 100–2,000 OUs
- 52 periods/year
- 5–50 metrics
- 5,000–500,000 statistic values/year

Initial approach:

- Use indexed recursive queries.
- Use RPC for dashboard summaries.
- Use pagination for detailed reports.
- Cache metric definitions in frontend for session lifetime.
- Avoid premature materialized views.

Indexes already recommended:

```text
idx_ou_church_parent
idx_ou_path
idx_submissions_church_period
idx_submissions_ou
idx_values_submission
idx_values_metric
```

Future optimization:

- Materialized dashboard views
- Cached summary table
- Monthly summary table
- Yearly summary table
- `ltree` indexing
- Partition `statistic_values` by year/church

---

# 22. Future Materialized Views

Do not implement in Phase 1 unless performance requires it.

Candidate materialized view:

```text
mv_dashboard_metric_summary
```

Possible columns:

| Column | Description |
|---|---|
| church_id | Tenant |
| ou_id | Reporting OU |
| period_id | Period |
| metric_id | Metric |
| aggregated_value | Aggregated numeric value |
| refreshed_at | Refresh timestamp |

Refresh strategy:

```text
After submission approval
After approval status change
Scheduled nightly refresh
```

---

# 23. AI Summary Future Design

Phase:

```text
Phase 4 Analytics
```

Purpose:

Generate natural-language summaries for leaders.

Example output:

```text
This week attendance increased by 8.4% compared with last week. District A had the highest growth, while District C has not submitted statistics yet.
```

Data source:

- Dashboard summary RPC
- Trend RPC
- Submission status RPC

Rules:

1. AI must not query the database directly from frontend.
2. AI summary must use authorized report data only.
3. AI summary must not expose inaccessible OUs.
4. AI output should be treated as assistant commentary, not official record.

---

# 24. Validation Rules

Report validation:

| Rule | Behavior |
|---|---|
| Missing OU | Return validation error |
| Missing period | Return validation error |
| No permission | Return forbidden |
| Invalid metric | Return validation error |
| Locked period | Still reportable |
| Deleted OU | Not reportable unless audit report |
| Rejected submission | Excluded from official reports |
| Returned submission | Excluded from official reports |
| Draft submission | Excluded from official reports |

---

# 25. Error Handling

Recommended error codes:

| Code | Meaning |
|---|---|
| `REPORT_OU_REQUIRED` | OU filter is required |
| `REPORT_PERIOD_REQUIRED` | Period filter is required |
| `REPORT_FORBIDDEN` | User cannot access selected OU/report |
| `REPORT_METRIC_NOT_FOUND` | Metric does not exist or inactive |
| `REPORT_NO_DATA` | No report data found |
| `EXPORT_FAILED` | Export generation failed |

Frontend behavior:

- Show friendly message.
- Do not expose SQL details.
- Log technical error to console only in development.

---

# 26. Report Page Wireframes

## 26.1 Dashboard Page

```text
┌───────────────────────────────────────────────┐
│ Dashboard                                     │
│ [OU Selector] [Period Selector] [Metric]      │
├───────────────────────────────────────────────┤
│ [KPI Card] [KPI Card] [KPI Card] [Status]     │
├───────────────────────────────────────────────┤
│ Weekly Trend Chart                            │
├───────────────────────────────────────────────┤
│ Child OU Comparison                           │
├───────────────────────────────────────────────┤
│ Submission Status Table                       │
└───────────────────────────────────────────────┘
```

---

## 26.2 Weekly Report Page

```text
┌───────────────────────────────────────────────┐
│ Weekly Report                                 │
│ [OU] [Week] [Category] [Export Excel] [PDF]   │
├───────────────────────────────────────────────┤
│ Summary Cards                                 │
├───────────────────────────────────────────────┤
│ Dynamic Metric Table                          │
│ OU | Attendance | Sunday School | Visitor ... │
└───────────────────────────────────────────────┘
```

---

## 26.3 Submission Status Page

```text
┌───────────────────────────────────────────────┐
│ Submission Status                             │
│ [OU] [Period] [Status]                        │
├───────────────────────────────────────────────┤
│ Submitted 18 / 22 | Missing 4 | Pending 3     │
├───────────────────────────────────────────────┤
│ OU | Parent | Expected | Status | Updated At  │
└───────────────────────────────────────────────┘
```

---

# 27. Testing Checklist

## 27.1 Dashboard Tests

- User can view assigned OU dashboard.
- User cannot view unauthorized OU dashboard.
- Parent OU summary includes descendant approved submissions.
- Parent OU summary excludes rejected/returned/draft submissions.
- Dynamic metric cards render correctly.
- Week-over-week growth handles zero previous value.
- Missing submission count is correct.

---

## 27.2 Report Tests

- Weekly report shows dynamic metric columns.
- Monthly report aggregates correct periods.
- Yearly report aggregates all selected-year periods.
- Export result matches on-screen result.
- RLS blocks unauthorized report rows.
- Soft-deleted submissions are excluded.
- Soft-deleted OUs are excluded.

---

## 27.3 Approval Report Tests

- Pending approvals appear only for approver subtree.
- Approved submissions disappear from pending queue.
- Override actions are visible in approval history.
- `auto_approve` submissions appear after their atomic approval; `approval_required` submissions appear only after approver action.

---

# 28. Implementation Order

Recommended order:

```text
1. Create dashboard/report RPC functions
2. Create TypeScript report types
3. Create report services
4. Build dashboard summary cards
5. Build metric trend chart
6. Build child OU comparison table/chart
7. Build weekly report table
8. Build submission status report
9. Add Excel export
10. Add PDF export
11. Add approval dashboard in Phase 2
```

---

# 29. AI Implementation Notes

When generating code:

1. Never create fixed report columns in the database.
2. Use `statistic_metrics` to define report columns.
3. Use `statistic_values` to store report data.
4. Always filter by `church_id`.
5. Always respect RLS.
6. Use RPC for recursive aggregation.
7. Do not aggregate sensitive business logic in frontend.
8. Do not show unauthorized OUs in filters.
9. Do not include draft/rejected/returned submissions in official reports.
10. Reports include only approved submissions in either tenant mode.
11. Use Chart.js for charts.
12. Use SheetJS for Excel export.
13. Keep report components reusable.
14. Keep UI thin and service-driven.

---

# 30. Next Document

Continue with:

- `08_Deployment.md`
- `09_Coding_Convention.md`
- `10_Backlog.md`
- `11_Phase_Plan.md`
- `12_AI_Context.md`
