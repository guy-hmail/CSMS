-- Ordered ratio operands, integer rounding, and explicit unavailable reasons.
-- Existing SUM definitions and input aggregations retain their behavior.
alter table public.statistic_metrics drop constraint ck_statistic_metric_calculation;
alter table public.statistic_metrics add constraint ck_statistic_metric_calculation check (
 (metric_kind = 'input' and calculation_operator is null and cardinality(calculation_source_metric_ids) = 0)
 or (metric_kind = 'calculated' and calculation_operator is not null and
   ((calculation_operator = 'sum' and cardinality(calculation_source_metric_ids) >= 2)
    or (calculation_operator = 'ratio' and cardinality(calculation_source_metric_ids) = 2))
   and data_type = 'number' and input_type = 'number' and aggregation = 'sum'
   and default_value is null and min_value is null and max_value is null and not is_required
   and not (id = any(calculation_source_metric_ids)))
);

-- Shared numeric policy: missing operands take precedence over a zero denominator.
create or replace function app_security.ratio_result(p_a numeric, p_b numeric)
returns jsonb language sql immutable set search_path = '' as $$
 select jsonb_build_object(
   'value', case when p_a is null or p_b is null or p_b = 0 then null else round(p_a / p_b) end,
   'error', case when p_a is null or p_b is null then 'MISSING_DATA'
                 when p_b = 0 then 'DIVISION_BY_ZERO' else null end);
$$;
revoke all on function app_security.ratio_result(numeric, numeric) from public;

-- Aggregate the same approved submissions for both operands, before rounding.
-- A missing operand on any included submission makes the result incomplete.
create or replace function app_security.report_ratio_result(
 p_metric_id uuid, p_scope_ou_id uuid, p_from_date date, p_to_date date, p_include_descendants boolean
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
 tenant_id uuid := app_security.current_church_id();
 target_metric public.statistic_metrics%rowtype;
 scope_ou public.organization_units%rowtype;
 a numeric; b numeric;
begin
 select * into target_metric from public.statistic_metrics where id = p_metric_id and church_id = tenant_id
   and is_active and deleted_at is null and calculation_operator = 'ratio';
 select * into scope_ou from public.organization_units where id = p_scope_ou_id and church_id = tenant_id
   and is_active and deleted_at is null;
 if target_metric.id is null or scope_ou.id is null or not app_security.can_view_ou(scope_ou.id) then
   return app_security.ratio_result(null, null);
 end if;
 select case when count(av.numeric_value) = count(*) then sum(av.numeric_value) end,
        case when count(bv.numeric_value) = count(*) then sum(bv.numeric_value) end
 into a, b
 from public.statistic_submissions submission
 join public.statistic_periods period on period.id = submission.period_id and period.church_id = tenant_id
   and period.period_end between p_from_date and p_to_date
 join public.organization_units ou on ou.id = submission.ou_id and ou.church_id = tenant_id
   and ou.structure_root_id = scope_ou.structure_root_id and ou.is_active and ou.deleted_at is null
   and ou.allow_data_entry and app_security.can_view_ou(ou.id)
   and (ou.id = scope_ou.id or (p_include_descendants and ou.path like scope_ou.path || '/%'))
 left join public.statistic_values av on av.church_id = tenant_id and av.submission_id = submission.id
   and av.metric_id = target_metric.calculation_source_metric_ids[1]
 left join public.statistic_values bv on bv.church_id = tenant_id and bv.submission_id = submission.id
   and bv.metric_id = target_metric.calculation_source_metric_ids[2]
 where submission.church_id = tenant_id and submission.status = 'approved' and submission.deleted_at is null;
 return app_security.ratio_result(a, b);
end;
$$;
revoke all on function app_security.report_ratio_result(uuid, uuid, date, date, boolean) from public;


create or replace function public.create_calculated_metric(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  actor_membership_id uuid := app_security.current_church_member_id();
  source_assignment_id uuid := app_security.require_direct_root_admin();
  tenant_id uuid := app_security.current_church_id();
  root_ou_id uuid;
  new_id uuid := gen_random_uuid();
  input_code text := upper(trim(p_payload ->> 'code'));
  input_name text := trim(p_payload ->> 'name');
  input_description text := nullif(trim(p_payload ->> 'description'), '');
  input_category text := lower(trim(p_payload ->> 'category'));
  input_unit text := trim(p_payload ->> 'unit');
  input_sort_order integer := coalesce((p_payload ->> 'sortOrder')::integer, 0);
  source_ids uuid[];
  input_operator text;
begin
  input_operator := coalesce(p_payload ->> 'operator', 'sum');
  if jsonb_typeof(p_payload -> 'sourceMetricIds') is distinct from 'array' then raise exception 'CALCULATION_SOURCES_REQUIRED'; end if;
  select array_agg(source_id order by ordinal) into source_ids
  from (select value::uuid source_id, ordinal from jsonb_array_elements_text(p_payload -> 'sourceMetricIds') with ordinality item(value, ordinal)) source;

  if input_code !~ '^[A-Z][A-Z0-9_]{0,79}$' or nullif(input_name, '') is null
     or length(input_name) > 255 or nullif(input_category, '') is null
     or length(input_category) > 80 or nullif(input_unit, '') is null
     or length(input_unit) > 50 or input_sort_order < 0 then raise exception 'VALIDATION_ERROR'; end if;
  if array_position(source_ids, null) is not null then raise exception 'CALCULATION_SOURCE_INVALID'; end if;
  if input_operator not in ('sum', 'ratio') then raise exception 'CALCULATION_OPERATOR_INVALID'; end if;
  if input_operator = 'sum' then
    select array_agg(distinct id order by id) into source_ids from unnest(source_ids) id;
  elsif coalesce(cardinality(source_ids), 0) <> 2 then
    raise exception 'CALCULATION_RATIO_REQUIRES_TWO_SOURCES';
  end if;
  if coalesce(cardinality(source_ids), 0) < 2 then raise exception 'CALCULATION_SOURCES_REQUIRED'; end if;
  if (select count(*) from public.statistic_metrics metric
      where metric.church_id = tenant_id and metric.id = any(source_ids)
        and metric.metric_kind = 'input' and metric.data_type = 'number'
        and metric.aggregation = 'sum' and metric.is_active and metric.deleted_at is null) <> (select count(distinct id) from unnest(source_ids) id)
  then raise exception 'CALCULATION_SOURCE_INVALID'; end if;

  select ou_id into root_ou_id from public.ou_members
  where id = source_assignment_id and church_id = tenant_id;

  insert into public.statistic_metrics (
    id, church_id, code, name, description, category, unit, data_type, input_type,
    aggregation, default_value, min_value, max_value, is_required, sort_order,
    metric_kind, calculation_operator, calculation_source_metric_ids
  ) values (
    new_id, tenant_id, input_code, input_name, input_description, input_category, input_unit,
    'number', 'number', 'sum', null, null, null, false, input_sort_order,
    'calculated', input_operator, source_ids
  );

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
    entity_type, entity_id, action, after_data
  ) values (
    tenant_id, actor_user_id, actor_membership_id, root_ou_id, source_assignment_id,
    'statistic_metrics', new_id, 'create_calculated_metric',
    jsonb_build_object('code', input_code, 'name', input_name, 'operator', input_operator, 'sourceMetricIds', to_jsonb(source_ids))
  );
  return jsonb_build_object('success', true, 'data', jsonb_build_object('metricId', new_id));
exception
  when unique_violation then raise exception 'DUPLICATE_METRIC_CODE';
  when invalid_text_representation or numeric_value_out_of_range then raise exception 'VALIDATION_ERROR';
end;
$$;

create or replace function public.update_calculated_metric(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  actor_membership_id uuid := app_security.current_church_member_id();
  source_assignment_id uuid := app_security.require_direct_root_admin();
  tenant_id uuid := app_security.current_church_id();
  target public.statistic_metrics%rowtype;
  root_ou_id uuid;
  source_ids uuid[];
  input_operator text;
  input_name text;
  input_description text;
  input_category text;
  input_unit text;
  input_sort_order integer;
  input_is_active boolean;
begin
  select * into target from public.statistic_metrics
  where id = (p_payload ->> 'metricId')::uuid and church_id = tenant_id
    and metric_kind = 'calculated' and deleted_at is null for update;
  if target.id is null then raise exception 'CALCULATED_METRIC_NOT_FOUND'; end if;

  input_name := trim(coalesce(p_payload ->> 'name', target.name));
  input_description := case when p_payload ? 'description' then nullif(trim(p_payload ->> 'description'), '') else target.description end;
  input_category := lower(trim(coalesce(p_payload ->> 'category', target.category)));
  input_unit := trim(coalesce(p_payload ->> 'unit', target.unit));
  input_sort_order := coalesce(nullif(p_payload ->> 'sortOrder', '')::integer, target.sort_order);
  input_is_active := coalesce((p_payload ->> 'isActive')::boolean, target.is_active);
  input_operator := coalesce(p_payload ->> 'operator', target.calculation_operator);
  source_ids := target.calculation_source_metric_ids;
  if p_payload ? 'sourceMetricIds' then
    if jsonb_typeof(p_payload -> 'sourceMetricIds') is distinct from 'array' then raise exception 'CALCULATION_SOURCES_REQUIRED'; end if;
    select array_agg(source_id order by ordinal) into source_ids
    from (select value::uuid source_id, ordinal from jsonb_array_elements_text(p_payload -> 'sourceMetricIds') with ordinality item(value, ordinal)) source;
  end if;

  if nullif(input_name, '') is null or length(input_name) > 255
     or nullif(input_category, '') is null or length(input_category) > 80
     or nullif(input_unit, '') is null or length(input_unit) > 50 or input_sort_order < 0
  then raise exception 'VALIDATION_ERROR'; end if;
  if array_position(source_ids, null) is not null then raise exception 'CALCULATION_SOURCE_INVALID'; end if;
  if input_operator not in ('sum', 'ratio') then raise exception 'CALCULATION_OPERATOR_INVALID'; end if;
  if input_operator = 'sum' then
    select array_agg(distinct id order by id) into source_ids from unnest(source_ids) id;
  elsif coalesce(cardinality(source_ids), 0) <> 2 then
    raise exception 'CALCULATION_RATIO_REQUIRES_TWO_SOURCES';
  end if;
  if coalesce(cardinality(source_ids), 0) < 2 then raise exception 'CALCULATION_SOURCES_REQUIRED'; end if;
  if (select count(*) from public.statistic_metrics metric
      where metric.church_id = tenant_id and metric.id = any(source_ids)
        and metric.metric_kind = 'input' and metric.data_type = 'number'
        and metric.aggregation = 'sum' and metric.is_active and metric.deleted_at is null) <> (select count(distinct id) from unnest(source_ids) id)
  then raise exception 'CALCULATION_SOURCE_INVALID'; end if;

  select ou_id into root_ou_id from public.ou_members where id = source_assignment_id and church_id = tenant_id;
  update public.statistic_metrics set
    name = input_name, description = input_description, category = input_category,
    unit = input_unit, sort_order = input_sort_order, is_active = input_is_active,
    calculation_operator = input_operator, calculation_source_metric_ids = source_ids, updated_at = now()
  where id = target.id;

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
    entity_type, entity_id, action, before_data, after_data
  ) values (
    tenant_id, actor_user_id, actor_membership_id, root_ou_id, source_assignment_id,
    'statistic_metrics', target.id, 'update_calculated_metric',
    jsonb_build_object('operator', target.calculation_operator, 'name', target.name, 'sourceMetricIds', to_jsonb(target.calculation_source_metric_ids), 'isActive', target.is_active),
    jsonb_build_object('operator', input_operator, 'name', input_name, 'sourceMetricIds', to_jsonb(source_ids), 'isActive', input_is_active)
  );
  return jsonb_build_object('success', true, 'data', jsonb_build_object('metricId', target.id));
exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'VALIDATION_ERROR';
end;
$$;

create or replace function app_security.report_metric_value(
  p_metric_id uuid, p_scope_ou_id uuid, p_from_date date, p_to_date date, p_include_descendants boolean
)
returns numeric
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  tenant_id uuid := app_security.current_church_id();
  target_metric public.statistic_metrics%rowtype;
  scope_ou public.organization_units%rowtype;
  sum_value numeric;
  avg_value numeric;
  max_value numeric;
  min_value numeric;
begin
  select * into target_metric from public.statistic_metrics
  where id = p_metric_id and church_id = tenant_id and is_active and deleted_at is null
    and data_type = 'number' and aggregation <> 'none';
  select * into scope_ou from public.organization_units
  where id = p_scope_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_metric.id is null or scope_ou.id is null then return null; end if;

  if target_metric.calculation_operator = 'ratio' then
    return (app_security.report_ratio_result(p_metric_id, p_scope_ou_id, p_from_date, p_to_date, p_include_descendants) ->> 'value')::numeric;
  end if;

  select sum(value.numeric_value), avg(value.numeric_value), max(value.numeric_value), min(value.numeric_value)
  into sum_value, avg_value, max_value, min_value
  from public.statistic_submissions submission
  join public.statistic_periods period on period.id = submission.period_id and period.church_id = submission.church_id
    and period.period_end between p_from_date and p_to_date
  join public.organization_units report_ou on report_ou.id = submission.ou_id and report_ou.church_id = submission.church_id
    and report_ou.structure_root_id = scope_ou.structure_root_id and report_ou.is_active
    and report_ou.deleted_at is null and report_ou.allow_data_entry
    and (report_ou.id = scope_ou.id or (p_include_descendants and report_ou.path like scope_ou.path || '/%'))
    and app_security.can_view_ou(report_ou.id)
  join public.statistic_values value on value.submission_id = submission.id and value.church_id = submission.church_id
    and ((target_metric.metric_kind = 'input' and value.metric_id = target_metric.id)
      or (target_metric.metric_kind = 'calculated' and value.metric_id = any(target_metric.calculation_source_metric_ids)))
  where submission.church_id = tenant_id and submission.status = 'approved' and submission.deleted_at is null;

  if target_metric.metric_kind = 'calculated' then return sum_value; end if;
  return case target_metric.aggregation when 'sum' then sum_value when 'avg' then avg_value
    when 'max' then max_value when 'min' then min_value else null end;
end;
$$;

create or replace function public.get_report_table(p_ou_id uuid, p_from_date date, p_to_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id(); tenant_id uuid := app_security.current_church_id();
  target_ou public.organization_units%rowtype; church_name text; metrics_data jsonb; rows_data jsonb; totals_data jsonb; total_errors jsonb;
begin
  if p_from_date is null or p_to_date is null or p_from_date > p_to_date then raise exception 'INVALID_REPORT_RANGE'; end if;
  select * into target_ou from public.organization_units where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then raise exception 'REPORT_FORBIDDEN'; end if;
  select name into church_name from public.churches where id = tenant_id and deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object('metricId', metric.id, 'metricCode', metric.code, 'metricName', metric.name,
    'category', metric.category, 'unit', metric.unit, 'aggregation', metric.aggregation, 'metricKind', metric.metric_kind,
    'calculationOperator', metric.calculation_operator,
    'sourceMetricCodes', coalesce((select jsonb_agg(source.code order by operand.ordinal)
      from unnest(metric.calculation_source_metric_ids) with ordinality operand(id, ordinal) join public.statistic_metrics source on source.id = operand.id), '[]'::jsonb))
    order by metric.sort_order, metric.name), '[]'::jsonb) into metrics_data
  from public.statistic_metrics metric where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
    and metric.data_type = 'number' and metric.aggregation <> 'none';

  with report_ous as (
    select ou.id, ou.code, ou.name, ou.path from public.organization_units ou
    where ou.church_id = tenant_id and ou.structure_root_id = target_ou.structure_root_id and ou.is_active
      and ou.deleted_at is null and ou.allow_data_entry and (ou.path = target_ou.path or ou.path like target_ou.path || '/%')
      and app_security.can_view_ou(ou.id)
  )
  select coalesce(jsonb_agg(jsonb_build_object('ouId', report_ou.id, 'ouCode', report_ou.code, 'ouName', report_ou.name,
    'errors', (select coalesce(jsonb_object_agg(metric.code, app_security.report_ratio_result(metric.id, report_ou.id, p_from_date, p_to_date, false) -> 'error'), '{}'::jsonb) from public.statistic_metrics metric where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null and metric.calculation_operator = 'ratio'),
    'values', (select coalesce(jsonb_object_agg(metric.code,
      app_security.report_metric_value(metric.id, report_ou.id, p_from_date, p_to_date, false)), '{}'::jsonb)
      from public.statistic_metrics metric where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
        and metric.data_type = 'number' and metric.aggregation <> 'none')) order by report_ou.path), '[]'::jsonb)
  into rows_data from report_ous report_ou;

  select coalesce(jsonb_object_agg(metric.code,
    app_security.report_metric_value(metric.id, target_ou.id, p_from_date, p_to_date, true)), '{}'::jsonb)
  into totals_data from public.statistic_metrics metric where metric.church_id = tenant_id and metric.is_active
    and metric.deleted_at is null and metric.data_type = 'number' and metric.aggregation <> 'none';
  select coalesce(jsonb_object_agg(metric.code, app_security.report_ratio_result(metric.id, target_ou.id, p_from_date, p_to_date, true) -> 'error'), '{}'::jsonb) into total_errors from public.statistic_metrics metric where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null and metric.calculation_operator = 'ratio';
  return jsonb_build_object('success', true, 'data', jsonb_build_object('church', jsonb_build_object('id', tenant_id, 'name', church_name),
    'ou', jsonb_build_object('id', target_ou.id, 'code', target_ou.code, 'name', target_ou.name), 'fromDate', p_from_date,
    'toDate', p_to_date, 'metrics', metrics_data, 'rows', rows_data, 'totals', totals_data, 'totalErrors', total_errors));
end;
$$;

create or replace function public.get_report_trend(p_ou_id uuid, p_metric_code text, p_from_date date, p_to_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id(); tenant_id uuid := app_security.current_church_id();
  target_ou public.organization_units%rowtype; target_metric public.statistic_metrics%rowtype; points_data jsonb;
begin
  if p_from_date is null or p_to_date is null or p_from_date > p_to_date then raise exception 'INVALID_REPORT_RANGE'; end if;
  select * into target_ou from public.organization_units where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then raise exception 'REPORT_FORBIDDEN'; end if;
  select * into target_metric from public.statistic_metrics where church_id = tenant_id and code = p_metric_code
    and is_active and deleted_at is null and data_type = 'number' and aggregation <> 'none';
  if target_metric.id is null then raise exception 'REPORT_METRIC_NOT_FOUND'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('periodId', period.id, 'label', period.label,
    'periodStart', period.period_start, 'periodEnd', period.period_end,
    'value', case when target_metric.calculation_operator = 'ratio' then app_security.report_metric_value(target_metric.id, target_ou.id, period.period_end, period.period_end, true) else coalesce(app_security.report_metric_value(target_metric.id, target_ou.id, period.period_end, period.period_end, true), 0) end,
    'error', case when target_metric.calculation_operator = 'ratio' then app_security.report_ratio_result(target_metric.id, target_ou.id, period.period_end, period.period_end, true) -> 'error' end)
    order by period.period_end), '[]'::jsonb) into points_data
  from public.statistic_periods period where period.church_id = tenant_id and period.period_end between p_from_date and p_to_date;
  return jsonb_build_object('success', true, 'data', jsonb_build_object('metricCode', target_metric.code,
    'metricName', target_metric.name, 'unit', target_metric.unit, 'points', points_data));
end;
$$;

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
    union all
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
  ), metric_values as (
    select metric.*,
      case when metric.calculation_operator = 'ratio' then app_security.report_metric_value(metric.id, target_ou.id, target_period.period_end, target_period.period_end, true)
        when metric.metric_kind = 'calculated' or metric.aggregation = 'sum' then current_aggregate.sum_value
        when metric.aggregation = 'avg' then current_aggregate.avg_value
        when metric.aggregation = 'max' then current_aggregate.max_value
        when metric.aggregation = 'min' then current_aggregate.min_value end current_value,
      case when compare_period.id is null then null
        when metric.calculation_operator = 'ratio' then app_security.report_metric_value(metric.id, target_ou.id, compare_period.period_end, compare_period.period_end, true)
        when metric.metric_kind = 'calculated' or metric.aggregation = 'sum' then compare_aggregate.sum_value
        when metric.aggregation = 'avg' then compare_aggregate.avg_value
        when metric.aggregation = 'max' then compare_aggregate.max_value
        when metric.aggregation = 'min' then compare_aggregate.min_value end compare_value
    from dashboard_metrics metric
    left join aggregates current_aggregate
      on current_aggregate.metric_id = metric.id and current_aggregate.period_id = target_period.id
    left join aggregates compare_aggregate
      on compare_aggregate.metric_id = metric.id and compare_aggregate.period_id = compare_period.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'metricId', metric.id, 'metricCode', metric.code, 'metricName', metric.name,
    'category', metric.category, 'unit', metric.unit, 'aggregation', metric.aggregation,
    'metricKind', metric.metric_kind, 'error', case when metric.calculation_operator = 'ratio' then app_security.report_ratio_result(metric.id, target_ou.id, target_period.period_end, target_period.period_end, true) -> 'error' end, 'currentValue', metric.current_value,
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
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'periodId', period.id, 'label', period.label, 'periodStart', period.period_start,
    'periodEnd', period.period_end, 'error', case when target_metric.calculation_operator = 'ratio' then app_security.report_ratio_result(target_metric.id, target_ou.id, period.period_end, period.period_end, true) -> 'error' end, 'value', case when target_metric.calculation_operator = 'ratio' then app_security.report_metric_value(target_metric.id, target_ou.id, period.period_end, period.period_end, true) else coalesce(case
      when target_metric.metric_kind = 'calculated' or target_metric.aggregation = 'sum' then aggregate.sum_value
      when target_metric.aggregation = 'avg' then aggregate.avg_value
      when target_metric.aggregation = 'max' then aggregate.max_value
      when target_metric.aggregation = 'min' then aggregate.min_value end, 0) end
  ) order by period.period_end), '[]'::jsonb)
  into points_data
  from selected_periods period
  left join aggregates aggregate on aggregate.period_id = period.id;

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
  ), child_metrics as (
    select child.id child_id, coalesce(jsonb_agg(jsonb_build_object(
      'metricCode', metric.code, 'metricName', metric.name, 'metricKind', metric.metric_kind,
      'unit', metric.unit, 'error', case when metric.calculation_operator = 'ratio' then app_security.report_ratio_result(metric.id, child.id, period_end_date, period_end_date, true) -> 'error' end, 'value', case
        when metric.calculation_operator = 'ratio' then app_security.report_metric_value(metric.id, child.id, period_end_date, period_end_date, true)
        when metric.metric_kind = 'calculated' or metric.aggregation = 'sum' then aggregate.sum_value
        when metric.aggregation = 'avg' then aggregate.avg_value
        when metric.aggregation = 'max' then aggregate.max_value
        when metric.aggregation = 'min' then aggregate.min_value end
    ) order by metric.dashboard_order, metric.name), '[]'::jsonb) metrics
    from direct_children child
    cross join dashboard_metrics metric
    left join aggregates aggregate on aggregate.child_id = child.id and aggregate.metric_id = metric.id
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
