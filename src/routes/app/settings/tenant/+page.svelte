<script lang="ts">
  import { onMount } from 'svelte';
  import { env } from '$env/dynamic/public';
  import {
    ArrowLeft, BarChart3, BellRing, Building2, Calculator, CalendarClock, CheckCircle2, CirclePlus, Copy, ExternalLink, Info, LayoutDashboard, ListTree,
    Link2, LockKeyhole, Pencil, Save, ShieldCheck, SlidersHorizontal, X
  } from '@lucide/svelte';
  import { normalizeLiffId } from '$lib/auth/liffConfig';
  import { tenantContext } from '$lib/stores/tenantContext';
  import { getSupabaseBrowserClient } from '$lib/supabase/browser';
  import {
    createOrganizationUnitType,
    createCalculatedMetric,
    createStatisticMetric,
    updateOrganizationUnitType,
    updateCalculatedMetric,
    updateDashboardMetricSettings,
    updateStatisticMetric,
    updateTenantNotificationSchedule,
    updateTenantSettings,
    type NotificationScheduleDay
  } from '$lib/api/tenantSettingsApi';

  type Tab = 'general' | 'ou-types' | 'metrics';
  type DataType = 'number' | 'text' | 'boolean';
  type InputType = 'number' | 'text' | 'checkbox';
  type Aggregation = 'sum' | 'avg' | 'max' | 'min' | 'none';
  type MetricKind = 'input' | 'calculated';
  type OuTypeSetting = {
    id: string;
    name: string;
    code: string;
    description: string;
    sortOrder: number;
    defaultAllowDataEntry: boolean;
    usageCount: number;
    active: boolean;
    locked: boolean;
  };
  type MetricSetting = {
    id: string;
    code: string;
    name: string;
    description: string;
    category: string;
    unit: string;
    dataType: DataType;
    inputType: InputType;
    aggregation: Aggregation;
    defaultValue: number | null;
    required: boolean;
    minValue: number | null;
    maxValue: number | null;
    sortOrder: number;
    active: boolean;
    metricKind: MetricKind;
    calculationOperator: 'sum' | 'ratio' | null;
    calculationSourceMetricIds: string[];
    numeratorCount: number;
    dashboardVisible: boolean;
    dashboardOrder: number;
  };

  let activeTab: Tab = 'general';
  let tenantName = '';
  let tenantTimezone = 'Asia/Bangkok';
  let tenantWeekEndsOn = '0';
  let tenantSubmissionDeadlineDays = '1';
  let tenantApprovalMode = 'auto_approve';
  let tenantPrimaryMetricId = '';
  let notificationScheduleEnabled = false;
  let notificationScheduleDays: NotificationScheduleDay[] = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];
  let missingReminderLocalHour = 9;
  let approvalDigestLocalHour = 9;
  const notificationDayOptions: { value: NotificationScheduleDay; label: string }[] = [
    { value: 'MON', label: 'จันทร์' },
    { value: 'TUE', label: 'อังคาร' },
    { value: 'WED', label: 'พุธ' },
    { value: 'THU', label: 'พฤหัสบดี' },
    { value: 'FRI', label: 'ศุกร์' },
    { value: 'SAT', label: 'เสาร์' },
    { value: 'SUN', label: 'อาทิตย์' }
  ];
  let toastMessage = '';
  let ouModalOpen = false;
  let metricModalOpen = false;
  let editingOuId: string | null = null;
  let editingMetricId: string | null = null;

  let ouTypes: OuTypeSetting[] = [];
  let metrics: MetricSetting[] = [];
  let settingsLoading = true;
  let settingsError = '';
  let mutationError = '';
  let mutationBusy = false;
  let rootOuName = '';
  let rootOuTypeId = '';

  let ouName = '';
  let ouCode = '';
  let ouSortOrder = 10;
  let ouDefaultAllowDataEntry = false;
  let ouDescription = '';
  let metricName = '';
  let metricCode = '';
  let metricDescription = '';
  let metricCategory = 'attendance';
  let metricUnit = 'คน';
  let metricDataType: DataType = 'number';
  let metricAggregation: Aggregation = 'sum';
  let metricDefaultValue: number | null = 0;
  let metricRequired = false;
  let metricMinValue: number | null = 0;
  let metricMaxValue: number | null = null;
  let metricSortOrder = 10;
  let metricKind: MetricKind = 'input';
  let metricSourceIds: string[] = [];
  let metricOperator: 'sum' | 'ratio' = 'sum';
  let numeratorIds: string[] = [];
  let denominatorIds: string[] = [];
  $: selectedSourceIds = metricOperator === 'ratio' ? [...numeratorIds, ...denominatorIds] : metricSourceIds;
  $: invalidCalculation = metricKind === 'calculated' && (metricOperator === 'ratio' ? !numeratorIds.length || !denominatorIds.length : metricSourceIds.length < 2);

  $: activeOuCount = ouTypes.filter((item) => item.active).length;
  $: activeMetricCount = metrics.filter((item) => item.active).length;
  $: calculationSourceOptions = metrics.filter((item) => item.active && item.metricKind === 'input' && item.dataType === 'number' && item.aggregation === 'sum' && item.id !== editingMetricId);
  $: dashboardMetricOptions = metrics.filter((item) => item.active && item.dataType === 'number' && item.aggregation !== 'none');
  $: selectedDashboardMetricCount = dashboardMetricOptions.filter((item) => item.dashboardVisible).length;
  $: formulaPreview = formatFormula(selectedSourceIds, metrics, metricOperator, numeratorIds.length);
  $: productionLiffId = normalizeLiffId(env.PUBLIC_LINE_LIFF_PRODUCTION_ID || env.PUBLIC_LINE_LIFF_ID);
  $: productionLiffUrl = productionLiffId ? `https://liff.line.me/${productionLiffId}` : '';
  $: productionAppUrl = (env.PUBLIC_PRODUCTION_APP_URL || '').replace(/\/$/, '');

  async function loadSettings(showLoading = true): Promise<void> {
    if (showLoading) settingsLoading = true;
    settingsError = '';
    try {
      const client = getSupabaseBrowserClient();
      const [tenantResult, ouTypeResult, ouUsageResult, metricResult] = await Promise.all([
        client
          .from('churches')
          .select('name,timezone,reporting_week_ends_on,submission_deadline_days_after_period_end,approval_mode,primary_metric_id,notification_schedule_enabled,notification_schedule_days,missing_reminder_local_hour,approval_digest_local_hour')
          .single(),
        client
          .from('organization_unit_types')
          .select('id,name,code,description,sort_order,default_allow_data_entry,is_active')
          .order('sort_order'),
        client
          .from('organization_units')
          .select('ou_type_id,name,parent_id,level'),
        client
          .from('statistic_metrics')
          .select('id,code,name,description,category,unit,data_type,input_type,aggregation,default_value,is_required,min_value,max_value,sort_order,is_active,metric_kind,calculation_operator,calculation_source_metric_ids,ratio_numerator_count,show_on_dashboard,dashboard_order')
          .is('deleted_at', null)
          .order('sort_order')
      ]);
      if (tenantResult.error) throw tenantResult.error;
      if (ouTypeResult.error) throw ouTypeResult.error;
      if (ouUsageResult.error) throw ouUsageResult.error;
      if (metricResult.error) throw metricResult.error;

      tenantName = tenantResult.data.name;
      tenantTimezone = tenantResult.data.timezone;
      tenantWeekEndsOn = String(tenantResult.data.reporting_week_ends_on);
      tenantSubmissionDeadlineDays = String(tenantResult.data.submission_deadline_days_after_period_end);
      tenantApprovalMode = tenantResult.data.approval_mode;
      tenantPrimaryMetricId = tenantResult.data.primary_metric_id ?? '';
      notificationScheduleEnabled = tenantResult.data.notification_schedule_enabled;
      notificationScheduleDays = tenantResult.data.notification_schedule_days as NotificationScheduleDay[];
      missingReminderLocalHour = tenantResult.data.missing_reminder_local_hour;
      approvalDigestLocalHour = tenantResult.data.approval_digest_local_hour;

      const usage = new Map<string, number>();
      for (const organization of ouUsageResult.data ?? []) {
        usage.set(organization.ou_type_id, (usage.get(organization.ou_type_id) ?? 0) + 1);
      }
      const rootOu = (ouUsageResult.data ?? []).find(
        (organization) => organization.parent_id === null && organization.level === 1
      );
      rootOuName = rootOu?.name ?? '';
      rootOuTypeId = rootOu?.ou_type_id ?? '';
      ouTypes = (ouTypeResult.data ?? []).map((item) => ({
        id: item.id,
        name: item.name,
        code: item.code,
        description: item.description ?? '',
        sortOrder: item.sort_order,
        defaultAllowDataEntry: item.default_allow_data_entry,
        usageCount: usage.get(item.id) ?? 0,
        active: item.is_active,
        locked: item.id === rootOuTypeId
      }));
      metrics = (metricResult.data ?? []).map((item) => ({
        id: item.id,
        code: item.code,
        name: item.name,
        description: item.description ?? '',
        category: item.category,
        unit: item.unit,
        dataType: item.data_type as DataType,
        inputType: item.input_type as InputType,
        aggregation: item.aggregation as Aggregation,
        defaultValue: item.default_value === null ? null : Number(item.default_value),
        required: item.is_required,
        minValue: item.min_value === null ? null : Number(item.min_value),
        maxValue: item.max_value === null ? null : Number(item.max_value),
        sortOrder: item.sort_order,
        active: item.is_active,
        metricKind: item.metric_kind as MetricKind,
        calculationOperator: item.calculation_operator as 'sum' | 'ratio' | null,
        calculationSourceMetricIds: item.calculation_source_metric_ids ?? [],
        numeratorCount: item.ratio_numerator_count ?? 1,
        dashboardVisible: item.show_on_dashboard,
        dashboardOrder: item.dashboard_order
      }));
    } catch (error) {
      settingsError = error instanceof Error ? error.message : 'ไม่สามารถโหลด Tenant Settings ได้';
    } finally {
      if (showLoading) settingsLoading = false;
    }
  }

  onMount(() => {
    void loadSettings();
  });

  function openCreateOu(): void {
    editingOuId = null;
    ouName = '';
    ouCode = '';
    ouSortOrder = Math.max(0, ...ouTypes.map((item) => item.sortOrder)) + 10;
    ouDefaultAllowDataEntry = false;
    ouDescription = '';
    ouModalOpen = true;
  }

  function openEditOu(item: OuTypeSetting): void {
    editingOuId = item.id;
    ouName = item.name;
    ouCode = item.code;
    ouSortOrder = item.sortOrder;
    ouDefaultAllowDataEntry = item.defaultAllowDataEntry;
    ouDescription = item.description;
    ouModalOpen = true;
  }

  async function saveOuType(): Promise<void> {
    if (!ouName.trim() || !ouCode.trim()) return;
    mutationBusy = true;
    mutationError = '';
    try {
      const client = getSupabaseBrowserClient();
      if (editingOuId) {
        const current = ouTypes.find((item) => item.id === editingOuId);
        await updateOrganizationUnitType(client, editingOuId, {
          name: ouName.trim(),
          description: ouDescription.trim(),
          sortOrder: ouSortOrder,
          defaultAllowDataEntry: ouDefaultAllowDataEntry,
          isActive: current?.active ?? true
        });
        toastMessage = `แก้ไข OU Type “${ouName.trim()}” แล้ว`;
      } else {
        await createOrganizationUnitType(client, {
          code: ouCode.trim().toUpperCase(),
          name: ouName.trim(),
          description: ouDescription.trim(),
          sortOrder: ouSortOrder,
          defaultAllowDataEntry: ouDefaultAllowDataEntry
        });
        toastMessage = `เพิ่ม OU Type “${ouName.trim()}” แล้ว`;
      }
      ouModalOpen = false;
      await loadSettings(false);
    } catch (error) {
      mutationError = error instanceof Error ? error.message : 'บันทึก OU Type ไม่สำเร็จ';
    } finally {
      mutationBusy = false;
    }
  }

  async function toggleOuType(id: string): Promise<void> {
    const item = ouTypes.find((candidate) => candidate.id === id);
    if (!item || item.locked) return;
    mutationBusy = true;
    mutationError = '';
    try {
      await updateOrganizationUnitType(getSupabaseBrowserClient(), id, {
        name: item.name,
        description: item.description,
        sortOrder: item.sortOrder,
        defaultAllowDataEntry: item.defaultAllowDataEntry,
        isActive: !item.active
      });
      toastMessage = 'อัปเดตสถานะ OU Type แล้ว';
      await loadSettings(false);
    } catch (error) {
      mutationError = error instanceof Error ? error.message : 'อัปเดต OU Type ไม่สำเร็จ';
    } finally {
      mutationBusy = false;
    }
  }

  function openCreateMetric(): void {
    mutationError = '';
    editingMetricId = null;
    metricName = '';
    metricCode = '';
    metricDescription = '';
    metricCategory = 'attendance';
    metricUnit = 'คน';
    metricDataType = 'number';
    metricAggregation = 'sum';
    metricDefaultValue = 0;
    metricRequired = false;
    metricMinValue = 0;
    metricMaxValue = null;
    metricSortOrder = Math.max(0, ...metrics.map((item) => item.sortOrder)) + 10;
    metricKind = 'input';
    metricSourceIds = [];
    metricOperator = 'sum';
    numeratorIds = [];
    denominatorIds = [];
    metricModalOpen = true;
  }

  function openEditMetric(item: MetricSetting): void {
    mutationError = '';
    editingMetricId = item.id;
    metricName = item.name;
    metricCode = item.code;
    metricDescription = item.description;
    metricCategory = item.category;
    metricUnit = item.unit;
    metricDataType = item.dataType;
    metricAggregation = item.aggregation;
    metricDefaultValue = item.defaultValue;
    metricRequired = item.required;
    metricMinValue = item.minValue;
    metricMaxValue = item.maxValue;
    metricSortOrder = item.sortOrder;
    metricKind = item.metricKind;
    metricSourceIds = [...item.calculationSourceMetricIds];
    metricOperator = item.calculationOperator ?? 'sum';
    numeratorIds = metricSourceIds.slice(0, item.numeratorCount);
    denominatorIds = metricSourceIds.slice(item.numeratorCount);
    metricModalOpen = true;
  }

  async function saveMetric(): Promise<void> {
    // Remove invisible formatting sometimes included in pasted metric codes.
    const code = metricCode.replace(/[\u200B-\u200D\uFEFF]/g, '').trim().toUpperCase();
    if (!editingMetricId) metricCode = code;
    if (!editingMetricId && !/^[A-Z][A-Z0-9_]{0,79}$/.test(code)) {
      mutationError = 'Metric Code ต้องขึ้นต้นด้วย A–Z ใช้ได้เฉพาะ A–Z, 0–9 และ _ รวมไม่เกิน 80 ตัวอักษร';
      return;
    }
    for (const [label, value, limit] of [
      ['ชื่อแสดงผล', metricName, 255], ['หมวดหมู่', metricCategory, 80], ['หน่วย', metricUnit, 50]
    ] as const) {
      if ((label !== 'หน่วย' || metricKind !== 'calculated' || metricOperator !== 'ratio') && (!value.trim() || [...value.trim()].length > limit)) {
        mutationError = `กรุณากรอก${label} ไม่เกิน ${limit} ตัวอักษร`;
        return;
      }
    }
    if (!Number.isInteger(metricSortOrder) || metricSortOrder < 0 || metricSortOrder > 2147483647) {
      mutationError = 'ลำดับแสดงผลต้องเป็นจำนวนเต็มตั้งแต่ 0 ถึง 2147483647';
      return;
    }
    if (invalidCalculation) {
      mutationError = metricOperator === 'ratio' ? 'กรุณาเลือกตัวตั้ง (A) และตัวหาร (B)' : 'Calculated Field ต้องเลือก Field ต้นทางอย่างน้อย 2 รายการ';
      return;
    }
    const values = {
      name: metricName.trim(),
      description: metricDescription.trim(),
      category: metricCategory.trim().toLowerCase(),
      unit: metricKind === 'calculated' && metricOperator === 'ratio' ? '%' : metricUnit.trim(),
      dataType: metricDataType,
      aggregation: metricDataType === 'number' ? metricAggregation : 'none' as Aggregation,
      defaultValue: metricDataType === 'number' ? metricDefaultValue : null,
      isRequired: metricRequired,
      minValue: metricDataType === 'number' ? metricMinValue : null,
      maxValue: metricDataType === 'number' ? metricMaxValue : null,
      sortOrder: metricSortOrder
    };
    mutationBusy = true;
    mutationError = '';
    try {
      const client = getSupabaseBrowserClient();
      if (metricKind === 'calculated') {
        const calculatedValues = {
          name: values.name,
          description: values.description,
          category: values.category,
          unit: values.unit,
          sortOrder: values.sortOrder,
          operator: metricOperator,
          numeratorCount: metricOperator === 'ratio' ? numeratorIds.length : undefined,
          sourceMetricIds: selectedSourceIds
        };
        if (editingMetricId) {
          const current = metrics.find((item) => item.id === editingMetricId);
          await updateCalculatedMetric(client, editingMetricId, { ...calculatedValues, isActive: current?.active ?? true });
          toastMessage = `แก้ไข Calculated Field “${metricName.trim()}” แล้ว`;
        } else {
          await createCalculatedMetric(client, { code, ...calculatedValues });
          toastMessage = `เพิ่ม Calculated Field “${metricName.trim()}” แล้ว`;
        }
      } else if (editingMetricId) {
        const current = metrics.find((item) => item.id === editingMetricId);
        await updateStatisticMetric(client, editingMetricId, {
          name: values.name,
          description: values.description,
          category: values.category,
          unit: values.unit,
          aggregation: values.aggregation,
          defaultValue: values.defaultValue,
          minValue: values.minValue,
          maxValue: values.maxValue,
          isRequired: values.isRequired,
          sortOrder: values.sortOrder,
          isActive: current?.active ?? true
        });
        toastMessage = `แก้ไข Field “${metricName.trim()}” แล้ว`;
      } else {
        await createStatisticMetric(client, {
          code,
          ...values
        });
        toastMessage = `เพิ่ม Field “${metricName.trim()}” แล้ว`;
      }
      metricModalOpen = false;
      await loadSettings(false);
    } catch (error) {
      mutationError = error instanceof Error ? error.message : 'บันทึก Field สถิติไม่สำเร็จ';
    } finally {
      mutationBusy = false;
    }
  }

  async function toggleMetric(id: string): Promise<void> {
    const item = metrics.find((candidate) => candidate.id === id);
    if (!item) return;
    mutationBusy = true;
    mutationError = '';
    try {
      if (item.metricKind === 'calculated') {
        await updateCalculatedMetric(getSupabaseBrowserClient(), id, {
          name: item.name, description: item.description, category: item.category, unit: item.unit,
          sortOrder: item.sortOrder, operator: item.calculationOperator ?? 'sum', sourceMetricIds: item.calculationSourceMetricIds, numeratorCount: item.numeratorCount, isActive: !item.active
        });
      } else {
        await updateStatisticMetric(getSupabaseBrowserClient(), id, {
          name: item.name, description: item.description, category: item.category, unit: item.unit,
          aggregation: item.aggregation, defaultValue: item.defaultValue, minValue: item.minValue,
          maxValue: item.maxValue, isRequired: item.required, sortOrder: item.sortOrder, isActive: !item.active
        });
      }
      toastMessage = 'อัปเดตสถานะ Field สถิติแล้ว';
      await loadSettings(false);
    } catch (error) {
      mutationError = error instanceof Error ? error.message : 'อัปเดต Field สถิติไม่สำเร็จ';
    } finally {
      mutationBusy = false;
    }
  }

  function toggleDashboardMetric(id: string): void {
    const item = metrics.find((candidate) => candidate.id === id);
    if (!item) return;
    item.dashboardVisible = !item.dashboardVisible;
    if (item.dashboardVisible && item.dashboardOrder <= 0) {
      item.dashboardOrder = Math.max(0, ...metrics.filter((metric) => metric.dashboardVisible).map((metric) => metric.dashboardOrder)) + 10;
    }
    metrics = [...metrics];
  }

  async function saveDashboardMetrics(): Promise<void> {
    const selectedIds = dashboardMetricOptions
      .filter((item) => item.dashboardVisible)
      .sort((left, right) => left.dashboardOrder - right.dashboardOrder || left.sortOrder - right.sortOrder || left.name.localeCompare(right.name))
      .map((item) => item.id);
    if (!selectedIds.length) {
      mutationError = 'กรุณาเลือก Matrix สำหรับ Dashboard อย่างน้อย 1 รายการ';
      return;
    }
    mutationBusy = true;
    mutationError = '';
    try {
      await updateDashboardMetricSettings(getSupabaseBrowserClient(), selectedIds);
      toastMessage = `บันทึก Matrix สำหรับ Dashboard ${selectedIds.length} รายการแล้ว`;
      await loadSettings(false);
    } catch (error) {
      mutationError = error instanceof Error ? error.message : 'บันทึกการตั้งค่า Dashboard ไม่สำเร็จ';
    } finally {
      mutationBusy = false;
    }
  }

  function toggleMetricSource(metricId: string): void {
    metricSourceIds = metricSourceIds.includes(metricId)
      ? metricSourceIds.filter((id) => id !== metricId)
      : [...metricSourceIds, metricId];
  }

  function formatFormula(ids: string[], fields: MetricSetting[], operator: 'sum' | 'ratio' | null, split: number): string {
    const names = ids.map(id => fields.find(field => field.id === id)?.name ?? '?');
    if (operator !== 'ratio') return names.join(' + ');
    return `[(${names.slice(0, split).join(' + ') || 'A'}) ÷ (${names.slice(split).join(' + ') || 'B'}) ] × 100`;
  }

  async function saveGeneralSettings(): Promise<void> {
    mutationBusy = true;
    mutationError = '';
    try {
      const client = getSupabaseBrowserClient();
      await updateTenantSettings(client, {
        name: tenantName.trim(),
        timezone: tenantTimezone,
        approvalMode: tenantApprovalMode as 'auto_approve' | 'approval_required',
        reportingWeekEndsOn: Number(tenantWeekEndsOn),
        submissionDeadlineDaysAfterPeriodEnd: Number(tenantSubmissionDeadlineDays),
        primaryMetricId: tenantPrimaryMetricId || null
      });
      toastMessage = 'อัปเดตค่าทั่วไปของ Tenant แล้ว';
      await loadSettings(false);
    } catch (error) {
      mutationError = error instanceof Error ? error.message : 'บันทึก Tenant Settings ไม่สำเร็จ';
    } finally {
      mutationBusy = false;
    }
  }

  function toggleNotificationDay(day: NotificationScheduleDay): void {
    notificationScheduleDays = notificationScheduleDays.includes(day)
      ? notificationScheduleDays.filter((item) => item !== day)
      : notificationDayOptions
          .map((item) => item.value)
          .filter((item) => item === day || notificationScheduleDays.includes(item));
  }

  async function saveNotificationSchedule(): Promise<void> {
    if (notificationScheduleDays.length === 0) {
      mutationError = 'กรุณาเลือกวันแจ้งเตือนอย่างน้อย 1 วัน';
      return;
    }
    mutationBusy = true;
    mutationError = '';
    try {
      await updateTenantNotificationSchedule(getSupabaseBrowserClient(), {
        enabled: notificationScheduleEnabled,
        scheduleDays: notificationScheduleDays,
        missingReminderLocalHour: Number(missingReminderLocalHour),
        approvalDigestLocalHour: Number(approvalDigestLocalHour)
      });
      toastMessage = 'อัปเดตตารางเวลาแจ้งเตือนแล้ว';
      await loadSettings(false);
    } catch (error) {
      mutationError = error instanceof Error ? error.message : 'บันทึกตารางเวลาแจ้งเตือนไม่สำเร็จ';
    } finally {
      mutationBusy = false;
    }
  }

  async function copyPlatformLink(value: string, label: string): Promise<void> {
    if (!value) return;
    await navigator.clipboard.writeText(value);
    toastMessage = `คัดลอก ${label} แล้ว`;
  }
</script>

<svelte:head><title>Tenant Settings | CSMS</title></svelte:head>

<div class="app-page space-y-5">
  {#if settingsLoading}
    <p class="app-card px-4 py-3 text-sm text-slate-500">กำลังโหลด Tenant Settings จากฐานข้อมูล...</p>
  {:else if settingsError}
    <p class="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700">{settingsError}</p>
  {:else}
    <p class="rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-xs leading-5 text-emerald-800">เชื่อมต่อ Tenant Settings API แล้ว การเปลี่ยนแปลงจะบันทึกลงฐานข้อมูลของ {$tenantContext.activeTenant?.name} และสร้าง Audit Log</p>
  {/if}
  {#if mutationError && !metricModalOpen}
    <p class="rounded-2xl border border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-700" role="alert">{mutationError}</p>
  {/if}
  <section class="app-card relative overflow-hidden p-4 sm:p-5 lg:p-6" aria-labelledby="tenant-settings-title">
    <div class="pointer-events-none absolute -right-16 -top-20 h-64 w-64 rounded-full bg-violet-200/40 blur-3xl"></div>
    <div class="relative flex flex-col gap-5 lg:flex-row lg:items-start lg:justify-between">
      <div class="max-w-2xl">
        <a class="app-focus inline-flex items-center gap-1.5 text-sm font-semibold text-slate-500 hover:text-sky-700" href="/app/settings"><ArrowLeft size={16} /> กลับไปหน้าตั้งค่า</a>
        <span class="mt-4 flex w-fit items-center gap-2 rounded-full border border-violet-200 bg-violet-50 px-3 py-1 text-[0.7rem] font-semibold uppercase tracking-[0.18em] text-violet-800"><SlidersHorizontal size={14} /> Tenant Settings</span>
        <h1 id="tenant-settings-title" class="mt-3 text-2xl font-semibold tracking-tight text-slate-950 sm:text-3xl">ตั้งค่าโครงสร้างและแบบฟอร์ม</h1>
        <p class="mt-2 text-sm leading-6 text-slate-600">ค่าหน้านี้มีผลกับทุก OU ภายใน {tenantName || $tenantContext.activeTenant?.name} และสงวนให้ Admin ที่ได้รับมอบหมายโดยตรงบน Root OU Level 1 เท่านั้น</p>
      </div>
      <div class="rounded-2xl border border-emerald-200 bg-emerald-50/90 p-4 lg:min-w-72">
        <p class="flex items-center gap-2 text-sm font-semibold text-emerald-900"><ShieldCheck size={18} /> สิทธิ์ระดับองค์กร</p>
        <p class="mt-1.5 text-xs leading-5 text-emerald-800">Root OU Admin · Direct assignment · {rootOuName || 'Root OU'}</p>
      </div>
    </div>
  </section>

  <section class="grid gap-3 sm:grid-cols-3" aria-label="Tenant setting summary">
    <article class="app-card p-4"><p class="text-xs text-slate-500">OU Type ที่เปิดใช้</p><p class="mt-1 text-2xl font-semibold text-slate-950">{activeOuCount}</p></article>
    <article class="app-card p-4"><p class="text-xs text-slate-500">Field สถิติที่เปิดใช้</p><p class="mt-1 text-2xl font-semibold text-slate-950">{activeMetricCount}</p></article>
    <article class="app-card p-4"><p class="text-xs text-slate-500">ขอบเขตการตั้งค่า</p><p class="mt-1 text-sm font-semibold text-violet-800">ทั้ง Tenant</p></article>
  </section>

  <section class="app-card overflow-hidden">
    <div class="flex gap-1 overflow-x-auto border-b border-slate-100 bg-slate-50/70 p-2" role="tablist" aria-label="Tenant setting sections">
      <button type="button" role="tab" aria-selected={activeTab === 'general'} class={`app-focus inline-flex min-w-max flex-1 items-center justify-center gap-2 rounded-2xl px-4 py-3 text-sm font-semibold transition ${activeTab === 'general' ? 'bg-white text-sky-800 shadow-sm ring-1 ring-sky-100' : 'text-slate-500 hover:bg-white/70'}`} on:click={() => (activeTab = 'general')}><Building2 size={17} /> ทั่วไป</button>
      <button type="button" role="tab" aria-selected={activeTab === 'ou-types'} class={`app-focus inline-flex min-w-max flex-1 items-center justify-center gap-2 rounded-2xl px-4 py-3 text-sm font-semibold transition ${activeTab === 'ou-types' ? 'bg-white text-sky-800 shadow-sm ring-1 ring-sky-100' : 'text-slate-500 hover:bg-white/70'}`} on:click={() => (activeTab = 'ou-types')}><ListTree size={17} /> ประเภท OU</button>
      <button type="button" role="tab" aria-selected={activeTab === 'metrics'} class={`app-focus inline-flex min-w-max flex-1 items-center justify-center gap-2 rounded-2xl px-4 py-3 text-sm font-semibold transition ${activeTab === 'metrics' ? 'bg-white text-sky-800 shadow-sm ring-1 ring-sky-100' : 'text-slate-500 hover:bg-white/70'}`} on:click={() => (activeTab = 'metrics')}><BarChart3 size={17} /> Field สถิติ</button>
    </div>

    {#if activeTab === 'general'}
      <div class="p-4 sm:p-5">
        <div><h2 class="app-section-title">ค่าทั่วไปของ Tenant</h2><p class="app-section-copy">ใช้กับรอบรายงาน ขั้นตอนอนุมัติ และ Dashboard ของทั้งองค์กร</p></div>
        <fieldset disabled={mutationBusy || settingsLoading} class="mt-5 grid gap-4 sm:grid-cols-2">
          <label class="sm:col-span-2"><span class="text-sm font-medium text-slate-700">ชื่อ Tenant</span><input class="app-input mt-2" bind:value={tenantName} /></label>
          <label><span class="text-sm font-medium text-slate-700">Timezone</span><select class="app-input mt-2" bind:value={tenantTimezone}><option>Asia/Bangkok</option><option>Asia/Singapore</option><option>UTC</option></select></label>
          <label><span class="text-sm font-medium text-slate-700">วันสิ้นสุดรอบคำนวณ</span><select class="app-input mt-2" bind:value={tenantWeekEndsOn}><option value="0">วันอาทิตย์</option><option value="6">วันเสาร์</option></select><span class="mt-1 block text-xs text-slate-500">กำหนด period_end และขอบเขตตัวเลขที่ใช้ในรายงาน</span></label>
          <label><span class="text-sm font-medium text-slate-700">กำหนดส่งหลังสิ้นสุดรอบ</span><select class="app-input mt-2" bind:value={tenantSubmissionDeadlineDays}><option value="1">1 วัน</option><option value="2">2 วัน</option><option value="3">3 วัน</option><option value="4">4 วัน</option><option value="5">5 วัน</option><option value="6">6 วัน</option></select><span class="mt-1 block text-xs text-slate-500">ปิดรับเวลา 23:59 ตาม Timezone ของ Tenant</span></label>
          <label><span class="text-sm font-medium text-slate-700">โหมดอนุมัติ</span><select class="app-input mt-2" bind:value={tenantApprovalMode}><option value="auto_approve">อนุมัติอัตโนมัติ</option><option value="approval_required">ต้องผ่านผู้อนุมัติ</option></select></label>
          <label><span class="text-sm font-medium text-slate-700">Primary KPI</span><select class="app-input mt-2" bind:value={tenantPrimaryMetricId}>{#each metrics.filter((item) => item.active && item.metricKind === 'input' && item.dataType === 'number') as item}<option value={item.id}>{item.name}</option>{/each}</select></label>
        </fieldset>
        <section class="mt-5 rounded-2xl border border-sky-200 bg-sky-50/50 p-4 sm:p-5" aria-labelledby="notification-schedule-title">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div>
              <h3 id="notification-schedule-title" class="flex items-center gap-2 text-sm font-semibold text-sky-950"><CalendarClock size={17} /> Scheduled Notification</h3>
              <p class="mt-1 text-xs leading-5 text-sky-800">กำหนดวันและเวลาตาม Timezone ของ Tenant ระบบ Cron กลางจะตรวจทุกชั่วโมงและไม่สร้างรายการซ้ำในวันเดียวกัน</p>
            </div>
            <label class="inline-flex w-fit items-center gap-2 rounded-full border border-sky-200 bg-white px-3 py-2 text-xs font-semibold text-sky-900">
              <input type="checkbox" class="h-4 w-4 accent-sky-700" bind:checked={notificationScheduleEnabled} disabled={mutationBusy || settingsLoading} />
              เปิดใช้งาน
            </label>
          </div>
          <fieldset disabled={mutationBusy || settingsLoading} class="mt-4 space-y-4">
            <div>
              <span class="text-sm font-medium text-slate-700">วันแจ้งเตือน</span>
              <div class="mt-2 grid grid-cols-2 gap-2 sm:grid-cols-4 lg:grid-cols-7">
                {#each notificationDayOptions as day}
                  <label class={`app-focus flex cursor-pointer items-center gap-2 rounded-xl border px-3 py-2.5 text-xs font-semibold transition ${notificationScheduleDays.includes(day.value) ? 'border-sky-300 bg-white text-sky-900 shadow-sm' : 'border-slate-200 bg-slate-50 text-slate-500'}`}>
                    <input type="checkbox" class="h-4 w-4 accent-sky-700" checked={notificationScheduleDays.includes(day.value)} on:change={() => toggleNotificationDay(day.value)} />
                    {day.label}
                  </label>
                {/each}
              </div>
              <p class="mt-2 text-xs text-slate-500">รหัสวันใช้ MON, TUE, WED, THU, FRI, SAT และ SUN</p>
            </div>
            <div class="grid gap-4 sm:grid-cols-2">
              <label><span class="text-sm font-medium text-slate-700">เวลาเตือนรายงานที่ยังไม่ส่ง</span><select class="app-input mt-2" bind:value={missingReminderLocalHour}>{#each Array.from({ length: 24 }, (_, hour) => hour) as hour}<option value={hour}>{String(hour).padStart(2, '0')}:00</option>{/each}</select></label>
              <label><span class="text-sm font-medium text-slate-700">เวลาสรุปรายงานรออนุมัติ</span><select class="app-input mt-2" bind:value={approvalDigestLocalHour}>{#each Array.from({ length: 24 }, (_, hour) => hour) as hour}<option value={hour}>{String(hour).padStart(2, '0')}:00</option>{/each}</select></label>
            </div>
          </fieldset>
          <div class="mt-4 flex justify-end"><button type="button" class="app-button-secondary inline-flex items-center gap-2" disabled={mutationBusy || settingsLoading} on:click={saveNotificationSchedule}><Save size={16} /> {mutationBusy ? 'กำลังบันทึก...' : 'บันทึกเวลาแจ้งเตือน'}</button></div>
        </section>
        <section class="mt-5 rounded-2xl border border-emerald-200 bg-emerald-50/50 p-4 sm:p-5" aria-labelledby="line-platform-title">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div><h3 id="line-platform-title" class="flex items-center gap-2 text-sm font-semibold text-emerald-950"><Link2 size={17} /> LINE OA & Rich Menu</h3><p class="mt-1 text-xs leading-5 text-emerald-800">Platform เป็นผู้ดูแล LINE Login และ LIFF กลาง Tenant ใช้ URL นี้สร้างปุ่ม Link/URI ใน Rich Menu ของ LINE OA โดยไม่ต้องตั้ง LIFF ID เอง</p></div>
            <span class="w-fit rounded-full border border-emerald-200 bg-white px-2.5 py-1 text-[0.68rem] font-semibold text-emerald-700">Read-only</span>
          </div>
          <div class="mt-4 grid gap-3 lg:grid-cols-2">
            <article class="rounded-2xl border border-emerald-100 bg-white p-4">
              <p class="text-xs font-semibold uppercase tracking-[0.12em] text-emerald-700">Production Rich Menu URL</p>
              <p class="mt-2 break-all text-sm font-semibold text-slate-900">{productionLiffUrl || 'Platform ยังไม่ได้ตั้งค่า Production LIFF URL'}</p>
              <div class="mt-3 flex flex-wrap gap-2"><button type="button" class="app-button-secondary min-h-0 px-3 py-2 text-xs" disabled={!productionLiffUrl} on:click={() => copyPlatformLink(productionLiffUrl, 'Rich Menu URL')}><Copy size={14} /> คัดลอก</button>{#if productionLiffUrl}<a class="app-button-secondary min-h-0 px-3 py-2 text-xs" href={productionLiffUrl} target="_blank" rel="noreferrer"><ExternalLink size={14} /> เปิดทดสอบ</a>{/if}</div>
            </article>
            <article class="rounded-2xl border border-sky-100 bg-white p-4">
              <p class="text-xs font-semibold uppercase tracking-[0.12em] text-sky-700">Production Web URL</p>
              <p class="mt-2 break-all text-sm font-semibold text-slate-900">{productionAppUrl || 'Platform ยังไม่ได้ตั้งค่า Production App URL'}</p>
              <div class="mt-3"><button type="button" class="app-button-secondary min-h-0 px-3 py-2 text-xs" disabled={!productionAppUrl} on:click={() => copyPlatformLink(productionAppUrl, 'Web URL')}><Copy size={14} /> คัดลอก</button></div>
            </article>
          </div>
          <div class="mt-4 flex gap-3 rounded-2xl border border-violet-200 bg-violet-50 p-4"><BellRing class="mt-0.5 shrink-0 text-violet-700" size={18} /><div><p class="text-sm font-semibold text-violet-950">เส้นทาง Notification: CSMS LINE OA กลาง</p><p class="mt-1 text-xs leading-5 text-violet-800">Tenant OA ใช้ Rich Menu เพื่อพาผู้ใช้เข้า CSMS เมื่อเปิดใช้บริการส่ง Notification ระบบจะส่งการเตือนผ่าน OA กลางของ Platform โดย Credential และการเปิดบริการเป็นการตั้งค่าระดับ Platform ไม่ใช่ Tenant Settings</p></div></div>
        </section>
        <div class="mt-5 flex justify-end"><button type="button" class="app-button-primary inline-flex items-center gap-2" disabled={mutationBusy || settingsLoading} on:click={saveGeneralSettings}><Save size={16} /> {mutationBusy ? 'กำลังบันทึก...' : 'บันทึกค่าทั่วไป'}</button></div>
      </div>
    {:else if activeTab === 'ou-types'}
      <div class="border-b border-slate-100 p-4 sm:p-5">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div><h2 class="app-section-title">รายการประเภท OU</h2><p class="app-section-copy">ประเภท OU ใช้ร่วมกันทั้ง Tenant และไม่ผูกตายกับระดับของโครงสร้าง</p></div>
          <button type="button" class="app-button-primary app-focus inline-flex items-center justify-center gap-2" disabled={mutationBusy} on:click={openCreateOu}><CirclePlus size={17} /> เพิ่ม OU Type</button>
        </div>
      </div>
      <div class="divide-y divide-slate-100">
        {#each ouTypes as item}
          <article class="grid gap-4 p-4 sm:p-5 lg:grid-cols-[4rem_minmax(0,1fr)_8rem_11rem] lg:items-center">
            <div class="flex h-12 w-12 items-center justify-center rounded-2xl bg-sky-50 text-xs font-bold text-sky-700">#{item.sortOrder}</div>
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2"><h3 class="text-sm font-semibold text-slate-950">{item.name}</h3><span class="rounded-full bg-slate-100 px-2 py-0.5 text-[0.68rem] font-semibold text-slate-500">{item.code}</span>{#if item.locked}<span class="inline-flex items-center gap-1 rounded-full bg-violet-50 px-2 py-0.5 text-[0.68rem] font-semibold text-violet-700"><LockKeyhole size={11} /> Root</span>{/if}</div>
              <p class="mt-1 text-xs leading-5 text-slate-500">{item.description} · ใช้งานอยู่ {item.usageCount} OU · {item.defaultAllowDataEntry ? 'รับข้อมูลโดยค่าเริ่มต้น' : 'ไม่รับข้อมูลโดยค่าเริ่มต้น'}</p>
            </div>
            <span class={`w-fit rounded-full border px-2.5 py-1 text-xs font-semibold ${item.active ? 'border-emerald-200 bg-emerald-50 text-emerald-700' : 'border-slate-200 bg-slate-100 text-slate-500'}`}>{item.active ? 'เปิดใช้งาน' : 'ปิดใช้งาน'}</span>
            <div class="flex gap-2 lg:justify-end">
              <button type="button" class="app-button-secondary app-focus min-h-0 px-3 py-2" disabled={mutationBusy} on:click={() => openEditOu(item)} aria-label={`แก้ไข ${item.name}`}><Pencil size={15} /></button>
              <button type="button" class="app-button-secondary app-focus min-h-0 px-3 py-2" disabled={mutationBusy || item.locked} on:click={() => toggleOuType(item.id)} title={item.locked ? 'ประเภทที่ Root OU ใช้อยู่ไม่สามารถปิดได้' : ''}>{item.active ? 'ปิดใช้' : 'เปิดใช้'}</button>
            </div>
          </article>
        {/each}
      </div>
      <div class="flex gap-3 border-t border-sky-100 bg-sky-50/70 p-4 sm:px-5"><Info class="mt-0.5 shrink-0 text-sky-700" size={18} /><p class="text-xs leading-5 text-sky-800">ลำดับมีผลเฉพาะการเรียงในรายการเลือก ไม่ได้จำกัดว่า OU Type ต้องใช้กับ Level ใด ส่วนประเภทที่เคยมีข้อมูลควรปิดใช้งานแทนการลบเพื่อรักษาประวัติย้อนหลัง</p></div>
    {:else}
      <div class="border-b border-slate-100 p-4 sm:p-5">
        <div class="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
          <div><h2 class="app-section-title">Field สถิติของ Tenant</h2><p class="app-section-copy">Input Field ใช้ในหน้า Submissions ส่วน Calculated Field คำนวณจากข้อมูลที่อนุมัติแล้ว สามารถเลือกทั้งสองชนิดไปแสดงบน Dashboard ได้</p></div>
          <button type="button" class="app-button-primary app-focus inline-flex items-center justify-center gap-2" disabled={mutationBusy} on:click={openCreateMetric}><CirclePlus size={17} /> เพิ่ม Field</button>
        </div>
      </div>
      <section class="border-b border-sky-100 bg-sky-50/50 p-4 sm:p-5" aria-labelledby="dashboard-metric-title">
        <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div><h3 id="dashboard-metric-title" class="flex items-center gap-2 text-sm font-semibold text-sky-950"><LayoutDashboard size={17} /> Matrix บน Dashboard</h3><p class="mt-1 text-xs leading-5 text-sky-800">เลือก Raw หรือ Calculated Matrix ที่ต้องการแสดง และกำหนดเลขลำดับจากน้อยไปมาก Dashboard จะแสดงเฉพาะรายการที่เลือก</p></div>
          <span class="w-fit rounded-full border border-sky-200 bg-white px-2.5 py-1 text-xs font-semibold text-sky-700">เลือกแล้ว {selectedDashboardMetricCount}</span>
        </div>
        <div class="mt-4 grid gap-2 lg:grid-cols-2">
          {#each dashboardMetricOptions as item}
            <article class={`flex items-center gap-3 rounded-2xl border p-3 transition ${item.dashboardVisible ? 'border-sky-300 bg-white shadow-sm' : 'border-slate-200 bg-white/60'}`}>
              <input class="h-5 w-5 shrink-0 accent-sky-600" type="checkbox" checked={item.dashboardVisible} aria-label={`แสดง ${item.name} บน Dashboard`} on:change={() => toggleDashboardMetric(item.id)} />
              <div class="min-w-0 flex-1"><p class="truncate text-sm font-semibold text-slate-900">{item.name}</p><p class="mt-0.5 text-xs text-slate-500">{item.metricKind === 'calculated' ? 'Calculated' : 'Raw Input'} · {item.unit}</p></div>
              <label class="w-20"><span class="sr-only">ลำดับ {item.name}</span><input class="app-input min-h-9 px-2 py-1.5 text-center text-sm" type="number" min="1" step="1" bind:value={item.dashboardOrder} disabled={!item.dashboardVisible} aria-label={`ลำดับของ ${item.name}`} /></label>
            </article>
          {:else}
            <p class="rounded-2xl border border-dashed border-sky-200 bg-white/60 px-4 py-6 text-center text-xs text-slate-500 lg:col-span-2">ยังไม่มี Matrix ตัวเลขที่เปิดใช้งาน</p>
          {/each}
        </div>
        <div class="mt-4 flex items-center justify-between gap-3"><p class="text-xs text-sky-700">แนะนำ 4–6 รายการ เพื่อให้ Dashboard อ่านง่าย</p><button type="button" class="app-button-primary inline-flex items-center gap-2" disabled={mutationBusy || selectedDashboardMetricCount === 0} on:click={saveDashboardMetrics}><Save size={15} /> บันทึก Dashboard</button></div>
      </section>
      <div class="divide-y divide-slate-100">
        {#each metrics as item}
          <article class="grid gap-4 p-4 sm:p-5 lg:grid-cols-[minmax(0,1fr)_8rem_8rem_11rem] lg:items-center">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-2"><h3 class="text-sm font-semibold text-slate-950">{item.name}</h3>{#if item.metricKind === 'calculated'}<span class="inline-flex items-center gap-1 rounded-full bg-violet-50 px-2 py-0.5 text-[0.68rem] font-semibold text-violet-700"><Calculator size={11} /> Calculated</span>{:else if item.required}<span class="rounded-full bg-amber-50 px-2 py-0.5 text-[0.68rem] font-semibold text-amber-700">บังคับกรอก</span>{/if}</div>
              <p class="mt-1 text-xs text-slate-500">{item.code} · {item.dataType} · หน่วย {item.unit} · ลำดับ {item.sortOrder}</p>
              {#if item.metricKind === 'calculated'}<p class="mt-1 text-xs font-medium text-violet-700">สูตร: {formatFormula(item.calculationSourceMetricIds, metrics, item.calculationOperator, item.numeratorCount) || 'ยังไม่พบ Field ต้นทาง'}</p>{/if}
            </div>
            <p class="text-xs text-slate-500">{item.metricKind === 'calculated' ? 'แสดงใน Report' : item.minValue !== null ? `ขั้นต่ำ ${item.minValue}` : 'ไม่จำกัดค่า'}</p>
            <span class={`w-fit rounded-full border px-2.5 py-1 text-xs font-semibold ${item.active ? 'border-emerald-200 bg-emerald-50 text-emerald-700' : 'border-slate-200 bg-slate-100 text-slate-500'}`}>{item.active ? 'เปิดใช้งาน' : 'ปิดใช้งาน'}</span>
            <div class="flex gap-2 lg:justify-end">
              <button type="button" class="app-button-secondary app-focus min-h-0 px-3 py-2" disabled={mutationBusy} on:click={() => openEditMetric(item)} aria-label={`แก้ไข ${item.name}`}><Pencil size={15} /></button>
              <button type="button" class="app-button-secondary app-focus min-h-0 px-3 py-2" disabled={mutationBusy || item.id === tenantPrimaryMetricId} on:click={() => toggleMetric(item.id)} title={item.id === tenantPrimaryMetricId ? 'Primary KPI ไม่สามารถปิดได้' : ''}>{item.active ? 'ปิดใช้' : 'เปิดใช้'}</button>
            </div>
          </article>
        {/each}
      </div>
    {/if}
  </section>
</div>

{#if ouModalOpen}
  <div class="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-4" role="presentation">
    <button class="absolute inset-0 bg-slate-950/50" type="button" aria-label="ปิด" on:click={() => (ouModalOpen = false)}></button>
    <div class="relative z-10 w-full max-w-xl rounded-t-3xl bg-white shadow-2xl sm:rounded-3xl" role="dialog" aria-modal="true" aria-labelledby="ou-dialog-title">
      <div class="flex items-start justify-between border-b border-slate-100 p-5"><div><h2 id="ou-dialog-title" class="text-lg font-semibold text-slate-950">{editingOuId ? 'แก้ไข OU Type' : 'เพิ่ม OU Type'}</h2><p class="mt-1 text-xs text-slate-500">การเปลี่ยนแปลงมีผลกับทั้ง Tenant</p></div><button type="button" class="text-slate-400" on:click={() => (ouModalOpen = false)}><X size={20} /></button></div>
      <div class="grid gap-4 p-5 sm:grid-cols-2">
        <label class="sm:col-span-2"><span class="text-sm font-medium text-slate-700">ชื่อประเภท</span><input class="app-input mt-2" bind:value={ouName} placeholder="เช่น เขต" /></label>
        <label><span class="text-sm font-medium text-slate-700">Code</span><input class="app-input mt-2 uppercase" bind:value={ouCode} disabled={editingOuId !== null} placeholder="DISTRICT" /></label>
        <label><span class="text-sm font-medium text-slate-700">ลำดับแสดงผล</span><input class="app-input mt-2" type="number" min="0" step="10" bind:value={ouSortOrder} /></label>
        <label class="sm:col-span-2"><span class="text-sm font-medium text-slate-700">คำอธิบาย</span><textarea class="app-input mt-2 min-h-24 resize-y rounded-2xl py-3" bind:value={ouDescription}></textarea></label>
        <label class="flex cursor-pointer items-center justify-between rounded-2xl border border-slate-200 bg-slate-50 p-4 sm:col-span-2"><span><span class="block text-sm font-semibold text-slate-900">รับข้อมูลโดยค่าเริ่มต้น</span><span class="mt-1 block text-xs text-slate-500">ใช้เป็นค่าเริ่มต้นเมื่อสร้าง OU ด้วยประเภทนี้ และแก้ต่างหากใน OU ได้</span></span><input class="h-5 w-5 accent-sky-600" type="checkbox" bind:checked={ouDefaultAllowDataEntry} /></label>
      </div>
      <div class="flex justify-end gap-3 border-t border-slate-100 bg-slate-50/70 p-4 sm:px-5"><button type="button" class="app-button-secondary" disabled={mutationBusy} on:click={() => (ouModalOpen = false)}>ยกเลิก</button><button type="button" class="app-button-primary inline-flex items-center gap-2" disabled={mutationBusy || !ouName.trim() || !ouCode.trim()} on:click={saveOuType}><Save size={16} /> {mutationBusy ? 'กำลังบันทึก...' : 'บันทึก'}</button></div>
    </div>
  </div>
{/if}

{#if metricModalOpen}
  <div class="fixed inset-0 z-50 flex items-end justify-center p-0 sm:items-center sm:p-4" role="presentation">
    <button class="absolute inset-0 bg-slate-950/50" type="button" aria-label="ปิด" on:click={() => (metricModalOpen = false)}></button>
    <div class="relative z-10 max-h-[95vh] w-full max-w-3xl overflow-y-auto rounded-t-3xl bg-white shadow-2xl sm:rounded-3xl" role="dialog" aria-modal="true" aria-labelledby="metric-dialog-title">
      <div class="flex items-start justify-between border-b border-slate-100 p-5"><div><h2 id="metric-dialog-title" class="text-lg font-semibold text-slate-950">{editingMetricId ? 'แก้ไข Field สถิติ' : 'เพิ่ม Field สถิติ'}</h2><p class="mt-1 text-xs text-slate-500">เลือกสร้าง Field สำหรับกรอกข้อมูล หรือสูตรคำนวณสำหรับ Report</p></div><button type="button" class="text-slate-400" on:click={() => (metricModalOpen = false)}><X size={20} /></button></div>
      <div class="grid gap-4 p-5 sm:grid-cols-2">
        <label class="sm:col-span-2"><span class="text-sm font-medium text-slate-700">ชนิด Field</span><select class="app-input mt-2" bind:value={metricKind} disabled={editingMetricId !== null}><option value="input">Input Field — ผู้ใช้กรอกใน Submissions</option><option value="calculated">Calculated Field — ระบบคำนวณและแสดงใน Report</option></select></label>
        <label><span class="text-sm font-medium text-slate-700">ชื่อแสดงผล</span><input class="app-input mt-2" bind:value={metricName} placeholder="เช่น ผู้ใหญ่มาคจ." /></label>
        <label><span class="text-sm font-medium text-slate-700">Metric Code</span><input class="app-input mt-2 uppercase" bind:value={metricCode} disabled={editingMetricId !== null} placeholder="ATTENDANCE" /></label>
        <label><span class="text-sm font-medium text-slate-700">หมวดหมู่</span><input class="app-input mt-2" bind:value={metricCategory} placeholder="attendance" /></label>
        <label><span class="text-sm font-medium text-slate-700">หน่วย</span><input class="app-input mt-2" value={metricKind === 'calculated' && metricOperator === 'ratio' ? '%' : metricUnit} on:input={(event) => (metricUnit = event.currentTarget.value)} readonly={metricKind === 'calculated' && metricOperator === 'ratio'} placeholder="คน" /></label>
        {#if metricKind === 'input'}
          <label><span class="text-sm font-medium text-slate-700">ประเภทข้อมูล</span><select class="app-input mt-2" bind:value={metricDataType} disabled={editingMetricId !== null}><option value="number">จำนวน (number)</option><option value="text">ข้อความ (text)</option><option value="boolean">ใช่/ไม่ใช่ (boolean)</option></select></label>
          <label><span class="text-sm font-medium text-slate-700">วิธีรวมผล</span><select class="app-input mt-2" bind:value={metricAggregation} disabled={metricDataType !== 'number'}><option value="sum">ผลรวม (sum)</option><option value="avg">ค่าเฉลี่ย (avg)</option><option value="max">ค่าสูงสุด (max)</option><option value="min">ค่าต่ำสุด (min)</option><option value="none">ไม่รวมผล (none)</option></select></label>
          <label><span class="text-sm font-medium text-slate-700">ค่าเริ่มต้น</span><input class="app-input mt-2" type="number" bind:value={metricDefaultValue} disabled={metricDataType !== 'number'} /></label>
          <label><span class="text-sm font-medium text-slate-700">ค่าต่ำสุด</span><input class="app-input mt-2" type="number" bind:value={metricMinValue} disabled={metricDataType !== 'number'} /></label>
          <label><span class="text-sm font-medium text-slate-700">ค่าสูงสุด</span><input class="app-input mt-2" type="number" bind:value={metricMaxValue} disabled={metricDataType !== 'number'} placeholder="ไม่จำกัด" /></label>
        {:else}
          <fieldset class="rounded-2xl border border-violet-200 bg-violet-50/60 p-4 sm:col-span-2">
            <legend class="px-1 text-sm font-semibold text-violet-950">สูตรคำนวณ</legend>
            <label><span class="text-sm font-medium">วิธีคำนวณ</span><select class="app-input mt-2" bind:value={metricOperator}><option value="sum">ผลรวม (A + B)</option><option value="ratio">อัตราส่วน (A ÷ B)</option></select></label>
            {#if metricOperator === 'ratio'}
              <div class="mt-3 grid gap-3 sm:grid-cols-2">
                <fieldset class="grid content-start gap-2 rounded-xl border border-violet-100 bg-white p-3">
                  <legend class="px-1 text-sm font-medium">ตัวตั้ง (A)</legend>
                  {#each calculationSourceOptions as source (source.id)}
                    <label class="flex items-center gap-2 text-sm"><input type="checkbox" class="accent-violet-600" bind:group={numeratorIds} value={source.id} />{source.name}</label>
                  {/each}
                </fieldset>
                <fieldset class="grid content-start gap-2 rounded-xl border border-violet-100 bg-white p-3">
                  <legend class="px-1 text-sm font-medium">ตัวหาร (B)</legend>
                  {#each calculationSourceOptions as source (source.id)}
                    <label class="flex items-center gap-2 text-sm"><input type="checkbox" class="accent-violet-600" bind:group={denominatorIds} value={source.id} />{source.name}</label>
                  {/each}
                </fieldset>
              </div>
              <p class="mt-2 text-xs leading-5 text-violet-800">(ผลรวม A ÷ ผลรวม B) × 100 จากข้อมูลที่อนุมัติแล้ว แสดงเปอร์เซ็นต์ ทศนิยม 2 ตำแหน่ง ฟิลด์ที่ว่างจะข้ามไป หากรายการที่อนุมัติขาดข้อมูลทั้งฝั่ง A หรือ B หรือยอดรวม B เป็นศูนย์ จะแสดง — พร้อมคำอธิบายเมื่อวางเมาส์</p>
            {:else}
            <p class="mt-1 text-xs leading-5 text-violet-800">เลือก Input Field ตัวเลขอย่างน้อย 2 รายการ ระบบจะคำนวณจากข้อมูลที่อนุมัติแล้วตาม OU และช่วงเวลาของ Report</p>
            <div class="mt-3 grid gap-2 sm:grid-cols-2">
              {#each calculationSourceOptions as source}
                <label class="flex cursor-pointer items-center gap-3 rounded-xl border border-violet-100 bg-white px-3 py-2.5 text-sm text-slate-700">
                  <input class="h-4 w-4 accent-violet-600" type="checkbox" checked={metricSourceIds.includes(source.id)} on:change={() => toggleMetricSource(source.id)} />
                  <span><span class="font-medium text-slate-900">{source.name}</span><span class="ml-1 text-xs text-slate-400">({source.code})</span></span>
                </label>
              {/each}
            </div>
            {/if}
            {#if calculationSourceOptions.length === 0}<p class="mt-3 text-xs text-rose-700">ยังไม่มี Input Field ชนิด number ที่รวมผลแบบ sum สำหรับสร้างสูตร</p>{/if}
            <div class="mt-3 rounded-xl bg-violet-100/70 px-3 py-2 text-xs font-semibold text-violet-900">ตัวอย่างผลลัพธ์: {metricName.trim() || 'Calculated Field'} = {formulaPreview || 'เลือก Field ต้นทาง'}</div>
          </fieldset>
        {/if}
        <label><span class="text-sm font-medium text-slate-700">ลำดับแสดงผล</span><input class="app-input mt-2" type="number" min="0" step="10" bind:value={metricSortOrder} /></label>
        <label class={metricKind === 'calculated' ? '' : 'sm:col-span-2'}><span class="text-sm font-medium text-slate-700">คำอธิบาย</span><textarea class="app-input mt-2 min-h-20 resize-y rounded-2xl py-3" bind:value={metricDescription}></textarea>{#if metricKind === 'input'}<span class="mt-1 block text-xs text-slate-500">Input type จะถูกกำหนดจากประเภทข้อมูลอัตโนมัติ: number, text หรือ checkbox</span>{/if}</label>
        {#if metricKind === 'input'}<label class="flex cursor-pointer items-center justify-between rounded-2xl border border-slate-200 bg-slate-50 p-4 sm:col-span-2"><span><span class="block text-sm font-semibold text-slate-900">บังคับกรอก</span><span class="mt-1 block text-xs text-slate-500">ผู้ส่งข้อมูลต้องกรอกก่อนส่งแบบฟอร์ม</span></span><input class="h-5 w-5 accent-sky-600" type="checkbox" bind:checked={metricRequired} /></label>{/if}
      </div>
      {#if mutationError}
        <p class="border-t border-rose-200 bg-rose-50 px-4 py-3 text-sm text-rose-800" role="alert">{mutationError}</p>
      {/if}
      <div class="flex justify-end gap-3 border-t border-slate-100 bg-slate-50/70 p-4 sm:px-5"><button type="button" class="app-button-secondary" disabled={mutationBusy} on:click={() => (metricModalOpen = false)}>ยกเลิก</button><button type="button" class="app-button-primary inline-flex items-center gap-2" disabled={mutationBusy} on:click={saveMetric}><Save size={16} /> {mutationBusy ? 'กำลังบันทึก...' : 'บันทึก'}</button></div>
    </div>
  </div>
{/if}

{#if toastMessage}
  <div class="fixed bottom-20 right-4 z-[60] max-w-sm rounded-2xl border border-emerald-200 bg-white px-4 py-3 shadow-xl md:bottom-5" role="status"><div class="flex gap-3"><CheckCircle2 class="mt-0.5 shrink-0 text-emerald-600" size={18} /><div><p class="text-sm font-semibold text-slate-900">บันทึกแล้ว</p><p class="mt-0.5 text-xs text-slate-600">{toastMessage}</p></div><button class="ml-auto text-slate-400" type="button" aria-label="ปิดข้อความ" on:click={() => (toastMessage = '')}><X size={16} /></button></div></div>
{/if}
