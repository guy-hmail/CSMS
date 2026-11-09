-- Ratios are percentage points, rounded once after multiplication by 100.
create or replace function app_security.ratio_result(p_a numeric, p_b numeric)
returns jsonb language sql immutable set search_path = '' as $$
 select jsonb_build_object(
   'value', case when p_a is null or p_b is null or p_b = 0 then null else round(p_a / p_b * 100, 2) end,
   'error', case when p_a is null or p_b is null then 'MISSING_DATA'
                 when p_b = 0 then 'DIVISION_BY_ZERO' else null end);
$$;

update public.statistic_metrics set unit = '%' where calculation_operator = 'ratio' and unit <> '%';
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
  if input_operator = 'ratio' then input_unit := '%'; end if;
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
  if input_operator = 'ratio' then input_unit := '%'; end if;
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
