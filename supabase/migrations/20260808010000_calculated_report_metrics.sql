-- Tenant-defined calculated report metrics (v1: SUM of input metrics).

alter table public.statistic_metrics
  add column metric_kind varchar(20) not null default 'input',
  add column calculation_operator varchar(20),
  add column calculation_source_metric_ids uuid[] not null default '{}';

alter table public.statistic_metrics
  add constraint ck_statistic_metric_kind check (metric_kind in ('input', 'calculated')),
  add constraint ck_statistic_metric_calculation check (
    (metric_kind = 'input' and calculation_operator is null and cardinality(calculation_source_metric_ids) = 0)
    or
    (metric_kind = 'calculated' and calculation_operator = 'sum'
      and cardinality(calculation_source_metric_ids) >= 2
      and data_type = 'number' and input_type = 'number' and aggregation = 'sum'
      and default_value is null and min_value is null and max_value is null and not is_required
      and not (id = any(calculation_source_metric_ids)))
  );

create or replace function app_security.enforce_metric_dependency_integrity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.metric_kind = 'input'
     and (new.is_active is false or new.aggregation <> 'sum')
     and exists (
       select 1 from public.statistic_metrics calculated
       where calculated.church_id = old.church_id
         and calculated.metric_kind = 'calculated'
         and calculated.is_active and calculated.deleted_at is null
         and old.id = any(calculated.calculation_source_metric_ids)
     ) then
    raise exception 'METRIC_USED_BY_CALCULATION';
  end if;
  return new;
end;
$$;

create trigger trg_metric_dependency_integrity
before update on public.statistic_metrics
for each row execute function app_security.enforce_metric_dependency_integrity();

create or replace function app_security.enforce_input_metric_value()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (
    select 1 from public.statistic_metrics metric
    where metric.id = new.metric_id and metric.church_id = new.church_id
      and metric.metric_kind = 'calculated'
  ) then
    raise exception 'CALCULATED_METRIC_VALUE_FORBIDDEN';
  end if;
  return new;
end;
$$;

create trigger trg_input_metric_value_only
before insert or update of metric_id on public.statistic_values
for each row execute function app_security.enforce_input_metric_value();

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
begin
  if jsonb_typeof(p_payload -> 'sourceMetricIds') <> 'array' then raise exception 'CALCULATION_SOURCES_REQUIRED'; end if;
  select array_agg(distinct source_id order by source_id) into source_ids
  from (select value::uuid source_id from jsonb_array_elements_text(p_payload -> 'sourceMetricIds')) source;

  if input_code !~ '^[A-Z][A-Z0-9_]{0,79}$' or nullif(input_name, '') is null
     or length(input_name) > 255 or nullif(input_category, '') is null
     or length(input_category) > 80 or nullif(input_unit, '') is null
     or length(input_unit) > 50 or input_sort_order < 0 then raise exception 'VALIDATION_ERROR'; end if;
  if coalesce(cardinality(source_ids), 0) < 2 then raise exception 'CALCULATION_SOURCES_REQUIRED'; end if;
  if (select count(*) from public.statistic_metrics metric
      where metric.church_id = tenant_id and metric.id = any(source_ids)
        and metric.metric_kind = 'input' and metric.data_type = 'number'
        and metric.aggregation = 'sum' and metric.is_active and metric.deleted_at is null) <> cardinality(source_ids)
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
    'calculated', 'sum', source_ids
  );

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
    entity_type, entity_id, action, after_data
  ) values (
    tenant_id, actor_user_id, actor_membership_id, root_ou_id, source_assignment_id,
    'statistic_metrics', new_id, 'create_calculated_metric',
    jsonb_build_object('code', input_code, 'name', input_name, 'operator', 'sum', 'sourceMetricIds', to_jsonb(source_ids))
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
  source_ids := target.calculation_source_metric_ids;
  if p_payload ? 'sourceMetricIds' then
    if jsonb_typeof(p_payload -> 'sourceMetricIds') <> 'array' then raise exception 'CALCULATION_SOURCES_REQUIRED'; end if;
    select array_agg(distinct source_id order by source_id) into source_ids
    from (select value::uuid source_id from jsonb_array_elements_text(p_payload -> 'sourceMetricIds')) source;
  end if;

  if nullif(input_name, '') is null or length(input_name) > 255
     or nullif(input_category, '') is null or length(input_category) > 80
     or nullif(input_unit, '') is null or length(input_unit) > 50 or input_sort_order < 0
  then raise exception 'VALIDATION_ERROR'; end if;
  if coalesce(cardinality(source_ids), 0) < 2 then raise exception 'CALCULATION_SOURCES_REQUIRED'; end if;
  if (select count(*) from public.statistic_metrics metric
      where metric.church_id = tenant_id and metric.id = any(source_ids)
        and metric.metric_kind = 'input' and metric.data_type = 'number'
        and metric.aggregation = 'sum' and metric.is_active and metric.deleted_at is null) <> cardinality(source_ids)
  then raise exception 'CALCULATION_SOURCE_INVALID'; end if;

  select ou_id into root_ou_id from public.ou_members where id = source_assignment_id and church_id = tenant_id;
  update public.statistic_metrics set
    name = input_name, description = input_description, category = input_category,
    unit = input_unit, sort_order = input_sort_order, is_active = input_is_active,
    calculation_source_metric_ids = source_ids, updated_at = now()
  where id = target.id;

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
    entity_type, entity_id, action, before_data, after_data
  ) values (
    tenant_id, actor_user_id, actor_membership_id, root_ou_id, source_assignment_id,
    'statistic_metrics', target.id, 'update_calculated_metric',
    jsonb_build_object('name', target.name, 'sourceMetricIds', to_jsonb(target.calculation_source_metric_ids), 'isActive', target.is_active),
    jsonb_build_object('name', input_name, 'sourceMetricIds', to_jsonb(source_ids), 'isActive', input_is_active)
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

create or replace function public.get_weekly_submission_context()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id(); tenant_id uuid := app_security.current_church_id();
  periods_data jsonb; ous_data jsonb; metrics_data jsonb;
begin
  perform 1 from public.ensure_recent_sunday_periods();
  select coalesce(jsonb_agg(jsonb_build_object('id', period.id, 'label', period.label, 'periodStart', period.period_start,
    'periodEnd', period.period_end, 'year', period.year, 'weekNo', period.week_no, 'status', period.status)
    order by period.period_end desc), '[]'::jsonb) into periods_data
  from public.statistic_periods period where period.church_id = tenant_id and period.period_type = 'week'
    and period.period_end between current_date + ((7 - extract(dow from current_date)::integer) % 7) - 28
      and current_date + ((7 - extract(dow from current_date)::integer) % 7);
  select coalesce(jsonb_agg(jsonb_build_object('id', ou.id, 'name', ou.name, 'code', ou.code, 'path', ou.path, 'level', ou.level)
    order by ou.path, ou.sort_order, ou.name), '[]'::jsonb) into ous_data
  from public.organization_units ou where ou.church_id = tenant_id and ou.is_active and ou.deleted_at is null
    and ou.allow_data_entry and app_security.can_submit_for_ou(ou.id);
  select coalesce(jsonb_agg(jsonb_build_object('id', metric.id, 'code', metric.code, 'name', metric.name,
    'category', metric.category, 'unit', metric.unit, 'dataType', metric.data_type, 'inputType', metric.input_type,
    'isRequired', metric.is_required, 'minValue', metric.min_value, 'maxValue', metric.max_value, 'sortOrder', metric.sort_order)
    order by metric.sort_order, metric.name), '[]'::jsonb) into metrics_data
  from public.statistic_metrics metric where metric.church_id = tenant_id and metric.metric_kind = 'input'
    and metric.is_active and metric.deleted_at is null;
  return jsonb_build_object('success', true, 'data', jsonb_build_object('periods', periods_data, 'organizationUnits', ous_data, 'metrics', metrics_data));
end;
$$;

create or replace function public.get_report_table(p_ou_id uuid, p_from_date date, p_to_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id(); tenant_id uuid := app_security.current_church_id();
  target_ou public.organization_units%rowtype; church_name text; metrics_data jsonb; rows_data jsonb; totals_data jsonb;
begin
  if p_from_date is null or p_to_date is null or p_from_date > p_to_date then raise exception 'INVALID_REPORT_RANGE'; end if;
  select * into target_ou from public.organization_units where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then raise exception 'REPORT_FORBIDDEN'; end if;
  select name into church_name from public.churches where id = tenant_id and deleted_at is null;

  select coalesce(jsonb_agg(jsonb_build_object('metricId', metric.id, 'metricCode', metric.code, 'metricName', metric.name,
    'category', metric.category, 'unit', metric.unit, 'aggregation', metric.aggregation, 'metricKind', metric.metric_kind,
    'calculationOperator', metric.calculation_operator,
    'sourceMetricCodes', coalesce((select jsonb_agg(source.code order by source.sort_order, source.name)
      from public.statistic_metrics source where source.id = any(metric.calculation_source_metric_ids)), '[]'::jsonb))
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
    'values', (select coalesce(jsonb_object_agg(metric.code,
      app_security.report_metric_value(metric.id, report_ou.id, p_from_date, p_to_date, false)), '{}'::jsonb)
      from public.statistic_metrics metric where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
        and metric.data_type = 'number' and metric.aggregation <> 'none')) order by report_ou.path), '[]'::jsonb)
  into rows_data from report_ous report_ou;

  select coalesce(jsonb_object_agg(metric.code,
    app_security.report_metric_value(metric.id, target_ou.id, p_from_date, p_to_date, true)), '{}'::jsonb)
  into totals_data from public.statistic_metrics metric where metric.church_id = tenant_id and metric.is_active
    and metric.deleted_at is null and metric.data_type = 'number' and metric.aggregation <> 'none';
  return jsonb_build_object('success', true, 'data', jsonb_build_object('church', jsonb_build_object('id', tenant_id, 'name', church_name),
    'ou', jsonb_build_object('id', target_ou.id, 'code', target_ou.code, 'name', target_ou.name), 'fromDate', p_from_date,
    'toDate', p_to_date, 'metrics', metrics_data, 'rows', rows_data, 'totals', totals_data));
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
    'value', coalesce(app_security.report_metric_value(target_metric.id, target_ou.id, period.period_end, period.period_end, true), 0))
    order by period.period_end), '[]'::jsonb) into points_data
  from public.statistic_periods period where period.church_id = tenant_id and period.period_end between p_from_date and p_to_date;
  return jsonb_build_object('success', true, 'data', jsonb_build_object('metricCode', target_metric.code,
    'metricName', target_metric.name, 'unit', target_metric.unit, 'points', points_data));
end;
$$;

revoke all on function public.create_calculated_metric(jsonb) from public;
revoke all on function public.update_calculated_metric(jsonb) from public;
revoke all on function app_security.report_metric_value(uuid, uuid, date, date, boolean) from public;
grant execute on function public.create_calculated_metric(jsonb) to authenticated;
grant execute on function public.update_calculated_metric(jsonb) to authenticated;
