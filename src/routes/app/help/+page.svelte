<script lang="ts">
  import {
    BookOpenCheck, Building2, CheckCircle2, ChevronRight, CirclePlus,
    ClipboardCheck, FilePenLine, FileText, Link2, LockKeyhole, Search, Send,
    ShieldCheck, UserCog, UserPlus, UsersRound
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

  const createOuSteps = [
    { title: 'เลือก OU แม่', detail: 'เข้าเมนู “องค์กร” แล้วคลิก OU ที่ต้องการให้เป็นหน่วยงานแม่ในแถบโครงสร้าง' },
    { title: 'เปิดแบบฟอร์ม', detail: 'กด “สร้าง OU ใหม่” ด้านขวาบน ปุ่มจะแสดงเมื่อคุณมีสิทธิ์จัดการ OU ที่เลือก' },
    { title: 'กรอกข้อมูล OU', detail: 'ตรวจ OU แม่ ระบุชื่อภาษาไทยหรือภาษาอังกฤษ เลือกประเภท และกำหนดว่าจะรับข้อมูลรายสัปดาห์โดยตรงหรือไม่' },
    { title: 'สร้างและตรวจสอบ', detail: 'กด “สร้าง OU” แล้วตรวจว่า OU ใหม่ปรากฏใต้หน่วยงานแม่ใน Tree ตามตำแหน่งที่ต้องการ' }
  ];

  const assignSteps = [
    { title: 'เลือก OU ปลายทาง', detail: 'เลือก OU จาก Tree แล้วเปิดแท็บ “LINE Accounts & Roles”' },
    { title: 'กด Assign Existing', detail: 'ใช้กรณีที่ผู้ใช้เคยเข้า CSMS ด้วย LINE และมีบัญชีอยู่ใน Tenant นี้แล้ว' },
    { title: 'ค้นหาและเลือกบัญชี', detail: 'ค้นหาด้วยชื่อ, LINE User ID หรืออีเมล แล้วเลือก LINE Account ที่ต้องการ' },
    { title: 'เลือก Role', detail: 'เลือกสิทธิ์ตามหน้าที่ หากเป็น Approver และผู้มอบเป็น Admin จึงจะเปิด “Can Override” ได้' },
    { title: 'ยืนยัน Assignment', detail: 'กด “Assign Account” ตรวจชื่อและ Role ในรายการสมาชิก จากนั้นให้ผู้ใช้ refresh หรือเข้าใหม่' }
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

  <nav class="app-card grid gap-2 p-3 sm:grid-cols-2 lg:grid-cols-3" aria-label="หัวข้อคู่มือ">
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#create-ou"><span class="flex items-center gap-2"><CirclePlus size={17} /> สร้าง OU</span><ChevronRight size={16} /></a>
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#assign-line"><span class="flex items-center gap-2"><UserPlus size={17} /> Assign LINE User</span><ChevronRight size={16} /></a>
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#weekly-submission"><span class="flex items-center gap-2"><ClipboardCheck size={17} /> ส่งข้อมูล</span><ChevronRight size={16} /></a>
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#edit-request"><span class="flex items-center gap-2"><LockKeyhole size={17} /> ขอแก้ไข</span><ChevronRight size={16} /></a>
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#roles"><span class="flex items-center gap-2"><ShieldCheck size={17} /> Role และสิทธิ์</span><ChevronRight size={16} /></a>
    <a class="app-focus flex items-center justify-between rounded-2xl px-4 py-3 text-sm font-semibold text-slate-700 hover:bg-sky-50 hover:text-sky-800" href="#ou-scope"><span class="flex items-center gap-2"><UsersRound size={17} /> OU Scope</span><ChevronRight size={16} /></a>
  </nav>

  <section id="create-ou" class="app-card scroll-mt-20 overflow-hidden" aria-labelledby="create-ou-guide-title">
    <div class="border-b border-sky-100 bg-gradient-to-r from-sky-50 to-emerald-50 p-4 sm:p-6">
      <div class="flex items-start gap-3"><span class="rounded-2xl bg-white p-2.5 text-sky-700 shadow-sm"><CirclePlus size={21} /></span><div><h2 id="create-ou-guide-title" class="app-section-title">การสร้าง OU ใหม่</h2><p class="app-section-copy">สำหรับ Admin หรือ Manager ที่มีสิทธิ์จัดการ OU แม่และ Subtree นั้น</p></div></div>
    </div>
    <div class="grid gap-6 p-4 sm:p-6 xl:grid-cols-[minmax(0,1fr)_minmax(22rem,0.9fr)]">
      <div>
        <div class="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-xs leading-5 text-amber-900"><strong>เตรียมก่อนสร้าง:</strong> ตรวจสอบ OU แม่, ชื่อ OU, ประเภท OU และกำหนดการรับข้อมูลให้ถูกต้อง</div>
        <ol class="mt-5 space-y-4">
          {#each createOuSteps as step, index}
            <li class="flex gap-3"><span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-sky-700 text-xs font-bold text-white">{index + 1}</span><div><h3 class="text-sm font-semibold text-slate-950">{step.title}</h3><p class="mt-1 text-xs leading-5 text-slate-500">{step.detail}</p></div></li>
          {/each}
        </ol>
        <div class="mt-5 rounded-2xl border border-slate-200 bg-slate-50 p-4 text-xs leading-5 text-slate-600"><strong class="text-slate-900">เลือก “รับข้อมูลรายสัปดาห์” เมื่อ:</strong> OU นี้มีผู้รับผิดชอบกรอกตัวเลขของตัวเอง หากไม่เลือก OU จะใช้สำหรับจัดกลุ่มและสรุปข้อมูลจาก OU ลูกเป็นหลัก เมื่อสร้าง OU ลูกที่รับข้อมูล ระบบจะปิดการรับข้อมูลของ OU แม่ให้อัตโนมัติและแจ้งผู้สร้าง เพื่อป้องกันการนับข้อมูลซ้ำ</div>
      </div>

      <figure class="overflow-hidden rounded-3xl border border-slate-200 bg-slate-100 shadow-sm">
        <figcaption class="flex items-center justify-between border-b border-slate-200 bg-slate-900 px-4 py-3 text-xs text-white"><span class="font-semibold">ตัวอย่างหน้าจอ · สร้าง OU ใหม่</span><span class="rounded-full bg-emerald-400/20 px-2 py-1 text-emerald-200">ข้อมูลตัวอย่าง</span></figcaption>
        <div class="p-3 sm:p-5">
          <div class="rounded-2xl bg-white p-4 shadow-lg sm:p-5">
            <div class="flex items-center gap-3"><span class="flex h-10 w-10 items-center justify-center rounded-xl bg-sky-50 text-sky-700"><CirclePlus size={20} /></span><div><p class="font-semibold text-slate-950">สร้าง OU ใหม่</p><p class="text-xs text-slate-500">OU ใหม่จะอยู่ภายใต้หน่วยงานแม่ที่เลือก</p></div></div>
            <div class="mt-4 grid gap-3 sm:grid-cols-2">
              <div class="sm:col-span-2"><p class="text-xs font-medium text-slate-600">OU แม่</p><div class="mt-1.5 rounded-xl border border-sky-200 bg-sky-50 px-3 py-2.5 text-sm text-sky-900">ภาคกลาง › เขต 2</div></div>
              <div><p class="text-xs font-medium text-slate-600">ชื่อ OU</p><div class="mt-1.5 rounded-xl border border-slate-200 px-3 py-2.5 text-sm text-slate-800">กลุ่มสามัคคี</div></div>
              <div><p class="text-xs font-medium text-slate-600">ประเภท</p><div class="mt-1.5 rounded-xl border border-slate-200 px-3 py-2.5 text-sm text-slate-800">กลุ่ม (GROUP)</div></div>
              <div class="flex items-center gap-3 rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2.5"><span class="flex h-5 w-5 items-center justify-center rounded bg-emerald-600 text-white"><CheckCircle2 size={14} /></span><span class="text-xs font-medium text-emerald-900">รับข้อมูลรายสัปดาห์</span></div>
            </div>
            <div class="mt-4 flex justify-end gap-2"><span class="rounded-full border border-slate-200 px-4 py-2 text-xs font-semibold text-slate-500">ยกเลิก</span><span class="rounded-full bg-sky-700 px-4 py-2 text-xs font-semibold text-white">สร้าง OU</span></div>
          </div>
        </div>
      </figure>
    </div>
  </section>

  <section id="assign-line" class="app-card scroll-mt-20 overflow-hidden" aria-labelledby="assign-line-title">
    <div class="border-b border-emerald-100 bg-emerald-50/70 p-4 sm:p-6"><div class="flex items-start gap-3"><span class="rounded-2xl bg-white p-2.5 text-emerald-700 shadow-sm"><UserPlus size={21} /></span><div><h2 id="assign-line-title" class="app-section-title">การ Assign สิทธิ์ให้ LINE User</h2><p class="app-section-copy">เลือกวิธีตามสถานะของบัญชี: มีบัญชีใน Tenant แล้ว หรือยังไม่เคยเข้าระบบ</p></div></div></div>
    <div class="p-4 sm:p-6">
      <div class="grid gap-4 lg:grid-cols-2">
        <article class="rounded-2xl border-2 border-emerald-200 bg-emerald-50/50 p-4"><div class="flex items-center gap-3"><span class="flex h-9 w-9 items-center justify-center rounded-xl bg-emerald-700 text-white"><Search size={17} /></span><div><h3 class="text-sm font-semibold text-emerald-950">มี LINE Account ใน Tenant แล้ว</h3><p class="text-xs text-emerald-800">ใช้ปุ่ม “Assign Existing”</p></div></div><p class="mt-3 text-xs leading-5 text-emerald-900">เหมาะกับผู้ใช้ที่เคย Login หรือรับ Invite มาก่อน ระบบค้นหาแล้วเพิ่ม Role ใหม่ใน OU นี้ได้ทันที โดย Assignment เดิมใน OU อื่นยังอยู่</p></article>
        <article class="rounded-2xl border border-sky-200 bg-sky-50/50 p-4"><div class="flex items-center gap-3"><span class="flex h-9 w-9 items-center justify-center rounded-xl bg-sky-700 text-white"><Link2 size={17} /></span><div><h3 class="text-sm font-semibold text-sky-950">ยังไม่มี LINE Account ใน Tenant</h3><p class="text-xs text-sky-800">ใช้ปุ่ม “สร้าง Invite Link”</p></div></div><p class="mt-3 text-xs leading-5 text-sky-900">กำหนด Role และวันหมดอายุ แล้วส่งลิงก์ทาง LINE ผู้รับต้องเปิดลิงก์และยืนยัน LINE Login ก่อน Assignment จึงมีผล</p></article>
      </div>

      <div class="mt-6 grid gap-6 xl:grid-cols-[minmax(0,1fr)_minmax(22rem,0.9fr)]">
        <div>
          <h3 class="text-sm font-semibold text-slate-950">ขั้นตอน Assign Existing Account</h3>
          <ol class="mt-4 space-y-4">
            {#each assignSteps as step, index}
              <li class="flex gap-3"><span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-emerald-700 text-xs font-bold text-white">{index + 1}</span><div><h4 class="text-sm font-semibold text-slate-950">{step.title}</h4><p class="mt-1 text-xs leading-5 text-slate-500">{step.detail}</p></div></li>
            {/each}
          </ol>
        </div>

        <figure class="overflow-hidden rounded-3xl border border-slate-200 bg-slate-100 shadow-sm">
          <figcaption class="flex items-center justify-between border-b border-slate-200 bg-slate-900 px-4 py-3 text-xs text-white"><span class="font-semibold">ตัวอย่างหน้าจอ · Assign LINE Account</span><span class="rounded-full bg-emerald-400/20 px-2 py-1 text-emerald-200">ข้อมูลตัวอย่าง</span></figcaption>
          <div class="p-3 sm:p-5">
            <div class="rounded-2xl bg-white p-4 shadow-lg sm:p-5">
              <div class="flex items-center gap-3"><span class="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-50 text-emerald-700"><UserPlus size={20} /></span><div><p class="font-semibold text-slate-950">Assign LINE Account</p><p class="text-xs text-slate-500">กำหนดสิทธิ์ใน “กลุ่มสามัคคี”</p></div></div>
              <div class="mt-4 space-y-3">
                <div><p class="text-xs font-medium text-slate-600">ค้นหา LINE Account</p><div class="mt-1.5 flex gap-2"><div class="min-w-0 flex-1 rounded-xl border border-slate-200 px-3 py-2.5 text-sm text-slate-700">สมชาย</div><span class="rounded-xl border border-slate-200 px-3 py-2.5 text-xs font-semibold text-slate-600">ค้นหา</span></div></div>
                <div><p class="text-xs font-medium text-slate-600">LINE Account</p><div class="mt-1.5 rounded-xl border border-sky-200 bg-sky-50 px-3 py-2.5"><p class="text-sm font-semibold text-sky-950">สมชาย ใจดี</p><p class="text-[0.68rem] text-sky-700">LINE U8f••••••••91</p></div></div>
                <div><p class="text-xs font-medium text-slate-600">Role</p><div class="mt-1.5 rounded-xl border border-slate-200 px-3 py-2.5 text-sm text-slate-800">ผู้กรอกข้อมูล (data_entry)</div></div>
                <div class="rounded-xl border border-sky-200 bg-sky-50 p-3 text-xs leading-5 text-sky-900"><strong>ขอบเขต:</strong> Data Entry กรอกได้เฉพาะ OU ที่ Assign โดยตรง หากต้องกรอกหลาย OU ต้องเพิ่ม Assignment แยกแต่ละ OU</div>
              </div>
              <div class="mt-4 flex justify-end gap-2"><span class="rounded-full border border-slate-200 px-4 py-2 text-xs font-semibold text-slate-500">ยกเลิก</span><span class="rounded-full bg-emerald-700 px-4 py-2 text-xs font-semibold text-white">Assign Account</span></div>
            </div>
          </div>
        </figure>
      </div>

      <div class="mt-6 grid gap-3 sm:grid-cols-3">
        <div class="rounded-2xl border border-violet-200 bg-violet-50 p-4 text-xs leading-5 text-violet-900"><strong class="block text-sm">Admin</strong>มอบได้ทุก Role ภายในขอบเขต และเปิด Override ให้ Approver ได้</div>
        <div class="rounded-2xl border border-sky-200 bg-sky-50 p-4 text-xs leading-5 text-sky-900"><strong class="block text-sm">Manager</strong>มอบ Manager, Data Entry, Approver และ Viewer ได้ แต่ให้ Admin หรือ Override ไม่ได้</div>
        <div class="rounded-2xl border border-amber-200 bg-amber-50 p-4 text-xs leading-5 text-amber-900"><strong class="block text-sm">ตรวจหลัง Assign</strong>ชื่อผู้ใช้และ Role ต้องปรากฏในรายการ และผู้ใช้ต้องอยู่ใน Tenant เดียวกัน</div>
      </div>
    </div>
  </section>

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
