<script lang="ts">
  import type { SubmissionSelectorOption } from '$lib/types/submission';
  export let periods: SubmissionSelectorOption[];
  export let organizationUnits: SubmissionSelectorOption[];
  export let selectedPeriodId: string;
  export let selectedOuId: string;
  export let disabled = false;
  $: selectedPeriod = periods.find((period) => period.id === selectedPeriodId);
</script>

<section class="app-card p-4 sm:p-5" aria-label="Submission context">
  <div class="grid min-w-0 gap-4 md:grid-cols-2 md:items-start xl:grid-cols-[minmax(0,1fr)_17rem_14rem]">
    <div class="min-w-0 md:col-span-2 xl:col-span-1">
      <span class="inline-flex rounded-md border border-sky-200 bg-sky-50 px-2 py-1 text-xs font-semibold uppercase tracking-wide text-sky-800">ข้อมูลรายสัปดาห์</span>
      <h1 class="mt-3 text-2xl font-semibold text-slate-950 sm:text-3xl">กรอกสถิติประจำสัปดาห์</h1>
      <p class="mt-1 text-sm text-slate-600">เลือกสัปดาห์และหน่วยงานที่คุณมีสิทธิ์บันทึกข้อมูล</p>
    </div>
    <label class="block min-w-0">
      <span class="text-sm font-medium text-slate-700">สัปดาห์สิ้นสุดวันอาทิตย์</span>
      <select class="app-input mt-1 min-w-0 max-w-full" bind:value={selectedPeriodId} {disabled}>
        {#each periods as period}<option value={period.id}>{period.label}</option>{/each}
      </select>
      {#if selectedPeriod?.helperText}<span class="mt-1.5 block text-xs text-slate-500">{selectedPeriod.helperText}</span>{/if}
    </label>
    <label class="block min-w-0">
      <span class="text-sm font-medium text-slate-700">หน่วยงาน</span>
      <select class="app-input mt-1 min-w-0 max-w-full" bind:value={selectedOuId} {disabled}>
        {#each organizationUnits as ou}<option value={ou.id}>{ou.label}</option>{/each}
      </select>
    </label>
  </div>
</section>
