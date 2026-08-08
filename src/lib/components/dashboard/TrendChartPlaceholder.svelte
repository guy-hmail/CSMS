<script lang="ts">
  import type { KpiSummary, TrendPoint } from '$lib/types/dashboard';

  export let title = 'แนวโน้มรายสัปดาห์';
  export let metricName = 'ผู้เข้าร่วมการนมัสการ';
  export let points: TrendPoint[];
  export let metrics: KpiSummary[] = [];
  export let selectedMetricCode = '';
  export let onMetricChange: (metricCode: string) => void = () => {};
  export let loading = false;

  $: maxValue = Math.max(...points.map((point) => point.value), 1);

  function changeMetric(event: Event): void {
    onMetricChange((event.currentTarget as HTMLSelectElement).value);
  }
</script>

<section class="app-card p-4 sm:p-5" aria-labelledby="trend-chart-title" aria-busy={loading}>
  <div class="flex flex-col gap-1 sm:flex-row sm:items-start sm:justify-between">
    <div>
      <h2 id="trend-chart-title" class="app-section-title">{title}</h2>
      <p class="app-section-copy">{metricName} · {points.length} สัปดาห์ล่าสุด{loading ? ' · กำลังโหลด...' : ''}</p>
    </div>
    <label class="w-full sm:w-56">
      <span class="sr-only">เลือก Metric สำหรับกราฟแนวโน้ม</span>
      <select class="app-input min-h-9 py-1.5 text-sm" value={selectedMetricCode} disabled={loading} on:change={changeMetric} aria-label="เลือก Metric สำหรับกราฟแนวโน้ม">
        {#each metrics as metric}
          <option value={metric.metricCode}>{metric.metricName}</option>
        {/each}
      </select>
    </label>
  </div>

  <div class={`mt-5 h-64 rounded-md border border-slate-200 bg-slate-50 p-4 transition-opacity sm:h-72 ${loading ? 'opacity-60' : ''}`}>
    <div class="flex h-full items-end gap-2 sm:gap-3" aria-label={`แนวโน้ม ${metricName}`}>
      {#each points as point}
        <div class="flex h-full min-w-0 flex-1 flex-col justify-end gap-2">
          <div class="flex min-h-0 flex-1 flex-col justify-end">
            <span class="mb-1 text-center text-xs font-semibold tabular-nums text-slate-700">{point.value.toLocaleString()}</span>
            <div
              class="min-h-1 rounded-t-md bg-gradient-to-t from-sky-700 to-cyan-400 shadow-sm transition hover:from-sky-800 hover:to-cyan-500"
              style={`height: ${Math.max(2, (point.value / maxValue) * 82)}%`}
              title={`${point.label}: ${point.value.toLocaleString()}`}
            ></div>
          </div>
          <span class="truncate text-center text-[0.68rem] text-slate-500">{point.label}</span>
        </div>
      {:else}
        <p class="m-auto text-sm text-slate-400">ยังไม่มีข้อมูลแนวโน้ม</p>
      {/each}
    </div>
  </div>
</section>
