-- Task 6: permission-scoped report table, trend and submission completeness.

create or replace function public.get_submission_completeness(
  p_ou_id uuid,
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  target_ou public.organization_units%rowtype;
  summary_data jsonb;
  items_data jsonb;
begin
  if p_from_date is null or p_to_date is null or p_from_date > p_to_date then
    raise exception 'INVALID_REPORT_RANGE';
  end if;

  select * into target_ou
  from public.organization_units
  where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then
    raise exception 'REPORT_FORBIDDEN';
  end if;

  with periods as (
    select id from public.statistic_periods
    where church_id = tenant_id and period_end between p_from_date and p_to_date
  ), expected_ous as (
    select ou.id, ou.code, ou.name, ou.path
    from public.organization_units ou
    where ou.church_id = tenant_id and ou.structure_root_id = target_ou.structure_root_id
      and ou.is_active and ou.deleted_at is null and ou.allow_data_entry
      and (ou.path = target_ou.path or ou.path like target_ou.path || '/%')
      and app_security.can_view_ou(ou.id)
  ), status_grid as (
    select ou.id, ou.code, ou.name, ou.path, period.id period_id,
      coalesce(submission.status, 'missing') status
    from expected_ous ou cross join periods period
    left join public.statistic_submissions submission
      on submission.church_id = tenant_id and submission.ou_id = ou.id
     and submission.period_id = period.id and submission.deleted_at is null
  ), per_ou as (
    select id, code, name, path, count(*) expected,
      count(*) filter (where status <> 'missing') submitted,
      count(*) filter (where status = 'approved') approved,
      count(*) filter (where status = 'submitted') pending,
      count(*) filter (where status = 'draft') draft,
      count(*) filter (where status = 'returned') returned,
      count(*) filter (where status = 'rejected') rejected,
      count(*) filter (where status = 'missing') missing
    from status_grid group by id, code, name, path
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'ouId', id, 'ouCode', code, 'ouName', name,
    'expected', expected, 'submitted', submitted, 'approved', approved,
    'pending', pending, 'draft', draft, 'returned', returned,
    'rejected', rejected, 'missing', missing
  ) order by path), '[]'::jsonb)
  into items_data from per_ou;

  with periods as (
    select id from public.statistic_periods
    where church_id = tenant_id and period_end between p_from_date and p_to_date
  ), expected_ous as (
    select ou.id
    from public.organization_units ou
    where ou.church_id = tenant_id and ou.structure_root_id = target_ou.structure_root_id
      and ou.is_active and ou.deleted_at is null and ou.allow_data_entry
      and (ou.path = target_ou.path or ou.path like target_ou.path || '/%')
      and app_security.can_view_ou(ou.id)
  ), status_grid as (
    select coalesce(submission.status, 'missing') status
    from expected_ous ou cross join periods period
    left join public.statistic_submissions submission
      on submission.church_id = tenant_id and submission.ou_id = ou.id
     and submission.period_id = period.id and submission.deleted_at is null
  )
  select jsonb_build_object(
    'expected', count(*),
    'submitted', count(*) filter (where status <> 'missing'),
    'approved', count(*) filter (where status = 'approved'),
    'pending', count(*) filter (where status = 'submitted'),
    'draft', count(*) filter (where status = 'draft'),
    'returned', count(*) filter (where status = 'returned'),
    'rejected', count(*) filter (where status = 'rejected'),
    'missing', count(*) filter (where status = 'missing')
  ) into summary_data from status_grid;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'fromDate', p_from_date, 'toDate', p_to_date,
    'summary', summary_data, 'items', items_data
  ));
end;
$$;

create or replace function public.get_report_table(
  p_ou_id uuid,
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  target_ou public.organization_units%rowtype;
  church_name text;
  metrics_data jsonb;
  rows_data jsonb;
  totals_data jsonb;
begin
  if p_from_date is null or p_to_date is null or p_from_date > p_to_date then
    raise exception 'INVALID_REPORT_RANGE';
  end if;
  select * into target_ou from public.organization_units
  where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then
    raise exception 'REPORT_FORBIDDEN';
  end if;
  select name into church_name from public.churches where id = tenant_id and deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object(
    'metricId', metric.id, 'metricCode', metric.code, 'metricName', metric.name,
    'category', metric.category, 'unit', metric.unit, 'aggregation', metric.aggregation
  ) order by metric.sort_order, metric.name), '[]'::jsonb)
  into metrics_data
  from public.statistic_metrics metric
  where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
    and metric.data_type = 'number' and metric.aggregation <> 'none';

  with report_ous as (
    select ou.id, ou.code, ou.name, ou.path
    from public.organization_units ou
    where ou.church_id = tenant_id and ou.structure_root_id = target_ou.structure_root_id
      and ou.is_active and ou.deleted_at is null and ou.allow_data_entry
      and (ou.path = target_ou.path or ou.path like target_ou.path || '/%')
      and app_security.can_view_ou(ou.id)
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'ouId', report_ou.id, 'ouCode', report_ou.code, 'ouName', report_ou.name,
    'values', coalesce(values_by_metric.values, '{}'::jsonb)
  ) order by report_ou.path), '[]'::jsonb)
  into rows_data
  from report_ous report_ou
  left join lateral (
    select jsonb_object_agg(metric.code,
      case metric.aggregation
        when 'sum' then aggregate.sum_value when 'avg' then aggregate.avg_value
        when 'max' then aggregate.max_value when 'min' then aggregate.min_value else null end
    ) values
    from public.statistic_metrics metric
    left join lateral (
      select sum(value.numeric_value) sum_value, avg(value.numeric_value) avg_value,
        max(value.numeric_value) max_value, min(value.numeric_value) min_value
      from public.statistic_submissions submission
      join public.statistic_periods period
        on period.id = submission.period_id and period.church_id = submission.church_id
       and period.period_end between p_from_date and p_to_date
      join public.statistic_values value
        on value.submission_id = submission.id and value.church_id = submission.church_id
       and value.metric_id = metric.id
      where submission.church_id = tenant_id and submission.ou_id = report_ou.id
        and submission.status = 'approved' and submission.deleted_at is null
    ) aggregate on true
    where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
      and metric.data_type = 'number' and metric.aggregation <> 'none'
  ) values_by_metric on true;

  select coalesce(jsonb_object_agg(metric.code,
    case metric.aggregation
      when 'sum' then aggregate.sum_value when 'avg' then aggregate.avg_value
      when 'max' then aggregate.max_value when 'min' then aggregate.min_value else null end
  ), '{}'::jsonb)
  into totals_data
  from public.statistic_metrics metric
  left join lateral (
    select sum(value.numeric_value) sum_value, avg(value.numeric_value) avg_value,
      max(value.numeric_value) max_value, min(value.numeric_value) min_value
    from public.statistic_submissions submission
    join public.statistic_periods period
      on period.id = submission.period_id and period.church_id = submission.church_id
     and period.period_end between p_from_date and p_to_date
    join public.organization_units report_ou
      on report_ou.id = submission.ou_id and report_ou.church_id = submission.church_id
     and report_ou.structure_root_id = target_ou.structure_root_id
     and report_ou.is_active and report_ou.deleted_at is null and report_ou.allow_data_entry
     and (report_ou.path = target_ou.path or report_ou.path like target_ou.path || '/%')
     and app_security.can_view_ou(report_ou.id)
    join public.statistic_values value
      on value.submission_id = submission.id and value.church_id = submission.church_id
     and value.metric_id = metric.id
    where submission.church_id = tenant_id and submission.status = 'approved'
      and submission.deleted_at is null
  ) aggregate on true
  where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
    and metric.data_type = 'number' and metric.aggregation <> 'none';

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'church', jsonb_build_object('id', tenant_id, 'name', church_name),
    'ou', jsonb_build_object('id', target_ou.id, 'code', target_ou.code, 'name', target_ou.name),
    'fromDate', p_from_date, 'toDate', p_to_date,
    'metrics', metrics_data, 'rows', rows_data, 'totals', totals_data
  ));
end;
$$;

create or replace function public.get_report_trend(
  p_ou_id uuid,
  p_metric_code text,
  p_from_date date,
  p_to_date date
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  target_ou public.organization_units%rowtype;
  target_metric public.statistic_metrics%rowtype;
  points_data jsonb;
begin
  if p_from_date is null or p_to_date is null or p_from_date > p_to_date then
    raise exception 'INVALID_REPORT_RANGE';
  end if;
  select * into target_ou from public.organization_units
  where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then
    raise exception 'REPORT_FORBIDDEN';
  end if;
  select * into target_metric from public.statistic_metrics
  where church_id = tenant_id and code = p_metric_code and is_active and deleted_at is null
    and data_type = 'number' and aggregation <> 'none';
  if target_metric.id is null then raise exception 'REPORT_METRIC_NOT_FOUND'; end if;

  with selected_periods as (
    select * from public.statistic_periods
    where church_id = tenant_id and period_end between p_from_date and p_to_date
  ), aggregates as (
    select period.id, sum(value.numeric_value) sum_value, avg(value.numeric_value) avg_value,
      max(value.numeric_value) max_value, min(value.numeric_value) min_value
    from selected_periods period
    left join public.statistic_submissions submission
      on submission.period_id = period.id and submission.church_id = tenant_id
     and submission.status = 'approved' and submission.deleted_at is null
    left join public.organization_units report_ou
      on report_ou.id = submission.ou_id and report_ou.church_id = submission.church_id
     and report_ou.structure_root_id = target_ou.structure_root_id
     and report_ou.is_active and report_ou.deleted_at is null and report_ou.allow_data_entry
     and (report_ou.path = target_ou.path or report_ou.path like target_ou.path || '/%')
     and app_security.can_view_ou(report_ou.id)
    left join public.statistic_values value
      on value.submission_id = submission.id and value.church_id = submission.church_id
     and value.metric_id = target_metric.id and report_ou.id is not null
    group by period.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'periodId', period.id, 'label', period.label, 'periodStart', period.period_start,
    'periodEnd', period.period_end, 'value', coalesce(case target_metric.aggregation
      when 'sum' then aggregate.sum_value when 'avg' then aggregate.avg_value
      when 'max' then aggregate.max_value when 'min' then aggregate.min_value else null end, 0)
  ) order by period.period_end), '[]'::jsonb)
  into points_data from selected_periods period join aggregates aggregate on aggregate.id = period.id;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'metricCode', target_metric.code, 'metricName', target_metric.name,
    'unit', target_metric.unit, 'points', points_data
  ));
end;
$$;

revoke all on function public.get_report_table(uuid, date, date) from public;
revoke all on function public.get_report_trend(uuid, text, date, date) from public;
revoke all on function public.get_submission_completeness(uuid, date, date) from public;
grant execute on function public.get_report_table(uuid, date, date) to authenticated;
grant execute on function public.get_report_trend(uuid, text, date, date) to authenticated;
grant execute on function public.get_submission_completeness(uuid, date, date) to authenticated;
