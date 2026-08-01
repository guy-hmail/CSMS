<script lang="ts">
  import type { SubmissionMetricDefinition, SubmissionMetricValue } from '$lib/types/submission';

  export let metric: SubmissionMetricDefinition;
  export let value: SubmissionMetricValue;
  export let errorMessage: string | null = null;
  export let disabled = false;

  function updateNumericValue(event: Event): void {
    const input = event.currentTarget as HTMLInputElement;
    value.numericValue = input.value === '' ? null : Number(input.value);
    value.textValue = null;
    value.booleanValue = null;
  }
  function updateTextValue(event: Event): void {
    value.textValue = (event.currentTarget as HTMLInputElement).value;
    value.numericValue = null;
    value.booleanValue = null;
  }
  function updateBooleanValue(event: Event): void {
    value.booleanValue = (event.currentTarget as HTMLInputElement).checked;
    value.numericValue = null;
    value.textValue = null;
  }
</script>

<div class="rounded-md border border-slate-200 bg-white p-4 transition hover:border-sky-200 hover:shadow-sm">
  <label class="text-sm font-semibold text-slate-900" for={`metric-${metric.id}`}>
    {metric.name}{#if metric.isRequired}<span class="text-rose-600"> *</span>{/if}
  </label>
  {#if metric.inputType === 'number'}
    <div class="mt-3 flex items-center gap-2">
      <input id={`metric-${metric.id}`} class="app-input min-w-0 flex-1" type="number" min={metric.minValue ?? undefined} max={metric.maxValue ?? undefined} inputmode="decimal" value={value.numericValue ?? ''} aria-invalid={errorMessage ? 'true' : 'false'} {disabled} on:input={updateNumericValue} />
      <span class="w-16 shrink-0 text-sm text-slate-500">{metric.unit}</span>
    </div>
  {:else if metric.inputType === 'text'}
    <input id={`metric-${metric.id}`} class="app-input mt-3" type="text" value={value.textValue ?? ''} aria-invalid={errorMessage ? 'true' : 'false'} {disabled} on:input={updateTextValue} />
  {:else}
    <label class="mt-3 flex min-h-11 items-center gap-3 rounded-md border border-slate-300 bg-white px-3">
      <input id={`metric-${metric.id}`} class="h-5 w-5 rounded border-slate-300" type="checkbox" checked={value.booleanValue ?? false} aria-invalid={errorMessage ? 'true' : 'false'} {disabled} on:change={updateBooleanValue} />
      <span class="text-sm text-slate-700">ใช่</span>
    </label>
  {/if}
  {#if errorMessage}<p class="mt-2 text-sm text-rose-700">{errorMessage}</p>{/if}
</div>
