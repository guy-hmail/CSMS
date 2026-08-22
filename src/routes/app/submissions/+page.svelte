<script lang="ts">
  import { onMount } from 'svelte';
  import DynamicMetricForm from '$lib/components/submissions/DynamicMetricForm.svelte';
  import SubmissionContextSelectors from '$lib/components/submissions/SubmissionContextSelectors.svelte';
  import ValidationMessageArea from '$lib/components/submissions/ValidationMessageArea.svelte';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';
  import { BackendError } from '$lib/api/rpc';
  import { getSubmissionByContext, getWeeklySubmissionContext, requestSubmissionEdit, saveStatisticsDraft, submitStatistics } from '$lib/api/submissionApi';
  import { tenantContext } from '$lib/stores/tenantContext';
  import type { SubmissionDetail, SubmissionMetricDefinition, SubmissionMetricValue, SubmissionSelectorOption, SubmissionStatus, SubmissionValidationMessage } from '$lib/types/submission';

  const statusLabels: Record<SubmissionStatus, string> = {
    draft: 'แบบร่าง', submitted: 'ส่งแล้ว', approved: 'อนุมัติแล้ว', rejected: 'ไม่อนุมัติ', edit_requested: 'รออนุมัติคำขอแก้ไข', returned: 'ส่งกลับแก้ไข'
  };
  let periods: SubmissionSelectorOption[] = [];
  let organizationUnits: SubmissionSelectorOption[] = [];
  let metrics: SubmissionMetricDefinition[] = [];
  let selectedPeriodId = '';
  let selectedOuId = '';
  let remarks = '';
  let metricValues: SubmissionMetricValue[] = [];
  let validationMessages: SubmissionValidationMessage[] = [];
  let currentSubmission: SubmissionDetail | null = null;
  let pageLoading = true;
  let detailLoading = false;
  let mutating = false;
  let pageError = '';
  let actionMessage = '';
  let mounted = false;
  let contextKey = '';
  let detailRequest = 0;
  let editRequestOpen = false;
  let editRequestReason = '';
  let requestingEdit = false;

  $: selectedPeriod = periods.find((period) => period.id === selectedPeriodId);
  $: windowLocked = selectedPeriod?.submissionState !== 'open' && currentSubmission?.submission.status !== 'returned';
  $: locked = windowLocked || (currentSubmission !== null && !['draft', 'returned'].includes(currentSubmission.submission.status));
  $: if (mounted && selectedOuId && selectedPeriodId && `${selectedOuId}:${selectedPeriodId}` !== contextKey) {
    contextKey = `${selectedOuId}:${selectedPeriodId}`;
    void loadSubmission();
  }

  function emptyValues(): SubmissionMetricValue[] {
    return metrics.map((metric) => ({ metricId: metric.id, numericValue: null, textValue: null, booleanValue: null }));
  }
  function formatDate(value: string): string {
    return new Intl.DateTimeFormat('th-TH', { day: 'numeric', month: 'short', year: 'numeric' }).format(new Date(`${value}T00:00:00`));
  }
  function formatDateTime(value: string): string {
    return new Intl.DateTimeFormat('th-TH', {
      day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit'
    }).format(new Date(value));
  }
  function submissionWindowLabel(): string {
    if (!selectedPeriod) return '';
    if (selectedPeriod.submissionState === 'not_open') return `ยังไม่เปิดรับรายงาน · เปิด ${selectedPeriod.submissionOpensAt ? formatDateTime(selectedPeriod.submissionOpensAt) : 'ตามกำหนด'}`;
    if (selectedPeriod.submissionState === 'overdue') return `เลยกำหนดส่งแล้ว · กำหนดส่ง ${selectedPeriod.submissionDueAt ? formatDateTime(selectedPeriod.submissionDueAt) : 'ตามกำหนด'}`;
    if (selectedPeriod.submissionState === 'locked') return 'รอบนี้ถูกปิดรับรายงานแล้ว';
    return `เปิดรับรายงาน · ส่งภายใน ${selectedPeriod.submissionDueAt ? formatDateTime(selectedPeriod.submissionDueAt) : 'กำหนดเวลา'}`;
  }
  async function loadContext(): Promise<void> {
    pageLoading = true;
    pageError = '';
    try {
      const data = await getWeeklySubmissionContext(getSupabaseBrowserClient());
      periods = data.periods.map((period) => ({
        id: period.id,
        label: formatDate(period.periodEnd),
        helperText: `${formatDate(period.periodStart)} – ${formatDate(period.periodEnd)} · สัปดาห์ที่ ${period.weekNo}`,
        submissionOpensAt: period.submissionOpensAt,
        submissionDueAt: period.submissionDueAt,
        submissionState: period.submissionState
      }));
      organizationUnits = data.organizationUnits.map((ou) => ({ id: ou.id, label: ou.name }));
      metrics = data.metrics;
      metricValues = emptyValues();
      const params = new URLSearchParams(window.location.search);
      const requestedPeriodId = params.get('periodId')?.trim() ?? '';
      selectedPeriodId = periods.some((period) => period.id === requestedPeriodId)
        ? requestedPeriodId
        : periods.some((period) => period.id === data.defaultPeriodId) ? data.defaultPeriodId ?? '' : periods[0]?.id ?? '';
      const preferredOuId = $tenantContext.preferences?.defaultOuId ?? '';
      const requestedOuId = params.get('ouId')?.trim() ?? '';
      selectedOuId = organizationUnits.some((ou) => ou.id === requestedOuId)
        ? requestedOuId
        : organizationUnits.some((ou) => ou.id === preferredOuId) ? preferredOuId : organizationUnits[0]?.id ?? '';
      mounted = true;
      if (selectedPeriodId && selectedOuId) {
        contextKey = `${selectedOuId}:${selectedPeriodId}`;
        await loadSubmission();
      }
    } catch (error) {
      pageError = friendlyError(error);
    } finally {
      pageLoading = false;
    }
  }
  async function loadSubmission(): Promise<void> {
    const request = ++detailRequest;
    detailLoading = true;
    pageError = '';
    validationMessages = [];
    try {
      const detail = await getSubmissionByContext(getSupabaseBrowserClient(), selectedOuId, selectedPeriodId);
      if (request !== detailRequest) return;
      currentSubmission = detail;
      remarks = detail?.submission.remarks ?? '';
      const saved = new Map((detail?.values ?? []).map((value) => [value.metricId, value]));
      metricValues = metrics.map((metric) => saved.get(metric.id) ?? { metricId: metric.id, numericValue: null, textValue: null, booleanValue: null });
      actionMessage = detail ? `โหลด${statusLabels[detail.submission.status]} รุ่นที่ ${detail.submission.revisionNo} แล้ว` : 'ยังไม่มีข้อมูลสำหรับสัปดาห์และหน่วยงานนี้';
    } catch (error) {
      if (request === detailRequest) pageError = friendlyError(error);
    } finally {
      if (request === detailRequest) detailLoading = false;
    }
  }
  function validateForm(requireAllRequired: boolean): SubmissionValidationMessage[] {
    const messages: SubmissionValidationMessage[] = [];
    for (const metric of metrics) {
      const value = metricValues.find((item) => item.metricId === metric.id);
      const actual = metric.dataType === 'number' ? value?.numericValue : metric.dataType === 'text' ? value?.textValue : value?.booleanValue;
      if (requireAllRequired && metric.isRequired && (actual === null || actual === undefined || actual === '')) {
        messages.push({ field: metric.id, message: `กรุณากรอก ${metric.name}` });
      }
      if (metric.dataType === 'number' && typeof actual === 'number') {
        if (metric.minValue !== null && actual < metric.minValue) messages.push({ field: metric.id, message: `${metric.name} ต้องไม่น้อยกว่า ${metric.minValue}` });
        if (metric.maxValue !== null && actual > metric.maxValue) messages.push({ field: metric.id, message: `${metric.name} ต้องไม่เกิน ${metric.maxValue}` });
      }
    }
    return messages;
  }
  function payloadValues(): SubmissionMetricValue[] {
    return metricValues.filter((value) => [value.numericValue, value.textValue, value.booleanValue].filter((item) => item !== null).length === 1);
  }
  async function mutate(submit: boolean): Promise<void> {
    validationMessages = validateForm(true);
    if (validationMessages.length) {
      actionMessage = 'กรุณาแก้ไขข้อมูลก่อนบันทึก';
      return;
    }
    mutating = true;
    pageError = '';
    try {
      const payload = { clientRequestId: crypto.randomUUID(), expectedRevision: currentSubmission?.submission.revisionNo ?? null, ouId: selectedOuId, periodId: selectedPeriodId, remarks: remarks.trim() || null, values: payloadValues() };
      const result = submit ? await submitStatistics(getSupabaseBrowserClient(), payload) : await saveStatisticsDraft(getSupabaseBrowserClient(), payload);
      actionMessage = submit ? 'ส่งข้อมูลเรียบร้อยแล้ว' : 'บันทึกแบบร่างเรียบร้อยแล้ว';
      await loadSubmission();
      if (currentSubmission) currentSubmission.submission.revisionNo = result.revisionNo;
    } catch (error) {
      if (error instanceof BackendError && error.code.includes('REVISION_CONFLICT')) {
        actionMessage = 'ข้อมูลถูกแก้ไขจากอีกหน้าต่าง กำลังโหลดรุ่นล่าสุด';
        await loadSubmission();
      } else {
        pageError = friendlyError(error);
      }
    } finally {
      mutating = false;
    }
  }
  async function submitEditRequest(): Promise<void> {
    if (!currentSubmission || !editRequestReason.trim()) return;
    requestingEdit = true;
    pageError = '';
    try {
      await requestSubmissionEdit(getSupabaseBrowserClient(), {
        submissionId: currentSubmission.submission.id,
        expectedRevision: currentSubmission.submission.revisionNo,
        clientRequestId: crypto.randomUUID(),
        reason: editRequestReason.trim()
      });
      editRequestOpen = false;
      editRequestReason = '';
      actionMessage = 'ส่งคำขอแก้ไขให้ Manager/Admin แล้ว';
      await loadSubmission();
      window.dispatchEvent(new CustomEvent('edit-request-count-changed'));
    } catch (error) {
      pageError = friendlyError(error);
    } finally {
      requestingEdit = false;
    }
  }
  function friendlyError(error: unknown): string {
    const code = error instanceof BackendError ? error.code : error instanceof Error ? error.message : '';
    if (code.includes('PERMISSION_DENIED')) return 'คุณไม่มีสิทธิ์บันทึกข้อมูลของหน่วยงานนี้';
    if (code.includes('PERIOD_LOCKED')) return 'ช่วงเวลานี้ถูกปิดรับข้อมูลแล้ว';
    if (code.includes('SUBMISSION_WINDOW_NOT_OPEN')) return 'รอบนี้ยังไม่เปิดรับรายงาน';
    if (code.includes('SUBMISSION_DEADLINE_PASSED')) return 'เลยกำหนดส่งรายงานของรอบนี้แล้ว';
    if (code.includes('SUBMISSION_ALREADY_APPROVED') || code.includes('INVALID_STATUS_TRANSITION')) return 'รายการนี้ถูกล็อกแล้ว หากต้องแก้ไขให้ผู้อนุมัติส่งกลับก่อน';
    return 'ไม่สามารถเชื่อมต่อข้อมูลได้ กรุณาลองอีกครั้ง';
  }
  onMount(loadContext);
</script>

<svelte:head><title>Weekly Submission | CSMS</title></svelte:head>

{#if pageLoading}
  <section class="app-card px-5 py-14 text-center" aria-busy="true"><p class="text-sm text-slate-600">กำลังโหลดแบบฟอร์ม...</p></section>
{:else if pageError && (!periods.length || !organizationUnits.length)}
  <section class="app-card px-5 py-14 text-center"><h1 class="text-lg font-semibold text-slate-900">โหลดแบบฟอร์มไม่สำเร็จ</h1><p class="mt-2 text-sm text-rose-700">{pageError}</p><button class="app-button-primary mt-5" type="button" on:click={loadContext}>ลองอีกครั้ง</button></section>
{:else if !organizationUnits.length}
  <section class="app-card px-5 py-14 text-center"><h1 class="text-lg font-semibold text-slate-900">ยังไม่มีหน่วยงานที่บันทึกข้อมูลได้</h1><p class="mt-2 text-sm text-slate-500">ติดต่อผู้ดูแลเพื่อเปิดรับข้อมูลหรือมอบหมายสิทธิ์ให้คุณ</p></section>
{:else if !metrics.length}
  <section class="app-card px-5 py-14 text-center"><h1 class="text-lg font-semibold text-slate-900">ยังไม่มีตัวชี้วัด</h1><p class="mt-2 text-sm text-slate-500">ผู้ดูแลต้องเปิดใช้งานตัวชี้วัดอย่างน้อยหนึ่งรายการ</p></section>
{:else}
  <div class="app-page space-y-5">
    <SubmissionContextSelectors {periods} {organizationUnits} bind:selectedPeriodId bind:selectedOuId disabled={detailLoading || mutating} />
    {#if selectedPeriod}<section class={`rounded-2xl border px-4 py-3 text-sm ${selectedPeriod.submissionState === 'open' ? 'border-emerald-200 bg-emerald-50 text-emerald-900' : selectedPeriod.submissionState === 'overdue' ? 'border-rose-200 bg-rose-50 text-rose-900' : 'border-amber-200 bg-amber-50 text-amber-900'}`}><p class="font-semibold">{submissionWindowLabel()}</p><p class="mt-1 text-xs opacity-80">รอบคำนวณ {selectedPeriod.helperText}</p></section>{/if}
    {#if pageError}<section class="rounded-md border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800" role="alert">{pageError} <button class="ml-2 underline" type="button" on:click={loadSubmission}>ลองอีกครั้ง</button></section>{/if}
    {#if currentSubmission}
      <section class="app-card flex flex-wrap items-center justify-between gap-3 p-4"><div><p class="text-xs font-semibold uppercase tracking-wide text-slate-500">สถานะ</p><p class="mt-1 font-semibold text-slate-900">{statusLabels[currentSubmission.submission.status]} · รุ่นที่ {currentSubmission.submission.revisionNo}</p></div>{#if currentSubmission.submission.status === 'edit_requested'}<p class="text-sm text-sky-800">ส่งคำขอแล้ว แบบฟอร์มจะปลดล็อกเมื่อ Manager/Admin อนุมัติ</p>{:else if locked}<div class="flex flex-wrap items-center gap-3"><p class="text-sm text-amber-800">รายการถูกล็อก</p>{#if ['submitted', 'approved'].includes(currentSubmission.submission.status)}<button class="app-button-secondary" type="button" on:click={() => (editRequestOpen = true)}>ร้องขอแก้ไข</button>{/if}</div>{/if}</section>
    {/if}
    {#if detailLoading}<section class="app-card p-8 text-center text-sm text-slate-600" aria-busy="true">กำลังโหลดข้อมูลเดิม...</section>{:else}
      <ValidationMessageArea messages={validationMessages} />
      <DynamicMetricForm {metrics} bind:values={metricValues} {validationMessages} disabled={locked || mutating} />
      <section class="app-card p-4 sm:p-5"><label class="block" for="submission-remarks"><span class="app-section-title">หมายเหตุ</span><textarea id="submission-remarks" class="app-input mt-3 min-h-32 resize-y py-3" bind:value={remarks} disabled={locked || mutating} placeholder="เพิ่มข้อมูลประกอบ (ถ้ามี)"></textarea></label></section>
      <section class="app-card flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5"><p class="text-sm text-slate-600" aria-live="polite">{actionMessage}</p><div class="flex flex-col gap-3 sm:flex-row"><button type="button" class="app-button-secondary" disabled={locked || mutating} on:click={() => mutate(false)}>{mutating ? 'กำลังบันทึก...' : 'บันทึกแบบร่าง'}</button><button type="button" class="app-button-primary" disabled={locked || mutating} on:click={() => mutate(true)}>ส่งข้อมูล</button></div></section>
    {/if}
  </div>
{/if}

{#if editRequestOpen && currentSubmission}
  <div class="fixed inset-0 z-50 flex min-h-[100dvh] items-end justify-center overflow-y-auto overscroll-contain bg-slate-950/50 p-0 sm:items-center sm:p-4" role="presentation">
    <div class="max-h-[calc(100vh-0.5rem)] max-h-[calc(100dvh-0.5rem)] w-full max-w-lg overflow-y-auto overscroll-contain rounded-t-3xl bg-white p-5 shadow-2xl sm:max-h-[calc(100dvh-2rem)] sm:rounded-3xl" style="padding-bottom: max(1.25rem, env(safe-area-inset-bottom));" role="dialog" aria-modal="true" aria-labelledby="edit-request-title">
      <h2 id="edit-request-title" class="text-lg font-semibold text-slate-950">ร้องขอแก้ไขข้อมูล</h2>
      <p class="mt-2 text-sm leading-6 text-slate-600">แบบฟอร์มจะยังถูกล็อกจนกว่า Manager หรือ Admin จะอนุมัติคำขอ</p>
      <label class="mt-5 block text-sm font-medium text-slate-700" for="edit-request-reason">เหตุผลที่ต้องการแก้ไข *</label>
      <textarea id="edit-request-reason" class="app-input mt-2 min-h-28 resize-y py-3" bind:value={editRequestReason} placeholder="เช่น กรอกจำนวนผู้เข้าร่วมผิด"></textarea>
      <div class="mt-5 flex justify-end gap-3"><button class="app-button-secondary" type="button" disabled={requestingEdit} on:click={() => (editRequestOpen = false)}>ยกเลิก</button><button class="app-button-primary" type="button" disabled={requestingEdit || !editRequestReason.trim()} on:click={submitEditRequest}>{requestingEdit ? 'กำลังส่ง...' : 'ส่งคำขอ'}</button></div>
    </div>
  </div>
{/if}
