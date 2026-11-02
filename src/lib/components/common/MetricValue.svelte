<script lang="ts">
  import { calculationMessage, type CalculationError } from '$lib/reports/metricCalculation';
  export let value: number | null | undefined;
  export let error: CalculationError | undefined = undefined;
  $: message = value == null ? calculationMessage(error) : undefined;
</script>

<span title={message} aria-label={message} class:cursor-help={Boolean(message)}>{value?.toLocaleString() ?? '—'}</span>
