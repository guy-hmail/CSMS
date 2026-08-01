<script lang="ts">
  import { ArrowDownRight, ArrowRight, ArrowUpRight } from '@lucide/svelte';
  import type { KpiSummary } from '$lib/types/dashboard';

  export let item: KpiSummary;
  export let selected = false;
  export let onSelect: () => void = () => {};

  $: growthLabel = item.growthPercent === null ? 'N/A vs previous week' : `${item.growthPercent > 0 ? '+' : ''}${item.growthPercent.toFixed(1)}% vs previous week`;
  $: trendTone = item.growthPercent === null ? 'text-slate-500' : item.growthPercent > 0 ? 'text-emerald-700' : item.growthPercent < 0 ? 'text-rose-700' : 'text-slate-600';
  $: badgeTone = item.growthPercent === null ? 'border-slate-200 bg-slate-50' : item.growthPercent > 0 ? 'border-emerald-200 bg-emerald-50' : item.growthPercent < 0 ? 'border-rose-200 bg-rose-50' : 'border-slate-200 bg-slate-50';
</script>

<button type="button" class={`app-card group relative w-full overflow-hidden p-4 text-left transition duration-200 hover:-translate-y-1 hover:border-sky-200 hover:shadow-[0_16px_35px_rgba(14,116,144,0.13)] sm:p-5 ${selected ? 'ring-2 ring-sky-500 ring-offset-2' : ''}`} aria-pressed={selected} on:click={onSelect}>
  <div class="absolute inset-x-0 top-0 h-1 bg-gradient-to-r from-sky-500 via-cyan-400 to-emerald-400"></div>
  <div class="flex items-start justify-between gap-3">
    <div class="min-w-0">
      <p class="truncate text-sm font-medium text-slate-600">{item.metricName}</p>
      <p class="mt-3 text-3xl font-semibold tracking-tight text-slate-950 sm:text-[2rem]">{item.value.toLocaleString()}</p>
      <p class="mt-1 text-sm text-slate-500">{item.unit}</p>
    </div>

    <div class={`mt-1 rounded-2xl border p-2.5 ${badgeTone} ${trendTone}`} aria-hidden="true">
      {#if item.growthPercent === null}
        <ArrowRight size={20} />
      {:else if item.growthPercent > 0}
        <ArrowUpRight size={20} />
      {:else if item.growthPercent < 0}
        <ArrowDownRight size={20} />
      {:else}
        <ArrowRight size={20} />
      {/if}
    </div>
  </div>

  <div class="mt-4">
    <p class={`text-sm font-medium ${trendTone}`}>{growthLabel}</p>
  </div>
</button>
