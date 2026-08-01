-- Task 3: tenant-scoped contracts used by the weekly submission page.

create or replace function public.get_weekly_submission_context()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    ignored_user_id uuid := app_security.require_current_user_id();
    tenant_id uuid := app_security.current_church_id();
    periods_data jsonb;
    ous_data jsonb;
    metrics_data jsonb;
begin
    perform 1 from public.ensure_recent_sunday_periods();

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', period.id,
        'label', period.label,
        'periodStart', period.period_start,
        'periodEnd', period.period_end,
        'year', period.year,
        'weekNo', period.week_no,
        'status', period.status
    ) order by period.period_end desc), '[]'::jsonb)
    into periods_data
    from public.statistic_periods as period
    where period.church_id = tenant_id
      and period.period_type = 'week'
      and period.period_end between (
          current_date + ((7 - extract(dow from current_date)::integer) % 7) - 28
      ) and (
          current_date + ((7 - extract(dow from current_date)::integer) % 7)
      );

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', ou.id,
        'name', ou.name,
        'code', ou.code,
        'path', ou.path,
        'level', ou.level
    ) order by ou.path, ou.sort_order, ou.name), '[]'::jsonb)
    into ous_data
    from public.organization_units as ou
    where ou.church_id = tenant_id
      and ou.is_active
      and ou.deleted_at is null
      and ou.allow_data_entry
      and app_security.can_submit_for_ou(ou.id);

    select coalesce(jsonb_agg(jsonb_build_object(
        'id', metric.id,
        'code', metric.code,
        'name', metric.name,
        'category', metric.category,
        'unit', metric.unit,
        'dataType', metric.data_type,
        'inputType', metric.input_type,
        'isRequired', metric.is_required,
        'minValue', metric.min_value,
        'maxValue', metric.max_value,
        'sortOrder', metric.sort_order
    ) order by metric.sort_order, metric.name), '[]'::jsonb)
    into metrics_data
    from public.statistic_metrics as metric
    where metric.church_id = tenant_id
      and metric.is_active
      and metric.deleted_at is null;

    return jsonb_build_object(
        'success', true,
        'data', jsonb_build_object(
            'periods', periods_data,
            'organizationUnits', ous_data,
            'metrics', metrics_data
        )
    );
end;
$$;

create or replace function public.get_submission_by_context(
    p_ou_id uuid,
    p_period_id uuid
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
    submission_id uuid;
begin
    if not exists (
        select 1 from public.organization_units as ou
        where ou.id = p_ou_id
          and ou.church_id = tenant_id
          and ou.is_active
          and ou.deleted_at is null
          and ou.allow_data_entry
          and app_security.can_submit_for_ou(ou.id)
    ) then
        raise exception using errcode = '42501', message = 'SUBMISSION_CONTEXT_NOT_FOUND';
    end if;

    if not exists (
        select 1 from public.statistic_periods as period
        where period.id = p_period_id and period.church_id = tenant_id
    ) then
        raise exception using errcode = '42501', message = 'SUBMISSION_CONTEXT_NOT_FOUND';
    end if;

    select submission.id into submission_id
    from public.statistic_submissions as submission
    where submission.church_id = tenant_id
      and submission.ou_id = p_ou_id
      and submission.period_id = p_period_id
      and submission.deleted_at is null;

    if submission_id is null then
        return jsonb_build_object('success', true, 'data', null);
    end if;

    return public.get_submission_detail(submission_id);
end;
$$;

revoke all on function public.get_weekly_submission_context() from public;
revoke all on function public.get_submission_by_context(uuid, uuid) from public;
grant execute on function public.get_weekly_submission_context() to authenticated;
grant execute on function public.get_submission_by_context(uuid, uuid) to authenticated;
