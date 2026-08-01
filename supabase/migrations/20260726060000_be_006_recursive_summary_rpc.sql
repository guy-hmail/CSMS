-- BE-006: Recursive approved-submission summary.

create or replace function public.get_recursive_summary(
    p_ou_id uuid,
    p_period_id uuid,
    p_compare_period_id uuid default null
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
    select *
    into target_ou
    from public.organization_units
    where id = p_ou_id
      and church_id = tenant_id
      and is_active
      and deleted_at is null;
    if target_ou.id is null or not app_security.can_view_ou(target_ou.id) then
        raise exception 'OU_NOT_FOUND';
    end if;

    select *
    into target_period
    from public.statistic_periods
    where id = p_period_id and church_id = tenant_id;
    if target_period.id is null then raise exception 'PERIOD_NOT_FOUND'; end if;

    if p_compare_period_id is not null then
        select *
        into compare_period
        from public.statistic_periods
        where id = p_compare_period_id and church_id = tenant_id;
        if compare_period.id is null then raise exception 'COMPARE_PERIOD_NOT_FOUND'; end if;
    end if;

    with descendants as (
        select organization.id
        from public.organization_units as organization
        where organization.church_id = tenant_id
          and organization.structure_root_id = target_ou.structure_root_id
          and organization.is_active
          and organization.deleted_at is null
          and (
              organization.path = target_ou.path
              or organization.path like target_ou.path || '/%'
          )
    ),
    current_values as (
        select
            value.metric_id,
            sum(value.numeric_value) as sum_value,
            avg(value.numeric_value) as avg_value,
            max(value.numeric_value) as max_value,
            min(value.numeric_value) as min_value
        from public.statistic_submissions as submission
        join public.statistic_values as value
          on value.church_id = submission.church_id
         and value.submission_id = submission.id
        where submission.church_id = tenant_id
          and submission.period_id = target_period.id
          and submission.ou_id in (select id from descendants)
          and submission.status = 'approved'
          and submission.deleted_at is null
        group by value.metric_id
    ),
    compare_values as (
        select
            value.metric_id,
            sum(value.numeric_value) as sum_value,
            avg(value.numeric_value) as avg_value,
            max(value.numeric_value) as max_value,
            min(value.numeric_value) as min_value
        from public.statistic_submissions as submission
        join public.statistic_values as value
          on value.church_id = submission.church_id
         and value.submission_id = submission.id
        where p_compare_period_id is not null
          and submission.church_id = tenant_id
          and submission.period_id = p_compare_period_id
          and submission.ou_id in (select id from descendants)
          and submission.status = 'approved'
          and submission.deleted_at is null
        group by value.metric_id
    ),
    metric_result as (
        select
            metric.id,
            metric.code,
            metric.name,
            metric.category,
            metric.unit,
            metric.aggregation,
            metric.sort_order,
            case metric.aggregation
                when 'sum' then current_values.sum_value
                when 'avg' then current_values.avg_value
                when 'max' then current_values.max_value
                when 'min' then current_values.min_value
                else null
            end as current_value,
            case metric.aggregation
                when 'sum' then compare_values.sum_value
                when 'avg' then compare_values.avg_value
                when 'max' then compare_values.max_value
                when 'min' then compare_values.min_value
                else null
            end as compare_value
        from public.statistic_metrics as metric
        left join current_values on current_values.metric_id = metric.id
        left join compare_values on compare_values.metric_id = metric.id
        where metric.church_id = tenant_id
          and metric.is_active
          and metric.deleted_at is null
          and metric.data_type = 'number'
          and metric.aggregation <> 'none'
    )
    select coalesce(
        jsonb_agg(
            jsonb_build_object(
                'metricId', result.id,
                'metricCode', result.code,
                'metricName', result.name,
                'category', result.category,
                'unit', result.unit,
                'aggregation', result.aggregation,
                'currentValue', result.current_value,
                'compareValue', result.compare_value,
                'growthPercent',
                case
                    when result.compare_value is null or result.compare_value = 0
                        or result.current_value is null then null
                    else round(
                        ((result.current_value - result.compare_value)
                          / abs(result.compare_value)) * 100,
                        2
                    )
                end
            )
            order by result.sort_order, result.name, result.id
        ),
        '[]'::jsonb
    )
    into metric_items
    from metric_result as result;

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'ou', jsonb_build_object(
                'id', target_ou.id,
                'name', target_ou.name,
                'path', target_ou.path
            ),
            'period', jsonb_build_object(
                'id', target_period.id,
                'periodEnd', target_period.period_end,
                'displayLabel', target_period.label
            ),
            'comparePeriod', case
                when compare_period.id is null then null
                else jsonb_build_object(
                    'id', compare_period.id,
                    'periodEnd', compare_period.period_end,
                    'displayLabel', compare_period.label
                )
            end,
            'metrics', metric_items
        )
    );
end;
$$;

revoke all on function public.get_recursive_summary(uuid, uuid, uuid) from public;
grant execute on function public.get_recursive_summary(uuid, uuid, uuid) to authenticated;
