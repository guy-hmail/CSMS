-- Authenticated clients need table privileges before row-level security policies
-- can decide which rows are visible. Mutations remain RPC-only: no INSERT,
-- UPDATE, or DELETE table privileges are granted here.

grant select on table
    public.churches,
    public.users,
    public.church_members,
    public.tenant_invitations,
    public.user_preferences,
    public.organization_unit_types,
    public.organization_units,
    public.ou_members,
    public.statistic_periods,
    public.metric_template_sets,
    public.statistic_metrics,
    public.statistic_submissions,
    public.statistic_values,
    public.submission_revisions,
    public.api_idempotency_keys,
    public.approval_logs,
    public.audit_logs
to authenticated;
