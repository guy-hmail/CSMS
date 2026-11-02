import type { CalculationError } from '$lib/reports/metricCalculation';
import type { SupabaseClient } from '@supabase/supabase-js';
import { callRpc } from './rpc';

export type ReportMetric = {
  metricId: string;
  metricCode: string;
  metricName: string;
  category: string;
  unit: string;
  aggregation: 'sum' | 'avg' | 'max' | 'min';
  metricKind: 'input' | 'calculated';
  calculationOperator: 'sum' | 'ratio' | null;
  sourceMetricCodes: string[];
};

export type ReportTable = {
  church: { id: string; name: string };
  ou: { id: string; code: string; name: string };
  fromDate: string;
  toDate: string;
  metrics: ReportMetric[];
  rows: Array<{ ouId: string; ouCode: string; ouName: string; values: Record<string, number | null>; errors?: Record<string, CalculationError> }>;
  totals: Record<string, number | null>;
  totalErrors?: Record<string, CalculationError>;
};

export type ReportTrend = {
  metricCode: string;
  metricName: string;
  unit: string;
  points: Array<{ periodId: string; label: string; periodStart: string; periodEnd: string; value: number | null; error?: CalculationError }>;
};

export type SubmissionCompleteness = {
  fromDate: string;
  toDate: string;
  summary: { expected: number; submitted: number; approved: number; pending: number; draft: number; returned: number; rejected: number; missing: number };
  items: Array<{ ouId: string; ouCode: string; ouName: string; expected: number; submitted: number; approved: number; pending: number; draft: number; returned: number; rejected: number; missing: number }>;
};

export function getReportTable(client: SupabaseClient, ouId: string, fromDate: string, toDate: string) {
  return callRpc<ReportTable>(client, 'get_report_table', { p_ou_id: ouId, p_from_date: fromDate, p_to_date: toDate });
}

export function getReportTrend(client: SupabaseClient, ouId: string, metricCode: string, fromDate: string, toDate: string) {
  return callRpc<ReportTrend>(client, 'get_report_trend', {
    p_ou_id: ouId,
    p_metric_code: metricCode,
    p_from_date: fromDate,
    p_to_date: toDate
  });
}

export function getSubmissionCompleteness(client: SupabaseClient, ouId: string, fromDate: string, toDate: string) {
  return callRpc<SubmissionCompleteness>(client, 'get_submission_completeness', { p_ou_id: ouId, p_from_date: fromDate, p_to_date: toDate });
}
