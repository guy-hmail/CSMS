<script lang="ts">
  import KpiSummaryCard from '$lib/components/dashboard/KpiSummaryCard.svelte';
  import type { KpiSummary } from '$lib/types/dashboard';

  export let items: KpiSummary[];
  export let selectedMetricCode = '';
  export let onSelectMetric: (metricCode: string) => void = () => {};
</script>

<section aria-labelledby="kpi-summary-title" class="space-y-3">
  <div>
    <h2 id="kpi-summary-title" class="app-section-title">สรุปช่วงปัจจุบัน</h2>
    <p class="app-section-copy">ข้อมูลเมตริกของ Tenant และรอบรายงานที่เลือก</p>
  </div>

  <div class="grid gap-3 sm:grid-cols-2 lg:gap-4 xl:grid-cols-4">
    {#each items as item}
      <KpiSummaryCard {item} selected={item.metricCode === selectedMetricCode} onSelect={() => onSelectMetric(item.metricCode)} />
    {/each}
  </div>
</section>
