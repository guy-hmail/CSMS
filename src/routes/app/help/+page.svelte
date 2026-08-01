<script lang="ts">
  import {
    BookOpenCheck, Building2, CheckCircle2, ChevronRight,
    ClipboardCheck, FilePenLine, FileText, LockKeyhole, Send, ShieldCheck,
    UserCog, UsersRound
  } from '@lucide/svelte';

  const roles = [
    {
      name: 'Admin',
      code: 'admin',
      description: 'ผู้ดูแลระบบภายในขอบเขต OU ที่ได้รับมอบหมาย',
      scope: 'OU ที่ Assign และ Child OU ทั้งหมด',
      tone: 'border-violet-200 bg-violet-50 text-violet-800',
      permissions: ['ดู Dashboard และรายงาน', 'กรอกและส่งข้อมูลใน Subtree', 'สร้างและแก้ไข Child OU', 'จัดการสมาชิกและ Invite Link', 'มอบ Role ได้ทุกประเภท', 'กำหนด Override ให้ Approver', 'อนุมัติคำร้องขอแก้ไข']
    },
    {
      name: 'Manager',
      code: 'manager',
      description: 'ผู้จัดการหน่วยงานและโครงสร้างภายใน Subtree',
      scope: 'OU ที่ Assign และ Child OU ทั้งหมด',
      tone: 'border-sky-200 bg-sky-50 text-sky-800',
      permissions: ['ดู Dashboard และรายงาน', 'กรอกและส่งข้อมูลใน Subtree', 'สร้างและแก้ไข Child OU', 'จัดการสมาชิกและ Invite Link', 'มอบ Manager, Data Entry, Approver และ Viewer', 'อนุมัติคำร้องขอแก้ไข']
    },
    {
      name: 'Data Entry',
      code: 'data_entry',
      description: 'ผู้บันทึกและส่งข้อมูลรายสัปดาห์',
      scope: 'เฉพาะ OU ที่ Assign โดยตรง',
      tone: 'border-emerald-200 bg-emerald-50 text-emerald-800',
      permissions: ['ดูแบบฟอร์มของ OU', 'บันทึกแบบร่าง', 'ส่งข้อมูลรายสัปดาห์', 'ร้องขอแก้ไขข้อมูลที่ส่งแล้ว', 'แก้ไขหลังคำขอได้รับอนุมัติ']
    },
    {
      name: 'Approver',
      code: 'approver',
      description: 'ผู้ตรวจสอบและอนุมัติข้อมูล',
      scope: 'OU ที่ Assign และ Child OU ตามลำดับผู้อนุมัติ',
      tone: 'border-amber-200 bg-amber-50 text-amber-800',
      permissions: ['ดูรายการรออนุมัติ', 'อนุมัติหรือไม่อนุมัติข้อมูล', 'ส่งรายการกลับแก้ไข', 'ดูเหตุผลและประวัติการดำเนินการ', 'Override ลำดับได้เมื่อ Admin เปิดสิทธิ์']
    },
    {
      name: 'Viewer',
      code: 'viewer',
      description: 'ผู้ดูข้อมูลแบบ Read-only',
      scope: 'OU ที่ Assign และ Child OU ทั้งหมด',
      tone: 'border-slate-200 bg-slate-50 text-slate-700',
      permissions: ['ดูโครงสร้างองค์กร', 'ดู Dashboard', 'ดูรายงานและข้อมูลสรุป', 'ไม่สามารถแก้ไขหรืออนุมัติข้อมูล']
    }
  ];

  const weeklySteps = [
    { title: 'เลือกสัปดาห์และ OU', detail: 'ระบบจะแสดงเฉพาะ OU ที่บัญชีมีสิทธิ์บันทึกข้อมูล', icon: Building2 },
    { title: 'กรอกข้อมูลสถิติ', detail: 'ช่องที่มีเครื่องหมาย * จำเป็นต้องกรอกก่อนส่ง', icon: FilePenLine },
    { title: 'บันทึกแบบร่างหรือส่งข้อมูล', detail: 'แบบร่างยังแก้ไขได้ ส่วนรายการที่ส่งแล้วจะถูกล็อก', icon: Send },
    { title: 'ตรวจสอบและอนุมัติ', detail: 'Approver ตรวจรายการ หรือระบบอนุมัติอัตโนมัติตามค่า Tenant', icon: CheckCircle2 }
  ];
</script>

<svelte:head><title>คู่มือใช้งาน | CSMS</title></svelte:head>

<div class="app-page space-y-6">
  <section class="relative overflow-hidden rounded-3xl bg-gradient-to-br from-slate-950 via-sky-950 to-teal-900 p-5 text-white shadow-xl sm:p-7">
    <div class="pointer-events-none absolute -right-12 -top-20 h-64 w-64 rounded-full bg-sky-400/20 blur-3xl"></div>
    <div class="relative flex max-w-3xl items-start gap-4">
      <span class="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl bg-white/10 text-emerald-200 ring-1 ring-white/15"><BookOpenCheck size={25} /></span>
      <div><p class="text-xs font-semibold uppercase tracking-[0.18em] text-emerald-300">CSMS User Guide</p><h1 class="mt-2 text-2xl font-semibold tracking-tight sm:text-3xl">คู่มือการใช้งาน</h1><p class="mt-2 text-sm leading-6 text-slate-300">ขั้นตอนส่งข้อมูล การอนุมัติ การร้องขอแก้ไข และขอบเขตสิทธิ์ของแต่ละ Role ในโครงสร้าง OU</p></div>
    </div>
  </section>

  <nav class="app-card grid gap-2 p-3 sm:grid-cols-2 lg:grid-cols-4" aria-label="หัวข้อคู่มือ">
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#weekly-submission"><span class="flex items-center gap-2"><ClipboardCheck size={17} /> ส่งข้อมูล</span><ChevronRight size={16} /></a>
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#edit-request"><span class="flex items-center gap-2"><LockKeyhole size={17} /> ขอแก้ไข</span><ChevronRight size={16} /></a>
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#roles"><span class="flex items-center gap-2"><ShieldCheck size={17} /> Role และสิทธิ์</span><ChevronRight size={16} /></a>
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#ou-scope"><span class="flex items-center gap-2"><UsersRound size={17} /> OU Scope</span><ChevronRight size={16} /></a>
  </nav>

  <section id="weekly-submission" class="app-card scroll-mt-20 p-4 sm:p-6" aria-labelledby="weekly-title">
    <div class="flex items-start gap-3"><span class="rounded-2xl bg-emerald-50 p-2.5 text-emerald-700"><ClipboardCheck size={21} /></span><div><h2 id="weekly-title" class="app-section-title">การส่งข้อมูลรายสัปดาห์</h2><p class="app-section-copy">ขั้นตอนตั้งแต่เลือก OU จนถึงการอนุมัติ</p></div></div>
    <ol class="mt-5 grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
      {#each weeklySteps as step, index}
        {@const Icon = step.icon}
        <li class="rounded-2xl border border-slate-200 bg-white p-4"><div class="flex items-center justify-between"><span class="flex h-9 w-9 items-center justify-center rounded-xl bg-sky-50 text-sky-700"><Icon size={18} /></span><span class="text-xs font-bold text-slate-300">0{index + 1}</span></div><h3 class="mt-4 text-sm font-semibold text-slate-950">{step.title}</h3><p class="mt-1 text-xs leading-5 text-slate-500">{step.detail}</p></li>
      {/each}
    </ol>
  </section>

  <section id="edit-request" class="app-card scroll-mt-20 overflow-hidden" aria-labelledby="edit-title">
    <div class="border-b border-amber-100 bg-amber-50/70 p-4 sm:p-6"><div class="flex items-start gap-3"><span class="rounded-2xl bg-white p-2.5 text-amber-700 shadow-sm"><LockKeyhole size={21} /></span><div><h2 id="edit-title" class="app-section-title">การร้องขอแก้ไขข้อมูลที่ส่งแล้ว</h2><p class="app-section-copy">ผู้ส่งไม่สามารถปลดล็อกรายการเองได้</p></div></div></div>
    <div class="grid gap-3 p-4 sm:grid-cols-3 sm:p-6">
      <div class="rounded-2xl border border-slate-200 p-4"><p class="text-xs font-semibold text-sky-700">ขั้นที่ 1 · ผู้ส่ง</p><p class="mt-2 text-sm font-semibold text-slate-950">กด “ร้องขอแก้ไข”</p><p class="mt-1 text-xs leading-5 text-slate-500">ระบุเหตุผล รายการจะยังคงล็อกระหว่างรอ</p></div>
      <div class="rounded-2xl border border-slate-200 p-4"><p class="text-xs font-semibold text-amber-700">ขั้นที่ 2 · Manager/Admin</p><p class="mt-2 text-sm font-semibold text-slate-950">อนุมัติคำขอ</p><p class="mt-1 text-xs leading-5 text-slate-500">ดู badge ที่เมนูอนุมัติ แล้วคลิกรายการเพื่อดำเนินการ</p></div>
      <div class="rounded-2xl border border-slate-200 p-4"><p class="text-xs font-semibold text-emerald-700">ขั้นที่ 3 · ผู้ส่ง</p><p class="mt-2 text-sm font-semibold text-slate-950">แก้ไขและส่งใหม่</p><p class="mt-1 text-xs leading-5 text-slate-500">เมื่อสถานะเป็น “ส่งกลับแก้ไข” แบบฟอร์มจึงจะปลดล็อก</p></div>
    </div>
  </section>

  <section id="roles" class="scroll-mt-20 space-y-4" aria-labelledby="roles-title">
    <div class="flex items-start gap-3 px-1"><span class="rounded-2xl bg-violet-50 p-2.5 text-violet-700"><UserCog size={21} /></span><div><h2 id="roles-title" class="app-section-title">Role และสิทธิ์</h2><p class="app-section-copy">สิทธิ์จริงตรวจโดย Backend ตาม Tenant, OU และ Assignment ปัจจุบัน</p></div></div>
    <div class="grid gap-4 lg:grid-cols-2">
      {#each roles as role}
        <article class="app-card p-4 sm:p-5">
          <div class="flex flex-wrap items-start justify-between gap-3"><div><h3 class="text-base font-semibold text-slate-950">{role.name}</h3><p class="mt-1 text-xs text-slate-500">{role.description}</p></div><span class={`rounded-full border px-2.5 py-1 text-[0.68rem] font-semibold ${role.tone}`}>{role.code}</span></div>
          <div class="mt-4 rounded-xl bg-slate-50 px-3 py-2 text-xs text-slate-600"><strong class="text-slate-800">ขอบเขต:</strong> {role.scope}</div>
          <ul class="mt-4 grid gap-2 sm:grid-cols-2">{#each role.permissions as permission}<li class="flex items-start gap-2 text-xs leading-5 text-slate-600"><CheckCircle2 class="mt-0.5 shrink-0 text-emerald-600" size={14} />{permission}</li>{/each}</ul>
        </article>
      {/each}
    </div>
  </section>

  <section id="ou-scope" class="app-card scroll-mt-20 p-4 sm:p-6" aria-labelledby="scope-title">
    <div class="flex items-start gap-3"><span class="rounded-2xl bg-sky-50 p-2.5 text-sky-700"><Building2 size={21} /></span><div><h2 id="scope-title" class="app-section-title">ขอบเขต OU และ Child OU</h2><p class="app-section-copy">ตัวอย่างเมื่อบัญชีได้รับ Role ที่ “ภาคกลาง”</p></div></div>
    <div class="mt-5 grid gap-4 lg:grid-cols-[1fr_1.3fr]">
      <div class="rounded-2xl border border-sky-100 bg-sky-50/50 p-4 font-medium text-slate-800"><p>ภาคกลาง <span class="text-xs text-sky-700">← OU ที่ Assign</span></p><div class="ml-5 mt-3 border-l-2 border-sky-200 pl-4"><p>เขต 1</p><div class="ml-5 mt-3 border-l-2 border-sky-200 pl-4"><p>กลุ่ม A</p><p class="mt-2">กลุ่ม B</p></div></div></div>
      <div class="space-y-3"><div class="rounded-2xl border border-emerald-200 bg-emerald-50 p-4"><p class="text-sm font-semibold text-emerald-900">Role ที่สืบทอดลง Child OU</p><p class="mt-2 text-xs leading-5 text-emerald-800">Admin, Manager, Approver และ Viewer ครอบคลุม “ภาคกลาง”, “เขต 1”, “กลุ่ม A” และ “กลุ่ม B” ตามหน้าที่ของ Role</p></div><div class="rounded-2xl border border-amber-200 bg-amber-50 p-4"><p class="text-sm font-semibold text-amber-900">Data Entry ไม่สืบทอด</p><p class="mt-2 text-xs leading-5 text-amber-800">ถ้า Assign Data Entry ที่ “ภาคกลาง” จะกรอกได้เฉพาะภาคกลาง ต้อง Assign เพิ่มที่กลุ่มหรือเขตที่ต้องการกรอกข้อมูล</p></div></div>
    </div>
  </section>

  <section class="rounded-2xl border border-sky-200 bg-sky-50 p-4 text-sm leading-6 text-sky-900"><div class="flex items-start gap-3"><FileText class="mt-0.5 shrink-0 text-sky-700" size={19} /><p><strong>หมายเหตุ:</strong> ผู้ใช้หนึ่งคนสามารถมีหลาย Assignment ได้ ระบบจะรวมขอบเขตที่ได้รับทั้งหมด แต่ทุกการเปลี่ยนแปลงยังถูกตรวจสิทธิ์และบันทึก Audit โดย Backend</p></div></section>
</div>
