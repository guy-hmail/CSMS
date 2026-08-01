import type { SupabaseClient } from '@supabase/supabase-js';
import { callRpc } from './rpc';

export type TenantSettingsPayload = {
  name: string;
  timezone: string;
  approvalMode: 'auto_approve' | 'approval_required';
  reportingWeekEndsOn: number;
  primaryMetricId: string | null;
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

export function updateTenantSettings(
  client: SupabaseClient,
  payload: TenantSettingsPayload
) {
  return callRpc<{ tenantId: string }>(client, 'update_tenant_settings', {
    p_payload: payload
  });
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
