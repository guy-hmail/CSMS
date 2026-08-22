-- A manager/admin-approved correction intentionally reopens one existing
-- submission. It may be saved and resubmitted after the normal Tenant deadline,
-- while new/draft submissions remain constrained by the period window.

create or replace function app_security.require_submission_window(p_payload jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  tenant_id uuid := app_security.current_church_id();
  target_period public.statistic_periods%rowtype;
  existing_status text;
  window_state text;
begin
  select * into target_period
  from public.statistic_periods
  where id = nullif(p_payload ->> 'periodId', '')::uuid
    and church_id = tenant_id;
  if target_period.id is null then raise exception 'PERIOD_NOT_FOUND'; end if;

  window_state := app_security.reporting_submission_state(
    target_period.status,
    target_period.submission_opens_at,
    target_period.submission_due_at,
    now()
  );
  if window_state = 'locked' then raise exception 'PERIOD_LOCKED'; end if;

  select submission.status into existing_status
  from public.statistic_submissions submission
  where submission.church_id = tenant_id
    and submission.period_id = target_period.id
    and submission.ou_id = nullif(p_payload ->> 'ouId', '')::uuid
    and submission.deleted_at is null;

  if existing_status = 'returned' then return; end if;
  if window_state = 'not_open' then raise exception 'SUBMISSION_WINDOW_NOT_OPEN'; end if;
  if window_state = 'overdue' then raise exception 'SUBMISSION_DEADLINE_PASSED'; end if;
end;
$$;

revoke all on function app_security.require_submission_window(jsonb) from public;
