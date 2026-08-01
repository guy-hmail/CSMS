-- Task 5: dashboard completeness, direct-child rollups and approved trends.

create or replace function public.get_submission_status_summary(p_ou_id uuid, p_period_id uuid)
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
    items_data jsonb;
    total_expected integer;
    submitted_count integer;
    approved_count integer;
    pending_count integer;
begin
    select * into target_ou from public.organization_units
    where id = p_ou_id and church_id = tenant_id and is_active and deleted_at is null;
    if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then raise exception 'OU_NOT_FOUND'; end if;
    if not exists (select 1 from public.statistic_periods where id = p_period_id and church_id = tenant_id) then raise exception 'PERIOD_NOT_FOUND'; end if;

    with expected as (
      select ou.id, ou.name, ou.parent_id, ou.path
      from public.organization_units ou
      where ou.church_id = tenant_id and ou.structure_root_id = target_ou.structure_root_id
        and ou.is_active and ou.deleted_at is null and ou.allow_data_entry
        and (ou.path = target_ou.path or ou.path like target_ou.path || '/%')
        and app_security.can_view_ou(ou.id)
    ), status_rows as (
      select expected.*, submission.status, submission.submitted_at, submission.approved_at
      from expected left join public.statistic_submissions submission
        on submission.church_id = tenant_id and submission.ou_id = expected.id
       and submission.period_id = p_period_id and submission.deleted_at is null
    )
    select count(*), count(*) filter (where status is not null),
      count(*) filter (where status = 'approved'), count(*) filter (where status = 'submitted'),
      coalesce(jsonb_agg(jsonb_build_object(
        'ouId', row.id, 'ouName', row.name, 'parentOuId', row.parent_id,
        'status', coalesce(row.status, 'missing'), 'submittedAt', row.submitted_at,
        'approvedAt', row.approved_at
      ) order by row.path), '[]'::jsonb)
    into total_expected, submitted_count, approved_count, pending_count, items_data
    from status_rows row;

    return jsonb_build_object('success', true, 'data', jsonb_build_object(
      'summary', jsonb_build_object(
        'totalExpected', total_expected, 'submitted', submitted_count,
        'approved', approved_count, 'missing', total_expected - submitted_count,
        'pending', pending_count
      ),
      'items', items_data
    ));
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
    child record;
    children_data jsonb := '[]'::jsonb;
    metrics_data jsonb;
    expected_count integer;
    approved_count integer;
    submitted_count integer;
    draft_count integer;
    returned_count integer;
    rejected_count integer;
    child_status text;
begin
    select * into parent_ou from public.organization_units
    where id = p_parent_ou_id and church_id = tenant_id and is_active and deleted_at is null;
    if parent_ou.id is null or not app_security.can_view_ou(parent_ou.id) then raise exception 'OU_NOT_FOUND'; end if;
    if not exists (select 1 from public.statistic_periods where id = p_period_id and church_id = tenant_id) then raise exception 'PERIOD_NOT_FOUND'; end if;

    for child in
      select ou.* from public.organization_units ou
      where ou.church_id = tenant_id and ou.parent_id = parent_ou.id
        and ou.is_active and ou.deleted_at is null and app_security.can_view_ou(ou.id)
      order by ou.sort_order, ou.name, ou.id
    loop
      select count(*), count(*) filter (where submission.status = 'approved'),
        count(*) filter (where submission.status = 'submitted'),
        count(*) filter (where submission.status = 'draft'),
        count(*) filter (where submission.status = 'returned'),
        count(*) filter (where submission.status = 'rejected')
      into expected_count, approved_count, submitted_count, draft_count, returned_count, rejected_count
      from public.organization_units reporting_ou
      left join public.statistic_submissions submission
        on submission.church_id = tenant_id and submission.ou_id = reporting_ou.id
       and submission.period_id = p_period_id and submission.deleted_at is null
      where reporting_ou.church_id = tenant_id and reporting_ou.structure_root_id = child.structure_root_id
        and reporting_ou.is_active and reporting_ou.deleted_at is null and reporting_ou.allow_data_entry
        and (reporting_ou.path = child.path or reporting_ou.path like child.path || '/%');

      child_status := case
        when expected_count = 0 then 'missing'
        when approved_count = expected_count then 'approved'
        when approved_count + submitted_count + draft_count + returned_count + rejected_count = 0 then 'missing'
        when submitted_count > 0 then 'submitted'
        when returned_count > 0 then 'returned'
        when rejected_count > 0 then 'rejected'
        when draft_count > 0 then 'draft'
        else 'mixed'
      end;

      select coalesce(jsonb_agg(jsonb_build_object(
        'metricCode', metric.code, 'metricName', metric.name, 'unit', metric.unit,
        'value', case metric.aggregation when 'sum' then aggregate.sum_value
          when 'avg' then aggregate.avg_value when 'max' then aggregate.max_value
          when 'min' then aggregate.min_value else null end
      ) order by metric.sort_order, metric.name), '[]'::jsonb)
      into metrics_data
      from public.statistic_metrics metric
      left join lateral (
        select sum(value.numeric_value) sum_value, avg(value.numeric_value) avg_value,
          max(value.numeric_value) max_value, min(value.numeric_value) min_value
        from public.organization_units reporting_ou
        join public.statistic_submissions submission
          on submission.church_id = reporting_ou.church_id and submission.ou_id = reporting_ou.id
         and submission.period_id = p_period_id and submission.status = 'approved' and submission.deleted_at is null
        join public.statistic_values value
          on value.church_id = submission.church_id and value.submission_id = submission.id
         and value.metric_id = metric.id
        where reporting_ou.church_id = tenant_id and reporting_ou.structure_root_id = child.structure_root_id
          and reporting_ou.is_active and reporting_ou.deleted_at is null and reporting_ou.allow_data_entry
          and (reporting_ou.path = child.path or reporting_ou.path like child.path || '/%')
      ) aggregate on true
      where metric.church_id = tenant_id and metric.is_active and metric.deleted_at is null
        and metric.data_type = 'number' and metric.aggregation <> 'none';

      children_data := children_data || jsonb_build_array(jsonb_build_object(
        'ouId', child.id, 'ouName', child.name, 'level', child.level,
        'status', child_status, 'expectedCount', expected_count,
        'approvedCount', approved_count, 'metrics', metrics_data
      ));
    end loop;

    return jsonb_build_object('success', true, 'data', jsonb_build_object('children', children_data));
end;
$$;

create or replace function public.get_dashboard_trend(
  p_ou_id uuid,
  p_metric_code text,
  p_end_period_id uuid,
  p_limit integer default 12
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
      and data_type = 'number' and aggregation <> 'none';
    if target_metric.id is null then raise exception 'METRIC_NOT_FOUND'; end if;
    select period_end into end_date from public.statistic_periods
    where id = p_end_period_id and church_id = tenant_id;
    if end_date is null then raise exception 'PERIOD_NOT_FOUND'; end if;

    with selected_periods as (
      select period.* from public.statistic_periods period
      where period.church_id = tenant_id and period.period_type = 'week' and period.period_end <= end_date
      order by period.period_end desc limit p_limit
    ), aggregate_values as (
      select period.id period_id, sum(value.numeric_value) sum_value, avg(value.numeric_value) avg_value,
        max(value.numeric_value) max_value, min(value.numeric_value) min_value
      from selected_periods period
      left join public.statistic_submissions submission
        on submission.church_id = tenant_id and submission.period_id = period.id
       and submission.status = 'approved' and submission.deleted_at is null
      left join public.organization_units reporting_ou
        on reporting_ou.id = submission.ou_id and reporting_ou.church_id = submission.church_id
       and reporting_ou.is_active and reporting_ou.deleted_at is null and reporting_ou.allow_data_entry
       and reporting_ou.structure_root_id = target_ou.structure_root_id
       and (reporting_ou.path = target_ou.path or reporting_ou.path like target_ou.path || '/%')
      left join public.statistic_values value
        on value.church_id = submission.church_id and value.submission_id = submission.id
       and value.metric_id = target_metric.id and reporting_ou.id is not null
      group by period.id
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'periodId', period.id, 'label', period.label, 'periodStart', period.period_start,
      'periodEnd', period.period_end, 'value', coalesce(case target_metric.aggregation
        when 'sum' then aggregate.sum_value when 'avg' then aggregate.avg_value
        when 'max' then aggregate.max_value when 'min' then aggregate.min_value else null end, 0)
    ) order by period.period_end), '[]'::jsonb)
    into points_data
    from selected_periods period join aggregate_values aggregate on aggregate.period_id = period.id;

    return jsonb_build_object('success', true, 'data', jsonb_build_object(
      'metricCode', target_metric.code, 'metricName', target_metric.name,
      'unit', target_metric.unit, 'points', points_data
    ));
end;
$$;

revoke all on function public.get_submission_status_summary(uuid, uuid) from public;
revoke all on function public.get_child_ou_summary(uuid, uuid) from public;
revoke all on function public.get_dashboard_trend(uuid, text, uuid, integer) from public;
grant execute on function public.get_submission_status_summary(uuid, uuid) to authenticated;
grant execute on function public.get_child_ou_summary(uuid, uuid) to authenticated;
grant execute on function public.get_dashboard_trend(uuid, text, uuid, integer) to authenticated;
