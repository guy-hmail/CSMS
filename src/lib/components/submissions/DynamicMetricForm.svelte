<script lang="ts">
  import MetricInputField from './MetricInputField.svelte';
  import type { SubmissionMetricDefinition, SubmissionMetricValue, SubmissionValidationMessage } from '$lib/types/submission';
  export let metrics: SubmissionMetricDefinition[];
  export let values: SubmissionMetricValue[];
  export let validationMessages: SubmissionValidationMessage[] = [];
  export let disabled = false;
  $: sortedMetrics = [...metrics].sort((a, b) => a.sortOrder - b.sortOrder);
  function valueForMetric(metricId: string): SubmissionMetricValue {
    let value = values.find((item) => item.metricId === metricId);
    if (!value) {
      value = { metricId, numericValue: null, textValue: null, booleanValue: null };
      values = [...values, value];
    }
    return value;
  }
  function errorForMetric(metricId: string): string | null {
    return validationMessages.find((message) => message.field === metricId)?.message ?? null;
  }
</script>

<section class="app-card p-4 sm:p-5" aria-labelledby="metric-form-title">
  <div class="border-b border-slate-200 pb-4">
    <h2 id="metric-form-title" class="app-section-title">สถิติ</h2>
    <p class="app-section-copy">รายการตัวชี้วัดมาจากการตั้งค่าขององค์กรปัจจุบัน</p>
  </div>
  <div class="mt-4 grid gap-3 lg:grid-cols-2">
    {#each sortedMetrics as metric}
      <MetricInputField {metric} value={valueForMetric(metric.id)} errorMessage={errorForMetric(metric.id)} {disabled} />
    {/each}
  </div>
</section>
