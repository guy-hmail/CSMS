<script lang="ts">
  import { Building2, ChevronRight, Database, FileClock, LogOut, Settings, ShieldCheck, Users } from '@lucide/svelte';
  import { goto } from '$app/navigation';
  import { dev } from '$app/environment';
  import { page } from '$app/stores';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';

  const navItems = [
    { label: 'Tenants', href: '/super-admin/tenants', icon: Building2 },
    { label: 'ผู้ดูแลระบบ', href: '/super-admin/users', icon: Users },
    { label: 'Audit Log', href: '/super-admin/audit', icon: FileClock },
    { label: 'Platform Settings', href: '/super-admin/settings', icon: Settings }
  ];

  async function signOut(): Promise<void> {
    await getSupabaseBrowserClient().auth.signOut();
    await goto('/super-admin/tenants');
    location.reload();
  }
</script>

<div class="min-h-screen bg-slate-950 text-slate-100">
  <header class="sticky top-0 z-30 border-b border-white/10 bg-slate-950/90 backdrop-blur">
    <div class="mx-auto flex h-16 max-w-[100rem] items-center justify-between gap-4 px-4 sm:px-6">
      <div class="flex items-center gap-3"><span class="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-violet-500 to-sky-500 shadow-lg shadow-violet-950/40"><ShieldCheck size={19} /></span><div><p class="text-sm font-semibold text-white">CSMS Control Plane</p><p class="text-[0.65rem] uppercase tracking-[0.2em] text-slate-400">Super Admin</p></div></div>
      <div class="flex items-center gap-3">{#if dev}<span class="hidden rounded-full border border-emerald-400/20 bg-emerald-400/10 px-3 py-1 text-xs font-semibold text-emerald-300 sm:inline-flex">Local</span>{/if}<button type="button" class="inline-flex items-center gap-2 rounded-xl border border-white/10 px-3 py-2 text-xs font-semibold text-slate-300 hover:bg-white/5" on:click={signOut}><LogOut size={15} /> ออกจากระบบ</button></div>
    </div>
  </header>

  <div class="mx-auto flex max-w-[100rem]">
    <aside class="sticky top-16 hidden h-[calc(100vh-4rem)] w-64 shrink-0 border-r border-white/10 bg-slate-950 p-4 md:flex md:flex-col">
      <div class="rounded-2xl border border-violet-400/15 bg-gradient-to-br from-violet-500/10 to-sky-500/10 p-4"><p class="text-xs font-semibold text-violet-300">Platform scope</p><p class="mt-1 text-sm font-semibold text-white">ทุก Tenant</p><p class="mt-1 text-xs leading-5 text-slate-400">การดำเนินการในส่วนนี้ไม่ขึ้นกับ OU</p></div>
      <nav class="mt-5 space-y-1" aria-label="Super admin navigation">
        {#each navItems as item}
          {@const Icon = item.icon}
          {@const active = $page.url.pathname === item.href || $page.url.pathname.startsWith(`${item.href}/`)}
          <a class={`flex items-center gap-3 rounded-2xl px-3 py-3 text-sm font-semibold transition ${active ? 'bg-white text-slate-950' : 'text-slate-400 hover:bg-white/5 hover:text-white'}`} href={item.href}><Icon size={18} /><span class="flex-1">{item.label}</span>{#if active}<ChevronRight size={15} />{/if}</a>
        {/each}
      </nav>
      <div class="mt-auto rounded-2xl border border-white/10 bg-white/5 p-4"><p class="flex items-center gap-2 text-xs font-semibold text-slate-300"><Database size={15} /> Platform database</p><p class="mt-2 text-[0.68rem] leading-5 text-slate-500">ระบบจริงต้องบันทึก Audit Log ทุกการสร้าง ปิด หรือเปลี่ยน Tenant</p></div>
    </aside>

    <main class="min-w-0 flex-1 bg-slate-50 px-3 py-5 text-slate-950 sm:px-5 md:min-h-[calc(100vh-4rem)] md:px-7 lg:px-10 lg:py-8">
      <slot />
    </main>
  </div>
</div>
