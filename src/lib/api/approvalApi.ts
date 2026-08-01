import type { SupabaseClient } from '@supabase/supabase-js';
import { callRpc } from './rpc';
import type { SubmissionStatus } from '$lib/types/submission';

export type ApprovalQueueItem = {
  id: string;
  status: SubmissionStatus;
  revisionNo: number;
  remarks: string | null;
  submittedAt: string | null;
  approvedAt: string | null;
  editRequestReason: string | null;
  editRequestedAt: string | null;
  periodId: string;
  periodLabel: string;
  periodEnd: string;
  ouId: string;
  ouName: string;
  ouCode: string;
  submittedByName: string | null;
  metricCount: number;
  isOverride: boolean;
};

export type ApprovalQueue = {
  approvalMode: 'auto_approve' | 'approval_required';
  items: ApprovalQueueItem[];
  periods: Array<{ id: string; label: string; periodEnd: string }>;
  organizationUnits: Array<{ id: string; name: string; code: string; path: string; level: number }>;
};

export type ApprovalMetricValue = {
  metricId: string;
  metricCode: string;
  metricName: string;
  unit: string;
  dataType: 'number' | 'text' | 'boolean';
  numericValue: number | null;
  textValue: string | null;
  booleanValue: boolean | null;
};

export type ApprovalHistoryItem = {
  id: string;
  action: 'submit' | 'approve' | 'reject' | 'return' | 'request_edit' | 'approve_edit_request';
  fromStatus: string | null;
  toStatus: string | null;
  isOverride: boolean;
  reason: string | null;
  createdAt: string;
  actorName: string;
};

export type ApprovalDetail = {
  submission: {
    id: string;
    status: SubmissionStatus;
    revisionNo: number;
    remarks: string | null;
    ouId: string;
    periodId: string;
    submittedAt: string | null;
    approvedAt: string | null;
    approvalNote: string | null;
    editRequestReason: string | null;
    editRequestedAt: string | null;
  };
  values: ApprovalMetricValue[];
  history: ApprovalHistoryItem[];
  capabilities: { canApprove: boolean; canReject: boolean; canReturn: boolean; canApproveEditRequest: boolean; isOverride: boolean };
};

export type ApprovalActionPayload = {
  submissionId: string;
  expectedRevision: number;
  clientRequestId: string;
  reason?: string | null;
};

export function listPendingSubmissions(client: SupabaseClient, periodId: string | null, ouId: string | null, status: string | null) {
  return callRpc<ApprovalQueue>(client, 'list_pending_submissions', {
    p_period_id: periodId,
    p_ou_id: ouId,
    p_status: status
  });
}

export function getApprovalSubmissionDetail(client: SupabaseClient, submissionId: string) {
  return callRpc<ApprovalDetail>(client, 'get_approval_submission_detail', { p_submission_id: submissionId });
}

export function approveSubmission(client: SupabaseClient, payload: ApprovalActionPayload) {
  return callRpc<{ submissionId: string; status: SubmissionStatus; revisionNo: number }>(client, 'approve_submission', { p_payload: payload });
}

export function rejectSubmission(client: SupabaseClient, payload: ApprovalActionPayload) {
  return callRpc<{ submissionId: string; status: SubmissionStatus; revisionNo: number }>(client, 'reject_submission', { p_payload: payload });
}

export function returnSubmissionForEdit(client: SupabaseClient, payload: ApprovalActionPayload) {
  return callRpc<{ submissionId: string; status: SubmissionStatus; revisionNo: number }>(client, 'return_submission_for_edit', { p_payload: payload });
}

export function approveSubmissionEditRequest(client: SupabaseClient, payload: ApprovalActionPayload) {
  return callRpc<{ submissionId: string; status: SubmissionStatus; revisionNo: number }>(client, 'approve_submission_edit_request', { p_payload: payload });
}

export async function getPendingEditRequestCount(client: SupabaseClient): Promise<number> {
  const result = await callRpc<{ count: number }>(client, 'get_pending_edit_request_count');
  return Number(result.count);
}
