import { createHmac, randomUUID } from 'node:crypto';
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { approveSubmission, getApprovalSubmissionDetail, listPendingSubmissions } from '../src/lib/api/approvalApi';
import { getRecursiveSummary, getSubmissionStatusSummary } from '../src/lib/api/dashboardApi';
import { getMyPreferences, getMyProfile, updateMyPreferences } from '../src/lib/api/identityApi';
import { createOuInviteLink, listOuInvitations } from '../src/lib/api/invitationApi';
import {
  createOrganizationUnit, getAccessibleOuTree, getOuMembers, removeOuMember,
  softDeleteOrganizationUnit, updateOrganizationUnit, updateOuMemberAssignment
} from '../src/lib/api/organizationApi';
import {
  createPlatformAdminInviteLink, createPlatformTenant, getPlatformTenantDetail,
  listPlatformTenantActivity, listPlatformTenantInvitations, listPlatformTenants,
  setPlatformTenantStatus
} from '../src/lib/api/platformTenantApi';
import { getReportTable, getSubmissionCompleteness } from '../src/lib/api/reportApi';
import { getSubmissionByContext, getWeeklySubmissionContext, saveStatisticsDraft, submitStatistics } from '../src/lib/api/submissionApi';
import { updateTenantSettings } from '../src/lib/api/tenantSettingsApi';

const postgrestUrl = process.env.POSTGREST_URL ?? 'http://127.0.0.1:54421';
const jwtSecret = process.env.POSTGREST_JWT_SECRET ?? 'super-secret-jwt-token-with-at-least-32-characters-long';
const publishableKey = process.env.POSTGREST_API_KEY ?? 'sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH';
const checkpoints: string[] = [];

function base64Url(value: string): string { return Buffer.from(value).toString('base64url'); }
function signJwt(payload: Record<string, unknown>): string {
  const header = base64Url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = base64Url(JSON.stringify(payload));
  const signature = createHmac('sha256', jwtSecret).update(`${header}.${body}`).digest('base64url');
  return `${header}.${body}.${signature}`;
}
function clientFor(role: 'authenticated' | 'service_role', sub: string, tenantId?: string): SupabaseClient {
  const token = signJwt({ sub, role, aud: 'authenticated', exp: Math.floor(Date.now() / 1000) + 900,
    ...(tenantId ? { app_metadata: { active_church_id: tenantId } } : {}) });
  return createClient(postgrestUrl, publishableKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { headers: { Authorization: `Bearer ${token}` } }
  });
}
function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(`FULL_LOOP_ASSERTION_FAILED: ${message}`);
}
function pass(name: string, evidence: unknown): void {
  checkpoints.push(name);
  console.log(`PASS ${String(checkpoints.length).padStart(2, '0')} ${name}: ${JSON.stringify(evidence)}`);
}
async function acceptToken(service: SupabaseClient, userId: string, rawToken: string): Promise<Record<string, unknown>> {
  const { data, error } = await service.rpc('accept_tenant_invitation_by_token', { p_user_id: userId, p_raw_token: rawToken });
  if (error) throw error;
  return data as Record<string, unknown>;
}

const systemClient = clientFor('authenticated', '80000000-0000-4000-8000-000000000002');
const serviceClient = clientFor('service_role', '00000000-0000-4000-8000-000000000001');
const suffix = randomUUID().slice(0, 8);
const tenantSlug = `full-loop-${suffix}`;
const rootAuthId = randomUUID();
const rootUserId = randomUUID();
const memberAuthId = randomUUID();
const memberUserId = randomUUID();

const tenantId = await createPlatformTenant(systemClient, {
  name: `Full Loop ${suffix}`,
  slug: tenantSlug,
  rootOuName: 'Full Loop Root',
  adminName: 'Full Loop Root Admin',
  adminEmail: `root-${suffix}@example.test`,
  timezone: 'Asia/Bangkok',
  weekEndsOn: 'sunday',
  approvalMode: 'auto_approve'
});
const provisioned = await getPlatformTenantDetail(systemClient, tenantId);
assert(provisioned.provisioning.ready, 'new tenant provisioning is not ready');
assert(provisioned.provisioning.rootOuCount === 1, 'new tenant must have exactly one Root OU');
assert(provisioned.provisioning.ouTypeCount >= 5, 'new tenant must have at least five OU Types');
assert(provisioned.provisioning.metricCount === 9, 'new tenant must have nine metrics');
pass('tenant provisioning', provisioned.provisioning);

const rootInvite = await createPlatformAdminInviteLink(systemClient, tenantId, 7);
const { error: rootUserError } = await serviceClient.from('users').insert({
  id: rootUserId, auth_user_id: rootAuthId, line_user_id: `line-root-${suffix}`,
  display_name: 'Full Loop Root Admin', email: `root-${suffix}@example.test`, global_role: 'user', is_active: true
});
if (rootUserError) throw rootUserError;
const acceptedRoot = await acceptToken(serviceClient, rootUserId, rootInvite.inviteToken);
assert(acceptedRoot.accepted === true && acceptedRoot.tenantId === tenantId, 'Root Admin invite acceptance failed');
const platformInvitations = await listPlatformTenantInvitations(systemClient, tenantId);
assert(platformInvitations.some((item) => item.id === rootInvite.invitationId && item.status === 'accepted'), 'Root invite status must be accepted');
pass('Root Admin invite acceptance', { invitationId: rootInvite.invitationId, status: 'accepted' });

const rootClient = clientFor('authenticated', rootAuthId, tenantId);
const profile = await getMyProfile(rootClient);
assert(profile.currentTenant?.id === tenantId, 'Root Admin profile tenant mismatch');
assert(profile.permissions.some((permission) => permission.permission === 'admin'), 'Root Admin permission missing');
const rootTree = await getAccessibleOuTree(rootClient);
assert(rootTree.items.length === 1 && rootTree.items[0].name === 'Full Loop Root', 'Root OU tree mismatch');
const rootOuId = rootTree.items[0].id;
const { data: foreignChurches, error: foreignError } = await rootClient.from('churches').select('id').eq('id', '81000000-0000-4000-8000-000000000001');
if (foreignError) throw foreignError;
assert(foreignChurches.length === 0, 'RLS exposed another tenant');
let nonSystemDenied = false;
try { await listPlatformTenants(rootClient); } catch { nonSystemDenied = true; }
assert(nonSystemDenied, 'non-system admin accessed control plane');
pass('identity, permission and tenant isolation', { tenantId, rootOuId, role: 'admin' });

const initialContext = await getWeeklySubmissionContext(rootClient);
assert(initialContext.periods.length === 5, 'new tenant must receive five recent reporting periods');
assert(initialContext.metrics.length === 9, 'submission context metric count mismatch');
const attendance = initialContext.metrics.find((metric) => metric.code === 'ATTENDANCE');
assert(attendance?.isRequired, 'required ATTENDANCE metric missing');
await updateTenantSettings(rootClient, {
  name: `Full Loop ${suffix}`, timezone: 'Asia/Bangkok', approvalMode: 'approval_required',
  reportingWeekEndsOn: 0, primaryMetricId: attendance.id
});
pass('tenant settings and dynamic metric context', { periods: initialContext.periods.length, metrics: initialContext.metrics.length, primaryMetric: attendance.code });

const { data: groupTypes, error: groupTypeError } = await rootClient.from('organization_unit_types').select('id,code').eq('code', 'GROUP');
if (groupTypeError) throw groupTypeError;
assert(groupTypes.length === 1, 'GROUP OU Type not found');
const child = await createOrganizationUnit(rootClient, {
  parentOuId: rootOuId, ouTypeId: groupTypes[0].id, code: 'FULL-LOOP-GROUP',
  name: 'Full Loop Group', description: 'Created by full-loop test', sortOrder: 10, allowDataEntry: true
});
await updateOrganizationUnit(rootClient, {
  ouId: child.ouId, parentOuId: rootOuId, ouTypeId: groupTypes[0].id,
  code: 'FULL-LOOP-GROUP', name: 'Full Loop Group Updated', description: 'Updated by full-loop test',
  sortOrder: 20, allowDataEntry: true
});
const disposable = await createOrganizationUnit(rootClient, {
  parentOuId: rootOuId, ouTypeId: groupTypes[0].id, code: 'FULL-LOOP-TEMP',
  name: 'Disposable Group', description: '', sortOrder: 99, allowDataEntry: true
});
await softDeleteOrganizationUnit(rootClient, { ouId: disposable.ouId, reason: 'Full-loop safe cleanup' });
const treeAfterOrganization = await getAccessibleOuTree(rootClient);
const treeJson = JSON.stringify(treeAfterOrganization);
assert(treeJson.includes('Full Loop Group Updated') && !treeJson.includes(disposable.ouId), 'OU update/soft delete did not refresh correctly');
pass('organization create, update and safe soft delete', { childOuId: child.ouId, disposableHidden: true });

const memberInvite = await createOuInviteLink(rootClient, {
  targetOuId: child.ouId, permission: 'viewer', canOverride: false, expiresInDays: 7,
  displayName: 'Full Loop Member'
});
const { error: memberUserError } = await serviceClient.from('users').insert({
  id: memberUserId, auth_user_id: memberAuthId, line_user_id: `line-member-${suffix}`,
  display_name: 'Full Loop Member', email: `member-${suffix}@example.test`, global_role: 'user', is_active: true
});
if (memberUserError) throw memberUserError;
await acceptToken(serviceClient, memberUserId, memberInvite.inviteToken);
let childMembers = await getOuMembers(rootClient, child.ouId);
assert(childMembers.items.length === 1 && childMembers.items[0].role === 'viewer', 'accepted OU member role mismatch');
const memberAssignmentId = childMembers.items[0].assignmentId;
await updateOuMemberAssignment(rootClient, { assignmentId: memberAssignmentId, permission: 'approver', canOverride: true });
childMembers = await getOuMembers(rootClient, child.ouId);
assert(childMembers.items[0].role === 'approver' && childMembers.items[0].canOverride, 'member role/override update failed');
await removeOuMember(rootClient, { assignmentId: memberAssignmentId, reason: 'Full-loop member cleanup' });
childMembers = await getOuMembers(rootClient, child.ouId);
assert(childMembers.items.length === 0, 'member assignment removal failed');
const invitationsAfterAccept = await listOuInvitations(rootClient, child.ouId);
assert(invitationsAfterAccept.items.some((item) => item.invitationId === memberInvite.invitationId && item.status === 'accepted'), 'OU invitation status mismatch');
pass('member invite, role, override and removal', { transitions: ['viewer', 'approver+override', 'removed'] });

const defaults = await getMyPreferences(rootClient);
assert(defaults.language === 'th' && defaults.landingPage === '/app/dashboard', 'preference defaults mismatch');
await updateMyPreferences(rootClient, {
  defaultOuId: child.ouId, language: 'th', landingPage: '/app/reports',
  notifyMissing: true, notifySubmitted: true, notifyApproval: true, notifyEmail: false
});
const preferences = await getMyPreferences(rootClient);
assert(preferences.defaultOuId === child.ouId && preferences.landingPage === '/app/reports', 'preferences did not persist');
pass('user preference persistence', { defaultOuId: preferences.defaultOuId, landingPage: preferences.landingPage });

const context = await getWeeklySubmissionContext(rootClient);
const period = context.periods[0];
const requiredMetric = context.metrics.find((metric) => metric.code === 'ATTENDANCE');
assert(requiredMetric, 'ATTENDANCE metric missing from refreshed context');
const draft = await saveStatisticsDraft(rootClient, {
  clientRequestId: randomUUID(), expectedRevision: null, ouId: child.ouId, periodId: period.id,
  remarks: 'Full-loop draft 42', values: [{ metricId: requiredMetric.id, numericValue: 42, textValue: null, booleanValue: null }]
});
const draftReadback = await getSubmissionByContext(rootClient, child.ouId, period.id);
assert(draft.status === 'draft' && draftReadback?.values[0].numericValue === 42, 'draft 42 did not persist');
const submitRequest = {
  clientRequestId: randomUUID(), expectedRevision: draft.revisionNo, ouId: child.ouId, periodId: period.id,
  remarks: 'Full-loop submitted 45', values: [{ metricId: requiredMetric.id, numericValue: 45, textValue: null, booleanValue: null }]
};
const submitted = await submitStatistics(rootClient, submitRequest);
const replay = await submitStatistics(rootClient, submitRequest);
assert(submitted.status === 'submitted' && replay.submissionId === submitted.submissionId, 'submit/idempotency failed');
pass('weekly draft, submit and idempotency', { draftValue: 42, submittedValue: 45, status: submitted.status, revision: submitted.revisionNo });

const queue = await listPendingSubmissions(rootClient, period.id, null, 'submitted');
assert(queue.items.some((item) => item.id === submitted.submissionId), 'submitted record missing from approval queue');
const approvalBefore = await getApprovalSubmissionDetail(rootClient, submitted.submissionId);
assert(approvalBefore.values.some((value) => value.numericValue === 45), 'approval detail value mismatch');
await approveSubmission(rootClient, {
  submissionId: submitted.submissionId, expectedRevision: submitted.revisionNo,
  clientRequestId: randomUUID(), reason: 'Full-loop approved'
});
const approvalAfter = await getApprovalSubmissionDetail(rootClient, submitted.submissionId);
assert(approvalAfter.submission.status === 'approved' && approvalAfter.history.length >= 2, 'approval state/history mismatch');
pass('approval queue, detail and approve', { status: approvalAfter.submission.status, history: approvalAfter.history.length });

const summary = await getRecursiveSummary(rootClient, rootOuId, period.id, null);
const dashboardAttendance = summary.metrics.find((metric) => metric.metricCode === 'ATTENDANCE');
assert(dashboardAttendance?.currentValue === 45, 'dashboard attendance must equal approved value 45');
const statusSummary = await getSubmissionStatusSummary(rootClient, rootOuId, period.id);
assert(statusSummary.summary.totalExpected === 1 && statusSummary.summary.approved === 1, 'dashboard completeness mismatch');
const report = await getReportTable(rootClient, rootOuId, period.periodStart, period.periodEnd);
const completeness = await getSubmissionCompleteness(rootClient, rootOuId, period.periodStart, period.periodEnd);
assert(report.totals.ATTENDANCE === 45 && report.rows.length === 1, 'report total/row count mismatch');
assert(completeness.summary.approved === 1 && completeness.summary.missing === 0, 'report completeness mismatch');
pass('submission/dashboard/report parity', { submission: 45, dashboard: dashboardAttendance.currentValue, report: report.totals.ATTENDANCE, approved: completeness.summary.approved, missing: completeness.summary.missing });

let protectedDeleteDenied = false;
try { await softDeleteOrganizationUnit(rootClient, { ouId: child.ouId, reason: 'Must be blocked because submission exists' }); }
catch { protectedDeleteDenied = true; }
assert(protectedDeleteDenied, 'OU with submissions was soft-deleted unsafely');
pass('OU deletion safety', { protectedDeleteDenied });

const activity = await listPlatformTenantActivity(systemClient, tenantId);
for (const expectedAction of ['create_tenant', 'create_platform_admin_invite_link', 'accept_tenant_invitation_by_token', 'update_settings', 'submit', 'approve']) {
  assert(activity.some((item) => item.action === expectedAction), `audit action missing: ${expectedAction}`);
}
pass('searchable audit activity', { count: activity.length, requiredActions: ['create_tenant', 'invite', 'accept', 'settings', 'submit', 'approve'] });

await setPlatformTenantStatus(systemClient, tenantId, 'suspended');
let suspendedDenied = false;
try { await getWeeklySubmissionContext(rootClient); } catch { suspendedDenied = true; }
assert(suspendedDenied, 'suspended tenant still accessed tenant RPC');
const suspendedDetail = await getPlatformTenantDetail(systemClient, tenantId);
assert(suspendedDetail.status === 'suspended', 'control plane did not show suspended status');
await setPlatformTenantStatus(systemClient, tenantId, 'active');
const contextAfterReactivate = await getWeeklySubmissionContext(rootClient);
assert(contextAfterReactivate.metrics.length === 9, 'reactivation did not restore tenant RPC');
pass('suspend enforcement and reactivation', { suspendedDenied, reactivatedMetrics: contextAfterReactivate.metrics.length });

await setPlatformTenantStatus(systemClient, tenantId, 'closed');
const closedDetail = await getPlatformTenantDetail(systemClient, tenantId);
assert(closedDetail.status === 'closed', 'closed lifecycle status mismatch');
let reopenDenied = false;
try { await setPlatformTenantStatus(systemClient, tenantId, 'active'); } catch { reopenDenied = true; }
assert(reopenDenied, 'closed tenant was reopened');
pass('closed retention and terminal lifecycle', { status: closedDetail.status, reopenDenied });

console.log(`FULL_LOOP_INTEGRATION_PASSED checkpoints=${checkpoints.length} tenant=${tenantSlug}`);
