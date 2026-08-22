<script lang="ts">
  import { onDestroy, onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { browser } from '$app/environment';
  import { env } from '$env/dynamic/public';
  import {
    Bell,
    BellOff,
    Check,
    CheckCheck,
    ChevronRight,
    Inbox,
    LoaderCircle,
    RefreshCw,
    ShieldCheck,
    TriangleAlert,
    UserPlus,
    X
  } from '@lucide/svelte';
  import {
    archiveNotification,
    getUnreadNotificationCount,
    listNotifications,
    markAllNotificationsRead,
    markNotificationRead,
    type NotificationItem
  } from '$lib/api/notificationApi';
  import { safeNotificationDeepLink } from '$lib/notifications/notificationLinks';
  import { buildLineOaAddFriendUrl } from '$lib/notifications/lineOa';
  import { initializeLiff } from '$lib/auth/lineAuth';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';

  export let tenantId = '';

  let open = false;
  let loading = false;
  let mutating = false;
  let errorMessage = '';
  let items: NotificationItem[] = [];
  let unreadCount = 0;
  let loadedTenantId = '';
  let loadSequence = 0;
  let panel: HTMLElement | null = null;
  let trigger: HTMLButtonElement | null = null;
  let friendshipStatus: 'checking' | 'friend' | 'not_friend' | 'unavailable' = 'checking';
  let friendshipBusy = false;
  const lineOaAddFriendUrl = buildLineOaAddFriendUrl(env.PUBLIC_LINE_MESSAGING_OA_BASIC_ID);

  $: if (tenantId !== loadedTenantId) {
    loadedTenantId = tenantId;
    open = false;
    items = [];
    unreadCount = 0;
    errorMessage = '';
    if (tenantId) void refresh(false);
  }

  $: badgeLabel = unreadCount > 99 ? '99+' : String(unreadCount);

  function readableError(error: unknown): string {
    const message = error instanceof Error ? error.message : '';
    if (message.includes('AUTH') || message.includes('JWT')) return 'Session หมดอายุ กรุณาเข้าสู่ระบบใหม่';
    return 'โหลดการแจ้งเตือนไม่สำเร็จ กรุณาลองอีกครั้ง';
  }

  async function refresh(showLoading = true): Promise<void> {
    if (!tenantId) return;
    const requestedTenantId = tenantId;
    const sequence = ++loadSequence;
    if (showLoading) loading = true;
    errorMessage = '';
    try {
      const client = getSupabaseBrowserClient();
      const [page, count] = await Promise.all([
        listNotifications(client, { limit: 50 }),
        getUnreadNotificationCount(client)
      ]);
      if (sequence !== loadSequence || requestedTenantId !== tenantId) return;
      items = page.items;
      unreadCount = count;
    } catch (error) {
      if (sequence !== loadSequence || requestedTenantId !== tenantId) return;
      errorMessage = readableError(error);
    } finally {
      if (sequence === loadSequence) loading = false;
    }
  }

  async function toggle(): Promise<void> {
    open = !open;
    if (open) {
      await refresh(items.length === 0);
      requestAnimationFrame(() => panel?.focus());
    }
  }

  function close(restoreFocus = false): void {
    open = false;
    if (restoreFocus) requestAnimationFrame(() => trigger?.focus());
  }

  async function read(item: NotificationItem): Promise<void> {
    if (item.readAt) return;
    const result = await markNotificationRead(getSupabaseBrowserClient(), item.id);
    items = items.map((entry) => entry.id === item.id ? { ...entry, readAt: result.readAt } : entry);
    unreadCount = Math.max(0, unreadCount - 1);
  }

  async function openNotification(item: NotificationItem): Promise<void> {
    const deepLink = safeNotificationDeepLink(item.deepLink);
    try {
      await read(item);
      close();
      if (deepLink) await goto(deepLink);
    } catch (error) {
      errorMessage = readableError(error);
    }
  }

  async function markAll(): Promise<void> {
    if (mutating || unreadCount === 0) return;
    mutating = true;
    errorMessage = '';
    try {
      await markAllNotificationsRead(getSupabaseBrowserClient());
      const readAt = new Date().toISOString();
      items = items.map((item) => item.readAt ? item : { ...item, readAt });
      unreadCount = 0;
    } catch (error) {
      errorMessage = readableError(error);
    } finally {
      mutating = false;
    }
  }

  async function archive(item: NotificationItem, event: MouseEvent): Promise<void> {
    event.stopPropagation();
    if (mutating) return;
    mutating = true;
    errorMessage = '';
    try {
      await archiveNotification(getSupabaseBrowserClient(), item.id);
      items = items.filter((entry) => entry.id !== item.id);
      if (!item.readAt) unreadCount = Math.max(0, unreadCount - 1);
    } catch (error) {
      errorMessage = readableError(error);
    } finally {
      mutating = false;
    }
  }

  function eventLabel(item: NotificationItem): string {
    if (item.eventType === 'missing_submission_reminder') return 'เตือนส่งรายงาน';
    if (item.eventType === 'pending_approval_digest' || item.eventType.includes('approval')) return 'การอนุมัติ';
    if (item.eventType === 'ou_assignment_created') return 'สิทธิ์การเข้าถึง';
    if (item.eventType.includes('edit_request')) return 'คำขอแก้ไข';
    return 'รายงานประจำสัปดาห์';
  }

  function relativeTime(value: string): string {
    const elapsed = Date.now() - new Date(value).getTime();
    if (!Number.isFinite(elapsed) || elapsed < 0) return 'เมื่อสักครู่';
    const minutes = Math.floor(elapsed / 60_000);
    if (minutes < 1) return 'เมื่อสักครู่';
    if (minutes < 60) return `${minutes} นาทีที่แล้ว`;
    const hours = Math.floor(minutes / 60);
    if (hours < 24) return `${hours} ชั่วโมงที่แล้ว`;
    return new Intl.DateTimeFormat('th-TH', { day: 'numeric', month: 'short' }).format(new Date(value));
  }

  function handleDocumentPointer(event: PointerEvent): void {
    const target = event.target as Node;
    if (open && !panel?.contains(target) && !trigger?.contains(target)) close();
  }

  function handleKeydown(event: KeyboardEvent): void {
    if (open && event.key === 'Escape') close(true);
  }

  async function refreshFriendship(): Promise<void> {
    if (!lineOaAddFriendUrl) {
      friendshipStatus = 'unavailable';
      return;
    }
    try {
      const liff = await initializeLiff();
      if (!liff.isLoggedIn()) {
        friendshipStatus = 'not_friend';
        return;
      }
      const result = await liff.getFriendship();
      friendshipStatus = result.friendFlag ? 'friend' : 'not_friend';
    } catch {
      friendshipStatus = 'not_friend';
    }
  }

  async function addLineFriend(): Promise<void> {
    if (!lineOaAddFriendUrl || friendshipBusy) return;
    friendshipBusy = true;
    try {
      const liff = await initializeLiff();
      if (liff.isInClient() && liff.isLoggedIn()) {
        await liff.requestFriendship();
        const result = await liff.getFriendship();
        friendshipStatus = result.friendFlag ? 'friend' : 'not_friend';
        return;
      }
    } catch {
      // Fall back to the official add-friend link outside a compatible LIFF client.
    } finally {
      friendshipBusy = false;
    }
    window.open(lineOaAddFriendUrl.toString(), '_blank', 'noopener,noreferrer');
  }

  if (browser) {
    document.addEventListener('pointerdown', handleDocumentPointer);
    document.addEventListener('keydown', handleKeydown);
  }

  onMount(() => {
    void refreshFriendship();
  });

  onDestroy(() => {
    loadSequence += 1;
    if (browser) {
      document.removeEventListener('pointerdown', handleDocumentPointer);
      document.removeEventListener('keydown', handleKeydown);
    }
  });
</script>

<div class="relative">
  <button
    bind:this={trigger}
    type="button"
    class="app-focus relative inline-flex h-10 w-10 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-700 shadow-sm transition hover:border-sky-200 hover:bg-sky-50 hover:text-sky-800"
    aria-label={unreadCount ? `การแจ้งเตือนที่ยังไม่ได้อ่าน ${unreadCount} รายการ` : 'การแจ้งเตือน'}
    aria-haspopup="dialog"
    aria-expanded={open}
    aria-controls="notification-center-panel"
    on:click={toggle}
  >
    <Bell size={19} aria-hidden="true" />
    {#if unreadCount > 0}
      <span class="absolute -right-1.5 -top-1.5 flex min-h-5 min-w-5 items-center justify-center rounded-full border-2 border-white bg-rose-600 px-1 text-[0.62rem] font-bold leading-none text-white">
        {badgeLabel}
      </span>
    {/if}
  </button>

  {#if open}
    <div
      bind:this={panel}
      id="notification-center-panel"
      class="fixed inset-x-3 top-[4.5rem] z-50 flex max-h-[calc(100dvh-5.25rem)] flex-col overflow-hidden rounded-[1.4rem] border border-sky-100 bg-white shadow-2xl outline-none sm:absolute sm:inset-auto sm:right-0 sm:top-12 sm:w-[24rem] sm:max-w-[calc(100vw-2rem)]"
      role="dialog"
      aria-modal="false"
      aria-labelledby="notification-center-title"
      tabindex="-1"
    >
      <header class="flex items-center justify-between gap-3 border-b border-slate-100 bg-gradient-to-r from-sky-50 to-emerald-50 px-4 py-3.5">
        <div class="min-w-0">
          <h2 id="notification-center-title" class="text-sm font-semibold text-slate-950">การแจ้งเตือน</h2>
          <p class="mt-0.5 text-xs text-slate-500">{unreadCount ? `ยังไม่ได้อ่าน ${unreadCount} รายการ` : 'อ่านครบแล้ว'}</p>
        </div>
        <div class="flex items-center gap-1">
          <button type="button" class="app-focus rounded-lg p-2 text-slate-500 hover:bg-white hover:text-sky-700" aria-label="โหลดการแจ้งเตือนใหม่" disabled={loading} on:click={() => refresh()}>
            <RefreshCw size={17} class={loading ? 'animate-spin' : ''} aria-hidden="true" />
          </button>
          <button type="button" class="app-focus rounded-lg p-2 text-slate-500 hover:bg-white hover:text-slate-900" aria-label="ปิดการแจ้งเตือน" on:click={() => close(true)}>
            <X size={18} aria-hidden="true" />
          </button>
        </div>
      </header>

      {#if items.length > 0}
        <div class="flex items-center justify-between border-b border-slate-100 px-4 py-2.5">
          <span class="text-xs text-slate-500">ล่าสุด {items.length} รายการ</span>
          <button type="button" class="app-focus inline-flex items-center gap-1.5 rounded-lg px-2 py-1.5 text-xs font-semibold text-sky-700 hover:bg-sky-50 disabled:opacity-50" disabled={mutating || unreadCount === 0} on:click={markAll}>
            <CheckCheck size={15} aria-hidden="true" /> อ่านทั้งหมด
          </button>
        </div>
      {/if}

      <div class="min-h-48 overflow-y-auto" aria-live="polite" aria-busy={loading}>
        {#if loading && items.length === 0}
          <div class="flex min-h-56 flex-col items-center justify-center px-6 text-center">
            <LoaderCircle class="animate-spin text-sky-600" size={27} aria-hidden="true" />
            <p class="mt-3 text-sm font-medium text-slate-700">กำลังโหลดการแจ้งเตือน</p>
          </div>
        {:else if errorMessage && items.length === 0}
          <div class="flex min-h-56 flex-col items-center justify-center px-6 text-center" role="alert">
            <span class="flex h-12 w-12 items-center justify-center rounded-2xl bg-rose-50 text-rose-700"><TriangleAlert size={23} /></span>
            <p class="mt-3 text-sm font-semibold text-slate-800">เปิดการแจ้งเตือนไม่สำเร็จ</p>
            <p class="mt-1 text-xs leading-5 text-slate-500">{errorMessage}</p>
            <button type="button" class="app-button-secondary mt-4 min-h-0 px-4 py-2 text-xs" on:click={() => refresh()}>ลองอีกครั้ง</button>
          </div>
        {:else if items.length === 0}
          <div class="flex min-h-56 flex-col items-center justify-center px-6 text-center">
            <span class="flex h-14 w-14 items-center justify-center rounded-3xl bg-sky-50 text-sky-600"><BellOff size={25} /></span>
            <p class="mt-4 text-sm font-semibold text-slate-800">ยังไม่มีการแจ้งเตือน</p>
            <p class="mt-1 max-w-56 text-xs leading-5 text-slate-500">เมื่อมีรายงานหรือรายการที่ต้องดำเนินการ ระบบจะแสดงที่นี่</p>
          </div>
        {:else}
          <ul class="divide-y divide-slate-100">
            {#each items as item (item.id)}
              <li class:item-unread={!item.readAt} class="group relative bg-white transition hover:bg-sky-50/70">
                <button type="button" class="app-focus flex w-full items-start gap-3 px-4 py-3.5 pr-12 text-left" on:click={() => openNotification(item)}>
                  <span class={`mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-2xl ${item.readAt ? 'bg-slate-100 text-slate-500' : 'bg-sky-100 text-sky-700'}`}>
                    {#if item.readAt}<Check size={17} />{:else}<Inbox size={17} />{/if}
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="flex items-center gap-2">
                      <span class={`truncate text-sm ${item.readAt ? 'font-medium text-slate-700' : 'font-semibold text-slate-950'}`}>{item.title}</span>
                      {#if !item.readAt}<span class="h-2 w-2 shrink-0 rounded-full bg-sky-600" aria-label="ยังไม่ได้อ่าน"></span>{/if}
                    </span>
                    <span class="mt-1 line-clamp-2 block text-xs leading-5 text-slate-500">{item.body}</span>
                    <span class="mt-2 flex items-center gap-1.5 text-[0.68rem] text-slate-400">
                      <span>{eventLabel(item)}</span><span aria-hidden="true">•</span><time datetime={item.createdAt}>{relativeTime(item.createdAt)}</time>
                    </span>
                  </span>
                  {#if safeNotificationDeepLink(item.deepLink)}<ChevronRight class="mt-2 shrink-0 text-slate-300" size={17} aria-hidden="true" />{/if}
                </button>
                <button type="button" class="app-focus absolute right-3 top-3 rounded-lg p-1.5 text-slate-400 opacity-70 hover:bg-white hover:text-rose-700 sm:opacity-0 sm:group-hover:opacity-100 sm:focus:opacity-100" aria-label={`เก็บการแจ้งเตือน ${item.title}`} disabled={mutating} on:click={(event) => archive(item, event)}>
                  <X size={15} aria-hidden="true" />
                </button>
              </li>
            {/each}
          </ul>
        {/if}
      </div>

      {#if errorMessage && items.length > 0}
        <p class="border-t border-rose-100 bg-rose-50 px-4 py-2.5 text-xs text-rose-700" role="alert">{errorMessage}</p>
      {/if}

      <footer class="border-t border-slate-100 bg-slate-50 px-4 py-3">
        {#if friendshipStatus === 'friend'}
          <div class="flex items-start gap-2.5 text-emerald-800">
            <ShieldCheck class="mt-0.5 shrink-0" size={18} aria-hidden="true" />
            <div>
              <p class="text-xs font-semibold">เชื่อมต่อ LINE Official Account แล้ว</p>
              <p class="mt-0.5 text-[0.7rem] leading-4 text-slate-500">คุณพร้อมรับการแจ้งเตือนทาง LINE และยังดูย้อนหลังได้ที่นี่</p>
            </div>
          </div>
        {:else if lineOaAddFriendUrl}
          <div class="flex items-center justify-between gap-3">
            <div class="min-w-0">
              <p class="text-xs font-semibold text-slate-800">รับการแจ้งเตือนผ่าน LINE</p>
              <p class="mt-0.5 text-[0.7rem] leading-4 text-slate-500">เพิ่มเพื่อนหรือปลดบล็อกบัญชีกลาง การแจ้งเตือนในระบบนี้ยังคงเป็นแหล่งข้อมูลหลัก</p>
            </div>
            <button type="button" class="app-focus inline-flex shrink-0 items-center gap-1.5 rounded-lg bg-[#06c755] px-3 py-2 text-xs font-semibold text-white hover:bg-[#05b84d] disabled:opacity-60" disabled={friendshipBusy || friendshipStatus === 'checking'} on:click={addLineFriend}>
              {#if friendshipBusy}<LoaderCircle class="animate-spin" size={15} />{:else}<UserPlus size={15} />{/if}
              เพิ่มเพื่อน
            </button>
          </div>
        {:else}
          <p class="text-[0.7rem] leading-4 text-slate-500">การแจ้งเตือนในระบบพร้อมใช้งาน ส่วน LINE ยังไม่ได้ตั้งค่าบัญชีกลาง</p>
        {/if}
      </footer>
    </div>
  {/if}
</div>

<style>
  .item-unread { background: linear-gradient(90deg, rgb(240 249 255), white 35%); }
</style>
