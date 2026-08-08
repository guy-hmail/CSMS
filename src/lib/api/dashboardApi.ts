import type { SupabaseClient } from '@supabase/supabase-js';
import { callRpc } from './rpc';

export type RecursiveSummaryMetric = {
  metricId: string;
  metricCode: string;
  metricName: string;
  category: string;
  unit: string;
  aggregation: string;
  metricKind: 'input' | 'calculated';
  currentValue: number | null;
  compareValue: number | null;
  growthPercent: number | null;
};

export type RecursiveSummary = {
  ou: { id: string; name: string; path: string };
  period: { id: string; periodEnd: string; displayLabel: string };
  comparePeriod: { id: string; periodEnd: string; displayLabel: string } | null;
  metrics: RecursiveSummaryMetric[];
};

export type SubmissionStatusResult = {
  summary: { totalExpected: number; submitted: number; approved: number; missing: number; pending: number };
  items: Array<{ ouId: string; ouName: string; parentOuId: string | null; status: string; submittedAt: string | null; approvedAt: string | null }>;
};

export type ChildOuSummaryResult = {
  children: Array<{
    ouId: string;
    ouName: string;
    level: number;
    status: 'approved' | 'missing' | 'submitted' | 'draft' | 'returned' | 'rejected' | 'mixed';
    expectedCount: number;
    approvedCount: number;
    metrics: Array<{ metricCode: string; metricName: string; metricKind: 'input' | 'calculated'; unit: string; value: number | null }>;
  }>;
};

export type DashboardTrend = {
  metricCode: string;
  metricName: string;
  metricKind: 'input' | 'calculated';
  unit: string;
  points: Array<{ periodId: string; label: string; periodStart: string; periodEnd: string; value: number }>;
};

export function getRecursiveSummary(
  client: SupabaseClient,
  ouId: string,
  periodId: string,
  comparePeriodId: string | null = null
) {
  return callRpc<RecursiveSummary>(client, 'get_recursive_summary', {
    p_ou_id: ouId,
    p_period_id: periodId,
    p_compare_period_id: comparePeriodId
  });
}

export function getSubmissionStatusSummary(client: SupabaseClient, ouId: string, periodId: string) {
  return callRpc<SubmissionStatusResult>(client, 'get_submission_status_summary', { p_ou_id: ouId, p_period_id: periodId });
}

export function getChildOuSummary(client: SupabaseClient, parentOuId: string, periodId: string) {
  return callRpc<ChildOuSummaryResult>(client, 'get_child_ou_summary', { p_parent_ou_id: parentOuId, p_period_id: periodId });
}

export function getDashboardTrend(client: SupabaseClient, ouId: string, metricCode: string, endPeriodId: string, limit = 12) {
  return callRpc<DashboardTrend>(client, 'get_dashboard_trend', {
    p_ou_id: ouId,
    p_metric_code: metricCode,
    p_end_period_id: endPeriodId,
    p_limit: limit
  });
}
