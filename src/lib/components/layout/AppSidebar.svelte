<script lang="ts">
  import { page } from '$app/stores';
  import { isAppNavItemActive, type AppNavItem } from '$lib/constants/routes';

  export let items: AppNavItem[];
  export let visible = true;
  export let collapsed = false;
  export let onNavigate: () => void = () => {};

  $: currentPath = normalizePath($page.url.pathname);

  function normalizePath(path: string): string {
    return path.replace(/\/+$/, '') || '/';
  }

</script>

{#if visible}
  <nav class={`flex h-full flex-col gap-1.5 ${collapsed ? 'items-center' : ''}`} aria-label="Primary navigation">
    {#each items as item}
      {@const Icon = item.icon}
      <a
        class={`app-focus group relative flex min-h-11 items-center rounded-xl py-2.5 text-sm font-semibold transition-all ${
          collapsed ? 'w-11 justify-center px-0' : 'w-full gap-3 px-3'
        } ${
          isAppNavItemActive(item.href, currentPath)
            ? 'border border-sky-200 bg-gradient-to-r from-sky-50 to-emerald-50 text-sky-950 shadow-sm'
            : 'border border-transparent text-slate-600 hover:border-sky-100 hover:bg-sky-50/70 hover:text-slate-950'
        }`}
        href={item.href}
        title={collapsed ? item.label : undefined}
        aria-current={isAppNavItemActive(item.href, currentPath) ? 'page' : undefined}
        on:click={onNavigate}
      >
        <span class={`flex h-8 w-8 shrink-0 items-center justify-center rounded-lg ${isAppNavItemActive(item.href, currentPath) ? 'bg-gradient-to-br from-sky-600 to-teal-600 text-white shadow-sm' : 'bg-slate-100 text-slate-500 group-hover:bg-sky-100 group-hover:text-sky-700'}`}>
          <Icon size={18} aria-hidden="true" />
        </span>
        {#if !collapsed}
          <span>{item.label}</span>
          {#if item.badgeCount}
            <span class="ml-auto inline-flex min-w-5 items-center justify-center rounded-full bg-rose-600 px-1.5 py-0.5 text-[0.65rem] font-bold text-white" aria-label={`${item.badgeCount} คำขอรอดำเนินการ`}>{item.badgeCount}</span>
          {/if}
        {:else if item.badgeCount}
          <span class="absolute -right-1 -top-1 inline-flex min-w-4 items-center justify-center rounded-full bg-rose-600 px-1 text-[0.6rem] font-bold text-white">{item.badgeCount}</span>
        {/if}
      </a>
    {/each}
  </nav>
{/if}
