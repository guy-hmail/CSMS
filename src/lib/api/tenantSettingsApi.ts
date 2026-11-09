import type { SupabaseClient } from '@supabase/supabase-js';
import { callRpc } from './rpc';

export type TenantSettingsPayload = {
  name: string;
  timezone: string;
  approvalMode: 'auto_approve' | 'approval_required';
  reportingWeekEndsOn: number;
  submissionDeadlineDaysAfterPeriodEnd: number;
  primaryMetricId: string | null;
};

export type NotificationScheduleDay = 'MON' | 'TUE' | 'WED' | 'THU' | 'FRI' | 'SAT' | 'SUN';

export type TenantNotificationSchedulePayload = {
  enabled: boolean;
  scheduleDays: NotificationScheduleDay[];
  missingReminderLocalHour: number;
  approvalDigestLocalHour: number;
};

export type OrganizationUnitTypePayload = {
  code: string;
  name: string;
  description: string;
  sortOrder: number;
  defaultAllowDataEntry: boolean;
};

export type StatisticMetricPayload = {
  code: string;
  name: string;
  description: string;
  category: string;
  unit: string;
  dataType: 'number' | 'text' | 'boolean';
  aggregation: 'sum' | 'avg' | 'max' | 'min' | 'none';
  defaultValue: number | null;
  minValue: number | null;
  maxValue: number | null;
  isRequired: boolean;
  sortOrder: number;
};

export type CalculatedMetricPayload = {
  operator?: 'sum' | 'ratio';
  code: string;
  name: string;
  description: string;
  category: string;
  unit: string;
  sortOrder: number;
  numeratorCount?: number;
  sourceMetricIds: string[];
};

export function updateTenantSettings(
  client: SupabaseClient,
  payload: TenantSettingsPayload
) {
  return callRpc<{ tenantId: string }>(client, 'update_tenant_settings', {
    p_payload: payload
  });
}

export function updateTenantNotificationSchedule(
  client: SupabaseClient,
  payload: TenantNotificationSchedulePayload
) {
  return callRpc<TenantNotificationSchedulePayload & { tenantId: string }>(
    client,
    'update_tenant_notification_schedule',
    { p_payload: payload }
  );
}

export function createOrganizationUnitType(
  client: SupabaseClient,
  payload: OrganizationUnitTypePayload
) {
  return callRpc<{ ouTypeId: string }>(client, 'create_organization_unit_type', {
    p_payload: payload
  });
}

export function updateOrganizationUnitType(
  client: SupabaseClient,
  ouTypeId: string,
  payload: Omit<OrganizationUnitTypePayload, 'code'> & { isActive: boolean }
) {
  return callRpc<{ ouTypeId: string }>(client, 'update_organization_unit_type', {
    p_payload: { ouTypeId, ...payload }
  });
}

export function createStatisticMetric(
  client: SupabaseClient,
  payload: StatisticMetricPayload
) {
  return callRpc<{ metricId: string }>(client, 'create_statistic_metric', {
    p_payload: payload
  });
}

export function updateStatisticMetric(
  client: SupabaseClient,
  metricId: string,
  payload: Omit<StatisticMetricPayload, 'code' | 'dataType'> & { isActive: boolean }
) {
  return callRpc<{ metricId: string }>(client, 'update_statistic_metric', {
    p_payload: { metricId, ...payload }
  });
}

export function createCalculatedMetric(client: SupabaseClient, payload: CalculatedMetricPayload) {
  return callRpc<{ metricId: string }>(client, 'create_calculated_metric', { p_payload: payload });
}

export function updateCalculatedMetric(
  client: SupabaseClient,
  metricId: string,
  payload: Omit<CalculatedMetricPayload, 'code'> & { isActive: boolean }
) {
  return callRpc<{ metricId: string }>(client, 'update_calculated_metric', {
    p_payload: { metricId, ...payload }
  });
}

export function updateDashboardMetricSettings(client: SupabaseClient, metricIds: string[]) {
  return callRpc<{ metricCount: number }>(client, 'update_dashboard_metric_settings', {
    p_payload: { metricIds }
  });
}
