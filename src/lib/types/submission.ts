export type MetricDataType = 'number' | 'text' | 'boolean';
export type MetricInputType = 'number' | 'text' | 'checkbox';

export type SubmissionMetricDefinition = {
  id: string;
  code: string;
  name: string;
  category: string;
  unit: string;
  dataType: MetricDataType;
  inputType: MetricInputType;
  isRequired: boolean;
  minValue: number | null;
  maxValue: number | null;
  sortOrder: number;
};

export type SubmissionMetricValue = {
  metricId: string;
  numericValue: number | null;
  textValue: string | null;
  booleanValue: boolean | null;
};

export type SubmissionSelectorOption = {
  id: string;
  label: string;
  helperText?: string;
};

export type SubmissionStatus = 'draft' | 'submitted' | 'approved' | 'rejected' | 'edit_requested' | 'returned';

export type SubmissionRecord = {
  id: string;
  periodId: string;
  ouId: string;
  status: SubmissionStatus;
  remarks: string | null;
  revisionNo: number;
  submittedAt: string | null;
  approvedAt: string | null;
};

export type SubmissionDetail = {
  submission: SubmissionRecord;
  values: SubmissionMetricValue[];
};

export type WeeklySubmissionContext = {
  periods: Array<{ id: string; label: string; periodStart: string; periodEnd: string; year: number; weekNo: number; status: 'open' | 'closed' | 'locked' }>;
  organizationUnits: Array<{ id: string; name: string; code: string; path: string; level: number }>;
  metrics: SubmissionMetricDefinition[];
};

export type SubmissionValidationMessage = {
  field: string;
  message: string;
};
