<script lang="ts">
  import { onMount } from 'svelte';
  import { env } from '$env/dynamic/public';
  import {
    Building2, CheckCircle2, ChevronRight, CirclePlus, Clock3, Copy, Database,
    Link2, LoaderCircle, LogIn, MoreHorizontal, Search, ShieldCheck, Users, X
  } from '@lucide/svelte';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';
  import {
    createPlatformTenant,
    createPlatformAdminInviteLink,
    listPlatformTenants,
    setPlatformTenantStatus,
    type PlatformTenant,
    type PlatformTenantStatus
  } from '$lib/api/platformTenantApi';

  type TenantStatus = PlatformTenantStatus;
  type Tenant = PlatformTenant;

  let searchQuery = '';
  let statusFilter: 'all' | TenantStatus = 'all';
  let createModalOpen = false;
  let toastMessage = '';
  let tenantName = '';
  let tenantSlug = '';
  let rootOuName = '';
  let adminName = '';
  let adminEmail = '';
  let timezone = 'Asia/Bangkok';
  let weekEndsOn = 'sunday';
  let submissionDeadlineDaysAfterPeriodEnd = 1;
  let approvalMode: 'auto_approve' | 'approval_required' = 'auto_approve';
  let tenants: Tenant[] = [];
  let authReady = false;
  let signedIn = false;
  let loadingTenants = false;
  let submitting = false;
  let pageError = '';
  let formError = '';
  let loginEmail = 'admin@csms.local';
  let loginPassword = '';
  let loginLoading = false;
  let inviteModalOpen = false;
  let inviteLink = '';
  let inviteTenantName = '';
  let inviteAdminEmail = '';
  let inviteExpiresAt = '';
  let inviteLoadingTenantId = '';

  $: filteredTenants = tenants.filter((tenant) => {
    const query = searchQuery.trim().toLowerCase();
    const matchesQuery = !query || `${tenant.name} ${tenant.slug} ${tenant.adminEmail}`.toLowerCase().includes(query);
    return matchesQuery && (statusFilter === 'all' || tenant.status === statusFilter);
  });
  $: activeCount = tenants.filter((tenant) => tenant.status === 'active').length;
  $: totalMembers = tenants.reduce((sum, tenant) => sum + tenant.memberCount, 0);

  function openCreateTenant(): void {
    tenantName = '';
    tenantSlug = '';
    rootOuName = '';
    adminName = '';
    adminEmail = '';
    timezone = 'Asia/Bangkok';
    weekEndsOn = 'sunday';
    submissionDeadlineDaysAfterPeriodEnd = 1;
    approvalMode = 'auto_approve';
    createModalOpen = true;
  }

  function deriveSlug(): void {
    if (tenantSlug || !tenantName) return;
    tenantSlug = tenantName.trim().toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
  }

  function errorMessage(error: unknown): string {
    if (!(error instanceof Error)) return 'เกิดข้อผิดพลาดที่ไม่ทราบสาเหตุ';
    if (error.message.includes('SYSTEM_ADMIN_REQUIRED')) return 'บัญชีนี้ไม่มีสิทธิ์ System Admin';
    if (error.message.includes('TENANT_SLUG_EXISTS')) return 'Slug นี้ถูกใช้งานแล้ว';
    return error.message;
  }

  async function loadTenants(): Promise<void> {
    loadingTenants = true;
    pageError = '';
    try {
      tenants = await listPlatformTenants(getSupabaseBrowserClient());
    } catch (error) {
      pageError = errorMessage(error);
    } finally {
      loadingTenants = false;
    }
  }

  async function signIn(): Promise<void> {
    loginLoading = true;
    pageError = '';
    try {
      const { error } = await getSupabaseBrowserClient().auth.signInWithPassword({
        email: loginEmail.trim(),
        password: loginPassword
      });
      if (error) throw error;
      signedIn = true;
      loginPassword = '';
      await loadTenants();
    } catch (error) {
      pageError = errorMessage(error);
    } finally {
      loginLoading = false;
    }
  }

  async function createTenant(): Promise<void> {
    formError = '';
    if (!tenantName.trim() || !tenantSlug.trim() || !rootOuName.trim() || !adminName.trim() || !adminEmail.trim()) {
      formError = 'กรุณากรอกข้อมูลที่จำเป็นให้ครบ';
      return;
    }
    submitting = true;
    try {
      const createdTenantId = await createPlatformTenant(getSupabaseBrowserClient(), {
        name: tenantName.trim(),
        slug: tenantSlug.trim().toLowerCase(),
        rootOuName: rootOuName.trim(),
        adminName: adminName.trim(),
        adminEmail: adminEmail.trim(),
        timezone,
        weekEndsOn: weekEndsOn as 'sunday' | 'saturday',
        submissionDeadlineDaysAfterPeriodEnd,
        approvalMode
      });
      createModalOpen = false;
      await loadTenants();
      await issueAdminInvite(
        createdTenantId,
        tenantName.trim(),
        adminEmail.trim()
      );
    } catch (error) {
      formError = errorMessage(error);
    } finally {
      submitting = false;
    }
  }

  async function issueAdminInvite(
    tenantId: string,
    tenantDisplayName: string,
    email: string
  ): Promise<void> {
    inviteLoadingTenantId = tenantId;
    pageError = '';
    try {
      const created = await createPlatformAdminInviteLink(
        getSupabaseBrowserClient(),
        tenantId,
        7
      );
      const liffId = env.PUBLIC_LINE_LIFF_ID;
      const baseUrl = liffId
        ? `https://liff.line.me/${liffId}`
        : `${window.location.origin}/`;
      inviteLink = `${baseUrl}?invite=${encodeURIComponent(created.inviteToken)}`;
      inviteTenantName = tenantDisplayName || created.tenantName;
      inviteAdminEmail = email;
      inviteExpiresAt = created.expiresAt;
      inviteModalOpen = true;
      toastMessage = `สร้าง Root Admin Invite Link สำหรับ “${inviteTenantName}” แล้ว`;
    } catch (error) {
      pageError = errorMessage(error);
    } finally {
      inviteLoadingTenantId = '';
    }
  }

  async function copyAdminInvite(): Promise<void> {
    if (!inviteLink) return;
    await navigator.clipboard.writeText(inviteLink);
    toastMessage = 'คัดลอก Admin Invite Link แล้ว ส่งให้ผู้ดูแลทาง LINE ได้เลย';
  }

  async function toggleTenantStatus(id: string): Promise<void> {
    const tenant = tenants.find((item) => item.id === id);
    if (!tenant) return;
    pageError = '';
    try {
      await setPlatformTenantStatus(
        getSupabaseBrowserClient(),
        id,
        tenant.status === 'suspended' ? 'active' : 'suspended'
      );
      await loadTenants();
      toastMessage = 'อัปเดตสถานะ Tenant ในฐานข้อมูลแล้ว';
    } catch (error) {
      pageError = errorMessage(error);
    }
  }

  function tenantStatusClass(status: TenantStatus): string {
    if (status === 'active') return 'border-emerald-200 bg-emerald-50 text-emerald-700';
    if (status === 'trial') return 'border-amber-200 bg-amber-50 text-amber-700';
    if (status === 'provisioning') return 'border-sky-200 bg-sky-50 text-sky-700';
    if (status === 'suspended') return 'border-rose-200 bg-rose-50 text-rose-700';
    return 'border-slate-200 bg-slate-100 text-slate-600';
  }

  function formatDate(value: string): string {
    return new Intl.DateTimeFormat('th-TH', { dateStyle: 'medium' }).format(new Date(value));
  }

  onMount(async () => {
    const { data } = await getSupabaseBrowserClient().auth.getSession();
    signedIn = Boolean(data.session);
    authReady = true;
    if (signedIn) await loadTenants();
  });
</script>

<svelte:head><title>Tenant Management | CSMS Super Admin</title></svelte:head>

{#if !authReady}
  <div class="grid min-h-[60vh] place-items-center">
    <LoaderCircle class="animate-spin text-violet-600" size={30} aria-label="กำลังตรวจสอบการเข้าสู่ระบบ" />
  </div>
{:else if !signedIn}
  <section class="mx-auto mt-10 max-w-md rounded-3xl border border-slate-200 bg-white p-6 shadow-xl sm:p-8">
    <span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-violet-50 text-violet-700">
      <ShieldCheck size={24} />
    </span>
    <h1 class="mt-5 text-xl font-semibold text-slate-950">เข้าสู่ระบบ Super Admin</h1>
    <p class="mt-2 text-sm leading-6 text-slate-500">ต้องยืนยันตัวตนและมี global role เป็น system_admin จึงจะจัดการ Tenant ได้</p>
    <form class="mt-6 space-y-4" on:submit|preventDefault={signIn}>
      <label class="block">
        <span class="text-sm font-medium text-slate-700">อีเมล</span>
        <input class="app-input mt-2" type="email" bind:value={loginEmail} autocomplete="username" required />
      </label>
      <label class="block">
        <span class="text-sm font-medium text-slate-700">รหัสผ่าน</span>
        <input class="app-input mt-2" type="password" bind:value={loginPassword} autocomplete="current-password" required />
      </label>
      {#if pageError}
        <p class="rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700" role="alert">{pageError}</p>
      {/if}
      <button class="app-button-primary flex w-full items-center justify-center gap-2" type="submit" disabled={loginLoading}>
        {#if loginLoading}<LoaderCircle class="animate-spin" size={17} />{:else}<LogIn size={17} />{/if}
        {loginLoading ? 'กำลังเข้าสู่ระบบ...' : 'เข้าสู่ระบบ'}
      </button>
    </form>
  </section>
{:else}
<div class="mx-auto max-w-7xl space-y-5">
  {#if pageError}
    <div class="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700" role="alert">{pageError}</div>
  {/if}
  <section class="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm">
    <div class="relative bg-gradient-to-br from-slate-950 via-violet-950 to-sky-950 p-5 text-white sm:p-7">
      <div class="pointer-events-none absolute -right-10 -top-20 h-72 w-72 rounded-full bg-violet-400/20 blur-3xl"></div>
      <div class="relative flex flex-col gap-5 lg:flex-row lg:items-end lg:justify-between">
        <div class="max-w-2xl"><span class="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/10 px-3 py-1 text-[0.68rem] font-semibold uppercase tracking-[0.18em] text-violet-200"><ShieldCheck size={14} /> Platform Administration</span><h1 class="mt-3 text-2xl font-semibold tracking-tight sm:text-3xl">จัดการ Tenant</h1><p class="mt-2 text-sm leading-6 text-slate-300">สร้าง workspace ใหม่ พร้อม Root OU Level 1 และบัญชีผู้ดูแลเริ่มต้นในขั้นตอนเดียว</p></div>
        <button type="button" class="inline-flex min-h-11 items-center justify-center gap-2 rounded-full bg-white px-5 py-2.5 text-sm font-semibold text-slate-950 shadow-lg hover:bg-slate-100" on:click={openCreateTenant}><CirclePlus size={18} /> สร้าง Tenant</button>
      </div>
    </div>
    <div class="grid divide-y divide-slate-100 sm:grid-cols-3 sm:divide-x sm:divide-y-0">
      <div class="p-4 sm:p-5"><p class="text-xs text-slate-500">Tenant ทั้งหมด</p><p class="mt-1 text-2xl font-semibold">{tenants.length}</p></div>
      <div class="p-4 sm:p-5"><p class="text-xs text-slate-500">Active</p><p class="mt-1 text-2xl font-semibold text-emerald-700">{activeCount}</p></div>
      <div class="p-4 sm:p-5"><p class="text-xs text-slate-500">สมาชิกทุก Tenant</p><p class="mt-1 text-2xl font-semibold">{totalMembers}</p></div>
    </div>
  </section>

  <section class="overflow-hidden rounded-3xl border border-slate-200 bg-white shadow-sm">
    <div class="flex flex-col gap-4 border-b border-slate-100 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
      <div><h2 class="text-base font-semibold text-slate-950">Tenant Directory</h2><p class="mt-1 text-xs text-slate-500">ค้นหา ตรวจสถานะ และเปิด workspace ของแต่ละองค์กร</p></div>
      <div class="flex flex-col gap-3 sm:flex-row">
        <label class="relative block min-w-0 sm:w-72"><span class="sr-only">ค้นหา Tenant</span><Search class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" size={16} /><input class="app-input pl-10" type="search" placeholder="ชื่อ, slug หรืออีเมล..." bind:value={searchQuery} /></label>
        <select class="app-input sm:w-40" aria-label="กรองสถานะ" bind:value={statusFilter}><option value="all">ทุกสถานะ</option><option value="provisioning">Provisioning</option><option value="trial">Trial</option><option value="active">Active</option><option value="suspended">Suspended</option><option value="closed">Closed</option></select>
      </div>
    </div>

    <div class="divide-y divide-slate-100">
      {#if loadingTenants}
        <div class="flex items-center justify-center gap-2 p-12 text-sm text-slate-500">
          <LoaderCircle class="animate-spin" size={18} /> กำลังโหลด Tenant จากฐานข้อมูล...
        </div>
      {:else}
      {#each filteredTenants as tenant}
        <article class="grid gap-4 p-4 sm:p-5 lg:grid-cols-[minmax(0,1.4fr)_minmax(12rem,0.8fr)_8rem_10rem] lg:items-center">
          <div class="flex min-w-0 items-start gap-3"><span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-violet-50 to-sky-50 text-violet-700 ring-1 ring-violet-100"><Building2 size={20} /></span><div class="min-w-0"><div class="flex flex-wrap items-center gap-2"><h3 class="truncate text-sm font-semibold text-slate-950">{tenant.name}</h3><span class="rounded-full bg-slate-100 px-2 py-0.5 text-[0.68rem] font-medium text-slate-500">{tenant.slug}</span></div><p class="mt-1 truncate text-xs text-slate-500">Root: {tenant.rootOuName} · สร้าง {formatDate(tenant.createdAt)}</p></div></div>
          <div class="min-w-0"><p class="truncate text-xs font-semibold text-slate-700">{tenant.adminName}</p><p class="mt-1 truncate text-xs text-slate-500">{tenant.adminEmail}</p></div>
          <div class="flex gap-3 text-xs text-slate-500 lg:block"><p class="inline-flex items-center gap-1"><Users size={13} /> {tenant.memberCount}</p><p class="inline-flex items-center gap-1 lg:mt-1"><Database size={13} /> {tenant.ouCount} OU</p></div>
          <div class="flex items-center justify-between gap-2 lg:justify-end">
            <span class={`rounded-full border px-2.5 py-1 text-xs font-semibold ${tenantStatusClass(tenant.status)}`}>{tenant.status}</span>
            <a class="rounded-xl border border-violet-200 px-3 py-2 text-xs font-semibold text-violet-700 hover:bg-violet-50" href={`/super-admin/tenants/${tenant.id}`}>รายละเอียด <ChevronRight class="inline" size={14} /></a>
            <button type="button" class="rounded-xl border border-slate-200 p-2 text-slate-500 hover:bg-slate-50" aria-label={`เมนู ${tenant.name}`} on:click={() => toggleTenantStatus(tenant.id)}><MoreHorizontal size={17} /></button>
            <button type="button" class="rounded-xl border border-sky-200 p-2 text-sky-700 hover:bg-sky-50 disabled:opacity-50" disabled={inviteLoadingTenantId === tenant.id} aria-label={`สร้าง Admin Invite Link สำหรับ ${tenant.name}`} title="สร้าง/ออก Admin Invite Link ใหม่" on:click={() => issueAdminInvite(tenant.id, tenant.name, tenant.adminEmail)}>{#if inviteLoadingTenantId === tenant.id}<LoaderCircle class="animate-spin" size={17} />{:else}<Link2 size={17} />{/if}</button>
          </div>
        </article>
      {:else}
        <div class="p-10 text-center"><Search class="mx-auto text-slate-300" size={28} /><p class="mt-3 text-sm font-semibold text-slate-700">ไม่พบ Tenant</p><p class="mt-1 text-xs text-slate-500">ลองเปลี่ยนคำค้นหาหรือตัวกรองสถานะ</p></div>
      {/each}
      {/if}
    </div>
  </section>
</div>

{#if createModalOpen}
  <div class="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-4" role="presentation">
    <button class="absolute inset-0 bg-slate-950/70" type="button" aria-label="ปิด" on:click={() => (createModalOpen = false)}></button>
    <div class="relative z-10 max-h-[95vh] w-full max-w-3xl overflow-y-auto rounded-t-3xl bg-white shadow-2xl sm:rounded-3xl" role="dialog" aria-modal="true" aria-labelledby="create-tenant-title">
      <div class="flex items-start justify-between border-b border-slate-100 p-5 sm:p-6"><div><span class="inline-flex items-center gap-2 text-xs font-semibold uppercase tracking-[0.16em] text-violet-700"><CirclePlus size={14} /> New Tenant</span><h2 id="create-tenant-title" class="mt-2 text-xl font-semibold text-slate-950">สร้าง Tenant ใหม่</h2><p class="mt-1 text-xs text-slate-500">ระบบจะสร้าง Tenant, Root OU และ Tenant Admin พร้อมกัน</p></div><button type="button" class="text-slate-400" on:click={() => (createModalOpen = false)}><X size={21} /></button></div>
      <div class="space-y-6 p-5 sm:p-6">
        <div><p class="flex items-center gap-2 text-sm font-semibold text-slate-900"><Building2 size={17} class="text-violet-700" /> ข้อมูลองค์กร</p><div class="mt-4 grid gap-4 sm:grid-cols-2"><label><span class="text-sm font-medium text-slate-700">ชื่อ Tenant</span><input class="app-input mt-2" bind:value={tenantName} on:blur={deriveSlug} placeholder="เช่น Hope Church" /></label><label><span class="text-sm font-medium text-slate-700">Slug</span><input class="app-input mt-2" bind:value={tenantSlug} placeholder="hope-church" /></label><label class="sm:col-span-2"><span class="text-sm font-medium text-slate-700">ชื่อ Root OU Level 1</span><input class="app-input mt-2" bind:value={rootOuName} placeholder="เช่น คริสตจักรหลัก" /></label></div></div>
        <div class="border-t border-slate-100 pt-6"><p class="flex items-center gap-2 text-sm font-semibold text-slate-900"><Users size={17} class="text-sky-700" /> ผู้ดูแล Tenant คนแรก</p><div class="mt-4 grid gap-4 sm:grid-cols-2"><label><span class="text-sm font-medium text-slate-700">ชื่อผู้ดูแล</span><input class="app-input mt-2" bind:value={adminName} placeholder="Tenant Admin" /></label><label><span class="text-sm font-medium text-slate-700">อีเมลสำหรับคำเชิญ</span><input class="app-input mt-2" type="email" bind:value={adminEmail} placeholder="admin@example.org" /></label></div></div>
        <div class="border-t border-slate-100 pt-6"><p class="flex items-center gap-2 text-sm font-semibold text-slate-900"><Clock3 size={17} class="text-emerald-700" /> ค่าเริ่มต้น</p><div class="mt-4 grid gap-4 sm:grid-cols-2"><label><span class="text-sm font-medium text-slate-700">Timezone</span><select class="app-input mt-2" bind:value={timezone}><option>Asia/Bangkok</option><option>Asia/Singapore</option><option>UTC</option></select></label><label><span class="text-sm font-medium text-slate-700">วันสิ้นสุดรอบคำนวณ</span><select class="app-input mt-2" bind:value={weekEndsOn}><option value="sunday">วันอาทิตย์</option><option value="saturday">วันเสาร์</option></select></label><label><span class="text-sm font-medium text-slate-700">กำหนดส่งหลังสิ้นสุดรอบ</span><select class="app-input mt-2" bind:value={submissionDeadlineDaysAfterPeriodEnd}><option value={1}>1 วัน</option><option value={2}>2 วัน</option><option value={3}>3 วัน</option><option value={4}>4 วัน</option><option value={5}>5 วัน</option><option value={6}>6 วัน</option></select></label><label><span class="text-sm font-medium text-slate-700">โหมดการอนุมัติ</span><select class="app-input mt-2" bind:value={approvalMode}><option value="auto_approve">ส่งแล้วอนุมัติอัตโนมัติ</option><option value="approval_required">ต้องผ่านผู้อนุมัติ</option></select></label></div></div>
        <div class="rounded-2xl border border-sky-200 bg-sky-50 p-4"><p class="flex items-start gap-2 text-xs leading-5 text-sky-800"><CheckCircle2 class="mt-0.5 shrink-0" size={16} /> หลังสร้าง ระบบจะเตรียม OU Type เริ่มต้นและ Field สถิติมาตรฐาน ผู้ดูแล Tenant สามารถแก้ไขต่อได้จาก Tenant Settings</p></div>
      </div>
      {#if formError}
        <p class="mx-5 mb-4 rounded-xl border border-rose-200 bg-rose-50 px-3 py-2 text-sm text-rose-700 sm:mx-6" role="alert">{formError}</p>
      {/if}
      <div class="flex flex-col-reverse gap-3 border-t border-slate-100 bg-slate-50/80 p-4 sm:flex-row sm:justify-end sm:px-6"><button type="button" class="app-button-secondary" on:click={() => (createModalOpen = false)} disabled={submitting}>ยกเลิก</button><button type="button" class="app-button-primary inline-flex items-center justify-center gap-2 disabled:cursor-not-allowed disabled:opacity-60" on:click={createTenant} disabled={submitting}>{#if submitting}<LoaderCircle class="animate-spin" size={17} />{:else}<CirclePlus size={17} />{/if} {submitting ? 'กำลังบันทึก...' : 'สร้าง Tenant และสร้าง Admin Link'}</button></div>
    </div>
  </div>
{/if}

{#if inviteModalOpen}
  <div class="fixed inset-0 z-[70] flex items-end justify-center p-0 sm:items-center sm:p-4" role="presentation">
    <button class="absolute inset-0 bg-slate-950/70" type="button" aria-label="ปิด Admin Invite Link" on:click={() => (inviteModalOpen = false)}></button>
    <div class="relative z-10 w-full max-w-xl rounded-t-3xl bg-white p-5 shadow-2xl sm:rounded-3xl sm:p-6" role="dialog" aria-modal="true" aria-labelledby="admin-invite-title">
      <div class="flex items-start justify-between gap-4">
        <div><span class="flex h-11 w-11 items-center justify-center rounded-2xl bg-sky-50 text-sky-700"><Link2 size={22} /></span><h2 id="admin-invite-title" class="mt-4 text-xl font-semibold text-slate-950">Root Admin Invite Link</h2><p class="mt-1 text-sm text-slate-500">{inviteTenantName}</p></div>
        <button type="button" class="text-slate-400" aria-label="ปิด" on:click={() => (inviteModalOpen = false)}><X size={20} /></button>
      </div>
      <div class="mt-5 rounded-2xl border border-amber-200 bg-amber-50 p-4 text-xs leading-5 text-amber-800">
        ส่งลิงก์นี้ให้ผู้ดูแลที่ {inviteAdminEmail || 'ระบุไว้'} ทาง LINE ผู้รับคนแรกที่ยืนยัน LINE Login จะได้รับสิทธิ์ <strong>admin</strong> บน Root OU
      </div>
      <label class="mt-4 block"><span class="text-sm font-medium text-slate-700">Invite Link</span><textarea class="app-input mt-2 min-h-28 resize-none text-xs" readonly value={inviteLink}></textarea></label>
      <p class="mt-3 text-xs text-slate-500">หมดอายุ {new Intl.DateTimeFormat('th-TH', { dateStyle: 'long', timeStyle: 'short' }).format(new Date(inviteExpiresAt))} · ใช้ได้ครั้งเดียว</p>
      <button type="button" class="app-button-primary mt-5 inline-flex w-full items-center justify-center gap-2" on:click={copyAdminInvite}><Copy size={17} /> Copy Link เพื่อส่งทาง LINE</button>
    </div>
  </div>
{/if}

{#if toastMessage}
  <div class="fixed bottom-5 right-4 z-[60] max-w-sm rounded-2xl border border-emerald-200 bg-white px-4 py-3 shadow-xl" role="status"><div class="flex gap-3"><CheckCircle2 class="mt-0.5 shrink-0 text-emerald-600" size={18} /><div><p class="text-sm font-semibold text-slate-900">ดำเนินการแล้ว</p><p class="mt-0.5 text-xs leading-5 text-slate-600">{toastMessage}</p></div><button class="ml-auto text-slate-400" type="button" aria-label="ปิดข้อความ" on:click={() => (toastMessage = '')}><X size={16} /></button></div></div>
{/if}
{/if}
