-- Move data entry to the next reporting week as soon as the latest completed
-- period passes its Tenant deadline. Dashboard and report consumers continue
-- to use ensure_recent_reporting_periods(), which returns completed periods only.

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
  local_date date;
  latest_completed_end date;
  submission_period_end date;
  next_period_end date;
  latest_period public.statistic_periods%rowtype;
  next_opens_at timestamptz;
  next_due_at timestamptz;
begin
  select * into tenant from public.churches where id = tenant_id;
  perform 1 from public.ensure_recent_reporting_periods();

  local_date := (now() at time zone tenant.timezone)::date;
  latest_completed_end := local_date - (
    (extract(dow from local_date)::integer - tenant.reporting_week_ends_on + 7) % 7
  );
  submission_period_end := latest_completed_end;

  select period.* into latest_period
  from public.statistic_periods period
  where period.church_id = tenant_id
    and period.period_type = 'week'
    and period.period_end = latest_completed_end
  limit 1;

  if latest_period.id is not null
     and app_security.reporting_submission_state(
       latest_period.status,
       latest_period.submission_opens_at,
       latest_period.submission_due_at,
       now()
     ) = 'overdue' then
    next_period_end := latest_completed_end + 7;
    next_opens_at := coalesce(
      latest_period.submission_due_at + interval '1 microsecond',
      (latest_completed_end + tenant.submission_deadline_days_after_period_end + 1)::timestamp
        at time zone tenant.timezone
    );
    next_due_at := (
      (next_period_end + tenant.submission_deadline_days_after_period_end + 1)::timestamp
        at time zone tenant.timezone
    ) - interval '1 microsecond';

    insert into public.statistic_periods as existing_period (
      church_id, year, week_no, period_start, period_end, label, status,
      submission_opens_at, submission_due_at
    ) values (
      tenant.id,
      extract(isoyear from next_period_end)::integer,
      extract(week from next_period_end)::integer,
      latest_completed_end + 1,
      next_period_end,
      to_char(next_period_end, 'YYYY-MM-DD'),
      'open',
      next_opens_at,
      next_due_at
    )
    on conflict on constraint uq_period_per_church do update
    set year = excluded.year,
        week_no = excluded.week_no,
        period_start = excluded.period_start,
        period_end = excluded.period_end,
        label = excluded.label,
        submission_opens_at = coalesce(existing_period.submission_opens_at, excluded.submission_opens_at),
        submission_due_at = coalesce(existing_period.submission_due_at, excluded.submission_due_at);

    submission_period_end := next_period_end;
  end if;

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
    and period.period_end between submission_period_end - 28 and submission_period_end;

  select period.id into default_period_id
  from public.statistic_periods period
  where period.church_id = tenant_id
    and period.period_type = 'week'
    and extract(dow from period.period_end)::integer = tenant.reporting_week_ends_on
    and period.period_end between submission_period_end - 28 and submission_period_end
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

revoke all on function public.get_weekly_submission_context() from public;
revoke all on function public.get_weekly_submission_context() from anon;
grant execute on function public.get_weekly_submission_context() to authenticated;

