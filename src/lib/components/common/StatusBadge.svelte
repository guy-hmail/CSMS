<script lang="ts">
  import type { StatusTone } from '$lib/types/dashboard';

  export let label: string;
  export let tone: StatusTone = 'neutral';

  const toneClasses: Record<StatusTone, string> = {
    success: 'border-emerald-200 bg-emerald-50 text-emerald-800',
    warning: 'border-amber-200 bg-amber-50 text-amber-800',
    info: 'border-sky-200 bg-sky-50 text-sky-800',
    neutral: 'border-slate-200 bg-slate-50 text-slate-700',
    error: 'border-rose-200 bg-rose-50 text-rose-800'
  };
</script>

<span class={`inline-flex items-center rounded-md border px-2 py-1 text-xs font-medium ${toneClasses[tone]}`}>
  {label}
</span>
