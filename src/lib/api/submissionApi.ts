import type { SupabaseClient } from '@supabase/supabase-js';
import { callRpc } from './rpc';
import type { SubmissionDetail, WeeklySubmissionContext } from '$lib/types/submission';

export type StatisticValueInput = {
  metricId: string;
  numericValue: number | null;
  textValue: string | null;
  booleanValue: boolean | null;
};

export type StatisticsPayload = {
  clientRequestId: string;
  expectedRevision: number | null;
  ouId: string;
  periodId: string;
  remarks?: string | null;
  values: StatisticValueInput[];
};

export function saveStatisticsDraft(client: SupabaseClient, payload: StatisticsPayload) {
  return callRpc<{ submissionId: string; status: string; revisionNo: number }>(
    client,
    'save_statistics_draft',
    { p_payload: payload }
  );
}

export function submitStatistics(client: SupabaseClient, payload: StatisticsPayload) {
  return callRpc<{ submissionId: string; status: string; revisionNo: number }>(
    client,
    'submit_statistics',
    { p_payload: payload }
  );
}

export function getSubmissionDetail(client: SupabaseClient, submissionId: string) {
  return callRpc<SubmissionDetail>(client, 'get_submission_detail', {
    p_submission_id: submissionId
  });
}

export function getWeeklySubmissionContext(client: SupabaseClient) {
  return callRpc<WeeklySubmissionContext>(client, 'get_weekly_submission_context');
}

export function getSubmissionByContext(client: SupabaseClient, ouId: string, periodId: string) {
  return callRpc<SubmissionDetail | null>(client, 'get_submission_by_context', {
    p_ou_id: ouId,
    p_period_id: periodId
  });
}

export function requestSubmissionEdit(
  client: SupabaseClient,
  payload: { submissionId: string; expectedRevision: number; clientRequestId: string; reason: string }
) {
  return callRpc<{ submissionId: string; status: string; revisionNo: number }>(
    client,
    'request_submission_edit',
    { p_payload: payload }
  );
}
