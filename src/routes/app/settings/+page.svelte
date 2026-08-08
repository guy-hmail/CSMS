<script lang="ts">
  import { onMount } from 'svelte';
  import {
    Bell, Building2, CalendarClock, CheckCircle2, ChevronRight, CircleUserRound,
    Info, Languages, LayoutDashboard, ListTree, LockKeyhole, Mail, MapPin, Save,
    LogOut, Settings, ShieldCheck, SlidersHorizontal, Smartphone, UserRound, X
  } from '@lucide/svelte';
  import type { Component } from 'svelte';
  import {
    clearTenantContext,
    initializeTenantContext,
    tenantContext
  } from '$lib/stores/tenantContext';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';
  import {
    getAccessibleOuTree,
    type OrganizationTreeNode
  } from '$lib/api/organizationApi';
  import { getMyPreferences, updateMyPreferences, updateMyProfile } from '$lib/api/identityApi';

  type SectionId = 'profile' | 'workspace' | 'notifications' | 'ou-operations' | 'access';
  type SettingItem = { id: SectionId; label: string; description: string; icon: Component };
  type ManagedOu = { id: string; name: string; code: string; type: string; allowDataEntry: boolean };

  const settingItems: SettingItem[] = [
    { id: 'profile', label: 'โปรไฟล์ของฉัน', description: 'ข้อมูลติดต่อและบัญชี LINE', icon: CircleUserRound },
    { id: 'workspace', label: 'พื้นที่ทำงาน', description: 'Tenant และ OU เริ่มต้น', icon: SlidersHorizontal },
    { id: 'notifications', label: 'การแจ้งเตือน', description: 'รายการที่ต้องติดตาม', icon: Bell },
    { id: 'ou-operations', label: 'การตั้งค่า OU', description: 'เฉพาะ Subtree ที่ดูแล', icon: ListTree },
    { id: 'access', label: 'สิทธิ์และขอบเขต', description: 'สิ่งที่บทบาทนี้จัดการได้', icon: ShieldCheck }
  ];

  const rootOnlySettings = [
    { label: 'ข้อมูลและค่าเริ่มต้นของ Tenant', detail: 'ชื่อองค์กร, timezone รอบสัปดาห์ และโหมดอนุมัติ', icon: Building2, href: '/app/settings/tenant' },
    { label: 'OU Type Setting', detail: 'สร้าง เปลี่ยนชื่อ และจัดลำดับประเภท OU', icon: ListTree, href: '/app/settings/tenant' },
    { label: 'Metrics & Forms', detail: 'กำหนด KPI และแบบฟอร์มของทั้งองค์กร', icon: LayoutDashboard, href: '/app/settings/tenant' },
    { label: 'Reporting Periods', detail: 'เปิด–ปิดช่วงเวลารายงานระดับ Tenant', icon: CalendarClock, href: null }
  ];
  const accessSettings = [
    { label: 'สมาชิก สิทธิ์ และ Invite Link', detail: 'เลือก OU กำหนด role แล้ว copy ลิงก์ส่งทาง LINE', icon: ShieldCheck, href: '/app/organization' }
  ];
  let hasDirectRootAdminAssignment = false;

  let activeSection: SectionId = 'access';
  let displayName = '';
  let email = '';
  let phone = '';
  let language = 'th';
  let defaultOuId = '';
  let landingPage: '/app/dashboard' | '/app/organization' | '/app/submissions' | '/app/reports' = '/app/dashboard';
  let notifyMissing = true;
  let notifySubmitted = true;
  let notifyApproval = false;
  let notifyEmail = false;
  let toastMessage = '';
  let managedOus: ManagedOu[] = [];
  let settingsLoading = true;
  let settingsSaving = false;
  let settingsError = '';

  $: activeItem = settingItems.find((item) => item.id === activeSection) ?? settingItems[0];
  $: enabledOuCount = managedOus.filter((ou) => ou.allowDataEntry).length;
  $: accessLabel = $tenantContext.permissions.length > 0
    ? $tenantContext.permissions
        .map((item) => `${item.permission} · ${item.ouName}`)
        .join(', ')
    : 'ยังไม่มี OU assignment';

  async function savePreferences(): Promise<void> {
    settingsSaving = true;
    settingsError = '';
    try {
      const saved = await updateMyPreferences(getSupabaseBrowserClient(), {
        defaultOuId: defaultOuId || null,
        language: language as 'th' | 'en',
        landingPage,
        notifyMissing,
        notifySubmitted,
        notifyApproval,
        notifyEmail
      });
      defaultOuId = saved.defaultOuId ?? '';
      toastMessage = `บันทึก “${activeItem.label}” ลงใน ${$tenantContext.activeTenant?.name ?? 'Tenant ปัจจุบัน'} แล้ว`;
    } catch (error) {
      settingsError = error instanceof Error ? error.message : 'ไม่สามารถบันทึกการตั้งค่าได้';
    } finally { settingsSaving = false; }
  }

  async function saveProfile(): Promise<void> {
    settingsSaving = true;
    settingsError = '';
    try {
      const saved = await updateMyProfile(getSupabaseBrowserClient(), { displayName, email, phone });
      displayName = saved.displayName;
      email = saved.email ?? '';
      phone = saved.phone ?? '';
      await initializeTenantContext(true);
      toastMessage = 'บันทึกโปรไฟล์และอัปเดตชื่อที่แสดงแล้ว';
    } catch (error) {
      settingsError = error instanceof Error ? error.message : 'ไม่สามารถบันทึกโปรไฟล์ได้';
    } finally { settingsSaving = false; }
  }

  async function logoutEverywhere(): Promise<void> {
    settingsSaving = true;
    settingsError = '';
    try {
      const { error } = await getSupabaseBrowserClient().auth.signOut({ scope: 'global' });
      if (error) throw error;
      clearTenantContext();
      location.assign('/');
    } catch (error) {
      settingsError = error instanceof Error ? error.message : 'ไม่สามารถออกจากระบบทุกอุปกรณ์ได้';
      settingsSaving = false;
    }
  }

  function flattenOus(nodes: OrganizationTreeNode[]): ManagedOu[] {
    return nodes.flatMap((node) => [
      {
        id: node.id,
        name: node.name,
        code: node.code,
        type: node.ouTypeName,
        allowDataEntry: node.allowDataEntry
      },
      ...flattenOus(node.children)
    ]);
  }

  onMount(async () => {
    try {
      const context = await initializeTenantContext();
      const client = getSupabaseBrowserClient();
      const [tree, profileResult, preferences] = await Promise.all([
        getAccessibleOuTree(client),
        client
          .from('users')
          .select('display_name,email,phone')
          .single(),
        getMyPreferences(client)
      ]);
      if (profileResult.error) throw profileResult.error;

      managedOus = flattenOus(tree.items);
      defaultOuId = preferences.defaultOuId ?? '';
      language = preferences.language;
      landingPage = preferences.landingPage;
      notifyMissing = preferences.notifyMissing;
      notifySubmitted = preferences.notifySubmitted;
      notifyApproval = preferences.notifyApproval;
      notifyEmail = preferences.notifyEmail;
      displayName = profileResult.data.display_name || context.userName;
      email = profileResult.data.email ?? '';
      phone = profileResult.data.phone ?? '';

      const tenantRootIds = tree.items
        .filter((node) => node.parentId === null && node.level === 1)
        .map((node) => node.id);
      hasDirectRootAdminAssignment = context.permissions.some(
        (permission) =>
          permission.permission === 'admin' &&
          tenantRootIds.includes(permission.ouId)
      );
    } catch (error) {
      settingsError = error instanceof Error ? error.message : 'ไม่สามารถโหลด Settings context ได้';
    } finally {
      settingsLoading = false;
    }
  });
</script>

<svelte:head><title>Settings | CSMS</title></svelte:head>

<div class="app-page space-y-5">
  <section class="app-card relative overflow-hidden p-4 sm:p-5 lg:p-6" aria-labelledby="settings-title">
    <div class="pointer-events-none absolute -right-20 -top-24 h-72 w-72 rounded-full bg-violet-200/40 blur-3xl"></div>
    <div class="pointer-events-none absolute -bottom-24 left-1/3 h-56 w-56 rounded-full bg-emerald-200/30 blur-3xl"></div>
    <div class="relative flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
      <div class="max-w-2xl">
        <span class="inline-flex items-center gap-2 rounded-full border border-violet-200 bg-violet-50 px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-[0.2em] text-violet-800"><Settings size={14} /> Settings Center</span>
        <h1 id="settings-title" class="mt-3 text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">ตั้งค่าพื้นที่ทำงาน</h1>
        <p class="mt-2 max-w-xl text-sm leading-6 text-slate-600 sm:text-[0.95rem]">จัดการข้อมูลส่วนตัว การแจ้งเตือน และค่าใช้งานของ OU ภายในขอบเขตที่คุณรับผิดชอบ</p>
      </div>
      <div class="grid gap-2 sm:grid-cols-2 lg:min-w-[23rem]">
        <div class="rounded-2xl border border-sky-200 bg-sky-50/90 p-3.5"><p class="settings-context-label-sky text-[0.68rem] font-semibold uppercase tracking-[0.16em] text-sky-700">Tenant ปัจจุบัน</p><p class="settings-context-value-sky mt-1.5 truncate text-sm font-semibold text-sky-950">{$tenantContext.activeTenant?.name ?? '—'}</p></div>
        <div class="rounded-2xl border border-emerald-200 bg-emerald-50/90 p-3.5"><p class="settings-context-label-emerald text-[0.68rem] font-semibold uppercase tracking-[0.16em] text-emerald-700">บทบาทและขอบเขต</p><p class="settings-context-value-emerald mt-1.5 truncate text-sm font-semibold text-emerald-950">{accessLabel}</p></div>
      </div>
    </div>
  </section>

  <section class="grid gap-2 sm:grid-cols-2" aria-label="ขอบเขตการตั้งค่า">
    <div class="rounded-2xl border border-violet-200 bg-violet-50/80 px-4 py-3"><p class="text-xs font-semibold uppercase tracking-[0.14em] text-violet-700">Personal Settings</p><p class="mt-1 text-xs text-violet-900">โปรไฟล์ · พื้นที่ทำงาน · การแจ้งเตือน — บันทึกเฉพาะบัญชีของคุณ</p></div>
    <div class="rounded-2xl border border-sky-200 bg-sky-50/80 px-4 py-3"><p class="text-xs font-semibold uppercase tracking-[0.14em] text-sky-700">Tenant & Access</p><p class="mt-1 text-xs text-sky-900">โครงสร้าง OU · สมาชิก · สิทธิ์ — จำกัดตาม Tenant และบทบาทปัจจุบัน</p></div>
  </section>

  {#if settingsError}
    <p class="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">{settingsError}</p>
  {/if}

  <div class="grid min-w-0 gap-5 lg:grid-cols-[17rem_minmax(0,1fr)]">
    <aside class="min-w-0 max-w-full space-y-4 lg:sticky lg:top-24 lg:self-start">
      <nav class="app-card min-w-0 max-w-full overflow-hidden p-2" aria-label="หมวดการตั้งค่า">
        <div class="flex min-w-0 max-w-full gap-2 overflow-x-auto lg:block lg:space-y-1">
          {#each settingItems as item}
            {@const Icon = item.icon}
            {#if item.id === 'profile'}<p class="hidden px-3 pb-1 pt-2 text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-slate-400 lg:block">Personal Settings</p>{/if}
            {#if item.id === 'ou-operations'}<p class="hidden px-3 pb-1 pt-4 text-[0.65rem] font-semibold uppercase tracking-[0.18em] text-slate-400 lg:block">Tenant & Access</p>{/if}
            <button type="button" class={`app-focus group flex min-w-max items-center gap-3 rounded-2xl px-3 py-3 text-left transition lg:w-full ${activeSection === item.id ? 'bg-gradient-to-r from-sky-50 to-emerald-50 text-sky-950 shadow-sm ring-1 ring-sky-100' : 'text-slate-600 hover:bg-slate-50'}`} aria-pressed={activeSection === item.id} on:click={() => (activeSection = item.id)}>
              <span class={`flex h-9 w-9 shrink-0 items-center justify-center rounded-xl ${activeSection === item.id ? 'bg-white text-sky-700 shadow-sm' : 'bg-slate-100 text-slate-500'}`}><Icon size={18} /></span>
              <span class="min-w-0 flex-1"><span class="block text-sm font-semibold">{item.label}</span><span class="mt-0.5 hidden truncate text-[0.68rem] text-slate-400 lg:block">{item.description}</span></span>
              <ChevronRight class="hidden shrink-0 text-slate-300 lg:block" size={16} />
            </button>
          {/each}
        </div>
      </nav>
      <div class="app-card hidden p-4 lg:block"><div class="flex gap-3"><span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-emerald-50 text-emerald-700"><ShieldCheck size={19} /></span><div><p class="text-sm font-semibold text-slate-900">{hasDirectRootAdminAssignment ? 'Direct Root Admin' : 'OU-scoped access'}</p><p class="mt-1 text-xs leading-5 text-slate-500">{accessLabel}</p></div></div></div>
    </aside>

    <section class="min-w-0">
      {#if activeSection === 'profile'}
        <article class="app-card overflow-hidden">
          <div class="border-b border-slate-100 p-4 sm:p-5"><div class="flex items-start gap-3"><span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-sky-50 text-sky-700"><UserRound size={21} /></span><div><h2 class="app-section-title">โปรไฟล์ของฉัน</h2><p class="app-section-copy">ข้อมูลนี้ใช้สำหรับการติดต่อและแสดงในประวัติการทำรายการ</p></div></div></div>
          <div class="grid gap-5 p-4 sm:p-5 xl:grid-cols-[11rem_minmax(0,1fr)]">
            <div class="flex flex-col items-center rounded-2xl border border-slate-200 bg-slate-50/70 p-5 text-center"><span class="flex h-20 w-20 items-center justify-center rounded-full bg-gradient-to-br from-sky-500 to-teal-600 text-2xl font-bold text-white shadow-lg">{displayName.slice(0, 1) || 'L'}</span><p class="mt-3 text-sm font-semibold text-slate-900">{displayName}</p><span class="mt-2 rounded-full border border-emerald-200 bg-emerald-50 px-2.5 py-1 text-[0.68rem] font-semibold text-emerald-700">LINE Connected</span></div>
            <div class="grid gap-4 sm:grid-cols-2">
              <label class="sm:col-span-2"><span class="text-sm font-medium text-slate-700">ชื่อที่แสดง</span><input class="app-input mt-2" bind:value={displayName} maxlength="255" /></label>
              <label><span class="text-sm font-medium text-slate-700">อีเมล</span><div class="relative mt-2"><Mail class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" size={16} /><input class="app-input pl-10" type="email" bind:value={email} placeholder="ไม่ได้ระบุ" /></div></label>
              <label><span class="text-sm font-medium text-slate-700">เบอร์โทรศัพท์</span><div class="relative mt-2"><Smartphone class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" size={16} /><input class="app-input pl-10" bind:value={phone} maxlength="50" placeholder="ไม่ได้ระบุ" /></div></label>
              <div class="rounded-2xl border border-sky-200 bg-sky-50 p-3.5 sm:col-span-2"><div class="flex gap-3"><Info class="mt-0.5 shrink-0 text-sky-700" size={17} /><p class="text-xs leading-5 text-sky-800">LINE User ID และข้อมูลยืนยันตัวตนแก้ไขจากหน้านี้ไม่ได้ หากเปลี่ยนบัญชีต้องผ่านขั้นตอนเชื่อมต่อบัญชีใหม่</p></div></div>
            </div>
          </div>
          <div class="flex flex-col gap-3 border-t border-slate-100 bg-slate-50/60 p-4 sm:flex-row sm:items-center sm:justify-between sm:px-5"><button type="button" class="app-button-secondary app-focus inline-flex items-center justify-center gap-2 text-rose-700" disabled={settingsSaving} on:click={logoutEverywhere}><LogOut size={16} /> ออกจากระบบทุกอุปกรณ์</button><button type="button" class="app-button-primary app-focus inline-flex items-center justify-center gap-2" disabled={settingsSaving || displayName.trim().length < 2} on:click={saveProfile}><Save size={16} /> บันทึกโปรไฟล์</button></div>
        </article>
      {:else if activeSection === 'workspace'}
        <article class="app-card overflow-hidden">
          <div class="border-b border-slate-100 p-4 sm:p-5"><div class="flex items-start gap-3"><span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-violet-50 text-violet-700"><SlidersHorizontal size={21} /></span><div><h2 class="app-section-title">พื้นที่ทำงานของฉัน</h2><p class="app-section-copy">กำหนดหน้าที่เปิดก่อนและบริบทเริ่มต้นหลังเข้าสู่ระบบ</p></div></div></div>
          <div class="grid gap-5 p-4 sm:p-5">
            <div class="rounded-2xl border border-sky-200 bg-gradient-to-r from-sky-50 to-emerald-50 p-4"><div class="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between"><div class="flex items-center gap-3"><span class="flex h-11 w-11 items-center justify-center rounded-2xl bg-white text-sky-700 shadow-sm"><Building2 size={21} /></span><div><p class="text-xs font-medium text-slate-500">Tenant ปัจจุบัน</p><p class="mt-0.5 text-sm font-semibold text-slate-950">{$tenantContext.activeTenant?.name ?? '—'}</p></div></div><span class="inline-flex w-fit items-center gap-1.5 rounded-full border border-emerald-200 bg-white px-3 py-1.5 text-xs font-semibold text-emerald-700"><CheckCircle2 size={14} /> Active membership</span></div></div>
            <div class="grid gap-4 sm:grid-cols-2">
              <label><span class="text-sm font-medium text-slate-700">OU เริ่มต้น</span><select class="app-input mt-2" bind:value={defaultOuId} disabled={settingsLoading}><option value="">ไม่กำหนด</option>{#each managedOus as ou}<option value={ou.id}>{ou.name}</option>{/each}</select><span class="mt-2 block text-xs text-slate-500">เลือกได้เฉพาะ OU ที่บัญชีเข้าถึงใน Tenant ปัจจุบัน</span></label>
              <label><span class="text-sm font-medium text-slate-700">หน้าเริ่มต้น</span><select class="app-input mt-2" bind:value={landingPage}><option value="/app/dashboard">แดชบอร์ด</option><option value="/app/organization">องค์กร/หน่วยงาน</option><option value="/app/submissions">ส่งข้อมูลรายสัปดาห์</option><option value="/app/reports">รายงาน</option></select></label>
              <label><span class="text-sm font-medium text-slate-700">ภาษา</span><div class="relative mt-2"><Languages class="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" size={16} /><select class="app-input pl-10" bind:value={language}><option value="th">ไทย</option><option value="en">English</option></select></div></label>
              <div class="rounded-2xl border border-slate-200 bg-slate-50 p-4"><p class="text-sm font-medium text-slate-700">Tenant อื่น</p><p class="mt-1 text-xs leading-5 text-slate-500">เมื่อมีหลาย membership ระบบจะแสดง Tenant Switcher ในแถบด้านบน</p></div>
            </div>
          </div>
          <div class="flex justify-end border-t border-slate-100 bg-slate-50/60 p-4 sm:px-5"><button type="button" class="app-button-primary app-focus inline-flex items-center justify-center gap-2" disabled={settingsSaving || settingsLoading} on:click={savePreferences}><Save size={16} /> บันทึกพื้นที่ทำงาน</button></div>
        </article>
      {:else if activeSection === 'notifications'}
        <article class="app-card overflow-hidden">
          <div class="border-b border-slate-100 p-4 sm:p-5"><div class="flex items-start gap-3"><span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-amber-50 text-amber-700"><Bell size={21} /></span><div><h2 class="app-section-title">การแจ้งเตือน</h2><p class="app-section-copy">เลือกเหตุการณ์ใน OU ที่คุณดูแลและช่องทางที่ต้องการรับ</p></div></div></div>
          <div class="divide-y divide-slate-100 px-4 sm:px-5">
            <label class="flex cursor-pointer items-start justify-between gap-4 py-4"><span><span class="block text-sm font-semibold text-slate-900">OU ยังไม่ส่งข้อมูล</span><span class="mt-1 block text-xs leading-5 text-slate-500">แจ้งเตือนเมื่อ OU ภายใต้เขต 1 ยังไม่ส่งก่อนปิดรอบ</span></span><input class="mt-1 h-5 w-5 shrink-0 accent-sky-600" type="checkbox" bind:checked={notifyMissing} /></label>
            <label class="flex cursor-pointer items-start justify-between gap-4 py-4"><span><span class="block text-sm font-semibold text-slate-900">มีการส่งข้อมูลใหม่</span><span class="mt-1 block text-xs leading-5 text-slate-500">รับทราบเมื่อสมาชิกส่งรายงานใน Subtree</span></span><input class="mt-1 h-5 w-5 shrink-0 accent-sky-600" type="checkbox" bind:checked={notifySubmitted} /></label>
            <label class="flex cursor-pointer items-start justify-between gap-4 py-4"><span><span class="block text-sm font-semibold text-slate-900">ผลการอนุมัติ</span><span class="mt-1 block text-xs leading-5 text-slate-500">ต้องมี role Approver แยกต่างหากจึงจะดำเนินการอนุมัติได้</span></span><input class="mt-1 h-5 w-5 shrink-0 accent-sky-600" type="checkbox" bind:checked={notifyApproval} /></label>
            <label class="flex cursor-pointer items-start justify-between gap-4 py-4"><span><span class="flex items-center gap-2 text-sm font-semibold text-slate-900"><Mail size={16} /> ส่งสำเนาทางอีเมล</span><span class="mt-1 block text-xs leading-5 text-slate-500">ค่าเริ่มต้นจะส่งผ่าน LINE เท่านั้น</span></span><input class="mt-1 h-5 w-5 shrink-0 accent-sky-600" type="checkbox" bind:checked={notifyEmail} /></label>
          </div>
          <div class="flex justify-end border-t border-slate-100 bg-slate-50/60 p-4 sm:px-5"><button type="button" class="app-button-primary app-focus inline-flex items-center justify-center gap-2" disabled={settingsSaving || settingsLoading} on:click={savePreferences}><Save size={16} /> บันทึกการแจ้งเตือน</button></div>
        </article>
      {:else if activeSection === 'ou-operations'}
        <div class="space-y-4">
          <article class="app-card overflow-hidden">
            <div class="border-b border-slate-100 p-4 sm:p-5"><div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between"><div class="flex items-start gap-3"><span class="flex h-11 w-11 shrink-0 items-center justify-center rounded-2xl bg-emerald-50 text-emerald-700"><ListTree size={21} /></span><div><h2 class="app-section-title">OU ที่เข้าถึงได้</h2><p class="app-section-copy">ข้อมูลจากโครงสร้างของ {$tenantContext.activeTenant?.name ?? 'Tenant ปัจจุบัน'}</p></div></div><span class="inline-flex w-fit items-center gap-1.5 rounded-full border border-emerald-200 bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-700"><MapPin size={14} /> {enabledOuCount}/{managedOus.length} เปิดรับข้อมูล</span></div></div>
            <div class="divide-y divide-slate-100">
              {#each managedOus as ou}
                <article class="flex flex-col gap-3 p-4 sm:flex-row sm:items-center sm:justify-between sm:p-5">
                  <div class="flex min-w-0 items-center gap-3"><span class={`flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl ${ou.allowDataEntry ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-500'}`}><Building2 size={19} /></span><div class="min-w-0"><p class="truncate text-sm font-semibold text-slate-900">{ou.name}</p><p class="mt-0.5 truncate text-xs text-slate-500">ประเภท {ou.type}</p></div></div>
                  <div class="flex items-center justify-between gap-4 rounded-2xl border border-slate-200 bg-slate-50/70 px-3.5 py-2.5 sm:min-w-52"><span><span class="block text-xs font-semibold text-slate-700">{ou.allowDataEntry ? 'เปิดรับข้อมูล' : 'ใช้ข้อมูลรวม'}</span><span class="block text-[0.68rem] text-slate-400">{ou.allowDataEntry ? 'ส่งรายงานได้โดยตรง' : 'รวมจาก OU ลูก'}</span></span><span class={`h-3 w-3 rounded-full ${ou.allowDataEntry ? 'bg-emerald-500' : 'bg-slate-300'}`}></span></div>
                </article>
              {/each}
            </div>
            <div class="flex flex-col gap-3 border-t border-slate-100 bg-slate-50/60 p-4 sm:flex-row sm:items-center sm:justify-between sm:px-5"><p class="text-xs leading-5 text-slate-500">ชื่อ รหัส ประเภท และสมาชิกของ OU จัดการต่อในหน้าองค์กร/หน่วยงาน</p><a class="app-button-secondary app-focus inline-flex items-center justify-center gap-2" href="/app/organization">เปิดหน้าองค์กร <ChevronRight size={16} /></a></div>
          </article>
          <div class="app-card flex gap-3 p-4 sm:p-5"><Info class="mt-0.5 shrink-0 text-sky-700" size={19} /><div><p class="text-sm font-semibold text-slate-900">OU Type เป็นค่าแบบอ่านอย่างเดียว</p><p class="mt-1 text-xs leading-5 text-slate-500">OU Manager เลือกใช้ประเภทที่ Root Admin กำหนดไว้ได้ แต่สร้าง เปลี่ยนชื่อ หรือปิดประเภทไม่ได้</p></div></div>
        </div>
      {:else}
        <div class="space-y-4">
          <article class="app-card overflow-hidden">
            <div class="border-b border-slate-100 p-4 sm:p-5"><h2 class="app-section-title">สมาชิกและ Invite Link ของ Tenant นี้</h2><p class="app-section-copy">สิทธิ์จริงจะถูกตรวจจาก Tenant และ OU ปัจจุบันโดย Backend</p></div>
            <div class="grid gap-3 p-4 sm:p-5">
              {#each accessSettings as item}
                {@const Icon = item.icon}
                <a class="app-focus flex gap-3 rounded-2xl border border-sky-200 bg-sky-50 p-4 transition hover:bg-sky-100" href={item.href}>
                  <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-white text-sky-700 shadow-sm"><Icon size={18} /></span>
                  <span class="min-w-0 flex-1"><span class="block text-sm font-semibold text-sky-950">{item.label}</span><span class="mt-1 block text-xs leading-5 text-sky-800">{item.detail}</span></span>
                  <ChevronRight class="mt-2 shrink-0 text-sky-600" size={17} />
                </a>
              {/each}
            </div>
          </article>
          <article class="app-card overflow-hidden">
            <div class="relative bg-gradient-to-br from-slate-950 via-sky-950 to-teal-900 p-5 text-white sm:p-6"><div class="pointer-events-none absolute right-0 top-0 h-44 w-44 rounded-full bg-sky-400/15 blur-3xl"></div><div class="relative flex items-start gap-4"><span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-white/10 text-emerald-200 ring-1 ring-white/15"><ShieldCheck size={24} /></span><div><p class="text-xs font-semibold uppercase tracking-[0.18em] text-emerald-300">Effective access</p><h2 class="mt-1 text-xl font-semibold">{$tenantContext.activeTenant?.name ?? 'Tenant ปัจจุบัน'}</h2><p class="mt-2 max-w-xl text-sm leading-6 text-slate-300">ทุกการสร้าง Invite Link และการจัดการ OU จะตรวจ role และ subtree ของบัญชีปัจจุบันจาก Backend</p></div></div></div>
            <div class="grid gap-3 p-4 sm:grid-cols-2 sm:p-5">
              <div class="rounded-2xl border border-emerald-200 bg-emerald-50 p-4"><p class="flex items-center gap-2 text-sm font-semibold text-emerald-900"><CheckCircle2 size={17} /> ทำได้ใน Subtree</p><ul class="mt-3 space-y-2 text-xs leading-5 text-emerald-800"><li>• สร้างและแก้ไข Child OU</li><li>• เปิด–ปิดการรับข้อมูลของ OU</li><li>• Assign/Remove LINE Account</li><li>• กำหนด manager, data_entry, approver, viewer</li></ul></div>
              <div class="rounded-2xl border border-amber-200 bg-amber-50 p-4"><p class="flex items-center gap-2 text-sm font-semibold text-amber-900"><LockKeyhole size={17} /> ไม่ได้มาจาก role Manager</p><ul class="mt-3 space-y-2 text-xs leading-5 text-amber-800"><li>• อนุมัติหรือ Override workflow</li><li>• มอบ role admin</li><li>• แก้ OU แม่หรือ OU นอกเขต 1</li><li>• เปลี่ยน Tenant-wide settings</li></ul></div>
            </div>
          </article>
          <article class="app-card overflow-hidden">
            <div class="border-b border-slate-100 p-4 sm:p-5"><h2 class="app-section-title">ตั้งค่าที่สงวนสำหรับ Root OU Admin</h2><p class="app-section-copy">ต้องเป็น Admin ที่ได้รับมอบหมายโดยตรงบน Root OU Level 1 เท่านั้น สิทธิ์จาก Manager หรือการสืบทอดสิทธิ์ไม่เพียงพอ</p></div>
            <div class="grid gap-3 p-4 sm:grid-cols-2 sm:p-5">
              {#each rootOnlySettings as item}
                {@const Icon = item.icon}
                <div class="flex gap-3 rounded-2xl border border-slate-200 bg-slate-50/70 p-4">
                  <span class="flex h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-white text-slate-500 shadow-sm"><Icon size={18} /></span>
                  <div class="min-w-0 flex-1">
                    <p class="flex items-center gap-1.5 text-sm font-semibold text-slate-800">{item.label}{#if !hasDirectRootAdminAssignment}<LockKeyhole class="shrink-0 text-slate-400" size={13} />{/if}</p>
                    <p class="mt-1 text-xs leading-5 text-slate-500">{item.detail}</p>
                    {#if item.href && hasDirectRootAdminAssignment}
                      <a class="app-focus mt-3 inline-flex items-center gap-1.5 text-xs font-semibold text-sky-700 hover:text-sky-900" href={item.href}>เปิด Tenant Settings <ChevronRight size={14} /></a>
                    {:else if item.href}
                      <p class="mt-3 inline-flex items-center gap-1.5 text-xs font-semibold text-amber-700"><LockKeyhole size={13} /> ต้องมี Direct Root Admin</p>
                    {:else}
                      <p class="mt-3 inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500"><CalendarClock size={13} /> ยังไม่เปิดใช้งาน</p>
                    {/if}
                  </div>
                </div>
              {/each}
            </div>
          </article>
        </div>
      {/if}
    </section>
  </div>

  {#if toastMessage}
    <div class="fixed bottom-20 right-4 z-40 max-w-sm rounded-2xl border border-emerald-200 bg-white px-4 py-3 shadow-xl md:bottom-5" role="status"><div class="flex gap-3"><CheckCircle2 class="mt-0.5 shrink-0 text-emerald-600" size={18} /><div><p class="text-sm font-semibold text-slate-900">บันทึกแล้ว</p><p class="mt-0.5 text-xs leading-5 text-slate-600">{toastMessage}</p></div><button class="ml-auto text-slate-400" type="button" aria-label="ปิดข้อความ" on:click={() => (toastMessage = '')}><X size={16} /></button></div></div>
  {/if}
</div>
