<script lang="ts">
  export let title: string;
  export let eyebrow = 'Base UI';
  export let description: string;
</script>

<section class="space-y-5">
  <div class="flex flex-col gap-3 sm:flex-row sm:items-end sm:justify-between">
    <div class="min-w-0">
      <p class="text-xs font-semibold uppercase tracking-wide text-sky-700">{eyebrow}</p>
      <h1 class="mt-1 text-2xl font-semibold text-slate-950">{title}</h1>
      <p class="mt-2 max-w-3xl text-sm text-slate-600">{description}</p>
    </div>
  </div>

  <div class="app-card p-5">
    <div class="grid gap-4 md:grid-cols-3">
      <div class="rounded-md border border-dashed border-slate-300 p-4">
        <p class="text-sm font-semibold text-slate-900">โครงสร้างหน้า</p>
        <p class="mt-1 text-sm text-slate-500">แถบหัวเรื่อง แถบด้านข้าง และพื้นที่เนื้อหาที่ตอบสนองต่อขนาดจอทำงานแล้ว</p>
      </div>
      <div class="rounded-md border border-dashed border-slate-300 p-4">
        <p class="text-sm font-semibold text-slate-900">สถานะแบ็กเอนด์</p>
        <p class="mt-1 text-sm text-slate-500">ยังไม่มีการเรียก API หรือสัญญา接口ใน UI shell นี้</p>
      </div>
      <div class="rounded-md border border-dashed border-slate-300 p-4">
        <p class="text-sm font-semibold text-slate-900">ชั้นต่อไป</p>
        <p class="mt-1 text-sm text-slate-500">หน้าฟีเจอร์สามารถแทนที่ placeholder นี้ด้วยคอมโพเนนต์ที่ผูกกับบริการได้</p>
      </div>
    </div>
  </div>
</section>
