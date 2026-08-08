-- Tenant-selected dashboard metrics, including calculated fields.
alter table public.statistic_metrics
  add column show_on_dashboard boolean not null default false,
  add column dashboard_order integer not null default 0,
  add constraint ck_statistic_metric_dashboard_order check (dashboard_order >= 0);

with ranked as (
  select metric.id,
    row_number() over (
      partition by metric.church_id
      order by (metric.id = church.primary_metric_id) desc,
        (metric.metric_kind = 'calculated') desc,
        metric.sort_order, metric.name, metric.id
    ) as position
  from public.statistic_metrics metric
  join public.churches church on church.id = metric.church_id
  where metric.is_active and metric.deleted_at is null
    and metric.data_type = 'number' and metric.aggregation <> 'none'
)
update public.statistic_metrics metric
set show_on_dashboard = ranked.position <= 4,
    dashboard_order = case when ranked.position <= 4 then ranked.position * 10 else 0 end
from ranked where ranked.id = metric.id;

create or replace function public.update_dashboard_metric_settings(p_payload jsonb)
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
  metric_ids uuid[];
  old_settings jsonb;
  metric_id uuid;
  position integer := 0;
begin
  if jsonb_typeof(p_payload -> 'metricIds') <> 'array' then
    raise exception 'DASHBOARD_METRICS_REQUIRED';
  end if;
  select array_agg(value::uuid order by ordinal)
  into metric_ids
  from jsonb_array_elements_text(p_payload -> 'metricIds') with ordinality item(value, ordinal);

  if coalesce(cardinality(metric_ids), 0) = 0 then raise exception 'DASHBOARD_METRICS_REQUIRED'; end if;
  if cardinality(metric_ids) <> (select count(distinct id) from unnest(metric_ids) id) then
    raise exception 'DUPLICATE_DASHBOARD_METRIC';
  end if;
  if cardinality(metric_ids) <> (
    select count(*) from public.statistic_metrics metric
    where metric.church_id = tenant_id and metric.id = any(metric_ids)
      and metric.is_active and metric.deleted_at is null
      and metric.data_type = 'number' and metric.aggregation <> 'none'
  ) then raise exception 'DASHBOARD_METRIC_INVALID'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('metricId', metric.id, 'order', metric.dashboard_order)
    order by metric.dashboard_order, metric.name), '[]'::jsonb)
  into old_settings from public.statistic_metrics metric
  where metric.church_id = tenant_id and metric.show_on_dashboard;

  update public.statistic_metrics
  set show_on_dashboard = false, dashboard_order = 0, updated_at = now()
  where church_id = tenant_id and show_on_dashboard;

  foreach metric_id in array metric_ids loop
    position := position + 1;
    update public.statistic_metrics
    set show_on_dashboard = true, dashboard_order = position * 10, updated_at = now()
    where id = metric_id and church_id = tenant_id;
  end loop;

  select ou_id into root_ou_id from public.ou_members
  where id = source_assignment_id and church_id = tenant_id;
  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, ou_id, source_ou_member_id,
    entity_type, entity_id, action, before_data, after_data
  ) values (
    tenant_id, actor_user_id, actor_membership_id, root_ou_id, source_assignment_id,
    'dashboard_settings', tenant_id, 'update_dashboard_metrics',
    jsonb_build_object('metrics', old_settings),
    jsonb_build_object('metricIds', to_jsonb(metric_ids))
  );
  return jsonb_build_object('success', true, 'data', jsonb_build_object('metricCount', cardinality(metric_ids)));
exception when invalid_text_representation then raise exception 'DASHBOARD_METRIC_INVALID';
end;
$$;

create or replace function public.get_recursive_summary(
  p_ou_id uuid, p_period_id uuid, p_compare_period_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  target_ou public.organization_units%rowtype;
  target_period public.statistic_periods%rowtype;
  compare_period public.statistic_periods%rowtype;
  metric_items jsonb;
begin
  select * into target_ou from public.organization_units
  where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then raise exception 'OU_NOT_FOUND'; end if;
  select * into target_period from public.statistic_periods where id = p_period_id and church_id = tenant_id;
  if target_period.id is null then raise exception 'PERIOD_NOT_FOUND'; end if;
  if p_compare_period_id is not null then
    select * into compare_period from public.statistic_periods where id = p_compare_period_id and church_id = tenant_id;
    if compare_period.id is null then raise exception 'COMPARE_PERIOD_NOT_FOUND'; end if;
  end if;

  with metric_values as (
    select metric.*,
      app_security.report_metric_value(metric.id, target_ou.id, target_period.period_end, target_period.period_end, true) current_value,
      case when compare_period.id is null then null else
        app_security.report_metric_value(metric.id, target_ou.id, compare_period.period_end, compare_period.period_end, true)
      end compare_value
    from public.statistic_metrics metric
    where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
      and metric.show_on_dashboard and metric.data_type = 'number' and metric.aggregation <> 'none'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'metricId', metric.id, 'metricCode', metric.code, 'metricName', metric.name,
    'category', metric.category, 'unit', metric.unit, 'aggregation', metric.aggregation,
    'metricKind', metric.metric_kind, 'currentValue', metric.current_value,
    'compareValue', metric.compare_value, 'growthPercent', case
      when metric.compare_value is null or metric.compare_value = 0 or metric.current_value is null then null
      else round(((metric.current_value - metric.compare_value) / abs(metric.compare_value)) * 100, 2) end
  ) order by metric.dashboard_order, metric.name, metric.id), '[]'::jsonb)
  into metric_items from metric_values metric;

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
returns jsonb language plpgsql stable security definer set search_path = '' as $$
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
  select period_end into end_date from public.statistic_periods where id = p_end_period_id and church_id = tenant_id;
  if end_date is null then raise exception 'PERIOD_NOT_FOUND'; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'periodId', period.id, 'label', period.label, 'periodStart', period.period_start,
    'periodEnd', period.period_end, 'value', coalesce(app_security.report_metric_value(
      target_metric.id, target_ou.id, period.period_end, period.period_end, true), 0)
  ) order by period.period_end), '[]'::jsonb)
  into points_data from (
    select * from public.statistic_periods
    where church_id = tenant_id and period_type = 'week' and period_end <= end_date
    order by period_end desc limit p_limit
  ) period;
  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'metricCode', target_metric.code, 'metricName', target_metric.name,
    'metricKind', target_metric.metric_kind, 'unit', target_metric.unit, 'points', points_data));
end;
$$;

create or replace function public.get_child_ou_summary(p_parent_ou_id uuid, p_period_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  parent_ou public.organization_units%rowtype; child record; period_end_date date;
  children_data jsonb := '[]'::jsonb; metrics_data jsonb;
  expected_count integer; approved_count integer; submitted_count integer;
  draft_count integer; returned_count integer; rejected_count integer; child_status text;
begin
  select * into parent_ou from public.organization_units
  where id = p_parent_ou_id and church_id = tenant_id and is_active and deleted_at is null;
  if parent_ou.id is null or not app_security.can_view_ou(parent_ou.id) then raise exception 'OU_NOT_FOUND'; end if;
  select period_end into period_end_date from public.statistic_periods where id = p_period_id and church_id = tenant_id;
  if period_end_date is null then raise exception 'PERIOD_NOT_FOUND'; end if;
  for child in select ou.* from public.organization_units ou
    where ou.church_id = tenant_id and ou.parent_id = parent_ou.id and ou.is_active and ou.deleted_at is null
      and app_security.can_view_ou(ou.id) order by ou.sort_order, ou.name, ou.id
  loop
    select count(*), count(*) filter (where submission.status = 'approved'),
      count(*) filter (where submission.status = 'submitted'), count(*) filter (where submission.status = 'draft'),
      count(*) filter (where submission.status = 'returned'), count(*) filter (where submission.status = 'rejected')
    into expected_count, approved_count, submitted_count, draft_count, returned_count, rejected_count
    from public.organization_units reporting_ou left join public.statistic_submissions submission
      on submission.church_id = tenant_id and submission.ou_id = reporting_ou.id
      and submission.period_id = p_period_id and submission.deleted_at is null
    where reporting_ou.church_id = tenant_id and reporting_ou.structure_root_id = child.structure_root_id
      and reporting_ou.is_active and reporting_ou.deleted_at is null and reporting_ou.allow_data_entry
      and (reporting_ou.path = child.path or reporting_ou.path like child.path || '/%');
    child_status := case when expected_count = 0 then 'missing' when approved_count = expected_count then 'approved'
      when approved_count + submitted_count + draft_count + returned_count + rejected_count = 0 then 'missing'
      when submitted_count > 0 then 'submitted' when returned_count > 0 then 'returned'
      when rejected_count > 0 then 'rejected' when draft_count > 0 then 'draft' else 'mixed' end;
    select coalesce(jsonb_agg(jsonb_build_object(
      'metricCode', metric.code, 'metricName', metric.name, 'metricKind', metric.metric_kind,
      'unit', metric.unit, 'value', app_security.report_metric_value(metric.id, child.id, period_end_date, period_end_date, true)
    ) order by metric.dashboard_order, metric.name), '[]'::jsonb)
    into metrics_data from public.statistic_metrics metric
    where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
      and metric.show_on_dashboard and metric.data_type = 'number' and metric.aggregation <> 'none';
    children_data := children_data || jsonb_build_array(jsonb_build_object(
      'ouId', child.id, 'ouName', child.name, 'level', child.level, 'status', child_status,
      'expectedCount', expected_count, 'approvedCount', approved_count, 'metrics', metrics_data));
  end loop;
  return jsonb_build_object('success', true, 'data', jsonb_build_object('children', children_data));
end;
$$;

revoke all on function public.update_dashboard_metric_settings(jsonb) from public;
grant execute on function public.update_dashboard_metric_settings(jsonb) to authenticated;
