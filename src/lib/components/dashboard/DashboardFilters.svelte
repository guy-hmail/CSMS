<script lang="ts">
  import type { DashboardOption } from '$lib/types/dashboard';

  export let organizationUnits: DashboardOption[];
  export let periods: DashboardOption[];
  export let selectedOuId: string;
  export let selectedPeriodId: string;
  export let onFiltersChange: () => void = () => {};

  $: selectedPeriod = periods.find((period) => period.id === selectedPeriodId);
</script>
<section class="app-card p-4 sm:p-5" aria-label="Dashboard filters">
  <div class="grid min-w-0 gap-4 md:grid-cols-2 md:items-start xl:grid-cols-[minmax(0,1fr)_17rem_14rem]">
    <div class="min-w-0 md:col-span-2 xl:col-span-1">
      <span class="inline-flex rounded-md border border-sky-200 bg-sky-50 px-2 py-1 text-xs font-semibold uppercase tracking-wide text-sky-800">ภาพรวมสด</span>
      <h1 class="mt-3 text-2xl font-semibold text-slate-950 sm:text-3xl">แดชบอร์ด</h1>
      <p class="mt-1 text-sm text-slate-600">ติดตามผู้เข้าร่วม งานส่งข้อมูล และความคืบหน้าของหน่วยงานย่อยในมุมมองเดียว</p>
    </div>

    <label class="block min-w-0">
      <span class="text-sm font-medium text-slate-700">วันที่รายงาน (วันอาทิตย์)</span>
      <select class="app-input mt-1 min-w-0 max-w-full" bind:value={selectedPeriodId} on:change={onFiltersChange}>
        {#each periods as period}
          <option value={period.id}>{period.label}</option>
        {/each}
      </select>
      {#if selectedPeriod?.helperText}
        <span class="mt-1.5 block text-xs text-slate-500">{selectedPeriod.helperText}</span>
      {/if}
    </label>

    <label class="block min-w-0">
      <span class="text-sm font-medium text-slate-700">หน่วยงาน</span>
      <select class="app-input mt-1 min-w-0 max-w-full" bind:value={selectedOuId} on:change={onFiltersChange}>
        {#each organizationUnits as ou}
          <option value={ou.id}>{ou.label}</option>
        {/each}
      </select>
    </label>
  </div>
</section>
