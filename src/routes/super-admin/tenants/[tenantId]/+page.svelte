<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  import { env } from '$env/dynamic/public';
  import { Activity, AlertTriangle, ArrowLeft, BellRing, CheckCircle2, Clock3, Copy, FileClock, Link2, LoaderCircle, RefreshCw, Save, Send, ShieldAlert, TimerReset, XCircle } from '@lucide/svelte';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';
  import {
    createPlatformAdminInviteLink, getPlatformNotificationOperations, getPlatformTenantDetail, listPlatformTenantActivity,
    listPlatformTenantInvitations, revokePlatformTenantInvitation, setPlatformTenantStatus,
    updatePlatformTenant, type PlatformTenantActivity, type PlatformTenantDetail,
    type PlatformNotificationOperations, type PlatformTenantInvitation
  } from '$lib/api/platformTenantApi';

  const tenantId = $page.params.tenantId ?? '';
  let detail: PlatformTenantDetail | null = null;
  let invitations: PlatformTenantInvitation[] = [];
  let activity: PlatformTenantActivity[] = [];
  let notificationOperations: PlatformNotificationOperations | null = null;
  let loading = true;
  let saving = false;
  let actionLoading = '';
  let error = '';
  let success = '';
  let generatedLink = '';
  let name = '';
  let slug = '';
  let description = '';
  let timezone = 'Asia/Bangkok';
  let approvalMode: 'auto_approve' | 'approval_required' = 'auto_approve';
  let weekEndsOn: 'sunday' | 'saturday' = 'sunday';
  let submissionDeadlineDaysAfterPeriodEnd = 1;

  function showError(value: unknown): void {
    error = value instanceof Error ? value.message : 'เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ';
  }

  function populateForm(value: PlatformTenantDetail): void {
    name = value.name; slug = value.slug; description = value.description ?? '';
    timezone = value.timezone; approvalMode = value.approvalMode; weekEndsOn = value.weekEndsOn;
    submissionDeadlineDaysAfterPeriodEnd = value.submissionDeadlineDaysAfterPeriodEnd;
  }

  async function loadAll(): Promise<void> {
    loading = true; error = '';
    try {
      const client = getSupabaseBrowserClient();
      const [nextDetail, nextInvitations, nextActivity, nextNotificationOperations] = await Promise.all([
        getPlatformTenantDetail(client, tenantId), listPlatformTenantInvitations(client, tenantId),
        listPlatformTenantActivity(client, tenantId), getPlatformNotificationOperations(client, tenantId)
      ]);
      detail = nextDetail; invitations = nextInvitations; activity = nextActivity;
      notificationOperations = nextNotificationOperations; populateForm(nextDetail);
    } catch (value) { showError(value); } finally { loading = false; }
  }

  async function save(): Promise<void> {
    if (!name.trim() || !slug.trim() || !timezone.trim()) { error = 'กรุณากรอกชื่อ Slug และ Timezone'; return; }
    saving = true; error = ''; success = '';
    try {
      await updatePlatformTenant(getSupabaseBrowserClient(), tenantId, { name: name.trim(), slug: slug.trim().toLowerCase(),
        description: description.trim() || null, timezone: timezone.trim(), approvalMode, weekEndsOn,
        submissionDeadlineDaysAfterPeriodEnd });
      success = 'บันทึกข้อมูล Tenant แล้ว'; await loadAll();
    } catch (value) { showError(value); } finally { saving = false; }
  }

  async function changeStatus(status: 'active' | 'suspended' | 'closed'): Promise<void> {
    const question = status === 'closed'
      ? 'ปิด Tenant นี้ถาวรหรือไม่? ข้อมูลจะถูกเก็บตาม retention policy และเปิดกลับไม่ได้'
      : `${status === 'suspended' ? 'ระงับ' : 'เปิดใช้งาน'} Tenant นี้หรือไม่?`;
    if (!confirm(question)) return;
    actionLoading = status; error = ''; success = '';
    try { await setPlatformTenantStatus(getSupabaseBrowserClient(), tenantId, status); success = 'อัปเดต lifecycle แล้ว'; await loadAll(); }
    catch (value) { showError(value); } finally { actionLoading = ''; }
  }

  async function reissueInvite(): Promise<void> {
    actionLoading = 'invite'; error = ''; success = '';
    try {
      const created = await createPlatformAdminInviteLink(getSupabaseBrowserClient(), tenantId, 7);
      const base = env.PUBLIC_LINE_LIFF_ID ? `https://liff.line.me/${env.PUBLIC_LINE_LIFF_ID}` : `${location.origin}/`;
      generatedLink = `${base}?invite=${encodeURIComponent(created.inviteToken)}`;
      success = 'ออก Root Admin Invite Link ใหม่แล้ว';
      invitations = await listPlatformTenantInvitations(getSupabaseBrowserClient(), tenantId);
      activity = await listPlatformTenantActivity(getSupabaseBrowserClient(), tenantId);
    } catch (value) { showError(value); } finally { actionLoading = ''; }
  }

  async function revoke(invitationId: string): Promise<void> {
    if (!confirm('ยกเลิกคำเชิญนี้หรือไม่?')) return;
    actionLoading = invitationId; error = ''; success = '';
    try { await revokePlatformTenantInvitation(getSupabaseBrowserClient(), tenantId, invitationId); generatedLink = ''; success = 'ยกเลิกคำเชิญแล้ว'; await loadAll(); }
    catch (value) { showError(value); } finally { actionLoading = ''; }
  }

  async function copyLink(): Promise<void> { await navigator.clipboard.writeText(generatedLink); success = 'คัดลอก Invite Link แล้ว'; }
  function date(value: string | null): string { return value ? new Intl.DateTimeFormat('th-TH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value)) : '—'; }
  function statusClass(status: string): string {
    if (status === 'active' || status === 'accepted') return 'bg-emerald-50 text-emerald-700 border-emerald-200';
    if (status === 'trial' || status === 'pending') return 'bg-amber-50 text-amber-700 border-amber-200';
    if (status === 'suspended' || status === 'revoked') return 'bg-rose-50 text-rose-700 border-rose-200';
    return 'bg-slate-100 text-slate-600 border-slate-200';
  }
  function percent(value: number): string { return `${Number(value).toFixed(1)}%`; }
  onMount(loadAll);
</script>

<svelte:head><title>Tenant Detail | CSMS Super Admin</title></svelte:head>

<div class="mx-auto max-w-7xl space-y-5">
  <a href="/super-admin/tenants" class="inline-flex items-center gap-2 text-sm font-semibold text-violet-700"><ArrowLeft size={16} /> Tenant Directory</a>
  {#if error}<p class="rounded-2xl border border-rose-200 bg-rose-50 p-4 text-sm text-rose-700" role="alert">{error}</p>{/if}
  {#if success}<p class="rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-sm text-emerald-700" role="status">{success}</p>{/if}
  {#if loading}
    <div class="grid min-h-72 place-items-center rounded-3xl border bg-white"><LoaderCircle class="animate-spin text-violet-600" size={30} /></div>
  {:else if detail}
    <section class="rounded-3xl bg-gradient-to-br from-slate-950 via-violet-950 to-sky-950 p-5 text-white sm:p-7">
      <div class="flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
        <div><p class="text-xs font-semibold uppercase tracking-[0.18em] text-violet-200">{detail.code}</p><h1 class="mt-2 text-2xl font-semibold sm:text-3xl">{detail.name}</h1><p class="mt-2 text-sm text-slate-300">/{detail.slug} · สร้าง {date(detail.createdAt)}</p></div>
        <div class="flex flex-wrap items-center gap-2"><span class={`rounded-full border px-3 py-1.5 text-xs font-semibold ${statusClass(detail.status)}`}>{detail.status}</span>
          {#if detail.status !== 'closed'}
            <button class="rounded-xl border border-white/20 px-3 py-2 text-xs font-semibold hover:bg-white/10" disabled={Boolean(actionLoading)} on:click={() => changeStatus(detail?.status === 'suspended' ? 'active' : 'suspended')}>{detail.status === 'suspended' ? 'Reactivate' : 'Suspend'}</button>
            <button class="rounded-xl border border-rose-300/40 px-3 py-2 text-xs font-semibold text-rose-200 hover:bg-rose-400/10" disabled={Boolean(actionLoading)} on:click={() => changeStatus('closed')}>Close tenant</button>
          {/if}
        </div>
      </div>
    </section>

    <section class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4" aria-label="Provisioning status">
      <div class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Root OU</p><p class="mt-1 text-2xl font-semibold">{detail.provisioning.rootOuCount}</p></div>
      <div class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">OU Types</p><p class="mt-1 text-2xl font-semibold">{detail.provisioning.ouTypeCount}</p></div>
      <div class="rounded-2xl border bg-white p-4"><p class="text-xs text-slate-500">Metrics</p><p class="mt-1 text-2xl font-semibold">{detail.provisioning.metricCount}</p></div>
      <div class={`rounded-2xl border p-4 ${detail.provisioning.ready ? 'border-emerald-200 bg-emerald-50' : 'border-amber-200 bg-amber-50'}`}><p class="text-xs text-slate-500">Provisioning</p><p class="mt-2 flex items-center gap-2 text-sm font-semibold">{#if detail.provisioning.ready}<CheckCircle2 size={18} /> พร้อมใช้งาน{:else}<Clock3 size={18} /> ยังไม่ครบ{/if}</p></div>
    </section>

    <div class="grid gap-5 xl:grid-cols-[1.05fr_0.95fr]">
      <section class="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
        <h2 class="text-lg font-semibold">ข้อมูลและ Configuration</h2>
        <div class="mt-5 grid gap-4 sm:grid-cols-2">
          <label><span class="text-sm font-medium">ชื่อ Tenant</span><input class="app-input mt-2" bind:value={name} disabled={detail.status === 'closed'} /></label>
          <label><span class="text-sm font-medium">Slug</span><input class="app-input mt-2" bind:value={slug} disabled={detail.status === 'closed'} /></label>
          <label class="sm:col-span-2"><span class="text-sm font-medium">คำอธิบาย</span><textarea class="app-input mt-2 min-h-24" bind:value={description} disabled={detail.status === 'closed'}></textarea></label>
          <label><span class="text-sm font-medium">Timezone</span><input class="app-input mt-2" bind:value={timezone} disabled={detail.status === 'closed'} /></label>
          <label><span class="text-sm font-medium">วันสิ้นสุดรอบคำนวณ</span><select class="app-input mt-2" bind:value={weekEndsOn} disabled={detail.status === 'closed'}><option value="sunday">วันอาทิตย์</option><option value="saturday">วันเสาร์</option></select></label>
          <label><span class="text-sm font-medium">กำหนดส่งหลังสิ้นสุดรอบ</span><select class="app-input mt-2" bind:value={submissionDeadlineDaysAfterPeriodEnd} disabled={detail.status === 'closed'}><option value={1}>1 วัน</option><option value={2}>2 วัน</option><option value={3}>3 วัน</option><option value={4}>4 วัน</option><option value={5}>5 วัน</option><option value={6}>6 วัน</option></select></label>
          <label class="sm:col-span-2"><span class="text-sm font-medium">Approval mode</span><select class="app-input mt-2" bind:value={approvalMode} disabled={detail.status === 'closed'}><option value="auto_approve">Auto approve</option><option value="approval_required">Approval required</option></select></label>
        </div>
        <button class="app-button-primary mt-5 inline-flex items-center gap-2" disabled={saving || detail.status === 'closed'} on:click={save}>{#if saving}<LoaderCircle class="animate-spin" size={17} />{:else}<Save size={17} />{/if} บันทึก</button>
      </section>

      <section class="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
        <div class="flex items-center justify-between gap-3"><div><h2 class="text-lg font-semibold">Root Admin Invitations</h2><p class="mt-1 text-xs text-slate-500">แสดงสถานะและหมุน token โดยไม่เปิดเผย token เก่า</p></div><button class="app-button-secondary inline-flex items-center gap-2" disabled={Boolean(actionLoading) || detail.status === 'closed'} on:click={reissueInvite}><RefreshCw size={16} /> ออกใหม่</button></div>
        {#if generatedLink}<div class="mt-4 rounded-2xl border border-sky-200 bg-sky-50 p-3"><p class="break-all text-xs text-sky-800">{generatedLink}</p><button class="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-sky-700" on:click={copyLink}><Copy size={14} /> คัดลอก</button></div>{/if}
        <div class="mt-4 space-y-3">
          {#each invitations as invitation}
            <article class="rounded-2xl border border-slate-200 p-3"><div class="flex items-start justify-between gap-2"><div><p class="text-sm font-semibold">{invitation.displayName || invitation.email || 'Manual LINE invite'}</p><p class="mt-1 text-xs text-slate-500">หมดอายุ {date(invitation.expiresAt)}</p></div><span class={`rounded-full border px-2 py-1 text-[0.68rem] font-semibold ${statusClass(invitation.status)}`}>{invitation.status}</span></div>{#if invitation.status === 'pending'}<button class="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-rose-700" disabled={Boolean(actionLoading)} on:click={() => revoke(invitation.id)}><XCircle size={14} /> Revoke</button>{/if}</article>
          {:else}<p class="rounded-2xl bg-slate-50 p-6 text-center text-sm text-slate-500">ยังไม่มีคำเชิญ</p>{/each}
        </div>
      </section>
    </div>

    {#if notificationOperations}
      <section class="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6" aria-labelledby="notification-operations-title">
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div><div class="flex items-center gap-2"><Activity class="text-violet-700" size={20} /><h2 id="notification-operations-title" class="text-lg font-semibold">Notification Operations</h2></div><p class="mt-1 text-xs text-slate-500">ภาพรวม 24 ชั่วโมงและ queue ปัจจุบัน โดยไม่แสดงผู้รับหรือเนื้อหาข้อความ</p></div>
          <button class="app-button-secondary inline-flex items-center gap-2" disabled={loading} on:click={loadAll}><RefreshCw size={16} /> Refresh</button>
        </div>
        <div class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-6">
          <div class="rounded-2xl border border-sky-100 bg-sky-50 p-4"><BellRing class="text-sky-700" size={18} /><p class="mt-3 text-xs text-slate-500">In-app created</p><p class="mt-1 text-2xl font-semibold">{notificationOperations.summary.notificationsCreated}</p></div>
          <div class="rounded-2xl border border-emerald-100 bg-emerald-50 p-4"><Send class="text-emerald-700" size={18} /><p class="mt-3 text-xs text-slate-500">Success rate</p><p class="mt-1 text-2xl font-semibold">{percent(notificationOperations.summary.successRate)}</p></div>
          <div class="rounded-2xl border border-amber-100 bg-amber-50 p-4"><Clock3 class="text-amber-700" size={18} /><p class="mt-3 text-xs text-slate-500">Pending / retry</p><p class="mt-1 text-2xl font-semibold">{notificationOperations.summary.pending + notificationOperations.summary.retryableFailed}</p></div>
          <div class="rounded-2xl border border-violet-100 bg-violet-50 p-4"><TimerReset class="text-violet-700" size={18} /><p class="mt-3 text-xs text-slate-500">Processing / stale</p><p class="mt-1 text-2xl font-semibold">{notificationOperations.summary.processing} / {notificationOperations.summary.staleProcessing}</p></div>
          <div class={`rounded-2xl border p-4 ${notificationOperations.summary.deadLetter ? 'border-rose-200 bg-rose-50' : 'border-slate-200 bg-slate-50'}`}><AlertTriangle class={notificationOperations.summary.deadLetter ? 'text-rose-700' : 'text-slate-500'} size={18} /><p class="mt-3 text-xs text-slate-500">Dead letter</p><p class="mt-1 text-2xl font-semibold">{notificationOperations.summary.deadLetter}</p></div>
          <div class="rounded-2xl border border-slate-200 bg-slate-50 p-4"><Activity class="text-slate-600" size={18} /><p class="mt-3 text-xs text-slate-500">Failure rate</p><p class="mt-1 text-2xl font-semibold">{percent(notificationOperations.summary.failureRate)}</p></div>
        </div>
        <div class="mt-5 grid gap-5 lg:grid-cols-2">
          <div><h3 class="text-sm font-semibold text-slate-800">Events in window</h3><div class="mt-2 divide-y divide-slate-100 rounded-2xl border border-slate-200 px-4">
            {#each notificationOperations.events as event}<div class="grid grid-cols-[1fr_auto_auto] items-center gap-4 py-3 text-xs"><span class="font-semibold text-slate-700">{event.eventType}</span><span class="text-slate-500">In-app {event.notificationCount}</span><span class="text-slate-500">LINE {event.deliveryCount}</span></div>
            {:else}<p class="py-6 text-center text-xs text-slate-500">ไม่มี notification ในช่วงเวลานี้</p>{/each}
          </div></div>
          <div><h3 class="text-sm font-semibold text-slate-800">Recent dead letters</h3><div class="mt-2 divide-y divide-slate-100 rounded-2xl border border-slate-200 px-4">
            {#each notificationOperations.recentDeadLetters as delivery}<div class="py-3"><div class="flex items-center justify-between gap-3"><span class="text-xs font-semibold text-slate-700">{delivery.eventType}</span><time class="text-[0.68rem] text-slate-400">{date(delivery.updatedAt)}</time></div><p class="mt-1 font-mono text-[0.68rem] text-slate-500">{delivery.errorCode || 'DELIVERY_FAILED'} · attempt {delivery.attemptCount} · cycle {delivery.deliveryCycle}</p></div>
            {:else}<p class="py-6 text-center text-xs text-slate-500">ไม่มี dead letter</p>{/each}
          </div></div>
        </div>
      </section>
    {/if}

    <section class="rounded-3xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6">
      <div class="flex items-center gap-2"><FileClock class="text-violet-700" size={20} /><h2 class="text-lg font-semibold">Tenant Activity</h2></div>
      <div class="mt-4 divide-y divide-slate-100">
        {#each activity as item}<article class="grid gap-1 py-3 sm:grid-cols-[1fr_auto] sm:gap-4"><div><p class="text-sm font-semibold text-slate-800">{item.action}</p><p class="mt-1 text-xs text-slate-500">{item.entityType} · {item.actorName}</p></div><time class="text-xs text-slate-500">{date(item.createdAt)}</time></article>
        {:else}<p class="py-8 text-center text-sm text-slate-500">ยังไม่มีกิจกรรม</p>{/each}
      </div>
    </section>
  {:else}
    <div class="rounded-3xl border border-amber-200 bg-amber-50 p-8 text-center"><ShieldAlert class="mx-auto text-amber-600" size={28} /><p class="mt-3 font-semibold">ไม่พบ Tenant</p></div>
  {/if}
</div>
