<script lang="ts">
  import type { SubmissionValidationMessage } from '$lib/types/submission';
  export let messages: SubmissionValidationMessage[] = [];
</script>
<section class={`rounded-md border p-4 shadow-sm ${messages.length ? 'border-amber-200 bg-amber-50' : 'border-emerald-200 bg-emerald-50'}`} aria-live="polite" aria-label="Validation messages">
  {#if messages.length}
    <h2 class="text-sm font-semibold text-amber-900">กรุณาตรวจสอบข้อมูลต่อไปนี้</h2>
    <ul class="mt-2 list-disc space-y-1 pl-5 text-sm text-amber-800">{#each messages as message}<li>{message.message}</li>{/each}</ul>
  {:else}<p class="text-sm font-medium text-emerald-800">ข้อมูลพร้อมบันทึก</p>{/if}
</section>
