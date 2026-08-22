import { createHmac } from 'node:crypto';
import { createClient } from '@supabase/supabase-js';
import { getMyPreferences, getMyProfile, listMyTenants, updateMyPreferences, updateMyProfile } from '../src/lib/api/identityApi';
import {
  assignOuMember,
  createOrganizationUnit,
  getAccessibleOuTree,
  getOuMembers,
  removeOuMember,
  softDeleteOrganizationUnit,
  updateOrganizationUnit,
  updateOuMemberAssignment
} from '../src/lib/api/organizationApi';
import {
  getChildOuSummary,
  getDashboardTrend,
  getRecursiveSummary,
  getSubmissionStatusSummary
} from '../src/lib/api/dashboardApi';
import {
  getSubmissionByContext,
  getWeeklySubmissionContext,
  saveStatisticsDraft,
  submitStatistics
} from '../src/lib/api/submissionApi';
import {
  approveSubmission,
  getApprovalSubmissionDetail,
  listPendingSubmissions,
  returnSubmissionForEdit
} from '../src/lib/api/approvalApi';
import {
  updateOrganizationUnitType,
  updateStatisticMetric,
  updateTenantSettings
} from '../src/lib/api/tenantSettingsApi';
import { getReportTable, getReportTrend, getSubmissionCompleteness } from '../src/lib/api/reportApi';
import {
  createPlatformAdminInviteLink,
  getPlatformTenantDetail,
  listPlatformTenantActivity,
  listPlatformTenantInvitations,
  updatePlatformTenant
} from '../src/lib/api/platformTenantApi';

const postgrestUrl = process.env.POSTGREST_URL ?? 'http://127.0.0.1:54421';
const jwtSecret =
  process.env.POSTGREST_JWT_SECRET ?? 'super-secret-jwt-token-with-at-least-32-characters-long';
const publishableKey =
  process.env.POSTGREST_API_KEY ?? 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';

function base64Url(value: string): string {
  return Buffer.from(value).toString('base64url');
}

function signJwt(payload: Record<string, unknown>): string {
  const header = base64Url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = base64Url(JSON.stringify(payload));
  const signature = createHmac('sha256', jwtSecret)
    .update(`${header}.${body}`)
    .digest('base64url');
  return `${header}.${body}.${signature}`;
}

const token = signJwt({
  sub: '80000000-0000-4000-8000-000000000002',
  role: 'authenticated',
  aud: 'authenticated',
  exp: Math.floor(Date.now() / 1000) + 300,
  app_metadata: {
    active_church_id: '81000000-0000-4000-8000-000000000001'
  }
});

const client = createClient(postgrestUrl, publishableKey, {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  global: {
    headers: { Authorization: `Bearer ${token}` }
  }
});

const serviceToken = signJwt({
  sub: '00000000-0000-4000-8000-000000000001',
  role: 'service_role',
  aud: 'authenticated',
  exp: Math.floor(Date.now() / 1000) + 300
});
const serviceClient = createClient(postgrestUrl, publishableKey, {
  auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  global: { headers: { Authorization: `Bearer ${serviceToken}` } }
});

const tenants = await listMyTenants(client);
if (tenants.length !== 1 || tenants[0].tenant_id !== '81000000-0000-4000-8000-000000000001') {
  throw new Error(`Frontend identity integration failed: ${JSON.stringify(tenants)}`);
}

const profile = await getMyProfile(client);
if (
  profile.currentTenant?.id !== '81000000-0000-4000-8000-000000000001' ||
  profile.currentTenant.name !== tenants[0].name ||
  profile.permissions[0]?.permission !== 'admin'
) {
  throw new Error(`Frontend tenant context integration failed: ${JSON.stringify(profile)}`);
}

const defaultPreferences = await getMyPreferences(client);
if (defaultPreferences.language !== 'th' || defaultPreferences.landingPage !== '/app/dashboard') {
  throw new Error(`Frontend preference defaults failed: ${JSON.stringify(defaultPreferences)}`);
}
await updateMyPreferences(client, {
  defaultOuId: '84000000-0000-4000-8000-000000000004',
  language: 'en',
  landingPage: '/app/reports',
  notifyMissing: false,
  notifySubmitted: true,
  notifyApproval: false,
  notifyEmail: true
});
const persistedPreferences = await getMyPreferences(client);
if (
  persistedPreferences.defaultOuId !== '84000000-0000-4000-8000-000000000004' ||
  persistedPreferences.language !== 'en' ||
  persistedPreferences.landingPage !== '/app/reports' ||
  !persistedPreferences.notifyEmail
) {
  throw new Error(`Frontend preference persistence failed: ${JSON.stringify(persistedPreferences)}`);
}
const persistedProfile = await updateMyProfile(client, {
  displayName: 'ผู้ดูแลระบบตัวอย่าง',
  email: 'admin@csms.local',
  phone: ''
});
if (persistedProfile.displayName !== 'ผู้ดูแลระบบตัวอย่าง' || persistedProfile.email !== 'admin@csms.local') {
  throw new Error(`Frontend profile persistence failed: ${JSON.stringify(persistedProfile)}`);
}

const submissionContext = await getWeeklySubmissionContext(client);
if (
  submissionContext.periods.length !== 5 ||
  submissionContext.organizationUnits.length < 2 ||
  submissionContext.metrics.length < 1
) {
  throw new Error(`Frontend submission context integration failed: ${JSON.stringify(submissionContext)}`);
}
const submissionPeriod = submissionContext.periods[0];
const submissionOu = submissionContext.organizationUnits.find((ou) => ou.code === 'GROUP-B')!;
const requiredMetric = submissionContext.metrics.find((metric) => metric.isRequired)!;
const { error: submissionWindowError } = await serviceClient
  .from('statistic_periods')
  .update({
    submission_opens_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
    submission_due_at: new Date(Date.now() + 60 * 60 * 1000).toISOString()
  })
  .eq('id', submissionPeriod.id);
if (submissionWindowError) throw submissionWindowError;
const existingSubmission = await getSubmissionByContext(client, submissionOu.id, submissionPeriod.id);
if (existingSubmission !== null) {
  throw new Error(`Expected an unused current context: ${JSON.stringify(existingSubmission)}`);
}
const draft = await saveStatisticsDraft(client, {
  clientRequestId: crypto.randomUUID(),
  expectedRevision: null,
  ouId: submissionOu.id,
  periodId: submissionPeriod.id,
  remarks: 'Task 3 frontend integration draft',
  values: [{ metricId: requiredMetric.id, numericValue: 12, textValue: null, booleanValue: null }]
});
const persistedDraft = await getSubmissionByContext(client, submissionOu.id, submissionPeriod.id);
if (draft.status !== 'draft' || persistedDraft?.submission.revisionNo !== 1 || persistedDraft.values[0]?.numericValue !== 12) {
  throw new Error(`Frontend submission draft did not persist: ${JSON.stringify(persistedDraft)}`);
}
const submitRequest = {
  clientRequestId: crypto.randomUUID(),
  expectedRevision: draft.revisionNo,
  ouId: submissionOu.id,
  periodId: submissionPeriod.id,
  remarks: 'Task 3 frontend integration submitted',
  values: [{ metricId: requiredMetric.id, numericValue: 14, textValue: null, booleanValue: null }]
};
const submitted = await submitStatistics(client, submitRequest);
const replay = await submitStatistics(client, submitRequest);
const persistedSubmission = await getSubmissionByContext(client, submissionOu.id, submissionPeriod.id);
if (
  submitted.status !== 'approved' ||
  replay.submissionId !== submitted.submissionId ||
  persistedSubmission?.submission.revisionNo !== 2 ||
  persistedSubmission.values[0]?.numericValue !== 14
) {
  throw new Error(`Frontend submission submit/idempotency failed: ${JSON.stringify(persistedSubmission)}`);
}

const tree = await getAccessibleOuTree(client);
if (tree.items.length !== 1 || tree.items[0].children.length !== 1) {
  throw new Error(`Frontend organization integration failed: ${JSON.stringify(tree)}`);
}

const testSuffix = crypto.randomUUID().slice(0, 8).toUpperCase();
const createdOu = await createOrganizationUnit(client, {
  parentOuId: '84000000-0000-4000-8000-000000000001',
  ouTypeId: '83000000-0000-4000-8000-000000000005',
  code: `INT-${testSuffix}`,
  name: `Integration OU ${testSuffix}`,
  allowDataEntry: false
});
await updateOrganizationUnit(client, {
  ouId: createdOu.ouId,
  parentOuId: '84000000-0000-4000-8000-000000000002',
  ouTypeId: '83000000-0000-4000-8000-000000000005',
  code: `INT-${testSuffix}`,
  name: `Integration OU Updated ${testSuffix}`,
  description: 'Frontend/backend Task 2 regression',
  allowDataEntry: true,
  sortOrder: 99
});
const assigned = await assignOuMember(client, {
  ouId: createdOu.ouId,
  churchMemberId: '82000000-0000-4000-8000-000000000001',
  permission: 'viewer',
  canOverride: false
});
await updateOuMemberAssignment(client, {
  assignmentId: assigned.assignmentId,
  permission: 'approver',
  canOverride: true
});
const persistedMembers = await getOuMembers(client, createdOu.ouId);
if (
  persistedMembers.items.length !== 1 ||
  persistedMembers.items[0].role !== 'approver' ||
  !persistedMembers.items[0].canOverride
) {
  throw new Error(`Frontend member mutation did not persist: ${JSON.stringify(persistedMembers)}`);
}
await removeOuMember(client, {
  assignmentId: assigned.assignmentId,
  reason: 'Frontend integration cleanup'
});
const removedMembers = await getOuMembers(client, createdOu.ouId);
if (removedMembers.items.length !== 0) {
  throw new Error(`Frontend member removal did not persist: ${JSON.stringify(removedMembers)}`);
}
await softDeleteOrganizationUnit(client, {
  ouId: createdOu.ouId,
  reason: 'Frontend integration cleanup'
});
const treeAfterDelete = await getAccessibleOuTree(client);
if (JSON.stringify(treeAfterDelete).includes(createdOu.ouId)) {
  throw new Error('Frontend OU soft delete remained visible after refresh');
}

const summary = await getRecursiveSummary(
  client,
  '84000000-0000-4000-8000-000000000001',
  '88000000-0000-4000-8000-000000000002',
  '88000000-0000-4000-8000-000000000001'
);
const attendance = summary.metrics.find((metric) => metric.metricCode === 'ATTENDANCE');
if (attendance?.currentValue !== 175 || attendance.compareValue !== 90) {
  throw new Error(`Frontend dashboard integration failed: ${JSON.stringify(attendance)}`);
}
const dashboardStatus = await getSubmissionStatusSummary(
  client,
  '84000000-0000-4000-8000-000000000001',
  '88000000-0000-4000-8000-000000000002'
);
if (dashboardStatus.summary.totalExpected !== 2 || dashboardStatus.summary.approved !== 2) {
  throw new Error(`Frontend dashboard status integration failed: ${JSON.stringify(dashboardStatus)}`);
}
const dashboardChildren = await getChildOuSummary(
  client,
  '84000000-0000-4000-8000-000000000001',
  '88000000-0000-4000-8000-000000000002'
);
if (dashboardChildren.children[0]?.metrics[0]?.value !== 175 || dashboardChildren.children[0]?.status !== 'approved') {
  throw new Error(`Frontend dashboard child integration failed: ${JSON.stringify(dashboardChildren)}`);
}
const dashboardTrend = await getDashboardTrend(
  client,
  '84000000-0000-4000-8000-000000000001',
  'ATTENDANCE',
  '88000000-0000-4000-8000-000000000002'
);
if (dashboardTrend.points.at(-1)?.value !== 175 || dashboardTrend.points.at(-2)?.value !== 90) {
  throw new Error(`Frontend dashboard trend integration failed: ${JSON.stringify(dashboardTrend)}`);
}

const reportTable = await getReportTable(
  client,
  '84000000-0000-4000-8000-000000000001',
  '2026-07-20',
  '2026-07-26'
);
const reportCompleteness = await getSubmissionCompleteness(
  client,
  '84000000-0000-4000-8000-000000000001',
  '2026-07-20',
  '2026-07-26'
);
const reportTrend = await getReportTrend(
  client,
  '84000000-0000-4000-8000-000000000001',
  'ATTENDANCE',
  '2026-07-13',
  '2026-07-26'
);
if (reportTable.totals.ATTENDANCE !== attendance.currentValue || reportTable.rows.length !== 2) {
  throw new Error(`Frontend report/dashboard parity failed: ${JSON.stringify(reportTable)}`);
}
if (reportCompleteness.summary.approved !== 2 || reportCompleteness.summary.missing !== 0) {
  throw new Error(`Frontend report completeness failed: ${JSON.stringify(reportCompleteness)}`);
}
if (reportTrend.points.at(-1)?.value !== 175 || reportTrend.points.at(-2)?.value !== 90) {
  throw new Error(`Frontend report trend failed: ${JSON.stringify(reportTrend)}`);
}

await updateTenantSettings(client, {
  name: tenants[0].name,
  timezone: 'Asia/Bangkok',
  approvalMode: 'approval_required',
  reportingWeekEndsOn: 0,
  submissionDeadlineDaysAfterPeriodEnd: 1,
  primaryMetricId: '87000000-0000-4000-8000-000000000001'
});
const approvalOu = submissionContext.organizationUnits.find((ou) => ou.code === 'GROUP-A')!;
const approvalSubmit = await submitStatistics(client, {
  clientRequestId: crypto.randomUUID(),
  expectedRevision: null,
  ouId: approvalOu.id,
  periodId: submissionPeriod.id,
  remarks: 'Task 4 frontend integration submitted',
  values: [{ metricId: requiredMetric.id, numericValue: 31, textValue: null, booleanValue: null }]
});
const pendingQueue = await listPendingSubmissions(client, submissionPeriod.id, null, 'submitted');
if (approvalSubmit.status !== 'submitted' || !pendingQueue.items.some((item) => item.id === approvalSubmit.submissionId)) {
  throw new Error(`Frontend approval queue integration failed: ${JSON.stringify(pendingQueue)}`);
}
const approvalDetail = await getApprovalSubmissionDetail(client, approvalSubmit.submissionId);
if (!approvalDetail.capabilities.canApprove || approvalDetail.values[0]?.numericValue !== 31) {
  throw new Error(`Frontend approval detail integration failed: ${JSON.stringify(approvalDetail)}`);
}
await approveSubmission(client, {
  submissionId: approvalSubmit.submissionId,
  expectedRevision: approvalSubmit.revisionNo,
  clientRequestId: crypto.randomUUID(),
  reason: 'Integration approved'
});
await returnSubmissionForEdit(client, {
  submissionId: approvalSubmit.submissionId,
  expectedRevision: approvalSubmit.revisionNo,
  clientRequestId: crypto.randomUUID(),
  reason: 'Integration return for correction'
});
const returnedDetail = await getApprovalSubmissionDetail(client, approvalSubmit.submissionId);
if (returnedDetail.submission.status !== 'returned' || returnedDetail.history.length < 3) {
  throw new Error(`Frontend approval history integration failed: ${JSON.stringify(returnedDetail)}`);
}

await updateTenantSettings(client, {
  name: tenants[0].name,
  timezone: 'Asia/Bangkok',
  approvalMode: 'auto_approve',
  reportingWeekEndsOn: 0,
  submissionDeadlineDaysAfterPeriodEnd: 1,
  primaryMetricId: '87000000-0000-4000-8000-000000000001'
});
await updateOrganizationUnitType(client, '83000000-0000-4000-8000-000000000002', {
  name: 'ภาค',
  description: '',
  sortOrder: 20,
  defaultAllowDataEntry: false,
  isActive: true
});
await updateStatisticMetric(client, '87000000-0000-4000-8000-000000000002', {
  name: 'รวีวารศึกษา',
  description: '',
  category: 'attendance',
  unit: 'person',
  aggregation: 'sum',
  defaultValue: null,
  minValue: 0,
  maxValue: null,
  isRequired: false,
  sortOrder: 20,
  isActive: true
});

const platformDetail = await getPlatformTenantDetail(client, '81000000-0000-4000-8000-000000000001');
if (!platformDetail.provisioning.ready || platformDetail.provisioning.metricCount < 9) {
  throw new Error(`Frontend platform detail integration failed: ${JSON.stringify(platformDetail)}`);
}
await updatePlatformTenant(client, platformDetail.id, {
  name: platformDetail.name,
  slug: platformDetail.slug,
  description: platformDetail.description,
  timezone: platformDetail.timezone,
  approvalMode: platformDetail.approvalMode,
  weekEndsOn: platformDetail.weekEndsOn,
  submissionDeadlineDaysAfterPeriodEnd: platformDetail.submissionDeadlineDaysAfterPeriodEnd
});
const platformInvite = await createPlatformAdminInviteLink(client, platformDetail.id, 7);
const [platformInvitations, platformActivity] = await Promise.all([
  listPlatformTenantInvitations(client, platformDetail.id),
  listPlatformTenantActivity(client, platformDetail.id)
]);
if (
  !platformInvitations.some((invitation) => invitation.id === platformInvite.invitationId && invitation.status === 'pending') ||
  !platformActivity.some((item) => item.action === 'update_platform_tenant')
) {
  throw new Error(`Frontend platform invitation/activity integration failed: ${JSON.stringify({ platformInvitations, platformActivity })}`);
}

console.log('FRONTEND_BACKEND_INTEGRATION_PASSED');
