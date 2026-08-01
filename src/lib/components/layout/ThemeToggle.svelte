<script lang="ts">
  import { onMount } from 'svelte';
  import { Moon, Sun } from '@lucide/svelte';

  type Theme = 'light' | 'dark';

  const storageKey = 'csms-theme';
  let theme: Theme = 'light';

  function applyTheme(nextTheme: Theme): void {
    theme = nextTheme;
    const root = document.documentElement;
    root.dataset.mode = nextTheme;
    root.classList.toggle('dark', nextTheme === 'dark');
    root.style.colorScheme = nextTheme;
  }

  function toggleTheme(): void {
    const nextTheme = theme === 'dark' ? 'light' : 'dark';
    localStorage.setItem(storageKey, nextTheme);
    applyTheme(nextTheme);
  }

  onMount(() => {
    theme = document.documentElement.dataset.mode === 'dark' ? 'dark' : 'light';
  });
</script>

<button
  type="button"
  class="theme-toggle app-focus"
  aria-label={theme === 'dark' ? 'Switch to light theme' : 'Switch to dark theme'}
  aria-pressed={theme === 'dark'}
  title={theme === 'dark' ? 'ใช้โหมดสว่าง' : 'ใช้โหมดมืด'}
  on:click={toggleTheme}
>
  <span class="theme-toggle__track" aria-hidden="true">
    <span class="theme-toggle__thumb">
      {#if theme === 'dark'}
        <Moon size={14} strokeWidth={2.25} />
      {:else}
        <Sun size={14} strokeWidth={2.25} />
      {/if}
    </span>
  </span>
  <span class="hidden text-sm font-medium sm:inline">
    {theme === 'dark' ? 'Dark' : 'Light'}
  </span>
</button>
