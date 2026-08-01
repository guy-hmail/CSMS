-- Maintain a rolling reporting window ending on the upcoming Sunday (or today
-- when today is Sunday) plus the four preceding Sundays for the active tenant.

create or replace function public.ensure_recent_sunday_periods()
returns table (
    period_id uuid,
    period_start date,
    period_end date,
    display_label varchar
)
language plpgsql
security definer
set search_path = ''
as $$
declare
    tenant_id uuid := app_security.current_church_id();
    latest_sunday date;
    target_end date;
    target_start date;
begin
    if tenant_id is null then
        raise exception using errcode = '42501', message = 'AUTH_REQUIRED';
    end if;

    latest_sunday := current_date
        + ((7 - extract(dow from current_date)::integer) % 7);

    for week_offset in 0..4 loop
        target_end := latest_sunday - (week_offset * 7);
        target_start := target_end - 6;

        insert into public.statistic_periods (
            church_id, year, week_no, period_start, period_end, label, status
        )
        values (
            tenant_id,
            extract(isoyear from target_end)::integer,
            extract(week from target_end)::integer,
            target_start,
            target_end,
            to_char(target_end, 'YYYY-MM-DD'),
            'open'
        )
        on conflict on constraint uq_period_per_church do update
        set year = excluded.year,
            week_no = excluded.week_no,
            period_end = excluded.period_end,
            label = excluded.label;
    end loop;

    return query
    select
        period.id,
        period.period_start,
        period.period_end,
        period.label
    from public.statistic_periods as period
    where period.church_id = tenant_id
      and period.period_end between latest_sunday - 28 and latest_sunday
    order by period.period_end desc;
end;
$$;

revoke all on function public.ensure_recent_sunday_periods() from public;
grant execute on function public.ensure_recent_sunday_periods() to authenticated;
