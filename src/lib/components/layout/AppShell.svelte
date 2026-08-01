<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import AppHeader from '$lib/components/layout/AppHeader.svelte';
  import AppSidebar from '$lib/components/layout/AppSidebar.svelte';
  import MobileBottomNav from '$lib/components/layout/MobileBottomNav.svelte';
  import { APP_NAV_ITEMS } from '$lib/constants/routes';
  import { getPendingEditRequestCount } from '$lib/api/approvalApi';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';
  import {
    initializeTenantContext,
    selectActiveTenant,
    tenantContext
  } from '$lib/stores/tenantContext';

  let mobileMenuOpen = false;
  let sidebarCollapsed = false;
  let editRequestCount = 0;
  let notificationTenantId = '';

  $: navItems = APP_NAV_ITEMS.map((item) => item.href === '/app/approval' ? { ...item, badgeCount: editRequestCount } : item);
  $: if ($tenantContext.status === 'ready' && $tenantContext.activeTenant?.tenant_id !== notificationTenantId) {
    notificationTenantId = $tenantContext.activeTenant?.tenant_id ?? '';
    void refreshEditRequestCount();
  }

  async function refreshEditRequestCount(): Promise<void> {
    try { editRequestCount = await getPendingEditRequestCount(getSupabaseBrowserClient()); }
    catch { editRequestCount = 0; }
  }

  $: shellContext = {
    churchName: $tenantContext.activeTenant?.name ?? 'กำลังโหลด Tenant...',
    periodLabel: $tenantContext.activeTenant?.slug ?? '',
    userName: $tenantContext.userName || 'LINE User'
  };

  function openMobileMenu(): void {
    mobileMenuOpen = true;
  }

  function closeMobileMenu(): void {
    mobileMenuOpen = false;
  }

  function toggleSidebar(): void {
    sidebarCollapsed = !sidebarCollapsed;
  }

  async function changeTenant(event: Event): Promise<void> {
    const tenantId = (event.currentTarget as HTMLSelectElement).value;
    if (!tenantId || tenantId === $tenantContext.activeTenant?.tenant_id) return;
    await selectActiveTenant(tenantId);
    location.reload();
  }

  onMount(() => {
    window.addEventListener('edit-request-count-changed', refreshEditRequestCount);
    void initializeTenantContext().catch((error) => {
      if (error instanceof Error && error.message.includes('AUTH_REQUIRED')) {
        void goto('/');
      }
    });
    return () => window.removeEventListener('edit-request-count-changed', refreshEditRequestCount);
  });
</script>

<div class="app-surface min-h-screen">
  <AppHeader
    context={shellContext}
    onMenuClick={openMobileMenu}
    {sidebarCollapsed}
    onSidebarToggle={toggleSidebar}
  />

  {#if $tenantContext.status === 'ready'}
  <div class="mx-auto flex min-h-[calc(100vh-4rem)] max-w-7xl gap-3 px-2 py-2 sm:px-3 lg:px-4">
    <aside class={`sticky top-16 hidden h-[calc(100vh-4rem)] shrink-0 rounded-[1.35rem] border border-sky-100/80 bg-white/80 p-2.5 shadow-[0_16px_40px_rgba(15,23,42,0.07)] backdrop-blur transition-all duration-300 md:flex md:flex-col ${sidebarCollapsed ? 'w-20' : 'w-64'}`}>
      <div class={`mb-3 rounded-2xl border border-sky-100 bg-gradient-to-br from-sky-50 via-white to-emerald-50 p-3 ${sidebarCollapsed ? 'text-center' : ''}`}>
        <p class="text-[0.65rem] font-semibold uppercase tracking-[0.25em] text-sky-700">{sidebarCollapsed ? 'CSMS' : 'พื้นที่ทำงาน'}</p>
        {#if !sidebarCollapsed}
          <p class="mt-1 truncate text-sm font-semibold text-slate-950">{shellContext.churchName}</p>
          <p class="mt-1 truncate text-xs text-slate-500">{shellContext.periodLabel}</p>
          {#if $tenantContext.tenants.length > 1}
            <label class="mt-3 block">
              <span class="sr-only">เปลี่ยน Tenant</span>
              <select class="app-input min-h-9 py-1.5 text-xs" value={$tenantContext.activeTenant?.tenant_id} on:change={changeTenant}>
                {#each $tenantContext.tenants as tenant}
                  <option value={tenant.tenant_id}>{tenant.name}</option>
                {/each}
              </select>
            </label>
          {/if}
        {/if}
      </div>
      <AppSidebar items={navItems} collapsed={sidebarCollapsed} />
    </aside>

    <main class="min-w-0 flex-1 rounded-[1.4rem] border border-white/70 bg-white/60 px-3 py-4 pb-24 shadow-[0_16px_45px_rgba(15,23,42,0.05)] backdrop-blur sm:px-4 md:px-6 md:py-6 md:pb-8 lg:px-8">
      <slot />
    </main>
  </div>

  <MobileBottomNav items={navItems} />
  {:else if $tenantContext.status === 'error'}
    <main class="mx-auto flex min-h-[calc(100vh-4rem)] max-w-xl items-center px-4">
      <section class="app-card w-full p-6 text-center">
        <h1 class="text-lg font-semibold text-slate-950">ไม่สามารถเปิดพื้นที่ทำงานได้</h1>
        <p class="mt-3 text-sm leading-6 text-rose-700">{$tenantContext.error}</p>
        <button type="button" class="app-button-primary mt-5" on:click={() => goto('/')}>กลับไปหน้าเข้าสู่ระบบ</button>
      </section>
    </main>
  {:else}
    <main class="mx-auto flex min-h-[calc(100vh-4rem)] max-w-xl items-center justify-center px-4">
      <p class="text-sm font-medium text-slate-500">กำลังโหลด Tenant และสิทธิ์ของบัญชี...</p>
    </main>
  {/if}

  {#if mobileMenuOpen}
    <div class="fixed inset-0 z-40 md:hidden" role="presentation">
      <button
        type="button"
        class="absolute inset-0 h-full w-full bg-slate-950/45"
        aria-label="Close navigation"
        on:click={closeMobileMenu}
      ></button>

      <aside class="absolute inset-y-0 left-0 w-[min(20rem,88vw)] rounded-r-[1.5rem] border-r border-slate-200 bg-white p-4 shadow-2xl">
        <div class="mb-6 flex items-start justify-between gap-3">
          <div class="min-w-0">
            <p class="text-sm font-semibold text-slate-950">CSMS</p>
            <p class="truncate text-xs text-slate-500">{shellContext.churchName}</p>
          </div>
          <button type="button" class="app-button-secondary min-h-0 px-3 py-1.5" on:click={closeMobileMenu}>
            ปิด
          </button>
        </div>

        <AppSidebar items={navItems} onNavigate={closeMobileMenu} />
      </aside>
    </div>
  {/if}
</div>
