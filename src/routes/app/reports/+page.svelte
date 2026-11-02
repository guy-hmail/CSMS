<script lang="ts">
  import { visibleRatioTotal } from '$lib/reports/metricCalculation';
  import MetricValue from '$lib/components/common/MetricValue.svelte';
  import { onMount, tick } from 'svelte';
  import { AlertTriangle, BarChart3, CheckCircle2, Download, FileSpreadsheet, FileText, Search, Table2, TrendingUp } from '@lucide/svelte';
  import { initializeTenantContext, tenantContext } from '$lib/stores/tenantContext';
  import { getSupabaseBrowserClient, isSupabaseConfigured } from '$lib/supabase/browser';
  import { getAccessibleOuTree, type OrganizationTreeNode } from '$lib/api/organizationApi';
  import { getReportTable, getReportTrend, getSubmissionCompleteness, type ReportTable, type ReportTrend, type SubmissionCompleteness } from '$lib/api/reportApi';
  import { exportCsv, exportExcel, exportPdf, type ExportMetadata, type ExportRow } from '$lib/reports/reportExport';

  type ReportType = 'weekly' | 'monthly' | 'yearly';
  type ReportingPeriod = { period_id: string; period_start: string; period_end: string; display_label: string; submission_due_at: string | null };
  type PeriodOption = { id: string; label: string; fromDate: string; toDate: string; submissionDueAt?: string | null };
  type OuOption = { id: string; code: string; label: string };

  let reportType: ReportType = 'weekly';
  let organizationUnits: OuOption[] = [];
  let weeklyPeriods: PeriodOption[] = [];
  let selectedOuId = '';
  let selectedPeriodId = '';
  let selectedMetricCode = '';
  let report: ReportTable | null = null;
  let trend: ReportTrend | null = null;
  let completeness: SubmissionCompleteness | null = null;
  let searchQuery = '';
  let statusFilter = 'all';
  let loading = true;
  let exporting = false;
  let errorMessage = '';
  let actionMessage = '';
  let generatedAt = '';
  let mounted = false;
  let lastTenantId = '';
  let requestVersion = 0;
  let focusTrendAfterLoad = false;

  const thaiDate = new Intl.DateTimeFormat('th-TH', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Asia/Bangkok' });
  const thaiMonth = new Intl.DateTimeFormat('th-TH', { month: 'long', year: 'numeric', timeZone: 'Asia/Bangkok' });
  const thaiDateTime = new Intl.DateTimeFormat('th-TH', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Bangkok' });
  $: activeTenantId = $tenantContext.activeTenant?.tenant_id ?? '';
  $: if (mounted && activeTenantId && activeTenantId !== lastTenantId) { lastTenantId = activeTenantId; void loadContext(); }
  $: monthPeriods = buildMonthPeriods(weeklyPeriods);
  $: yearPeriods = buildYearPeriods(weeklyPeriods);
  $: periodOptions = reportType === 'weekly' ? weeklyPeriods : reportType === 'monthly' ? monthPeriods : yearPeriods;
  $: selectedPeriod = periodOptions.find((period) => period.id === selectedPeriodId) ?? periodOptions[0];
  $: selectedMetric = report?.metrics.find((metric) => metric.metricCode === selectedMetricCode) ?? report?.metrics[0];
  $: completenessByOu = new Map((completeness?.items ?? []).map((item) => [item.ouId, item]));
  $: visibleRows = (report?.rows ?? []).filter((row) => {
    const completenessRow = completenessByOu.get(row.ouId);
    const status = !completenessRow?.submitted ? 'missing' : completenessRow.approved === completenessRow.expected ? 'approved' : 'partial';
    return `${row.ouCode} ${row.ouName}`.toLocaleLowerCase().includes(searchQuery.trim().toLocaleLowerCase())
      && (statusFilter === 'all' || statusFilter === status);
  });
  $: completionPercent = completeness?.summary.expected ? Math.round((completeness.summary.submitted / completeness.summary.expected) * 100) : 0;
  $: chartMax = Math.max(...(trend?.points.map((point) => (point.value ?? 0)) ?? [0]), 1);

  $: visibleTotal = selectedMetric?.calculationOperator === 'ratio'
    ? visibleRatioTotal(visibleRows.filter((row) => (completenessByOu.get(row.ouId)?.approved ?? 0) > 0), selectedMetric)
    : { value: visibleRows.reduce((sum, row) => sum + (row.values[selectedMetricCode] ?? 0), 0), error: null };

  function asDate(value: string): Date { return new Date(`${value}T00:00:00+07:00`); }
  function formatDate(value: string): string { return thaiDate.format(asDate(value)); }
  function formatGeneratedAt(): string { return generatedAt ? thaiDateTime.format(new Date(generatedAt)) : '—'; }
  function flattenOus(nodes: OrganizationTreeNode[]): OuOption[] {
    return nodes.flatMap((node) => [{ id: node.id, code: node.code, label: `${'— '.repeat(Math.max(node.level - 1, 0))}${node.name}` }, ...flattenOus(node.children)]);
  }
  function buildMonthPeriods(periods: PeriodOption[]): PeriodOption[] {
    const groups = new Map<string, PeriodOption>();
    for (const period of periods) {
      const date = asDate(period.toDate);
      const id = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
      const fromDate = `${id}-01`;
      const toDate = new Date(date.getFullYear(), date.getMonth() + 1, 0, 12).toISOString().slice(0, 10);
      groups.set(id, { id, label: thaiMonth.format(date), fromDate, toDate });
    }
    return [...groups.values()].sort((a, b) => b.id.localeCompare(a.id));
  }
  function buildYearPeriods(periods: PeriodOption[]): PeriodOption[] {
    const years = new Set(periods.map((period) => asDate(period.toDate).getFullYear()));
    return [...years].sort((a, b) => b - a).map((year) => ({
      id: String(year), label: `ปี ${year + 543}`, fromDate: `${year}-01-01`, toDate: `${year}-12-31`
    }));
  }

  function requestedPeriodId(params: URLSearchParams): string {
    const requested = params.get('period')?.trim() ?? '';
    if (!requested) return periodOptions[0]?.id ?? '';
    if (periodOptions.some((period) => period.id === requested)) return requested;
    if (reportType === 'monthly') {
      const sourceWeek = weeklyPeriods.find((period) => period.id === requested);
      if (sourceWeek) {
        const date = asDate(sourceWeek.toDate);
        const monthId = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
        if (periodOptions.some((period) => period.id === monthId)) return monthId;
      }
    }
    return periodOptions[0]?.id ?? '';
  }

  async function loadContext(): Promise<void> {
    if (!isSupabaseConfigured()) return;
    loading = true;
    errorMessage = '';
    try {
      const client = getSupabaseBrowserClient();
      const { data: sessionData } = await client.auth.getSession();
      if (!sessionData.session) { loading = false; return; }
      const [tree, periodResult] = await Promise.all([getAccessibleOuTree(client), client.rpc('ensure_recent_reporting_periods')]);
      if (periodResult.error) throw periodResult.error;
      organizationUnits = flattenOus(tree.items);
      weeklyPeriods = ((periodResult.data ?? []) as ReportingPeriod[]).map((period) => ({
        id: period.period_id,
        label: `${formatDate(period.period_end)} · รอบคำนวณ ${period.display_label}`,
        fromDate: period.period_start,
        toDate: period.period_end,
        submissionDueAt: period.submission_due_at
      }));
      const params = new URLSearchParams(window.location.search);
      const requestedType = params.get('type');
      reportType = requestedType === 'monthly' || requestedType === 'yearly' ? requestedType : 'weekly';
      await tick();
      const preferredOuId = $tenantContext.preferences?.defaultOuId ?? '';
      const requestedOuId = params.get('ou')?.trim() ?? '';
      selectedOuId = organizationUnits.some((ou) => ou.id === requestedOuId)
        ? requestedOuId
        : organizationUnits.some((ou) => ou.id === preferredOuId) ? preferredOuId : organizationUnits[0]?.id ?? '';
      selectedPeriodId = requestedPeriodId(params);
      selectedMetricCode = params.get('metric')?.trim() ?? '';
      focusTrendAfterLoad = params.get('focus') === 'trend';
      await tick();
      if (selectedOuId && selectedPeriodId) await loadReport();
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : 'ไม่สามารถโหลดตัวกรองรายงานได้';
    } finally { loading = false; }
  }

  async function loadReport(): Promise<void> {
    const period = periodOptions.find((item) => item.id === selectedPeriodId) ?? periodOptions[0];
    if (!selectedOuId || !period) return;
    const version = ++requestVersion;
    loading = true;
    errorMessage = '';
    try {
      const client = getSupabaseBrowserClient();
      const [tableResult, completenessResult] = await Promise.all([
        getReportTable(client, selectedOuId, period.fromDate, period.toDate),
        getSubmissionCompleteness(client, selectedOuId, period.fromDate, period.toDate)
      ]);
      if (version !== requestVersion) return;
      const nextMetricCode = tableResult.metrics.some((metric) => metric.metricCode === selectedMetricCode)
        ? selectedMetricCode
        : tableResult.metrics[0]?.metricCode ?? '';
      selectedMetricCode = '';
      report = tableResult;
      completeness = completenessResult;
      await tick();
      selectedMetricCode = nextMetricCode;
      await tick();
      trend = selectedMetricCode ? await getReportTrend(client, selectedOuId, selectedMetricCode, period.fromDate, period.toDate) : null;
      generatedAt = new Date().toISOString();
    } catch (error) {
      if (version !== requestVersion) return;
      report = null; trend = null; completeness = null;
      errorMessage = error instanceof Error ? error.message : 'ไม่สามารถสร้างรายงานได้';
    } finally { if (version === requestVersion) loading = false; }
    if (version === requestVersion && focusTrendAfterLoad && report) {
      focusTrendAfterLoad = false;
      await tick();
      document.getElementById('report-trend')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    }
  }

  async function changeReportType(next: ReportType): Promise<void> {
    reportType = next;
    await tick();
    selectedPeriodId = periodOptions[0]?.id ?? '';
    await loadReport();
  }
  async function changeMetric(): Promise<void> {
    if (!selectedPeriod || !selectedMetricCode) return;
    loading = true;
    try { trend = await getReportTrend(getSupabaseBrowserClient(), selectedOuId, selectedMetricCode, selectedPeriod.fromDate, selectedPeriod.toDate); }
    catch (error) { errorMessage = error instanceof Error ? error.message : 'ไม่สามารถโหลดแนวโน้มได้'; }
    finally { loading = false; }
  }
  function exportRows(): ExportRow[] {
    return visibleRows.map((row) => {
      const item = completenessByOu.get(row.ouId);
      const status = !item?.submitted ? 'missing' : item.approved === item.expected ? 'approved' : 'partial';
      return {
        ouCode: row.ouCode,
        ouName: row.ouName,
        values: Object.fromEntries((report?.metrics ?? []).map((metric) => [metric.metricCode, row.values[metric.metricCode] ?? null])),
        status,
        expected: item?.expected ?? 0,
        submitted: item?.submitted ?? 0,
        approved: item?.approved ?? 0,
        pending: item?.pending ?? 0,
        draft: item?.draft ?? 0,
        returned: item?.returned ?? 0,
        rejected: item?.rejected ?? 0,
        missing: item?.missing ?? 0
      };
    });
  }
  function exportMetadata(): ExportMetadata {
    return {
      churchName: report?.church.name ?? '',
      ouName: report?.ou.name ?? '',
      ouCode: report?.ou.code ?? 'OU',
      reportType,
      periodLabel: selectedPeriod?.label ?? '',
      metrics: (report?.metrics ?? []).map(({ metricCode, metricName, unit }) => ({ metricCode, metricName, unit })),
      selectedMetricCode,
      metricName: selectedMetric?.metricName ?? '',
      unit: selectedMetric?.unit ?? '',
      generatedAt: thaiDateTime.format(new Date())
    };
  }
  async function handleExport(format: 'CSV' | 'Excel' | 'PDF'): Promise<void> {
    if (!report || !selectedMetric) return;
    exporting = true;
    actionMessage = '';
    try {
      const metadata = exportMetadata(); const rows = exportRows();
      if (format === 'CSV') exportCsv(metadata, rows);
      else if (format === 'Excel') await exportExcel(metadata, rows);
      else await exportPdf(metadata, rows);
      actionMessage = `ส่งออก ${format} สำเร็จ · ${rows.length} หน่วยงาน · ${metadata.metrics.length} Metrics · ${metadata.generatedAt}`;
    } catch (error) { actionMessage = `ส่งออกไม่สำเร็จ: ${error instanceof Error ? error.message : 'EXPORT_FAILED'}`; }
    finally { exporting = false; }
  }
  onMount(() => {
    void initializeTenantContext()
      .then(() => { mounted = true; })
      .catch((error) => {
        loading = false;
        errorMessage = error instanceof Error ? error.message : 'ไม่สามารถโหลด Tenant context ได้';
      });
  });
</script>

<svelte:head><title>Reports | CSMS</title></svelte:head>

<div class="app-page space-y-5">
  <section class="app-card relative overflow-hidden p-4 sm:p-6" aria-labelledby="reports-title">
    <div class="pointer-events-none absolute -right-16 -top-20 h-64 w-64 rounded-full bg-sky-200/40 blur-3xl"></div>
    <div class="relative flex flex-col gap-5 xl:flex-row xl:items-start xl:justify-between">
      <div><span class="inline-flex items-center gap-2 rounded-full border border-sky-200 bg-sky-50 px-3 py-1 text-xs font-semibold text-sky-800"><BarChart3 size={14} /> REPORTS</span><h1 id="reports-title" class="mt-3 text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">รายงานสถิติคริสตจักร</h1><p class="mt-2 text-sm leading-6 text-slate-600">เปรียบเทียบหน่วยงาน ติดตามแนวโน้ม และตรวจสอบความครบถ้วนจากข้อมูลที่อนุมัติแล้ว</p></div>
      <div class="flex flex-wrap gap-2">
        <button class="app-button-secondary app-focus inline-flex items-center gap-2" disabled={!report || exporting} on:click={() => handleExport('CSV')}><Download size={17} /> CSV</button>
        <button class="app-button-secondary app-focus inline-flex items-center gap-2" disabled={!report || exporting} on:click={() => handleExport('PDF')}><FileText size={17} /> PDF</button>
        <button class="app-button-primary app-focus inline-flex items-center gap-2" disabled={!report || exporting} on:click={() => handleExport('Excel')}><FileSpreadsheet size={17} /> Excel</button>
      </div>
    </div>
    <div class="relative mt-6 flex gap-1 rounded-2xl border border-slate-200 bg-slate-50 p-1.5" aria-label="ประเภทรายงาน">
      <button class={`app-focus flex-1 rounded-xl px-4 py-2.5 text-sm font-semibold ${reportType === 'weekly' ? 'bg-white text-sky-800 shadow-sm' : 'text-slate-500'}`} aria-pressed={reportType === 'weekly'} on:click={() => changeReportType('weekly')}>รายสัปดาห์</button>
      <button class={`app-focus flex-1 rounded-xl px-4 py-2.5 text-sm font-semibold ${reportType === 'monthly' ? 'bg-white text-sky-800 shadow-sm' : 'text-slate-500'}`} aria-pressed={reportType === 'monthly'} on:click={() => changeReportType('monthly')}>รายเดือน</button>
      <button class={`app-focus flex-1 rounded-xl px-4 py-2.5 text-sm font-semibold ${reportType === 'yearly' ? 'bg-white text-sky-800 shadow-sm' : 'text-slate-500'}`} aria-pressed={reportType === 'yearly'} on:click={() => changeReportType('yearly')}>รายปี</button>
    </div>
  </section>

  <section class="app-card p-4 sm:p-5" aria-labelledby="filter-title">
    <h2 id="filter-title" class="app-section-title">ตัวกรองรายงาน</h2>
    <div class="mt-4 grid gap-4 md:grid-cols-3">
      <label><span class="text-sm font-medium text-slate-700">หน่วยงาน</span><select class="app-input mt-1" bind:value={selectedOuId} on:change={loadReport}>{#each organizationUnits as ou}<option value={ou.id}>{ou.label}</option>{/each}</select></label>
      <label><span class="text-sm font-medium text-slate-700">{reportType === 'weekly' ? 'สัปดาห์' : reportType === 'monthly' ? 'เดือน' : 'ปี'}</span><select class="app-input mt-1" bind:value={selectedPeriodId} on:change={loadReport}>{#each periodOptions as period}<option value={period.id}>{period.label}</option>{/each}</select></label>
      <label><span class="text-sm font-medium text-slate-700">Metric</span><select class="app-input mt-1" bind:value={selectedMetricCode} on:change={changeMetric}>{#each report?.metrics ?? [] as metric}<option value={metric.metricCode}>{metric.metricName} ({metric.unit})</option>{/each}</select></label>
    </div>
    {#if report && selectedPeriod}<div class="mt-4 flex flex-wrap justify-between gap-2 border-t border-slate-100 pt-4 text-xs text-slate-500"><span>{report.church.name} · {report.ou.name} · {selectedPeriod.label}{selectedPeriod.submissionDueAt ? ` · กำหนดส่ง ${thaiDateTime.format(new Date(selectedPeriod.submissionDueAt))}` : ''}</span><span class="inline-flex items-center gap-1.5 font-semibold text-emerald-700"><CheckCircle2 size={14} /> เฉพาะ submission ที่อนุมัติแล้ว · สร้าง {formatGeneratedAt()}</span></div>{/if}
  </section>

  {#if errorMessage}<section class="rounded-xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700" role="alert"><AlertTriangle class="mr-2 inline" size={17} />{errorMessage} <button class="ml-2 underline" on:click={loadContext}>ลองอีกครั้ง</button></section>{/if}
  {#if loading}<section class="app-card px-5 py-14 text-center text-sm text-slate-600" aria-busy="true">กำลังคำนวณรายงาน...</section>
  {:else if report}
    <section class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4" aria-label="สรุปรายงาน">
      <article class="app-card p-5"><p class="text-sm text-slate-600">{selectedMetric?.metricName}</p><p class="mt-2 text-3xl font-semibold"><MetricValue value={report.totals[selectedMetricCode]} error={report.totalErrors?.[selectedMetricCode]} /> <small class="text-sm font-normal text-slate-500">{selectedMetric?.unit}</small></p><p class="mt-2 text-xs text-slate-500">ยอดรวม approved</p></article>
      <article class="app-card p-5"><p class="text-sm text-slate-600">ความครบถ้วน</p><p class="mt-2 text-3xl font-semibold">{completionPercent}%</p><p class="mt-2 text-xs text-slate-500">ส่งแล้ว {completeness?.summary.submitted ?? 0} / {completeness?.summary.expected ?? 0} รายการ</p></article>
      <article class="app-card p-5"><p class="text-sm text-slate-600">อนุมัติแล้ว</p><p class="mt-2 text-3xl font-semibold text-emerald-700">{completeness?.summary.approved ?? 0}</p><p class="mt-2 text-xs text-slate-500">รายการที่รวมในรายงาน</p></article>
      <article class="app-card p-5"><p class="text-sm text-slate-600">ยังไม่ส่ง</p><p class="mt-2 text-3xl font-semibold text-amber-700">{completeness?.summary.missing ?? 0}</p><p class="mt-2 text-xs text-slate-500">รอติดตามจากหน่วยงาน</p></article>
    </section>

    <section class="grid gap-5 xl:grid-cols-[minmax(0,1.5fr)_minmax(18rem,0.5fr)]">
      <article id="report-trend" class="app-card scroll-mt-20 p-4 sm:p-5" aria-labelledby="trend-title"><div class="flex items-start justify-between gap-3"><div><h2 id="trend-title" class="app-section-title">แนวโน้ม {trend?.metricName}</h2><p class="app-section-copy">ข้อมูลจริงตามช่วงเวลาที่เลือก</p></div><TrendingUp class="text-sky-700" size={20} /></div>
        {#if trend?.points.length}<div class="mt-5 flex h-56 items-end gap-2 rounded-2xl border border-slate-100 bg-sky-50/50 px-3 pb-4 pt-7 sm:gap-4">{#each trend.points as point}<div class="group flex h-full min-w-0 flex-1 flex-col items-center justify-end gap-2"><span class="text-xs font-semibold text-slate-600"><MetricValue value={point.value} error={point.error} /></span>{#if point.value !== null}<div class="w-full max-w-14 rounded-t-xl bg-gradient-to-t from-sky-700 to-cyan-300" style={`height: ${Math.max(8, ((point.value ?? 0) / chartMax) * 145)}px`}></div>{/if}<span class="text-[0.65rem] text-slate-500">{formatDate(point.periodEnd)}</span></div>{/each}</div>{:else}<p class="py-16 text-center text-sm text-slate-500">ไม่มีข้อมูล trend ในช่วงนี้</p>{/if}
      </article>
      <aside class="app-card p-4 sm:p-5"><h2 class="app-section-title">Submission completeness</h2><div class="mt-5 h-3 overflow-hidden rounded-full bg-slate-100"><div class="h-full rounded-full bg-gradient-to-r from-sky-500 to-emerald-500" style={`width: ${completionPercent}%`}></div></div><div class="mt-5 space-y-3 text-sm"><div class="flex justify-between rounded-xl bg-emerald-50 p-3"><span>อนุมัติแล้ว</span><strong>{completeness?.summary.approved ?? 0}</strong></div><div class="flex justify-between rounded-xl bg-sky-50 p-3"><span>รอตรวจ / แบบร่าง / ส่งกลับ</span><strong>{(completeness?.summary.pending ?? 0) + (completeness?.summary.draft ?? 0) + (completeness?.summary.returned ?? 0)}</strong></div><div class="flex justify-between rounded-xl bg-amber-50 p-3"><span>ยังไม่ส่ง</span><strong>{completeness?.summary.missing ?? 0}</strong></div></div></aside>
    </section>

    <section class="app-card overflow-hidden" aria-labelledby="detail-title">
      <div class="flex flex-col gap-4 border-b border-slate-100 p-4 sm:p-5 lg:flex-row lg:items-center lg:justify-between"><div class="flex items-start gap-3"><span class="rounded-2xl bg-sky-50 p-2.5 text-sky-700"><Table2 size={20} /></span><div><h2 id="detail-title" class="app-section-title">เปรียบเทียบหน่วยงาน</h2><p class="app-section-copy">{visibleRows.length} หน่วยงาน · {selectedMetric?.metricName}</p></div></div><div class="flex flex-col gap-2 sm:flex-row"><select class="app-input sm:w-44" bind:value={statusFilter}><option value="all">ทุกสถานะ</option><option value="approved">ครบและอนุมัติแล้ว</option><option value="partial">ส่งบางส่วน</option><option value="missing">ยังไม่ส่ง</option></select><label class="relative"><Search class="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" size={17} /><input class="app-input pl-10" type="search" placeholder="ค้นหาหน่วยงาน" bind:value={searchQuery} /></label></div></div>
      <div class="overflow-x-auto"><table class="w-full min-w-[760px] text-left"><thead><tr class="border-b bg-slate-50"><th class="px-5 py-3 text-xs text-slate-500">หน่วยงาน</th><th class="px-4 py-3 text-right text-xs text-slate-500">{selectedMetric?.metricName}</th><th class="px-4 py-3 text-right text-xs text-slate-500">คาดหวัง</th><th class="px-4 py-3 text-right text-xs text-slate-500">ส่งแล้ว</th><th class="px-4 py-3 text-right text-xs text-slate-500">อนุมัติ</th><th class="px-5 py-3 text-right text-xs text-slate-500">ขาด</th></tr></thead><tbody>
        {#each visibleRows as row}{@const item = completenessByOu.get(row.ouId)}<tr class="border-b border-slate-100"><td class="px-5 py-4"><p class="text-sm font-semibold text-slate-900">{row.ouName}</p></td><td class="px-4 py-4 text-right font-semibold tabular-nums"><MetricValue value={row.values[selectedMetricCode]} error={row.errors?.[selectedMetricCode]} /></td><td class="px-4 py-4 text-right">{item?.expected ?? 0}</td><td class="px-4 py-4 text-right">{item?.submitted ?? 0}</td><td class="px-4 py-4 text-right text-emerald-700">{item?.approved ?? 0}</td><td class="px-5 py-4 text-right text-amber-700">{item?.missing ?? 0}</td></tr>{:else}<tr><td colspan="6" class="px-5 py-14 text-center text-sm text-slate-500">ไม่พบหน่วยงานที่ตรงกับตัวกรอง</td></tr>{/each}</tbody>
        {#if visibleRows.length}<tfoot><tr class="bg-slate-900 text-white"><td class="px-5 py-4 font-semibold">รวมที่แสดง</td><td class="px-4 py-4 text-right font-semibold"><MetricValue value={visibleTotal.value} error={visibleTotal.error} /></td><td class="px-4 py-4 text-right">{visibleRows.reduce((sum, row) => sum + (completenessByOu.get(row.ouId)?.expected ?? 0), 0)}</td><td class="px-4 py-4 text-right">{visibleRows.reduce((sum, row) => sum + (completenessByOu.get(row.ouId)?.submitted ?? 0), 0)}</td><td class="px-4 py-4 text-right">{visibleRows.reduce((sum, row) => sum + (completenessByOu.get(row.ouId)?.approved ?? 0), 0)}</td><td class="px-5 py-4 text-right">{visibleRows.reduce((sum, row) => sum + (completenessByOu.get(row.ouId)?.missing ?? 0), 0)}</td></tr></tfoot>{/if}
      </table></div>
      <div class="flex flex-col gap-2 bg-slate-50 px-5 py-4 text-xs text-slate-500 sm:flex-row sm:justify-between"><span>CSV/Excel ส่งออก {visibleRows.length} แถว · ครบทั้ง {report.metrics.length} Metric และทุกสถานะ Submission</span><span>{selectedPeriod?.label} · สร้าง {formatGeneratedAt()}</span></div>
    </section>
  {:else if !errorMessage}<section class="app-card px-5 py-14 text-center text-sm text-slate-500">ยังไม่มีข้อมูลสำหรับสร้างรายงาน</section>{/if}

  {#if actionMessage}<div class="fixed bottom-20 right-4 z-40 max-w-sm rounded-2xl border border-sky-200 bg-white px-4 py-3 shadow-xl md:bottom-5" role="status"><p class="text-sm font-semibold text-slate-900">การส่งออก</p><p class="mt-1 text-xs text-slate-600">{actionMessage}</p></div>{/if}
</div>
