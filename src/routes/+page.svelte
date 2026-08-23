<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import {
    ArrowRight,
    Building2,
    CheckCircle2,
    LoaderCircle,
    LogIn,
    ShieldCheck,
    Smartphone,
    TriangleAlert
  } from '@lucide/svelte';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';
  import { getMyPreferences, listMyTenants } from '$lib/api/identityApi';
  import { extractInviteToken } from '$lib/auth/inviteToken';
  import { extractSafeAppRedirectPath } from '$lib/auth/liffConfig';
  import {
    exchangeLineSession,
    initializeLiff,
    switchLineTenant,
    type LineTenantOption
  } from '$lib/auth/lineAuth';
  import type { Liff } from '@line/liff';

  type LoginState =
    | 'initializing'
    | 'ready'
    | 'authenticating'
    | 'select-tenant'
    | 'no-tenant'
    | 'error';

  let state: LoginState = 'initializing';
  let errorMessage = '';
  let displayName = '';
  let tenantOptions: LineTenantOption[] = [];
  let selectedTenantId = '';
  let liffClient: Liff | undefined;
  let inviteToken = '';
  let nextPath = '';

  function readableError(error: unknown): string {
    const message = error instanceof Error ? error.message : 'เกิดข้อผิดพลาดระหว่างเข้าสู่ระบบ';
    if (message.includes('LINE_TOKEN_EXPIRED')) return 'LINE session หมดอายุ กรุณาเข้าสู่ระบบใหม่';
    if (message.includes('LINE_TOKEN_INVALID')) return 'LINE session ไม่ถูกต้องหรือหมดอายุ กรุณาเข้าสู่ระบบใหม่';
    if (message.includes('ORIGIN_NOT_ALLOWED')) return 'URL นี้ยังไม่ได้รับอนุญาตให้เรียก Backend';
    if (message.includes('Failed to send a request')) return 'ไม่สามารถเชื่อมต่อ Supabase Edge Function ได้ กรุณาลองอีกครั้ง';
    return message;
  }

  async function preferredLandingPage(): Promise<string> {
    try { return (await getMyPreferences(getSupabaseBrowserClient())).landingPage; }
    catch { return '/app/dashboard'; }
  }

  async function authenticatedLandingPage(): Promise<string> {
    return nextPath || preferredLandingPage();
  }

  async function finishLineAuthentication(): Promise<void> {
    if (!liffClient) return;
    state = 'authenticating';
    errorMessage = '';
    try {
      const decoded = liffClient.getDecodedIDToken();
      displayName = decoded?.name ?? 'LINE User';
      const result = await exchangeLineSession(
        getSupabaseBrowserClient(),
        liffClient,
        inviteToken || undefined
      );
      tenantOptions = result.tenants;

      if (result.activeTenantId) {
        await goto(await authenticatedLandingPage());
        return;
      }
      if (tenantOptions.length > 1 || result.requiresTenantSelection) {
        selectedTenantId = tenantOptions[0]?.tenantId ?? '';
        state = 'select-tenant';
        return;
      }
      state = 'no-tenant';
    } catch (error) {
      if (error instanceof Error && error.message.includes('LINE_TOKEN_EXPIRED') && liffClient) {
        liffClient.logout();
        liffClient.login({
          redirectUri: `${window.location.origin}${window.location.pathname}${window.location.search}`
        });
        return;
      }
      errorMessage = readableError(error);
      state = 'error';
    }
  }

  function startLineLogin(): void {
    if (!liffClient) return;
    if (liffClient.isLoggedIn()) {
      void finishLineAuthentication();
      return;
    }
    liffClient.login({
      redirectUri: `${window.location.origin}${window.location.pathname}${window.location.search}`
    });
  }

  async function chooseTenant(): Promise<void> {
    if (!selectedTenantId) return;
    state = 'authenticating';
    errorMessage = '';
    try {
      await switchLineTenant(getSupabaseBrowserClient(), selectedTenantId);
      await goto(await authenticatedLandingPage());
    } catch (error) {
      errorMessage = readableError(error);
      state = 'error';
    }
  }

  async function initializeLogin(): Promise<void> {
    try {
      nextPath = extractSafeAppRedirectPath(window.location.search);
      inviteToken = extractInviteToken(window.location.search);
      const client = getSupabaseBrowserClient();
      const { data: sessionData } = await client.auth.getSession();
      const existingUser = sessionData.session?.user;
      if (!inviteToken && existingUser?.app_metadata?.auth_provider === 'line') {
        displayName =
          (existingUser.user_metadata?.name as string | undefined) ??
          (existingUser.user_metadata?.display_name as string | undefined) ??
          'LINE User';
        const memberships = await listMyTenants(client);
        const current = memberships.find((tenant) => tenant.is_current);
        if (current) {
          await goto(await authenticatedLandingPage());
          return;
        }
        if (memberships.length > 1) {
          tenantOptions = memberships.map((tenant) => ({
            tenantId: tenant.tenant_id,
            slug: tenant.slug,
            name: tenant.name
          }));
          selectedTenantId = tenantOptions[0]?.tenantId ?? '';
          state = 'select-tenant';
          return;
        }
        if (memberships.length === 0) {
          state = 'no-tenant';
          return;
        }
      }

      liffClient = await initializeLiff();
      nextPath = extractSafeAppRedirectPath(window.location.search) || nextPath;
      if (liffClient.isLoggedIn()) {
        await finishLineAuthentication();
      } else {
        state = 'ready';
      }
    } catch (error) {
      errorMessage = readableError(error);
      state = 'error';
    }
  }

  async function resetLineLogin(): Promise<void> {
    await getSupabaseBrowserClient().auth.signOut();
    if (liffClient?.isLoggedIn()) liffClient.logout();
    location.reload();
  }

  onMount(() => {
    void initializeLogin();
  });
</script>

<svelte:head>
  <title>เข้าสู่ระบบ | CSMS</title>
  <meta
    name="description"
    content="เข้าสู่ระบบ Church Statistics Management System ด้วยบัญชี LINE"
  />
</svelte:head>

<main class="app-surface relative flex min-h-screen items-center justify-center overflow-hidden px-4 py-10">
  <div class="pointer-events-none absolute -left-24 top-12 h-72 w-72 rounded-full bg-sky-300/20 blur-3xl"></div>
  <div class="pointer-events-none absolute -right-24 bottom-12 h-72 w-72 rounded-full bg-emerald-300/20 blur-3xl"></div>

  <section class="app-card relative w-full max-w-md overflow-hidden">
    <div class="bg-gradient-to-br from-sky-700 via-sky-700 to-teal-700 px-6 py-7 text-white sm:px-8">
      <div class="flex items-center gap-3">
        <span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-white/15 ring-1 ring-white/20">
          <ShieldCheck size={24} />
        </span>
        <div>
          <p class="text-xs font-semibold uppercase tracking-[0.22em] text-sky-100">CSMS</p>
          <h1 class="mt-1 text-xl font-semibold">Church Statistics</h1>
        </div>
      </div>
      <p class="mt-5 text-sm leading-6 text-sky-50">
        เข้าสู่ระบบด้วยบัญชี LINE ที่ได้รับสิทธิ์จากคริสตจักรของคุณ
      </p>
    </div>

    <div class="p-6 sm:p-8">
      {#if state === 'initializing'}
        <div class="py-8 text-center" aria-live="polite">
          <LoaderCircle class="mx-auto animate-spin text-sky-600" size={30} />
          <p class="mt-4 text-sm font-semibold text-slate-800">กำลังเตรียม LINE Login</p>
          <p class="mt-1 text-xs text-slate-500">ตรวจสอบ LIFF และ Supabase session...</p>
        </div>
      {:else if state === 'ready'}
        <div class="text-center">
          <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-3xl bg-emerald-50 text-emerald-600 ring-1 ring-emerald-200">
            <Smartphone size={29} />
          </span>
          <h2 class="mt-5 text-lg font-semibold text-slate-950">พร้อมเข้าสู่ระบบ</h2>
          <p class="mt-2 text-sm leading-6 text-slate-500">
            ระบบจะยืนยันตัวตนกับ LINE แล้วสร้าง session สำหรับ CSMS
          </p>
          <button
            type="button"
            class="app-button-primary app-focus mt-6 inline-flex w-full items-center justify-center gap-2"
            on:click={startLineLogin}
          >
            <LogIn size={18} /> เข้าสู่ระบบด้วย LINE
          </button>
        </div>
      {:else if state === 'authenticating'}
        <div class="py-8 text-center" aria-live="polite">
          <LoaderCircle class="mx-auto animate-spin text-emerald-600" size={30} />
          <p class="mt-4 text-sm font-semibold text-slate-800">กำลังยืนยันบัญชี LINE</p>
          <p class="mt-1 text-xs text-slate-500">เชื่อมบัญชีและตรวจสอบสิทธิ์ Tenant...</p>
        </div>
      {:else if state === 'select-tenant'}
        <div>
          <span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-sky-50 text-sky-700">
            <Building2 size={23} />
          </span>
          <h2 class="mt-4 text-lg font-semibold text-slate-950">เลือก Tenant</h2>
          <p class="mt-1 text-sm text-slate-500">{displayName} มีสิทธิ์มากกว่าหนึ่งองค์กร</p>
          <label class="mt-5 block">
            <span class="text-sm font-medium text-slate-700">องค์กรที่ต้องการใช้งาน</span>
            <select class="app-input mt-2" bind:value={selectedTenantId}>
              {#each tenantOptions as tenant}
                <option value={tenant.tenantId}>{tenant.name}</option>
              {/each}
            </select>
          </label>
          <button
            type="button"
            class="app-button-primary mt-5 inline-flex w-full items-center justify-center gap-2"
            on:click={chooseTenant}
          >
            ใช้งาน Tenant นี้ <ArrowRight size={17} />
          </button>
        </div>
      {:else if state === 'no-tenant'}
        <div class="text-center">
          <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-3xl bg-amber-50 text-amber-700 ring-1 ring-amber-200">
            <Building2 size={28} />
          </span>
          <h2 class="mt-5 text-lg font-semibold text-slate-950">เข้าสู่ระบบสำเร็จ</h2>
          <p class="mt-2 text-sm font-medium text-slate-700">{displayName}</p>
          <p class="mt-3 text-sm leading-6 text-slate-500">
            บัญชี LINE นี้ยังไม่มีสิทธิ์ใน Tenant กรุณาขอ Invite Link จากผู้ดูแล แล้วเปิดลิงก์ผ่าน LINE
          </p>
          <div class="mt-5 flex items-start gap-2 rounded-2xl border border-sky-200 bg-sky-50 p-3 text-left text-xs leading-5 text-sky-800">
            <CheckCircle2 class="mt-0.5 shrink-0" size={16} />
            <span>บัญชีถูกสร้างในระบบแล้ว ผู้ดูแลสามารถ Assign บัญชีนี้ให้ Tenant และ Root OU ได้</span>
          </div>
          <button type="button" class="app-button-secondary mt-5 w-full" on:click={resetLineLogin}>
            ใช้บัญชี LINE อื่น
          </button>
        </div>
      {:else}
        <div class="text-center" role="alert">
          <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-3xl bg-rose-50 text-rose-700 ring-1 ring-rose-200">
            <TriangleAlert size={28} />
          </span>
          <h2 class="mt-5 text-lg font-semibold text-slate-950">เข้าสู่ระบบไม่สำเร็จ</h2>
          <p class="mt-3 rounded-2xl bg-rose-50 px-4 py-3 text-sm leading-6 text-rose-700">
            {errorMessage}
          </p>
          <button type="button" class="app-button-secondary mt-5 w-full" on:click={() => location.reload()}>
            ลองอีกครั้ง
          </button>
        </div>
      {/if}

      <div class="mt-7 border-t border-slate-100 pt-5 text-center">
        <p class="text-[0.68rem] leading-5 text-slate-400">
          การเข้าสู่ระบบจะใช้ LINE ID token เพื่อยืนยันตัวตนกับ Backend เท่านั้น
        </p>
      </div>
    </div>
  </section>
</main>
