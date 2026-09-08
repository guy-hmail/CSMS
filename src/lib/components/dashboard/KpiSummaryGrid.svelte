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
    {#if calculatedItems.length}
      <section aria-labelledby="calculated-metrics-title" class="metric-section metric-section--calculated rounded-2xl border border-violet-100 bg-violet-50/40 p-3 sm:p-4">
        <div class="mb-3 flex items-start gap-3">
          <span class="metric-section__icon flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-violet-100 text-violet-700"><Calculator size={18} /></span>
          <div>
            <h3 id="calculated-metrics-title" class="metric-section__title text-sm font-semibold text-slate-950">Calculated Data</h3>
            <p class="metric-section__copy mt-0.5 text-xs text-slate-500">ข้อมูลที่ระบบคำนวณจาก Raw Data</p>
          </div>
        </div>
        <div class="grid gap-3 sm:grid-cols-2 lg:gap-4 xl:grid-cols-4">
          {#each calculatedItems as item}
            <KpiSummaryCard {item} selected={item.metricCode === selectedMetricCode} onSelect={() => onSelectMetric(item.metricCode)} reportHref={reportHrefForMetric(item.metricCode)} />
          {/each}
        </div>
      </section>
    {/if}

    {#if rawItems.length}
      <section aria-labelledby="raw-metrics-title" class="metric-section metric-section--raw rounded-2xl border border-sky-100 bg-sky-50/40 p-3 sm:p-4">
        <div class="mb-3 flex items-start gap-3">
          <span class="metric-section__icon flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-sky-100 text-sky-700"><Database size={18} /></span>
          <div>
            <h3 id="raw-metrics-title" class="metric-section__title text-sm font-semibold text-slate-950">Raw Data</h3>
            <p class="metric-section__copy mt-0.5 text-xs text-slate-500">ข้อมูลต้นทางที่บันทึกจากแบบฟอร์ม</p>
          </div>
        </div>
        <div class="grid gap-3 sm:grid-cols-2 lg:gap-4 xl:grid-cols-4">
          {#each rawItems as item}
            <KpiSummaryCard {item} selected={item.metricCode === selectedMetricCode} onSelect={() => onSelectMetric(item.metricCode)} reportHref={reportHrefForMetric(item.metricCode)} />
          {/each}
        </div>
      </section>
    {/if}
  </div>
</section>

<style>
  :global(html[data-mode='dark']) .metric-section--calculated {
    border-color: rgb(139 92 246 / 0.58) !important;
    background: linear-gradient(135deg, rgb(46 16 101 / 0.88), rgb(30 27 75 / 0.92)) !important;
  }

  :global(html[data-mode='dark']) .metric-section--raw {
    border-color: rgb(14 165 233 / 0.58) !important;
    background: linear-gradient(135deg, rgb(7 47 73 / 0.9), rgb(8 51 68 / 0.92)) !important;
  }

  :global(html[data-mode='dark']) .metric-section__title {
    color: #f8fafc !important;
  }

  :global(html[data-mode='dark']) .metric-section--calculated .metric-section__copy {
    color: #ddd6fe !important;
  }

  :global(html[data-mode='dark']) .metric-section--raw .metric-section__copy {
    color: #bae6fd !important;
  }

  :global(html[data-mode='dark']) .metric-section--calculated .metric-section__icon {
    background-color: rgb(91 33 182 / 0.72) !important;
    color: #ddd6fe !important;
  }

  :global(html[data-mode='dark']) .metric-section--raw .metric-section__icon {
    background-color: rgb(3 105 161 / 0.68) !important;
    color: #bae6fd !important;
  }
</style>
