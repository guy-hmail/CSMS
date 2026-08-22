-- Separate the calculation boundary from the submission deadline.
-- period_end remains the canonical calculation/reporting date. Submission
-- timestamps are snapshotted on each generated period so later Tenant setting
-- changes do not rewrite historical deadlines.

alter table public.churches
  add column if not exists submission_deadline_days_after_period_end smallint not null default 1;

alter table public.churches
  drop constraint if exists ck_churches_submission_deadline_days;
alter table public.churches
  add constraint ck_churches_submission_deadline_days
  check (submission_deadline_days_after_period_end between 1 and 6);

alter table public.statistic_periods
  add column if not exists submission_opens_at timestamptz,
  add column if not exists submission_due_at timestamptz;

alter table public.statistic_periods
  drop constraint if exists ck_statistic_periods_submission_window;
alter table public.statistic_periods
  add constraint ck_statistic_periods_submission_window check (
    (submission_opens_at is null and submission_due_at is null)
    or (
      submission_opens_at is not null
      and submission_due_at is not null
      and submission_due_at >= submission_opens_at
    )
  );

comment on column public.churches.reporting_week_ends_on is
  'Calculation/reporting weekday using PostgreSQL DOW (0=Sunday..6=Saturday).';
comment on column public.churches.submission_deadline_days_after_period_end is
  'Whole local calendar days after period_end before the submission window closes; 1..6.';
comment on column public.statistic_periods.submission_opens_at is
  'Snapshotted instant when data entry opens for this calculation period.';
comment on column public.statistic_periods.submission_due_at is
  'Snapshotted inclusive deadline for normal submission; report aggregation still uses period_end.';

-- Backfill existing production periods once. Periods inserted manually after
-- this migration may remain null and retain the legacy status-only behavior;
-- all canonical periods created by ensure_recent_reporting_periods are timed.
update public.statistic_periods period
set submission_opens_at = period.period_end::timestamp at time zone church.timezone,
    submission_due_at = (
      (period.period_end + church.submission_deadline_days_after_period_end + 1)::timestamp
      at time zone church.timezone
    ) - interval '1 microsecond'
from public.churches church
where church.id = period.church_id
  and period.submission_opens_at is null
  and period.submission_due_at is null;

create or replace function app_security.reporting_submission_state(
  p_period_status text,
  p_submission_opens_at timestamptz,
  p_submission_due_at timestamptz,
  p_reference_at timestamptz default now()
)
returns text
language sql
stable
set search_path = ''
as $$
  select case
    when p_period_status <> 'open' then 'locked'
    when p_submission_opens_at is null or p_submission_due_at is null then 'open'
    when p_reference_at < p_submission_opens_at then 'not_open'
    when p_reference_at <= p_submission_due_at then 'open'
    else 'overdue'
  end;
$$;

create or replace function public.ensure_recent_reporting_periods()
returns table (
  period_id uuid,
  period_start date,
  period_end date,
  display_label varchar,
  submission_opens_at timestamptz,
  submission_due_at timestamptz,
  submission_state text,
  is_submission_open boolean
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  tenant public.churches%rowtype;
  local_date date;
  latest_period_end date;
  target_end date;
  target_start date;
  target_opens_at timestamptz;
  target_due_at timestamptz;
begin
  select church.* into tenant
  from public.churches church
  where church.id = app_security.current_church_id()
    and church.is_active
    and church.deleted_at is null;
  if tenant.id is null then
    raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
  end if;

  local_date := (now() at time zone tenant.timezone)::date;
  latest_period_end := local_date - (
    (extract(dow from local_date)::integer - tenant.reporting_week_ends_on + 7) % 7
  );

  for week_offset in 0..4 loop
    target_end := latest_period_end - (week_offset * 7);
    target_start := target_end - 6;
    target_opens_at := target_end::timestamp at time zone tenant.timezone;
    target_due_at := (
      (target_end + tenant.submission_deadline_days_after_period_end + 1)::timestamp
      at time zone tenant.timezone
    ) - interval '1 microsecond';

    insert into public.statistic_periods as existing_period (
      church_id, year, week_no, period_start, period_end, label, status,
      submission_opens_at, submission_due_at
    )
    values (
      tenant.id,
      extract(isoyear from target_end)::integer,
      extract(week from target_end)::integer,
      target_start,
      target_end,
      to_char(target_end, 'YYYY-MM-DD'),
      'open',
      target_opens_at,
      target_due_at
    )
    on conflict on constraint uq_period_per_church do update
    set year = excluded.year,
        week_no = excluded.week_no,
        period_end = excluded.period_end,
        label = excluded.label,
        submission_opens_at = coalesce(existing_period.submission_opens_at, excluded.submission_opens_at),
        submission_due_at = coalesce(existing_period.submission_due_at, excluded.submission_due_at);
  end loop;

  return query
  select
    period.id,
    period.period_start,
    period.period_end,
    period.label,
    period.submission_opens_at,
    period.submission_due_at,
    app_security.reporting_submission_state(
      period.status, period.submission_opens_at, period.submission_due_at, now()
    ),
    app_security.reporting_submission_state(
      period.status, period.submission_opens_at, period.submission_due_at, now()
    ) = 'open'
  from public.statistic_periods period
  where period.church_id = tenant.id
    and period.period_end between latest_period_end - 28 and latest_period_end
    and extract(dow from period.period_end)::integer = tenant.reporting_week_ends_on
  order by period.period_end desc;
end;
$$;

-- Backward-compatible name for older clients. Its behavior is now Tenant
-- configured and no longer promises a Sunday boundary.
create or replace function public.ensure_recent_sunday_periods()
returns table (
  period_id uuid,
  period_start date,
  period_end date,
  display_label varchar
)
language sql
security definer
set search_path = ''
as $$
  select period_id, period_start, period_end, display_label
  from public.ensure_recent_reporting_periods();
$$;

create or replace function public.get_weekly_submission_context()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  tenant public.churches%rowtype;
  periods_data jsonb;
  ous_data jsonb;
  metrics_data jsonb;
  default_period_id uuid;
begin
  select * into tenant from public.churches where id = tenant_id;
  perform 1 from public.ensure_recent_reporting_periods();

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', period.id,
    'label', period.label,
    'periodStart', period.period_start,
    'periodEnd', period.period_end,
    'year', period.year,
    'weekNo', period.week_no,
    'status', period.status,
    'submissionOpensAt', period.submission_opens_at,
    'submissionDueAt', period.submission_due_at,
    'submissionState', app_security.reporting_submission_state(
      period.status, period.submission_opens_at, period.submission_due_at, now()
    ),
    'isSubmissionOpen', app_security.reporting_submission_state(
      period.status, period.submission_opens_at, period.submission_due_at, now()
    ) = 'open'
  ) order by period.period_end desc), '[]'::jsonb)
  into periods_data
  from public.statistic_periods period
  where period.church_id = tenant_id
    and period.period_type = 'week'
    and extract(dow from period.period_end)::integer = tenant.reporting_week_ends_on
    and period.period_end between (
      (now() at time zone tenant.timezone)::date
      - ((extract(dow from (now() at time zone tenant.timezone)::date)::integer - tenant.reporting_week_ends_on + 7) % 7)
      - 28
    ) and (
      (now() at time zone tenant.timezone)::date
      - ((extract(dow from (now() at time zone tenant.timezone)::date)::integer - tenant.reporting_week_ends_on + 7) % 7)
    );

  select period.id into default_period_id
  from public.statistic_periods period
  where period.church_id = tenant_id
    and period.period_type = 'week'
    and extract(dow from period.period_end)::integer = tenant.reporting_week_ends_on
    and period.period_end <= (now() at time zone tenant.timezone)::date
  order by
    (app_security.reporting_submission_state(
      period.status, period.submission_opens_at, period.submission_due_at, now()
    ) = 'open') desc,
    period.period_end desc
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', ou.id, 'name', ou.name, 'code', ou.code, 'path', ou.path, 'level', ou.level
  ) order by ou.path, ou.sort_order, ou.name), '[]'::jsonb)
  into ous_data
  from public.organization_units ou
  where ou.church_id = tenant_id
    and ou.is_active and ou.deleted_at is null
    and ou.allow_data_entry
    and app_security.can_submit_for_ou(ou.id);

  select coalesce(jsonb_agg(jsonb_build_object(
    'id', metric.id, 'code', metric.code, 'name', metric.name,
    'category', metric.category, 'unit', metric.unit, 'dataType', metric.data_type,
    'inputType', metric.input_type, 'isRequired', metric.is_required,
    'minValue', metric.min_value, 'maxValue', metric.max_value, 'sortOrder', metric.sort_order
  ) order by metric.sort_order, metric.name), '[]'::jsonb)
  into metrics_data
  from public.statistic_metrics metric
  where metric.church_id = tenant_id
    and metric.metric_kind = 'input'
    and metric.is_active and metric.deleted_at is null;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'periods', periods_data,
    'defaultPeriodId', default_period_id,
    'reportingWeekEndsOn', tenant.reporting_week_ends_on,
    'submissionDeadlineDaysAfterPeriodEnd', tenant.submission_deadline_days_after_period_end,
    'timezone', tenant.timezone,
    'organizationUnits', ous_data,
    'metrics', metrics_data
  ));
end;
$$;

create or replace function app_security.require_submission_window(p_payload jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  tenant_id uuid := app_security.current_church_id();
  target_period public.statistic_periods%rowtype;
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
  if window_state = 'not_open' then raise exception 'SUBMISSION_WINDOW_NOT_OPEN'; end if;
  if window_state = 'overdue' then raise exception 'SUBMISSION_DEADLINE_PASSED'; end if;
  if window_state = 'locked' then raise exception 'PERIOD_LOCKED'; end if;
end;
$$;

create or replace function public.save_statistics_draft(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform app_security.require_submission_window(p_payload);
  return app_security.process_statistics_payload(p_payload, false);
end;
$$;

create or replace function public.submit_statistics(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior_context text := current_setting('app.notification_event_context', true);
  result jsonb;
begin
  perform app_security.require_submission_window(p_payload);
  perform set_config('app.notification_event_context', 'stage_c', true);
  result := app_security.submit_statistics_without_notification_events(p_payload);
  perform set_config('app.notification_event_context', coalesce(prior_context, ''), true);
  return result;
end;
$$;

create or replace function public.update_tenant_settings(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  actor_membership_id uuid := app_security.current_church_member_id();
  source_assignment_id uuid := app_security.require_direct_root_admin();
  target public.churches%rowtype;
  root_ou_id uuid;
  before_snapshot jsonb;
  input_name text;
  input_timezone text;
  input_approval_mode text;
  input_week_end smallint;
  input_deadline_days smallint;
  input_primary_metric_id uuid;
begin
  select * into target from public.churches
  where id = app_security.current_church_id() and is_active and deleted_at is null
  for update;
  if target.id is null then raise exception 'TENANT_NOT_FOUND'; end if;

  select ou_id into root_ou_id from public.ou_members
  where id = source_assignment_id and church_id = target.id;

  input_name := trim(coalesce(p_payload ->> 'name', target.name));
  input_timezone := trim(coalesce(p_payload ->> 'timezone', target.timezone));
  input_approval_mode := coalesce(p_payload ->> 'approvalMode', target.approval_mode);
  input_week_end := coalesce(nullif(p_payload ->> 'reportingWeekEndsOn', '')::smallint, target.reporting_week_ends_on);
  input_deadline_days := coalesce(
    nullif(p_payload ->> 'submissionDeadlineDaysAfterPeriodEnd', '')::smallint,
    target.submission_deadline_days_after_period_end
  );
  input_primary_metric_id := case
    when p_payload ? 'primaryMetricId' and nullif(p_payload ->> 'primaryMetricId', '') is not null
      then (p_payload ->> 'primaryMetricId')::uuid
    when p_payload ? 'primaryMetricId' then null
    else target.primary_metric_id
  end;

  if nullif(input_name, '') is null or length(input_name) > 255
     or nullif(input_timezone, '') is null
     or not exists (select 1 from pg_catalog.pg_timezone_names where name = input_timezone)
     or input_approval_mode not in ('auto_approve', 'approval_required')
     or input_week_end not between 0 and 6
     or input_deadline_days not between 1 and 6 then
    raise exception 'VALIDATION_ERROR';
  end if;

  if input_primary_metric_id is not null and not exists (
    select 1 from public.statistic_metrics
    where id = input_primary_metric_id and church_id = target.id
      and data_type = 'number' and is_active and deleted_at is null
  ) then raise exception 'PRIMARY_METRIC_NOT_FOUND'; end if;

  before_snapshot := jsonb_build_object(
    'name', target.name,
    'timezone', target.timezone,
    'approvalMode', target.approval_mode,
    'reportingWeekEndsOn', target.reporting_week_ends_on,
    'submissionDeadlineDaysAfterPeriodEnd', target.submission_deadline_days_after_period_end,
    'primaryMetricId', target.primary_metric_id
  );

  update public.churches set
    name = input_name,
    timezone = input_timezone,
    approval_mode = input_approval_mode,
    reporting_week_ends_on = input_week_end,
    submission_deadline_days_after_period_end = input_deadline_days,
    primary_metric_id = input_primary_metric_id
  where id = target.id;

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, ou_id,
    source_ou_member_id, entity_type, entity_id, action,
    before_data, after_data
  ) values (
    target.id, actor_user_id, actor_membership_id, root_ou_id,
    source_assignment_id, 'churches', target.id, 'update_settings',
    before_snapshot,
    jsonb_build_object(
      'name', input_name,
      'timezone', input_timezone,
      'approvalMode', input_approval_mode,
      'reportingWeekEndsOn', input_week_end,
      'submissionDeadlineDaysAfterPeriodEnd', input_deadline_days,
      'primaryMetricId', input_primary_metric_id
    )
  );

  return jsonb_build_object('success', true, 'data', jsonb_build_object('tenantId', target.id));
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'VALIDATION_ERROR';
end;
$$;

revoke all on function app_security.reporting_submission_state(text, timestamptz, timestamptz, timestamptz) from public;
revoke all on function app_security.require_submission_window(jsonb) from public;
revoke all on function public.ensure_recent_reporting_periods() from public;
revoke all on function public.ensure_recent_sunday_periods() from public;
revoke all on function public.get_weekly_submission_context() from public;
revoke all on function public.save_statistics_draft(jsonb) from public;
revoke all on function public.submit_statistics(jsonb) from public;
revoke all on function public.update_tenant_settings(jsonb) from public;

grant execute on function public.ensure_recent_reporting_periods() to authenticated;
grant execute on function public.ensure_recent_sunday_periods() to authenticated;
grant execute on function public.get_weekly_submission_context() to authenticated;
grant execute on function public.save_statistics_draft(jsonb) to authenticated;
grant execute on function public.submit_statistics(jsonb) to authenticated;
grant execute on function public.update_tenant_settings(jsonb) to authenticated;
