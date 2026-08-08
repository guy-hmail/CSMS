<script lang="ts">
  import { onMount } from 'svelte';
  import { goto } from '$app/navigation';
  import { CheckCircle2, Copy, LoaderCircle, Send, TriangleAlert } from '@lucide/svelte';
  import { initializeLiff } from '$lib/auth/lineAuth';

  type ShareState = 'initializing' | 'sharing' | 'success' | 'cancelled' | 'error';

  let state: ShareState = 'initializing';
  let errorMessage = '';
  let inviteLink = '';
  let ouName = '';
  let roleLabel = '';
  let recipientName = '';

  function readShareDetails(): void {
    const params = new URLSearchParams(window.location.search);
    inviteLink = params.get('invite')?.trim() ?? '';
    ouName = params.get('ou')?.trim() ?? '';
    roleLabel = params.get('role')?.trim() ?? '';
    recipientName = params.get('recipient')?.trim() ?? '';
    if (!inviteLink || !ouName || !roleLabel) throw new Error('ข้อมูลสำหรับส่ง Invite Link ไม่ครบถ้วน');

    const inviteUrl = new URL(inviteLink);
    if (inviteUrl.hostname !== 'liff.line.me' || !inviteUrl.searchParams.has('invite')) {
      throw new Error('Invite Link ไม่ถูกต้อง');
    }
  }

  async function shareInvite(): Promise<void> {
    state = 'initializing';
    errorMessage = '';
    try {
      const liff = await initializeLiff();
      if (!liff.isLoggedIn()) {
        liff.login({ redirectUri: window.location.href });
        return;
      }

      readShareDetails();
      window.history.replaceState({}, '', '/line/share-invite');

      if (!liff.isInClient() || !liff.isApiAvailable('shareTargetPicker')) {
        throw new Error('ไม่สามารถเปิดรายชื่อเพื่อนได้ กรุณาเปิดหน้านี้ผ่านแอป LINE และเปิด Share Target Picker ใน LINE Developers Console');
      }

      state = 'sharing';
      const recipient = recipientName ? `สำหรับ ${recipientName}\n` : '';
      const result = await liff.shareTargetPicker(
        [
          {
            type: 'text',
            text: `คำเชิญเข้าร่วม CSMS\n${recipient}หน่วยงาน: ${ouName}\nสิทธิ์: ${roleLabel}\n\nเปิดลิงก์นี้ผ่าน LINE เพื่อรับสิทธิ์\n${inviteLink}`
          }
        ],
        { isMultiple: false }
      );
      state = result ? 'success' : 'cancelled';
    } catch (error) {
      errorMessage = error instanceof Error ? error.message : 'ไม่สามารถส่ง Invite Link ผ่าน LINE ได้';
      state = 'error';
    }
  }

  async function copyInviteLink(): Promise<void> {
    if (!inviteLink) return;
    await navigator.clipboard.writeText(inviteLink);
  }

  onMount(() => {
    void shareInvite();
  });
</script>

<svelte:head><title>ส่งคำเชิญผ่าน LINE | CSMS</title></svelte:head>

<main class="app-surface flex min-h-screen items-center justify-center px-4 py-10">
  <section class="app-card w-full max-w-md p-6 text-center sm:p-8">
    {#if state === 'initializing' || state === 'sharing'}
      <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-3xl bg-sky-50 text-sky-700"><LoaderCircle class="animate-spin" size={28} /></span>
      <h1 class="mt-5 text-xl font-semibold text-slate-950">{state === 'initializing' ? 'กำลังเชื่อมต่อ LINE' : 'กำลังเปิดรายชื่อเพื่อน'}</h1>
      <p class="mt-2 text-sm leading-6 text-slate-500">กรุณารอสักครู่และเลือกเพื่อนที่ต้องการส่งคำเชิญ</p>
    {:else if state === 'success'}
      <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-3xl bg-emerald-50 text-emerald-700"><CheckCircle2 size={28} /></span>
      <h1 class="mt-5 text-xl font-semibold text-slate-950">ส่งคำเชิญแล้ว</h1>
      <p class="mt-2 text-sm leading-6 text-slate-500">Invite Link ถูกส่งให้เพื่อนที่เลือกเรียบร้อยแล้ว</p>
      <button type="button" class="app-button-primary mt-6 w-full" on:click={() => goto('/app/organization')}>กลับหน้าองค์กร</button>
    {:else if state === 'cancelled'}
      <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-3xl bg-slate-100 text-slate-600"><Send size={28} /></span>
      <h1 class="mt-5 text-xl font-semibold text-slate-950">ยังไม่ได้ส่งคำเชิญ</h1>
      <p class="mt-2 text-sm leading-6 text-slate-500">คุณปิดหน้ารายชื่อเพื่อนโดยไม่ได้ส่งข้อความ</p>
      <button type="button" class="app-button-secondary mt-6 w-full" on:click={() => goto('/app/organization')}>กลับหน้าองค์กร</button>
    {:else}
      <span class="mx-auto flex h-16 w-16 items-center justify-center rounded-3xl bg-rose-50 text-rose-700"><TriangleAlert size={28} /></span>
      <h1 class="mt-5 text-xl font-semibold text-slate-950">เปิดรายชื่อเพื่อนไม่สำเร็จ</h1>
      <p class="mt-3 rounded-2xl bg-rose-50 px-4 py-3 text-sm leading-6 text-rose-700">{errorMessage}</p>
      {#if inviteLink}<button type="button" class="app-button-secondary mt-5 inline-flex w-full items-center justify-center gap-2" on:click={copyInviteLink}><Copy size={17} /> Copy Invite Link</button>{/if}
      <button type="button" class="app-button-primary mt-3 w-full" on:click={() => goto('/app/organization')}>กลับหน้าองค์กร</button>
    {/if}
  </section>
</main>
