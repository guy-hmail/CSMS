<script lang="ts">
  import type { SubmissionStatusSummary } from '$lib/types/dashboard';

  export let summary: SubmissionStatusSummary;

  $: completionPercent = summary.totalExpected > 0
    ? Math.round((summary.submitted / summary.totalExpected) * 100)
    : 0;
</script>

<section class="app-card min-w-0 max-w-full overflow-hidden p-4 sm:p-5" aria-labelledby="submission-status-title">
  <div class="flex items-start justify-between gap-4">
    <div class="min-w-0">
      <h2 id="submission-status-title" class="app-section-title">สถานะการส่งข้อมูล</h2>
      <p class="app-section-copy">หน่วยงานที่คาดว่าจะกรอกข้อมูลในช่วงเวลาที่เลือก</p>
    </div>
    <div class="shrink-0 rounded-2xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-center">
      <p class="text-2xl font-semibold text-emerald-800">{completionPercent}%</p>
      <p class="text-[0.7rem] font-semibold uppercase tracking-[0.2em] text-emerald-700">complete</p>
    </div>
  </div>

  <div class="mt-5 h-3 overflow-hidden rounded-full bg-slate-100" aria-label={`Submitted ${summary.submitted} of ${summary.totalExpected}`}>
    <div class="h-full rounded-full bg-gradient-to-r from-emerald-500 to-sky-500" style={`width: ${completionPercent}%`}></div>
  </div>

  <dl class="mt-5 grid grid-cols-2 gap-3 text-sm">
    <div class="rounded-2xl border border-slate-200 bg-white p-3">
      <dt class="text-slate-500">Submitted</dt>
      <dd class="mt-1 font-semibold text-slate-950">{summary.submitted} / {summary.totalExpected}</dd>
    </div>
    <div class="rounded-2xl border border-slate-200 bg-white p-3">
      <dt class="text-slate-500">Approved</dt>
      <dd class="mt-1 font-semibold text-emerald-700">{summary.approved}</dd>
    </div>
    <div class="rounded-2xl border border-slate-200 bg-white p-3">
      <dt class="text-slate-500">Missing</dt>
      <dd class="mt-1 font-semibold text-amber-700">{summary.missing}</dd>
    </div>
    <div class="rounded-2xl border border-slate-200 bg-white p-3">
      <dt class="text-slate-500">Pending</dt>
      <dd class="mt-1 font-semibold text-sky-700">{summary.pending}</dd>
    </div>
  </dl>
</section>
