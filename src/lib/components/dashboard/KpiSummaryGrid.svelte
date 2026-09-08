<script lang="ts">
  import { Calculator, Database } from '@lucide/svelte';
  import KpiSummaryCard from '$lib/components/dashboard/KpiSummaryCard.svelte';
  import type { KpiSummary } from '$lib/types/dashboard';

  export let items: KpiSummary[];
  export let selectedMetricCode = '';
  export let onSelectMetric: (metricCode: string) => void = () => {};
  export let reportHrefForMetric: (metricCode: string) => string = () => '/app/reports';

  $: rawItems = items.filter((item) => item.metricKind === 'input');
  $: calculatedItems = items.filter((item) => item.metricKind === 'calculated');
</script>

<section aria-labelledby="kpi-summary-title" class="space-y-3">
  <div>
    <h2 id="kpi-summary-title" class="app-section-title">สรุปช่วงปัจจุบัน</h2>
    <p class="app-section-copy">ข้อมูลเมตริกของ Tenant และรอบรายงานที่เลือก</p>
  </div>

  <div class="space-y-5">
    {#if rawItems.length}
      <section aria-labelledby="raw-metrics-title" class="rounded-2xl border border-sky-100 bg-sky-50/40 p-3 sm:p-4">
        <div class="mb-3 flex items-start gap-3">
          <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-sky-100 text-sky-700"><Database size={18} /></span>
          <div>
            <h3 id="raw-metrics-title" class="text-sm font-semibold text-slate-950">Raw Data</h3>
            <p class="mt-0.5 text-xs text-slate-500">ข้อมูลต้นทางที่บันทึกจากแบบฟอร์ม</p>
          </div>
        </div>
        <div class="grid gap-3 sm:grid-cols-2 lg:gap-4 xl:grid-cols-4">
          {#each rawItems as item}
            <KpiSummaryCard {item} selected={item.metricCode === selectedMetricCode} onSelect={() => onSelectMetric(item.metricCode)} reportHref={reportHrefForMetric(item.metricCode)} />
          {/each}
        </div>
      </section>
    {/if}

    {#if calculatedItems.length}
      <section aria-labelledby="calculated-metrics-title" class="rounded-2xl border border-violet-100 bg-violet-50/40 p-3 sm:p-4">
        <div class="mb-3 flex items-start gap-3">
          <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-violet-100 text-violet-700"><Calculator size={18} /></span>
          <div>
            <h3 id="calculated-metrics-title" class="text-sm font-semibold text-slate-950">Calculated Data</h3>
            <p class="mt-0.5 text-xs text-slate-500">ข้อมูลที่ระบบคำนวณจาก Raw Data</p>
          </div>
        </div>
        <div class="grid gap-3 sm:grid-cols-2 lg:gap-4 xl:grid-cols-4">
          {#each calculatedItems as item}
            <KpiSummaryCard {item} selected={item.metricCode === selectedMetricCode} onSelect={() => onSelectMetric(item.metricCode)} reportHref={reportHrefForMetric(item.metricCode)} />
          {/each}
        </div>
      </section>
    {/if}
  </div>
</section>
