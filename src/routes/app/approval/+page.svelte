<script lang="ts">
  import { onMount } from 'svelte';
  import StatusBadge from '$lib/components/common/StatusBadge.svelte';
  import { BackendError } from '$lib/api/rpc';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';
  import {
    approveSubmission,
    approveSubmissionEditRequest,
    getApprovalSubmissionDetail,
    listPendingSubmissions,
    rejectSubmission,
    returnSubmissionForEdit,
    type ApprovalDetail,
    type ApprovalQueue,
    type ApprovalQueueItem
  } from '$lib/api/approvalApi';
  import type { SubmissionStatus } from '$lib/types/submission';
  import type { StatusTone } from '$lib/types/dashboard';

  type Action = 'approve' | 'reject' | 'return' | 'approve_edit_request';
  const statusMeta: Record<SubmissionStatus, { label: string; tone: StatusTone }> = {
    draft: { label: 'แบบร่าง', tone: 'neutral' },
    submitted: { label: 'รออนุมัติ', tone: 'warning' },
    approved: { label: 'อนุมัติแล้ว', tone: 'success' },
    rejected: { label: 'ไม่อนุมัติ', tone: 'error' },
    edit_requested: { label: 'ร้องขอแก้ไข', tone: 'warning' },
    returned: { label: 'ส่งกลับแก้ไข', tone: 'info' }
  };
  const actionLabels: Record<Action, string> = { approve: 'อนุมัติ', reject: 'ไม่อนุมัติ', return: 'ส่งกลับแก้ไข', approve_edit_request: 'อนุมัติให้แก้ไข' };
  let queue: ApprovalQueue | null = null;
  let selectedItem: ApprovalQueueItem | null = null;
  let detail: ApprovalDetail | null = null;
  let periodFilter = '';
  let ouFilter = '';
  let statusFilter = 'edit_requested';
  let loading = true;
  let detailLoading = false;
  let mutating = false;
  let errorMessage = '';
  let successMessage = '';
  let action: Action | null = null;
  let actionReason = '';
  let initialPeriodSelected = false;

  function currentWeekPeriodId(periods: ApprovalQueue['periods']): string {
    return periods[0]?.id ?? '';
  }

  async function loadQueue(keepSelection = false): Promise<void> {
    loading = true;
    errorMessage = '';
    try {
      queue = await listPendingSubmissions(getSupabaseBrowserClient(), periodFilter || null, ouFilter || null, statusFilter || null);
      if (!initialPeriodSelected) {
        initialPeriodSelected = true;
        periodFilter = currentWeekPeriodId(queue.periods);
        if (periodFilter) queue = await listPendingSubmissions(getSupabaseBrowserClient(), periodFilter, ouFilter || null, statusFilter || null);
      }
      if (keepSelection && selectedItem) {
        selectedItem = queue.items.find((item) => item.id === selectedItem?.id) ?? null;
      } else {
        selectedItem = queue.items[0] ?? null;
      }
      if (selectedItem) await loadDetail(selectedItem);
      else detail = null;
    } catch (error) {
      errorMessage = friendlyError(error);
    } finally {
      loading = false;
    }
  }
  async function loadDetail(item: ApprovalQueueItem): Promise<void> {
    selectedItem = item;
    detailLoading = true;
    errorMessage = '';
    try {
      detail = await getApprovalSubmissionDetail(getSupabaseBrowserClient(), item.id);
    } catch (error) {
      errorMessage = friendlyError(error);
      detail = null;
    } finally {
      detailLoading = false;
    }
  }
  function openAction(nextAction: Action): void {
    action = nextAction;
    actionReason = '';
    errorMessage = '';
  }
  async function confirmAction(): Promise<void> {
    if (!action || !detail) return;
    if ((action === 'reject' || action === 'return') && !actionReason.trim()) {
      errorMessage = 'กรุณาระบุเหตุผล';
      return;
    }
    mutating = true;
    errorMessage = '';
    try {
      const payload = {
        submissionId: detail.submission.id,
        expectedRevision: detail.submission.revisionNo,
        clientRequestId: crypto.randomUUID(),
        reason: actionReason.trim() || null
      };
      if (action === 'approve') await approveSubmission(getSupabaseBrowserClient(), payload);
      else if (action === 'reject') await rejectSubmission(getSupabaseBrowserClient(), payload);
      else if (action === 'approve_edit_request') await approveSubmissionEditRequest(getSupabaseBrowserClient(), payload);
      else await returnSubmissionForEdit(getSupabaseBrowserClient(), payload);
      successMessage = `${actionLabels[action]}รายการเรียบร้อยแล้ว`;
      action = null;
      window.dispatchEvent(new CustomEvent('edit-request-count-changed'));
      await loadQueue(false);
    } catch (error) {
      if (error instanceof BackendError && (error.code.includes('REVISION_CONFLICT') || error.code.includes('INVALID_STATUS_TRANSITION'))) {
        errorMessage = 'รายการนี้ถูกดำเนินการจากอีกหน้าต่างแล้ว ระบบโหลดข้อมูลล่าสุดให้แล้ว';
        action = null;
        await loadQueue(false);
      } else errorMessage = friendlyError(error);
    } finally {
      mutating = false;
    }
  }
  function friendlyError(error: unknown): string {
    const code = error instanceof BackendError ? error.code : error instanceof Error ? error.message : '';
    if (code.includes('PERMISSION_DENIED') || code.includes('SUBMISSION_NOT_FOUND')) return 'คุณไม่มีสิทธิ์ดำเนินการรายการนี้ หรือรายการไม่มีอยู่แล้ว';
    if (code.includes('REASON_REQUIRED')) return 'กรุณาระบุเหตุผล';
    return 'ไม่สามารถโหลดหรือบันทึกข้อมูลได้ กรุณาลองอีกครั้ง';
  }
  function formatDate(value: string | null): string {
    if (!value) return '—';
    return new Intl.DateTimeFormat('th-TH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value));
  }
  function displayValue(value: ApprovalDetail['values'][number]): string {
    if (value.dataType === 'number') return `${value.numericValue ?? '—'} ${value.unit}`;
    if (value.dataType === 'boolean') return value.booleanValue ? 'ใช่' : 'ไม่ใช่';
    return value.textValue || '—';
  }
  onMount(() => loadQueue());
</script>

<svelte:head><title>Approval | CSMS</title></svelte:head>

<div class="app-page space-y-5">
  <section class="app-card p-4 sm:p-5">
    <div class="flex flex-col gap-4 xl:flex-row xl:items-end xl:justify-between">
      <div><span class="inline-flex rounded-md border border-violet-200 bg-violet-50 px-2 py-1 text-xs font-semibold uppercase tracking-wide text-violet-800">Approval workflow</span><h1 class="mt-3 text-2xl font-semibold text-slate-950 sm:text-3xl">ตรวจสอบและอนุมัติข้อมูล</h1><p class="mt-1 text-sm text-slate-600">รายการจะแสดงตามขอบเขต OU และสิทธิ์ของผู้อนุมัติที่ใกล้หน่วยงานที่สุด</p></div>
      <div class="grid gap-3 sm:grid-cols-3">
        <label class="text-sm text-slate-700">สถานะ<select class="app-input mt-1" bind:value={statusFilter} on:change={() => loadQueue(false)}><option value="edit_requested">ร้องขอแก้ไข</option><option value="submitted">รออนุมัติ</option><option value="approved">อนุมัติแล้ว</option><option value="rejected">ไม่อนุมัติ</option><option value="returned">ส่งกลับแก้ไข</option><option value="">ทุกสถานะ</option></select></label>
        <label class="text-sm text-slate-700">สัปดาห์<select class="app-input mt-1" bind:value={periodFilter} on:change={() => loadQueue(false)}><option value="">ทุกสัปดาห์</option>{#each queue?.periods ?? [] as period}<option value={period.id}>{period.label}</option>{/each}</select></label>
        <label class="text-sm text-slate-700">หน่วยงาน<select class="app-input mt-1" bind:value={ouFilter} on:change={() => loadQueue(false)}><option value="">ทุกหน่วยงาน</option>{#each queue?.organizationUnits ?? [] as ou}<option value={ou.id}>{ou.name}</option>{/each}</select></label>
      </div>
    </div>
    {#if queue?.approvalMode === 'auto_approve'}<div class="mt-4 rounded-md border border-sky-200 bg-sky-50 p-3 text-sm text-sky-800">องค์กรนี้ใช้โหมดอนุมัติอัตโนมัติ จึงไม่มีรายการใหม่ค้างในคิว “รออนุมัติ”</div>{/if}
  </section>

  {#if errorMessage}<section class="rounded-md border border-rose-200 bg-rose-50 p-4 text-sm text-rose-800" role="alert">{errorMessage} <button class="ml-2 underline" type="button" on:click={() => loadQueue(true)}>ลองอีกครั้ง</button></section>{/if}
  {#if successMessage}<section class="rounded-md border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-800" aria-live="polite">{successMessage}</section>{/if}

  {#if loading}
    <section class="app-card p-12 text-center text-sm text-slate-600" aria-busy="true">กำลังโหลดรายการอนุมัติ...</section>
  {:else if !queue?.items.length}
    <section class="app-card p-12 text-center"><h2 class="text-lg font-semibold text-slate-900">ไม่มีรายการตามตัวกรอง</h2><p class="mt-2 text-sm text-slate-500">ลองเปลี่ยนสถานะ สัปดาห์ หรือหน่วยงาน</p></section>
  {:else}
    <div class="grid gap-5 xl:grid-cols-[22rem_minmax(0,1fr)]">
      <section class="app-card overflow-hidden" aria-label="Approval queue">
        <div class="border-b border-slate-200 p-4"><h2 class="app-section-title">รายการ ({queue.items.length})</h2></div>
        <div class="max-h-[42rem] overflow-y-auto">
          {#each queue.items as item}
            <button type="button" class={`block w-full border-b border-slate-100 p-4 text-left transition hover:bg-slate-50 ${selectedItem?.id === item.id ? 'bg-sky-50 ring-1 ring-inset ring-sky-200' : ''}`} on:click={() => loadDetail(item)}>
              <div class="flex items-start justify-between gap-2"><div><p class="font-semibold text-slate-900">{item.ouName}</p><p class="mt-1 text-xs text-slate-500">{item.periodLabel} · {item.metricCount} ตัวชี้วัด</p></div><StatusBadge label={statusMeta[item.status].label} tone={statusMeta[item.status].tone} /></div>
              <p class="mt-3 text-xs text-slate-500">ส่งโดย {item.submittedByName ?? 'ไม่ระบุ'} · {formatDate(item.submittedAt)}</p>
              {#if item.editRequestReason}<p class="mt-2 line-clamp-2 text-xs font-medium text-amber-800">เหตุผล: {item.editRequestReason}</p>{/if}
              {#if item.isOverride}<p class="mt-2 text-xs font-medium text-violet-700">ดำเนินการในฐานะผู้มีสิทธิ์ override</p>{/if}
            </button>
          {/each}
        </div>
      </section>

      <section class="app-card p-4 sm:p-5" aria-label="Submission detail">
        {#if detailLoading}<div class="p-10 text-center text-sm text-slate-600" aria-busy="true">กำลังโหลดรายละเอียด...</div>
        {:else if detail}
          <div class="flex flex-wrap items-start justify-between gap-3 border-b border-slate-200 pb-4"><div><h2 class="text-xl font-semibold text-slate-950">{selectedItem?.ouName}</h2><p class="mt-1 text-sm text-slate-500">{selectedItem?.periodLabel} · รุ่นที่ {detail.submission.revisionNo}</p></div><StatusBadge label={statusMeta[detail.submission.status].label} tone={statusMeta[detail.submission.status].tone} /></div>
          <div class="mt-5 grid gap-3 sm:grid-cols-2">{#each detail.values as value}<div class="rounded-md border border-slate-200 p-4"><p class="text-sm font-medium text-slate-900">{value.metricName}</p><p class="mt-3 text-lg font-semibold text-slate-950">{displayValue(value)}</p></div>{/each}</div>
          <div class="mt-5 rounded-md bg-slate-50 p-4"><h3 class="text-sm font-semibold text-slate-900">หมายเหตุจากผู้ส่ง</h3><p class="mt-2 whitespace-pre-wrap text-sm text-slate-600">{detail.submission.remarks || 'ไม่มีหมายเหตุ'}</p></div>
          {#if detail.submission.editRequestReason}<div class="mt-4 rounded-md border border-amber-200 bg-amber-50 p-4"><h3 class="text-sm font-semibold text-amber-950">เหตุผลที่ร้องขอแก้ไข</h3><p class="mt-2 whitespace-pre-wrap text-sm text-amber-900">{detail.submission.editRequestReason}</p><p class="mt-2 text-xs text-amber-700">ร้องขอเมื่อ {formatDate(detail.submission.editRequestedAt)}</p></div>{/if}
          {#if detail.capabilities.canApprove || detail.capabilities.canReject || detail.capabilities.canReturn || detail.capabilities.canApproveEditRequest}<div class="mt-5 flex flex-col gap-3 border-t border-slate-200 pt-5 sm:flex-row sm:justify-end">{#if detail.capabilities.canReturn}<button class="app-button-secondary" type="button" on:click={() => openAction('return')}>ส่งกลับแก้ไข</button>{/if}{#if detail.capabilities.canReject}<button class="rounded-md border border-rose-300 px-4 py-2 text-sm font-medium text-rose-700 hover:bg-rose-50" type="button" on:click={() => openAction('reject')}>ไม่อนุมัติ</button>{/if}{#if detail.capabilities.canApprove}<button class="app-button-primary" type="button" on:click={() => openAction('approve')}>อนุมัติ</button>{/if}{#if detail.capabilities.canApproveEditRequest}<button class="app-button-primary" type="button" on:click={() => openAction('approve_edit_request')}>อนุมัติให้แก้ไข</button>{/if}</div>{/if}
          <div class="mt-6 border-t border-slate-200 pt-5"><h3 class="app-section-title">ประวัติการดำเนินการ</h3>{#if detail.history.length}<ol class="mt-3 space-y-3">{#each detail.history as history}<li class="rounded-md border border-slate-200 p-3"><div class="flex flex-wrap items-center justify-between gap-2"><p class="text-sm font-medium text-slate-900">{history.action === 'submit' ? 'ส่งข้อมูล' : history.action === 'approve' ? 'อนุมัติ' : history.action === 'reject' ? 'ไม่อนุมัติ' : history.action === 'request_edit' ? 'ร้องขอแก้ไข' : history.action === 'approve_edit_request' ? 'อนุมัติให้แก้ไข' : 'ส่งกลับแก้ไข'}{history.isOverride ? ' (override)' : ''}</p><time class="text-xs text-slate-500">{formatDate(history.createdAt)}</time></div><p class="mt-1 text-xs text-slate-500">{history.actorName}</p>{#if history.reason}<p class="mt-2 text-sm text-slate-700">{history.reason}</p>{/if}</li>{/each}</ol>{:else}<p class="mt-3 text-sm text-slate-500">ยังไม่มีประวัติการดำเนินการ</p>{/if}</div>
        {:else}<div class="p-10 text-center text-sm text-slate-500">เลือกรายการเพื่อดูรายละเอียด</div>{/if}
      </section>
    </div>
  {/if}
</div>

{#if action && detail}
  <div class="fixed inset-0 z-50 flex items-end justify-center bg-slate-950/50 p-0 sm:items-center sm:p-4" role="presentation">
    <div class="w-full max-w-lg rounded-t-xl bg-white p-5 shadow-xl sm:rounded-xl" role="dialog" aria-modal="true" aria-labelledby="action-title">
      <h2 id="action-title" class="text-lg font-semibold text-slate-950">{actionLabels[action]}รายการ</h2>
      <p class="mt-1 text-sm text-slate-600">{selectedItem?.ouName} · {selectedItem?.periodLabel}</p>
      <label class="mt-5 block text-sm font-medium text-slate-700" for="approval-reason">{action === 'approve' || action === 'approve_edit_request' ? 'หมายเหตุ (ถ้ามี)' : 'เหตุผล'}{action === 'reject' || action === 'return' ? ' *' : ''}<textarea id="approval-reason" class="app-input mt-2 min-h-28 resize-y py-3" bind:value={actionReason} placeholder={action === 'approve' || action === 'approve_edit_request' ? 'เพิ่มหมายเหตุการอนุมัติ' : 'ระบุเหตุผลสำหรับผู้ส่งข้อมูล'}></textarea></label>
      <div class="mt-5 flex justify-end gap-3"><button class="app-button-secondary" type="button" disabled={mutating} on:click={() => (action = null)}>ยกเลิก</button><button class="app-button-primary" type="button" disabled={mutating} on:click={confirmAction}>{mutating ? 'กำลังบันทึก...' : 'ยืนยัน'}</button></div>
    </div>
  </div>
{/if}
