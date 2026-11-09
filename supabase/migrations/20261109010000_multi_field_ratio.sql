-- The first N source IDs form the numerator. Existing A/B pairs split at 1.
alter table public.statistic_metrics add column ratio_numerator_count integer not null default 1;

alter table public.statistic_metrics drop constraint ck_statistic_metric_calculation;
alter table public.statistic_metrics add constraint ck_statistic_metric_calculation check (
 (metric_kind = 'input' and calculation_operator is null and cardinality(calculation_source_metric_ids) = 0)
 or (metric_kind = 'calculated' and calculation_operator is not null and
   ((calculation_operator = 'sum' and cardinality(calculation_source_metric_ids) >= 2)
    or (calculation_operator = 'ratio' and ratio_numerator_count between 1 and cardinality(calculation_source_metric_ids) - 1))
   and data_type = 'number' and input_type = 'number' and aggregation = 'sum'
   and default_value is null and min_value is null and max_value is null and not is_required
   and not (id = any(calculation_source_metric_ids)))
);



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
 select case when bool_and(v.numeric_value is not null) then
          sum(v.numeric_value) filter (where operand.pos <= target_metric.ratio_numerator_count) end,
        case when bool_and(v.numeric_value is not null) then
          sum(v.numeric_value) filter (where operand.pos > target_metric.ratio_numerator_count) end
 into a, b
 from public.statistic_submissions submission
 join public.statistic_periods period on period.id = submission.period_id and period.church_id = tenant_id
   and period.period_end between p_from_date and p_to_date
 join public.organization_units ou on ou.id = submission.ou_id and ou.church_id = tenant_id
   and ou.structure_root_id = scope_ou.structure_root_id and ou.is_active and ou.deleted_at is null
   and ou.allow_data_entry and app_security.can_view_ou(ou.id)
   and (ou.id = scope_ou.id or (p_include_descendants and ou.path like scope_ou.path || '/%'))
 cross join unnest(target_metric.calculation_source_metric_ids) with ordinality operand(id, pos)
 left join public.statistic_values v on v.church_id = tenant_id and v.submission_id = submission.id and v.metric_id = operand.id
 where submission.church_id = tenant_id and submission.status = 'approved' and submission.deleted_at is null;
 return app_security.ratio_result(a, b);
end;
$$;

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
  numerator_count integer;
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
  numerator_count := coalesce((p_payload ->> 'numeratorCount')::integer, 1);
  if input_operator = 'sum' then
    numerator_count := 1;
    select array_agg(distinct id order by id) into source_ids from unnest(source_ids) id;
  elsif numerator_count < 1 or numerator_count >= coalesce(cardinality(source_ids), 0) then
    raise exception 'CALCULATION_RATIO_EMPTY_SIDE';
  elsif exists (select 1 from unnest(source_ids) with ordinality operand(id, pos)
                group by (pos <= numerator_count), id having count(*) > 1) then
    raise exception 'CALCULATION_DUPLICATE_SOURCE_ON_SIDE';
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
    metric_kind, calculation_operator, calculation_source_metric_ids, ratio_numerator_count
  ) values (
    new_id, tenant_id, input_code, input_name, input_description, input_category, input_unit,
    'number', 'number', 'sum', null, null, null, false, input_sort_order,
    'calculated', input_operator, source_ids, numerator_count
  );

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
    entity_type, entity_id, action, after_data
  ) values (
    tenant_id, actor_user_id, actor_membership_id, root_ou_id, source_assignment_id,
    'statistic_metrics', new_id, 'create_calculated_metric',
    jsonb_build_object('code', input_code, 'name', input_name, 'operator', input_operator, 'numeratorCount', numerator_count, 'sourceMetricIds', to_jsonb(source_ids))
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
  numerator_count integer;
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
  numerator_count := coalesce((p_payload ->> 'numeratorCount')::integer, target.ratio_numerator_count);
  if input_operator = 'sum' then
    numerator_count := 1;
    select array_agg(distinct id order by id) into source_ids from unnest(source_ids) id;
  elsif numerator_count < 1 or numerator_count >= coalesce(cardinality(source_ids), 0) then
    raise exception 'CALCULATION_RATIO_EMPTY_SIDE';
  elsif exists (select 1 from unnest(source_ids) with ordinality operand(id, pos)
                group by (pos <= numerator_count), id having count(*) > 1) then
    raise exception 'CALCULATION_DUPLICATE_SOURCE_ON_SIDE';
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
    calculation_operator = input_operator, calculation_source_metric_ids = source_ids, ratio_numerator_count = numerator_count, updated_at = now()
  where id = target.id;

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
    entity_type, entity_id, action, before_data, after_data
  ) values (
    tenant_id, actor_user_id, actor_membership_id, root_ou_id, source_assignment_id,
    'statistic_metrics', target.id, 'update_calculated_metric',
    jsonb_build_object('operator', target.calculation_operator, 'numeratorCount', target.ratio_numerator_count, 'name', target.name, 'sourceMetricIds', to_jsonb(target.calculation_source_metric_ids), 'isActive', target.is_active),
    jsonb_build_object('operator', input_operator, 'numeratorCount', numerator_count, 'name', input_name, 'sourceMetricIds', to_jsonb(source_ids), 'isActive', input_is_active)
  );
  return jsonb_build_object('success', true, 'data', jsonb_build_object('metricId', target.id));
exception when invalid_text_representation or numeric_value_out_of_range then raise exception 'VALIDATION_ERROR';
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
    'numeratorCount', metric.ratio_numerator_count, 'sourceMetricCodes', coalesce((select jsonb_agg(source.code order by operand.ordinal)
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
