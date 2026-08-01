<script lang="ts">
  import { page } from '$app/stores';
  import { isAppNavItemActive, type AppNavItem } from '$lib/constants/routes';

  export let items: AppNavItem[];

  $: currentPath = normalizePath($page.url.pathname);

  function normalizePath(path: string): string {
    return path.replace(/\/+$/, '') || '/';
  }

</script>

{#key currentPath}
  <nav class="fixed inset-x-0 bottom-0 z-30 grid grid-cols-7 border-t border-sky-100 bg-white/95 px-1 py-2 shadow-[0_-12px_24px_rgb(15_23_42_/_0.08)] backdrop-blur md:hidden" aria-label="Mobile navigation">
    {#each items as item}
      {@const Icon = item.icon}
      <a
        class={`app-focus flex min-h-12 flex-col items-center justify-center gap-1 rounded-xl px-1 py-1.5 text-[0.66rem] font-semibold leading-tight ${
          isAppNavItemActive(item.href, currentPath) ? 'bg-gradient-to-br from-sky-50 to-emerald-50 text-sky-700 shadow-sm' : 'text-slate-500'
        }`}
        href={item.href}
        aria-current={isAppNavItemActive(item.href, currentPath) ? 'page' : undefined}
      >
        <span class="relative"><Icon size={18} aria-hidden="true" />{#if item.badgeCount}<span class="absolute -right-3 -top-2 inline-flex min-w-4 items-center justify-center rounded-full bg-rose-600 px-1 text-[0.58rem] font-bold text-white">{item.badgeCount}</span>{/if}</span>
        <span class="w-full truncate text-center">{item.label}</span>
      </a>
    {/each}
  </nav>
{/key}
