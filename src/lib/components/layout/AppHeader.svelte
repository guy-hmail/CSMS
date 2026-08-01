<script lang="ts">
  import { Menu, PanelLeftClose, PanelLeftOpen, UserRound } from '@lucide/svelte';
  import ThemeToggle from '$lib/components/layout/ThemeToggle.svelte';

  type HeaderContext = {
    churchName: string;
    periodLabel: string;
    userName: string;
  };

  export let context: HeaderContext;
  export let onMenuClick: () => void;
  export let sidebarCollapsed = false;
  export let onSidebarToggle: () => void = () => {};
</script>

<header class="sticky top-0 z-30 border-b border-sky-100/80 bg-white/80 backdrop-blur-xl">
  <div class="mx-auto flex h-16 max-w-7xl items-center justify-between gap-3 px-4 sm:px-5 md:h-18 md:px-6 lg:px-8">
    <div class="flex min-w-0 items-center gap-3">
      <button
        type="button"
        class="app-focus inline-flex h-10 w-10 items-center justify-center rounded-xl border border-slate-200 bg-white text-slate-700 shadow-sm md:hidden"
        aria-label="Open navigation"
        on:click={onMenuClick}
      >
        <Menu size={20} aria-hidden="true" />
      </button>

      <button
        type="button"
        class="app-focus hidden h-10 w-10 items-center justify-center rounded-xl border border-sky-100 bg-sky-50 text-sky-800 shadow-sm transition hover:bg-sky-100 md:inline-flex"
        aria-label={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}
        aria-pressed={sidebarCollapsed}
        on:click={onSidebarToggle}
      >
        {#if sidebarCollapsed}
          <PanelLeftOpen size={19} aria-hidden="true" />
        {:else}
          <PanelLeftClose size={19} aria-hidden="true" />
        {/if}
      </button>

      <div class="flex min-w-0 items-center gap-3">
        <div class="hidden h-10 w-10 shrink-0 items-center justify-center rounded-2xl bg-gradient-to-br from-sky-600 to-teal-600 text-sm font-bold text-white shadow-sm sm:flex">
          C
        </div>
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-slate-950">CSMS</p>
          <p class="truncate text-xs text-slate-500">Church Statistics Management System</p>
        </div>
      </div>
    </div>


    <div class="flex shrink-0 items-center gap-2">
      <ThemeToggle />
      <button
        type="button"
        class="app-focus inline-flex min-w-0 items-center gap-2 rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-700 shadow-sm"
        aria-label="Open user profile"
      >
        <span class="hidden max-w-32 truncate sm:inline">{context.userName}</span>
        <UserRound size={18} aria-hidden="true" />
      </button>
    </div>
  </div>
</header>
