-- The rollover period may be open before its calculation week has ended, but
-- the Input Data page must still default to the latest completed period.

do $migration$
declare
  function_definition text;
  old_default_query text := $old$
  select period.id into default_period_id
  from public.statistic_periods period
  where period.church_id = tenant_id
    and period.period_type = 'week'
    and extract(dow from period.period_end)::integer = tenant.reporting_week_ends_on
    and period.period_end between submission_period_end - 28 and submission_period_end
  order by
    (app_security.reporting_submission_state(
      period.status, period.submission_opens_at, period.submission_due_at, now()
    ) = 'open') desc,
    period.period_end desc
  limit 1;
$old$;
  new_default_query text := $new$
  select period.id into default_period_id
  from public.statistic_periods period
  where period.church_id = tenant_id
    and period.period_type = 'week'
    and extract(dow from period.period_end)::integer = tenant.reporting_week_ends_on
    and period.period_end between submission_period_end - 28 and latest_completed_end
  order by period.period_end desc
  limit 1;
$new$;
begin
  select pg_get_functiondef('public.get_weekly_submission_context()'::regprocedure)
  into function_definition;

  if position(old_default_query in function_definition) = 0 then
    raise exception 'Expected weekly submission default-period query was not found';
  end if;

  function_definition := replace(function_definition, old_default_query, new_default_query);
  execute function_definition;
end;
$migration$;
