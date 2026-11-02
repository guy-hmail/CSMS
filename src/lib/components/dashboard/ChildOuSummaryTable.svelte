<script lang="ts">
  import MetricValue from '$lib/components/common/MetricValue.svelte';
  import StatusBadge from '$lib/components/common/StatusBadge.svelte';
  import type { ChildOuSummaryRow, StatusTone } from '$lib/types/dashboard';

  export let rows: ChildOuSummaryRow[];
  export let onSelectOu: (ouId: string) => void = () => {};
  $: metricColumns = rows[0]?.metrics ?? [];

  const statusMeta: Record<ChildOuSummaryRow['status'], { label: string; tone: StatusTone }> = {
    approved: { label: 'Approved', tone: 'success' },
    missing: { label: 'Missing', tone: 'warning' },
    submitted: { label: 'Submitted', tone: 'info' },
    draft: { label: 'Draft', tone: 'neutral' }
    ,returned: { label: 'Returned', tone: 'info' }
    ,rejected: { label: 'Rejected', tone: 'error' }
    ,mixed: { label: 'Mixed', tone: 'warning' }
  };
</script>

<section class="app-card overflow-hidden" aria-labelledby="child-ou-summary-title">
  <div class="border-b border-slate-200 p-4 sm:p-5">
    <h2 id="child-ou-summary-title" class="app-section-title">สรุปหน่วยงานย่อย</h2>
    <p class="app-section-copy">หน่วยงานย่อยที่อยู่ภายใต้หน่วยงานหลักพร้อมค่าตัวชี้วัด</p>
  </div>

  <div class="hidden overflow-x-auto md:block">
    <table class="w-full min-w-[42rem] text-left text-sm">
      <thead class="bg-slate-50/80 text-xs font-semibold uppercase tracking-[0.2em] text-slate-500">
        <tr>
          <th class="px-4 py-3">หน่วยงาน</th>
          {#each metricColumns as metric}<th class="px-4 py-3 text-right">{metric.metricName}</th>{/each}
          <th class="px-4 py-3">สถานะ</th>
          <th class="px-4 py-3 text-right">ดำเนินการ</th>
        </tr>
      </thead>
      <tbody class="divide-y divide-slate-100">
        {#each rows as row}
          <tr class="bg-white transition hover:bg-slate-50/80">
            <td class="px-4 py-4 font-medium text-slate-950">{row.ouName}</td>
            {#each metricColumns as column}
              {@const metric = row.metrics.find((item) => item.metricCode === column.metricCode)}
              <td class="px-4 py-4 text-right text-slate-700"><MetricValue value={metric?.value} error={metric?.error} /></td>
            {/each}
            <td class="px-4 py-4">
              <StatusBadge label={statusMeta[row.status].label} tone={statusMeta[row.status].tone} />
            </td>
            <td class="px-4 py-4 text-right">
              <button type="button" class="app-button-secondary min-h-0 px-3 py-1.5" on:click={() => onSelectOu(row.ouId)}>ดู Dashboard</button>
            </td>
          </tr>
        {:else}
          <tr><td class="px-4 py-10 text-center text-sm text-slate-400" colspan={metricColumns.length + 3}>ไม่มีหน่วยงานย่อย</td></tr>
        {/each}
      </tbody>
    </table>
  </div>

  <div class="divide-y divide-slate-100 md:hidden">
    {#each rows as row}
      <article class="space-y-3 p-4">
        <div class="flex items-start justify-between gap-3">
          <h3 class="font-medium text-slate-950">{row.ouName}</h3>
          <StatusBadge label={statusMeta[row.status].label} tone={statusMeta[row.status].tone} />
        </div>
        {#each row.metrics as metric}<div class="flex items-center justify-between gap-4 text-sm"><span class="text-slate-500">{metric.metricName}</span><span class="shrink-0 text-right font-medium tabular-nums text-slate-900"><MetricValue value={metric.value} error={metric.error} /></span></div>{/each}
        <div class="flex justify-end">
          <button type="button" class="app-button-secondary min-h-0 px-3 py-1.5" on:click={() => onSelectOu(row.ouId)}>ดู Dashboard</button>
        </div>
      </article>
    {/each}
  </div>
</section>
