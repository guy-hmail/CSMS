<script lang="ts">
  import MetricValue from '$lib/components/common/MetricValue.svelte';
  import { ArrowDown, ArrowRight, ArrowUp, Minus } from '@lucide/svelte';
  import type { KpiSummary } from '$lib/types/dashboard';

  export let item: KpiSummary;
  export let selected = false;
  export let onSelect: () => void = () => {};
  export let reportHref = '/app/reports';

  $: growthLabel = item.growthPercent === null ? 'N/A vs previous week' : `${item.growthPercent > 0 ? '+' : ''}${item.growthPercent.toFixed(1)}% vs previous week`;
  $: trendTone = item.growthPercent === null ? 'text-slate-500' : item.growthPercent > 0 ? 'text-emerald-700' : item.growthPercent < 0 ? 'text-rose-700' : 'text-slate-600';
</script>

<article class={`app-card group relative w-full overflow-hidden p-3 text-left transition duration-200 hover:-translate-y-0.5 hover:border-sky-200 hover:shadow-[0_12px_28px_rgba(14,116,144,0.12)] sm:p-4 ${selected ? 'ring-2 ring-sky-500 ring-offset-2' : ''}`}>
  <div class="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-sky-500 via-cyan-400 to-emerald-400"></div>
  <div class="flex items-start justify-between gap-3">
    <button type="button" class="min-w-0 flex-1 text-left" aria-pressed={selected} on:click={onSelect}>
      <div class="flex items-center gap-2"><p class="truncate text-sm font-medium text-slate-600">{item.metricName}</p>{#if item.metricKind === 'calculated'}<span class="shrink-0 rounded-full bg-violet-50 px-2 py-0.5 text-[0.62rem] font-semibold text-violet-700">Calculated</span>{/if}</div>
      <p class="mt-2 flex items-baseline gap-1.5 text-2xl font-semibold tracking-tight text-slate-950 sm:text-[1.75rem]">
        <span><MetricValue value={item.value} error={item.error} unit={item.unit} /></span><span class="text-xs font-medium text-slate-500">{item.unit}</span>
      </p>
      <p class={`mt-2 flex items-center gap-1 text-xs font-medium ${trendTone}`}>
        {#if item.growthPercent === null || item.growthPercent === 0}
          <Minus size={13} />
        {:else if item.growthPercent > 0}
          <ArrowUp size={13} />
        {:else}
          <ArrowDown size={13} />
        {/if}
        {growthLabel}
      </p>
    </button>

    <a href={reportHref} class="app-focus mt-1 rounded-xl border border-sky-200 bg-sky-50 p-2 text-sky-700 transition hover:scale-105 hover:bg-sky-100" aria-label={`ดูกราฟรายเดือน ${item.metricName} ในรายงาน`} title="ดูกราฟรายเดือนใน Reports">
      <ArrowRight size={18} />
    </a>
  </div>
</article>
