<script lang="ts">
  import type { TrendPoint } from '$lib/types/dashboard';

  export let title = 'แนวโน้มรายสัปดาห์';
  export let metricName = 'ผู้เข้าร่วมการนมัสการ';
  export let points: TrendPoint[];

  $: maxValue = Math.max(...points.map((point) => point.value), 1);
</script>

<section class="app-card p-4 sm:p-5" aria-labelledby="trend-chart-title">
  <div class="flex flex-col gap-1 sm:flex-row sm:items-start sm:justify-between">
    <div>
      <h2 id="trend-chart-title" class="app-section-title">{title}</h2>
      <p class="app-section-copy">{metricName} · {points.length} สัปดาห์ล่าสุด</p>
    </div>
      <span class="rounded-md border border-slate-200 bg-slate-50 px-2 py-1 text-xs font-medium text-slate-600">Tenant ปัจจุบัน</span>
  </div>

  <div class="mt-5 h-64 rounded-md border border-slate-200 bg-slate-50 p-4 sm:h-72">
    <div class="flex h-full items-end gap-2 sm:gap-3" aria-label={`แนวโน้ม ${metricName}`}>
      {#each points as point}
        <div class="flex h-full min-w-0 flex-1 flex-col justify-end gap-2">
          <div
            class="min-h-2 rounded-t-md bg-gradient-to-t from-sky-700 to-cyan-400 shadow-sm transition hover:from-sky-800 hover:to-cyan-500"
            style={`height: ${(point.value / maxValue) * 100}%`}
            title={`${point.label}: ${point.value.toLocaleString()}`}
          ></div>
          <span class="truncate text-center text-[0.68rem] text-slate-500">{point.label}</span>
        </div>
      {:else}
        <p class="m-auto text-sm text-slate-400">ยังไม่มีข้อมูลแนวโน้ม</p>
      {/each}
    </div>
  </div>
</section>
