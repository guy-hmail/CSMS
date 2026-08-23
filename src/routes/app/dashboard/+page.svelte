<script lang="ts">
  import { onMount } from 'svelte';
  import ChildOuSummaryTable from '$lib/components/dashboard/ChildOuSummaryTable.svelte';
  import DashboardFilters from '$lib/components/dashboard/DashboardFilters.svelte';
  import KpiSummaryGrid from '$lib/components/dashboard/KpiSummaryGrid.svelte';
  import SubmissionStatusPanel from '$lib/components/dashboard/SubmissionStatusPanel.svelte';
  import TrendChartPlaceholder from '$lib/components/dashboard/TrendChartPlaceholder.svelte';
  import type { ChildOuSummaryRow, DashboardOption, KpiSummary, SubmissionStatusSummary, TrendPoint } from '$lib/types/dashboard';
  import { getSupabaseBrowserClient, isSupabaseConfigured } from '$lib/supabase/browser';
  import { getAccessibleOuTree, type OrganizationTreeNode } from '$lib/api/organizationApi';
  import { getChildOuSummary, getDashboardTrend, getRecursiveSummary, getSubmissionStatusSummary } from '$lib/api/dashboardApi';
  import { initializeTenantContext, tenantContext } from '$lib/stores/tenantContext';

  let organizationUnits: DashboardOption[] = [];
  let periods: DashboardOption[] = [];
  let selectedOuId = '';
  let selectedPeriodId = '';
  let selectedMetricCode = '';
  let selectedMetricName = '';
  let kpiSummaries: KpiSummary[] = [];
  let trendPoints: TrendPoint[] = [];
  let submissionSummary: SubmissionStatusSummary = { totalExpected: 0, submitted: 0, approved: 0, missing: 0, pending: 0 };
  let childOuRows: ChildOuSummaryRow[] = [];
  let backendStatus: 'connecting' | 'awaiting-auth' | 'live' | 'error' = 'connecting';
  let backendError = '';
  let dashboardLoading = false;
  let trendLoading = false;
  let summaryEmpty = false;
  let mounted = false;
  let lastTenantId = '';
  let requestVersion = 0;
  let trendRequestVersion = 0;

  type ReportingPeriodRow = {
    period_id: string;
    period_start: string;
    period_end: string;
    display_label: string;
    submission_due_at: string | null;
    submission_state: 'not_open' | 'open' | 'overdue' | 'locked';
  };
  const thaiDateFormatter = new Intl.DateTimeFormat('th-TH', { day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Asia/Bangkok' });
  const shortDateFormatter = new Intl.DateTimeFormat('th-TH', { day: 'numeric', month: 'short', timeZone: 'Asia/Bangkok' });
  const weekdayFormatter = new Intl.DateTimeFormat('th-TH', { weekday: 'long', timeZone: 'Asia/Bangkok' });
  const dueFormatter = new Intl.DateTimeFormat('th-TH', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  $: activeTenantId = $tenantContext.activeTenant?.tenant_id ?? '';
  $: if (mounted && activeTenantId && activeTenantId !== lastTenantId) {
    lastTenantId = activeTenantId;
    void loadLiveDashboard();
  }

  function thaiDate(value: string): string { return thaiDateFormatter.format(new Date(`${value}T00:00:00+07:00`)); }
  function shortDate(value: string): string { return shortDateFormatter.format(new Date(`${value}T00:00:00+07:00`)); }
  function periodOption(period: ReportingPeriodRow): DashboardOption {
    const date = new Date(`${period.period_end}T00:00:00+07:00`);
    const deadline = period.submission_due_at ? ` · กำหนดส่ง ${dueFormatter.format(new Date(period.submission_due_at))}` : '';
    return { id: period.period_id, label: `${weekdayFormatter.format(date)}ที่ ${thaiDate(period.period_end)}`, helperText: `รอบคำนวณ ${thaiDate(period.period_start)} – ${thaiDate(period.period_end)}${deadline}` };
  }
  function flattenOus(nodes: OrganizationTreeNode[]): DashboardOption[] {
    return nodes.flatMap((node) => [{ id: node.id, label: `${'— '.repeat(Math.max(node.level - 1, 0))}${node.name}` }, ...flattenOus(node.children)]);
  }

  async function loadSelectedDashboard(): Promise<void> {
    if (!selectedOuId || !selectedPeriodId) return;
    const version = ++requestVersion;
    dashboardLoading = true;
    backendError = '';
    try {
      const selectedIndex = periods.findIndex((period) => period.id === selectedPeriodId);
      const comparePeriodId = selectedIndex >= 0 ? periods[selectedIndex + 1]?.id ?? null : null;
      const client = getSupabaseBrowserClient();
      const summary = await getRecursiveSummary(client, selectedOuId, selectedPeriodId, comparePeriodId);
      if (version !== requestVersion) return;
      kpiSummaries = summary.metrics.map((metric) => ({ metricCode: metric.metricCode, metricName: metric.metricName, metricKind: metric.metricKind, value: metric.currentValue ?? 0, unit: metric.unit, growthPercent: metric.growthPercent }));
      summaryEmpty = summary.metrics.every((metric) => metric.currentValue === null);
      if (!summary.metrics.some((metric) => metric.metricCode === selectedMetricCode)) selectedMetricCode = summary.metrics[0]?.metricCode ?? '';
      selectedMetricName = summary.metrics.find((metric) => metric.metricCode === selectedMetricCode)?.metricName ?? '';
      const [status, children, trend] = await Promise.all([
        getSubmissionStatusSummary(client, selectedOuId, selectedPeriodId),
        getChildOuSummary(client, selectedOuId, selectedPeriodId),
        selectedMetricCode ? getDashboardTrend(client, selectedOuId, selectedMetricCode, selectedPeriodId, 12) : Promise.resolve(null)
      ]);
      if (version !== requestVersion) return;
      submissionSummary = status.summary;
      childOuRows = children.children.map((child) => ({ ouId: child.ouId, ouName: child.ouName, status: child.status, metrics: child.metrics }));
      trendPoints = (trend?.points ?? []).map((point) => ({ label: shortDate(point.periodEnd), value: point.value }));
      selectedMetricName = trend?.metricName ?? selectedMetricName;
      backendStatus = 'live';
    } catch (error) {
      if (version !== requestVersion) return;
      backendStatus = 'error';
      backendError = error instanceof Error ? error.message : 'ไม่สามารถโหลดข้อมูล Dashboard ได้';
      kpiSummaries = [];
      trendPoints = [];
      childOuRows = [];
    } finally {
      if (version === requestVersion) dashboardLoading = false;
    }
  }

  async function selectMetric(metricCode: string): Promise<void> {
    const version = ++trendRequestVersion;
    selectedMetricCode = metricCode;
    selectedMetricName = kpiSummaries.find((item) => item.metricCode === metricCode)?.metricName ?? '';
    trendLoading = true;
    try {
      const trend = await getDashboardTrend(getSupabaseBrowserClient(), selectedOuId, metricCode, selectedPeriodId, 12);
      if (version !== trendRequestVersion) return;
      trendPoints = trend.points.map((point) => ({ label: shortDate(point.periodEnd), value: point.value }));
      selectedMetricName = trend.metricName;
    } catch (error) {
      if (version !== trendRequestVersion) return;
      backendError = error instanceof Error ? error.message : 'ไม่สามารถโหลดแนวโน้มได้';
    } finally {
      if (version === trendRequestVersion) trendLoading = false;
    }
  }

  function selectChildOu(ouId: string): void {
    selectedOuId = ouId;
    void loadSelectedDashboard();
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  function monthlyReportHref(metricCode: string): string {
    const params = new URLSearchParams({
      type: 'monthly',
      ou: selectedOuId,
      period: selectedPeriodId,
      metric: metricCode,
      focus: 'trend'
    });
    return `/app/reports?${params.toString()}`;
  }

  async function loadLiveDashboard(): Promise<void> {
    if (!isSupabaseConfigured()) return;
    backendStatus = 'connecting';
    backendError = '';
    try {
      const client = getSupabaseBrowserClient();
      const { data: sessionData } = await client.auth.getSession();
      if (!sessionData.session) { backendStatus = 'awaiting-auth'; return; }
      const [tree, periodResult] = await Promise.all([getAccessibleOuTree(client), client.rpc('ensure_recent_reporting_periods')]);
      if (periodResult.error) throw periodResult.error;
      organizationUnits = flattenOus(tree.items);
      periods = ((periodResult.data ?? []) as ReportingPeriodRow[]).map(periodOption);
      const preferredOuId = $tenantContext.preferences?.defaultOuId ?? '';
      selectedOuId = organizationUnits.some((ou) => ou.id === preferredOuId) ? preferredOuId : organizationUnits[0]?.id ?? '';
      selectedPeriodId = periods[0]?.id ?? '';
      selectedMetricCode = '';
      kpiSummaries = [];
      trendPoints = [];
      childOuRows = [];
      submissionSummary = { totalExpected: 0, submitted: 0, approved: 0, missing: 0, pending: 0 };
      if (!organizationUnits.length || !periods.length) { backendStatus = 'live'; return; }
      await loadSelectedDashboard();
    } catch (error) {
      backendStatus = 'error';
      backendError = error instanceof Error ? error.message : 'ไม่สามารถโหลด Dashboard ได้';
      organizationUnits = [];
      periods = [];
    }
  }
  onMount(() => {
    void initializeTenantContext()
      .then(() => { mounted = true; })
      .catch((error) => {
        backendStatus = 'error';
        backendError = error instanceof Error ? error.message : 'ไม่สามารถโหลด Tenant context ได้';
      });
  });
</script>

<svelte:head><title>Dashboard | CSMS</title></svelte:head>

<div class="app-page space-y-5">
  <p class="text-xs text-slate-500" aria-live="polite">แหล่งข้อมูล: {backendStatus === 'live' ? 'Supabase' : backendStatus === 'connecting' ? 'กำลังโหลด…' : backendStatus === 'awaiting-auth' ? 'รอการเข้าสู่ระบบ' : 'เชื่อมต่อไม่ได้'}</p>
  <DashboardFilters {organizationUnits} {periods} bind:selectedOuId bind:selectedPeriodId onFiltersChange={() => void loadSelectedDashboard()} />

  {#if backendStatus === 'error'}
    <section class="rounded-md border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700" role="alert">โหลด Dashboard ไม่สำเร็จ: {backendError} <button class="ml-2 underline" type="button" on:click={loadLiveDashboard}>ลองอีกครั้ง</button></section>
  {:else if backendStatus === 'connecting' || dashboardLoading}
    <section class="app-card px-5 py-14 text-center text-sm text-slate-600" aria-busy="true">กำลังคำนวณ Dashboard...</section>
  {:else if backendStatus === 'live' && organizationUnits.length === 0}
    <section class="app-card px-5 py-14 text-center"><h2 class="text-base font-semibold text-slate-900">ยังไม่มีหน่วยงานที่เข้าถึงได้</h2><p class="mt-2 text-sm text-slate-500">ติดต่อผู้ดูแลเพื่อกำหนดสิทธิ์ OU</p></section>
  {:else if backendStatus === 'live' && periods.length === 0}
    <section class="app-card px-5 py-14 text-center"><h2 class="text-base font-semibold text-slate-900">Tenant นี้ยังไม่มีรอบรายงาน</h2></section>
  {:else if periods.length > 0}
    {#if summaryEmpty}<section class="rounded-md border border-slate-200 bg-slate-50 p-4 text-sm text-slate-600">ยังไม่มีสถิติที่อนุมัติแล้วสำหรับหน่วยงานและสัปดาห์นี้ สถานะการส่งข้อมูลยังแสดงด้านล่าง</section>{/if}
    <KpiSummaryGrid items={kpiSummaries} {selectedMetricCode} onSelectMetric={(code) => void selectMetric(code)} reportHrefForMetric={monthlyReportHref} />
    <div class="grid min-w-0 max-w-full gap-5 xl:grid-cols-[minmax(0,1fr)_23rem]">
      <TrendChartPlaceholder points={trendPoints} metricName={selectedMetricName || 'ตัวชี้วัด'} metrics={kpiSummaries} {selectedMetricCode} loading={trendLoading} onMetricChange={(code) => void selectMetric(code)} />
      <SubmissionStatusPanel summary={submissionSummary} />
    </div>
    <ChildOuSummaryTable rows={childOuRows} onSelectOu={selectChildOu} />
  {/if}
</div>
