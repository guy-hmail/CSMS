-- Evaluate all ratio operands in batches and reuse accessible OU lists.
-- Preserve per-submission missing-side checks and percentage rounding.

create or replace function public.get_recursive_summary(
  p_ou_id uuid, p_period_id uuid, p_compare_period_id uuid default null
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
  target_period public.statistic_periods%rowtype;
  compare_period public.statistic_periods%rowtype;
  metric_items jsonb;
begin
  select * into target_ou
  from public.organization_units
  where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then
    raise exception 'OU_NOT_FOUND';
  end if;

  select * into target_period
  from public.statistic_periods
  where id = p_period_id and church_id = tenant_id;
  if target_period.id is null then raise exception 'PERIOD_NOT_FOUND'; end if;

  if p_compare_period_id is not null then
    select * into compare_period
    from public.statistic_periods
    where id = p_compare_period_id and church_id = tenant_id;
    if compare_period.id is null then raise exception 'COMPARE_PERIOD_NOT_FOUND'; end if;
  end if;

  with dashboard_metrics as materialized (
    select metric.*
    from public.statistic_metrics metric
    where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
      and metric.show_on_dashboard and metric.data_type = 'number' and metric.aggregation <> 'none'
  ), metric_sources as materialized (
    select metric.id metric_id,
      case when metric.metric_kind = 'input' then metric.id else source.id end source_metric_id
    from dashboard_metrics metric
    left join lateral unnest(metric.calculation_source_metric_ids) source(id)
      on metric.metric_kind = 'calculated'
  ), accessible_ous as materialized (
    select ou.id
    from public.organization_units ou
    where ou.church_id = tenant_id and ou.structure_root_id = target_ou.structure_root_id
      and ou.is_active and ou.deleted_at is null and ou.allow_data_entry
      and (ou.id = target_ou.id or ou.path like target_ou.path || '/%')
      and app_security.can_view_ou(ou.id)
  ), selected_periods as materialized (
    select target_period.id period_id
    union
    select compare_period.id where compare_period.id is not null
  ), aggregates as (
    select source.metric_id, submission.period_id,
      sum(value.numeric_value) sum_value,
      avg(value.numeric_value) avg_value,
      max(value.numeric_value) max_value,
      min(value.numeric_value) min_value
    from selected_periods period
    join public.statistic_submissions submission
      on submission.church_id = tenant_id and submission.period_id = period.period_id
      and submission.status = 'approved' and submission.deleted_at is null
    join accessible_ous ou on ou.id = submission.ou_id
    join public.statistic_values value
      on value.church_id = tenant_id and value.submission_id = submission.id
    join metric_sources source on source.source_metric_id = value.metric_id
    group by source.metric_id, submission.period_id
  ), ratio_submission_sides as materialized (
    select submission.id, submission.period_id, metric.id metric_id,
      sum(value.numeric_value) filter (where operand.position <= metric.ratio_numerator_count) numerator,
      sum(value.numeric_value) filter (where operand.position > metric.ratio_numerator_count) denominator
    from accessible_ous scope
    join public.statistic_submissions submission
      on submission.church_id = tenant_id and submission.ou_id = scope.id
      and submission.period_id in (select period_id from selected_periods) and submission.status = 'approved' and submission.deleted_at is null
    cross join dashboard_metrics metric
    cross join lateral unnest(metric.calculation_source_metric_ids) with ordinality operand(id, position)
    left join public.statistic_values value
      on value.church_id = tenant_id and value.submission_id = submission.id and value.metric_id = operand.id
    where metric.calculation_operator = 'ratio'
    group by submission.id, submission.period_id, metric.id
  ), ratio_aggregates as materialized (
    select metric_id, period_id, app_security.ratio_result(
      case when count(numerator) = count(*) then sum(numerator) end,
      case when count(denominator) = count(*) then sum(denominator) end
    ) result
    from ratio_submission_sides
    group by metric_id, period_id
  ), metric_values as (
    select metric.*, current_ratio.result ratio_result,
      case when metric.calculation_operator = 'ratio' then (current_ratio.result ->> 'value')::numeric
        when metric.metric_kind = 'calculated' or metric.aggregation = 'sum' then current_aggregate.sum_value
        when metric.aggregation = 'avg' then current_aggregate.avg_value
        when metric.aggregation = 'max' then current_aggregate.max_value
        when metric.aggregation = 'min' then current_aggregate.min_value end current_value,
      case when compare_period.id is null then null
        when metric.calculation_operator = 'ratio' then (compare_ratio.result ->> 'value')::numeric
        when metric.metric_kind = 'calculated' or metric.aggregation = 'sum' then compare_aggregate.sum_value
        when metric.aggregation = 'avg' then compare_aggregate.avg_value
        when metric.aggregation = 'max' then compare_aggregate.max_value
        when metric.aggregation = 'min' then compare_aggregate.min_value end compare_value
    from dashboard_metrics metric
    left join ratio_aggregates current_ratio
      on current_ratio.metric_id = metric.id and current_ratio.period_id = target_period.id
    left join ratio_aggregates compare_ratio
      on compare_ratio.metric_id = metric.id and compare_ratio.period_id = compare_period.id
    left join aggregates current_aggregate
      on current_aggregate.metric_id = metric.id and current_aggregate.period_id = target_period.id
    left join aggregates compare_aggregate
      on compare_aggregate.metric_id = metric.id and compare_aggregate.period_id = compare_period.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'metricId', metric.id, 'metricCode', metric.code, 'metricName', metric.name,
    'category', metric.category, 'unit', metric.unit, 'aggregation', metric.aggregation,
    'metricKind', metric.metric_kind, 'error', case when metric.calculation_operator = 'ratio' then coalesce(metric.ratio_result, app_security.ratio_result(null, null)) -> 'error' end, 'currentValue', metric.current_value,
    'compareValue', metric.compare_value, 'growthPercent', case
      when metric.compare_value is null or metric.compare_value = 0 or metric.current_value is null then null
      else round(((metric.current_value - metric.compare_value) / abs(metric.compare_value)) * 100, 2) end
  ) order by metric.dashboard_order, metric.name, metric.id), '[]'::jsonb)
  into metric_items
  from metric_values metric;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'ou', jsonb_build_object('id', target_ou.id, 'name', target_ou.name, 'path', target_ou.path),
    'period', jsonb_build_object('id', target_period.id, 'periodEnd', target_period.period_end, 'displayLabel', target_period.label),
    'comparePeriod', case when compare_period.id is null then null else jsonb_build_object(
      'id', compare_period.id, 'periodEnd', compare_period.period_end, 'displayLabel', compare_period.label) end,
    'metrics', metric_items));
end;
$$;

create or replace function public.get_dashboard_trend(
  p_ou_id uuid, p_metric_code text, p_end_period_id uuid, p_limit integer default 12
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
  end_date date;
  points_data jsonb;
begin
  if p_limit < 1 or p_limit > 52 then raise exception 'INVALID_TREND_LIMIT'; end if;
  select * into target_ou from public.organization_units
  where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then raise exception 'OU_NOT_FOUND'; end if;
  select * into target_metric from public.statistic_metrics
  where church_id = tenant_id and code = p_metric_code and is_active and deleted_at is null
    and show_on_dashboard and data_type = 'number' and aggregation <> 'none';
  if target_metric.id is null then raise exception 'METRIC_NOT_FOUND'; end if;
  select period_end into end_date from public.statistic_periods
  where id = p_end_period_id and church_id = tenant_id;
  if end_date is null then raise exception 'PERIOD_NOT_FOUND'; end if;

  with selected_periods as materialized (
    select period.id, period.label, period.period_start, period.period_end
    from public.statistic_periods period
    where period.church_id = tenant_id and period.period_type = 'week' and period.period_end <= end_date
    order by period.period_end desc limit p_limit
  ), accessible_ous as materialized (
    select ou.id
    from public.organization_units ou
    where ou.church_id = tenant_id and ou.structure_root_id = target_ou.structure_root_id
      and ou.is_active and ou.deleted_at is null and ou.allow_data_entry
      and (ou.id = target_ou.id or ou.path like target_ou.path || '/%')
      and app_security.can_view_ou(ou.id)
  ), metric_sources as materialized (
    select case when target_metric.metric_kind = 'input' then target_metric.id else source.id end source_metric_id
    from (select 1) seed
    left join lateral unnest(target_metric.calculation_source_metric_ids) source(id)
      on target_metric.metric_kind = 'calculated'
  ), aggregates as (
    select submission.period_id,
      sum(value.numeric_value) sum_value, avg(value.numeric_value) avg_value,
      max(value.numeric_value) max_value, min(value.numeric_value) min_value
    from public.statistic_submissions submission
    join selected_periods period on period.id = submission.period_id
    join accessible_ous ou on ou.id = submission.ou_id
    join public.statistic_values value
      on value.church_id = tenant_id and value.submission_id = submission.id
    join metric_sources source on source.source_metric_id = value.metric_id
    where submission.church_id = tenant_id and submission.status = 'approved' and submission.deleted_at is null
    group by submission.period_id
  ), ratio_submission_sides as materialized (
    select submission.id, submission.period_id, target_metric.id metric_id,
      sum(value.numeric_value) filter (where operand.position <= target_metric.ratio_numerator_count) numerator,
      sum(value.numeric_value) filter (where operand.position > target_metric.ratio_numerator_count) denominator
    from accessible_ous scope
    join public.statistic_submissions submission
      on submission.church_id = tenant_id and submission.ou_id = scope.id
      and submission.period_id in (select id from selected_periods) and submission.status = 'approved' and submission.deleted_at is null
    cross join lateral unnest(target_metric.calculation_source_metric_ids) with ordinality operand(id, position)
    left join public.statistic_values value
      on value.church_id = tenant_id and value.submission_id = submission.id and value.metric_id = operand.id
    where target_metric.calculation_operator = 'ratio'
    group by submission.id, submission.period_id, target_metric.id
  ), ratio_aggregates as materialized (
    select period_id, app_security.ratio_result(
      case when count(numerator) = count(*) then sum(numerator) end,
      case when count(denominator) = count(*) then sum(denominator) end
    ) result
    from ratio_submission_sides
    group by period_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'periodId', period.id, 'label', period.label, 'periodStart', period.period_start,
    'periodEnd', period.period_end, 'error', case when target_metric.calculation_operator = 'ratio' then coalesce(ratio.result, app_security.ratio_result(null, null)) -> 'error' end, 'value', case when target_metric.calculation_operator = 'ratio' then (ratio.result ->> 'value')::numeric else coalesce(case
      when target_metric.metric_kind = 'calculated' or target_metric.aggregation = 'sum' then aggregate.sum_value
      when target_metric.aggregation = 'avg' then aggregate.avg_value
      when target_metric.aggregation = 'max' then aggregate.max_value
      when target_metric.aggregation = 'min' then aggregate.min_value end, 0) end
  ) order by period.period_end), '[]'::jsonb)
  into points_data
  from selected_periods period
  left join aggregates aggregate on aggregate.period_id = period.id
  left join ratio_aggregates ratio on ratio.period_id = period.id;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'metricCode', target_metric.code, 'metricName', target_metric.name,
    'metricKind', target_metric.metric_kind, 'unit', target_metric.unit, 'points', points_data));
end;
$$;

create or replace function public.get_child_ou_summary(p_parent_ou_id uuid, p_period_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  parent_ou public.organization_units%rowtype;
  period_end_date date;
  children_data jsonb;
begin
  select * into parent_ou from public.organization_units
  where id = p_parent_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if parent_ou.id is null or not app_security.can_view_ou(parent_ou.id) then raise exception 'OU_NOT_FOUND'; end if;
  select period_end into period_end_date from public.statistic_periods
  where id = p_period_id and church_id = tenant_id;
  if period_end_date is null then raise exception 'PERIOD_NOT_FOUND'; end if;

  with direct_children as materialized (
    select ou.id, ou.name, ou.path, ou.level, ou.sort_order
    from public.organization_units ou
    where ou.church_id = tenant_id and ou.parent_id = parent_ou.id
      and ou.is_active and ou.deleted_at is null and app_security.can_view_ou(ou.id)
  ), accessible_reporting_ous as materialized (
    select ou.id, ou.path
    from public.organization_units ou
    where ou.church_id = tenant_id and ou.structure_root_id = parent_ou.structure_root_id
      and ou.is_active and ou.deleted_at is null and ou.allow_data_entry
      and ou.path like parent_ou.path || '/%'
      and app_security.can_view_ou(ou.id)
  ), child_ous as materialized (
    select child.id child_id, ou.id ou_id
    from direct_children child
    join accessible_reporting_ous ou on ou.path = child.path or ou.path like child.path || '/%'
  ), status_counts as (
    select child.id child_id, count(child_ou.ou_id)::integer expected_count,
      count(*) filter (where submission.status = 'approved')::integer approved_count,
      count(*) filter (where submission.status = 'submitted')::integer submitted_count,
      count(*) filter (where submission.status = 'draft')::integer draft_count,
      count(*) filter (where submission.status = 'returned')::integer returned_count,
      count(*) filter (where submission.status = 'rejected')::integer rejected_count
    from direct_children child
    left join child_ous child_ou on child_ou.child_id = child.id
    left join public.statistic_submissions submission
      on submission.church_id = tenant_id and submission.ou_id = child_ou.ou_id
      and submission.period_id = p_period_id and submission.deleted_at is null
    group by child.id
  ), dashboard_metrics as materialized (
    select metric.*
    from public.statistic_metrics metric
    where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
      and metric.show_on_dashboard and metric.data_type = 'number' and metric.aggregation <> 'none'
  ), metric_sources as materialized (
    select metric.id metric_id,
      case when metric.metric_kind = 'input' then metric.id else source.id end source_metric_id
    from dashboard_metrics metric
    left join lateral unnest(metric.calculation_source_metric_ids) source(id)
      on metric.metric_kind = 'calculated'
  ), aggregates as (
    select child_ou.child_id, source.metric_id,
      sum(value.numeric_value) sum_value, avg(value.numeric_value) avg_value,
      max(value.numeric_value) max_value, min(value.numeric_value) min_value
    from child_ous child_ou
    join public.statistic_submissions submission
      on submission.church_id = tenant_id and submission.ou_id = child_ou.ou_id
      and submission.period_id = p_period_id and submission.status = 'approved' and submission.deleted_at is null
    join public.statistic_values value
      on value.church_id = tenant_id and value.submission_id = submission.id
    join metric_sources source on source.source_metric_id = value.metric_id
    group by child_ou.child_id, source.metric_id
  ), ratio_submission_sides as materialized (
    select child.child_id, submission.id, submission.period_id, metric.id metric_id,
      sum(value.numeric_value) filter (where operand.position <= metric.ratio_numerator_count) numerator,
      sum(value.numeric_value) filter (where operand.position > metric.ratio_numerator_count) denominator
    from child_ous child
    join public.statistic_submissions submission
      on submission.church_id = tenant_id and submission.ou_id = child.ou_id
      and submission.period_id = p_period_id and submission.status = 'approved' and submission.deleted_at is null
    cross join dashboard_metrics metric
    cross join lateral unnest(metric.calculation_source_metric_ids) with ordinality operand(id, position)
    left join public.statistic_values value
      on value.church_id = tenant_id and value.submission_id = submission.id and value.metric_id = operand.id
    where metric.calculation_operator = 'ratio'
    group by child.child_id, submission.id, submission.period_id, metric.id
  ), ratio_aggregates as materialized (
    select child_id, metric_id, app_security.ratio_result(
      case when count(numerator) = count(*) then sum(numerator) end,
      case when count(denominator) = count(*) then sum(denominator) end
    ) result
    from ratio_submission_sides
    group by child_id, metric_id
  ), child_metrics as (
    select child.id child_id, coalesce(jsonb_agg(jsonb_build_object(
      'metricCode', metric.code, 'metricName', metric.name, 'metricKind', metric.metric_kind,
      'unit', metric.unit, 'error', case when metric.calculation_operator = 'ratio' then coalesce(ratio.result, app_security.ratio_result(null, null)) -> 'error' end, 'value', case
        when metric.calculation_operator = 'ratio' then (ratio.result ->> 'value')::numeric
        when metric.metric_kind = 'calculated' or metric.aggregation = 'sum' then aggregate.sum_value
        when metric.aggregation = 'avg' then aggregate.avg_value
        when metric.aggregation = 'max' then aggregate.max_value
        when metric.aggregation = 'min' then aggregate.min_value end
    ) order by metric.dashboard_order, metric.name), '[]'::jsonb) metrics
    from direct_children child
    cross join dashboard_metrics metric
    left join aggregates aggregate on aggregate.child_id = child.id and aggregate.metric_id = metric.id
    left join ratio_aggregates ratio on ratio.child_id = child.id and ratio.metric_id = metric.id
    group by child.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'ouId', child.id, 'ouName', child.name, 'level', child.level,
    'status', case
      when status.expected_count = 0 then 'missing'
      when status.approved_count = status.expected_count then 'approved'
      when status.approved_count + status.submitted_count + status.draft_count + status.returned_count + status.rejected_count = 0 then 'missing'
      when status.submitted_count > 0 then 'submitted'
      when status.returned_count > 0 then 'returned'
      when status.rejected_count > 0 then 'rejected'
      when status.draft_count > 0 then 'draft' else 'mixed' end,
    'expectedCount', status.expected_count, 'approvedCount', status.approved_count,
    'metrics', coalesce(metric.metrics, '[]'::jsonb)
  ) order by child.sort_order, child.name, child.id), '[]'::jsonb)
  into children_data
  from direct_children child
  join status_counts status on status.child_id = child.id
  left join child_metrics metric on metric.child_id = child.id;

  return jsonb_build_object('success', true, 'data', jsonb_build_object('children', children_data));
end;
$$;
