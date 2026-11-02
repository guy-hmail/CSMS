import type { CalculationError } from '$lib/reports/metricCalculation';
export type StatusTone = 'success' | 'warning' | 'info' | 'neutral' | 'error';

export type DashboardOption = {
  id: string;
  label: string;
  helperText?: string;
};

export type KpiSummary = {
  metricCode: string;
  metricName: string;
  metricKind: 'input' | 'calculated';
  value: number | null;
  error?: CalculationError;
  unit: string;
  growthPercent: number | null;
};

export type TrendPoint = {
  label: string;
  value: number | null;
  error?: CalculationError;
};

export type SubmissionStatusSummary = {
  totalExpected: number;
  submitted: number;
  approved: number;
  missing: number;
  pending: number;
};

export type ChildOuSummaryRow = {
  ouId: string;
  ouName: string;
  metrics: Array<{
    metricCode: string;
    metricName: string;
    metricKind: 'input' | 'calculated';
    value: number | null;
    error?: CalculationError;
    unit: string;
  }>;
  status: 'approved' | 'missing' | 'submitted' | 'draft' | 'returned' | 'rejected' | 'mixed';
};
