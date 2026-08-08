-- Bootstrap a usable Dashboard for new tenants without auto-selecting every future metric.
create or replace function app_security.assign_default_dashboard_metric()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  existing_numeric_count integer;
  next_order integer;
begin
  if new.data_type <> 'number' or new.aggregation = 'none' then return new; end if;
  select count(*), coalesce(max(metric.dashboard_order), 0) + 10
  into existing_numeric_count, next_order
  from public.statistic_metrics metric
  where metric.church_id = new.church_id and metric.deleted_at is null
    and metric.data_type = 'number' and metric.aggregation <> 'none';
  if existing_numeric_count < 4 then
    new.show_on_dashboard := true;
    new.dashboard_order := next_order;
  end if;
  return new;
end;
$$;

create trigger trg_default_dashboard_metric
before insert on public.statistic_metrics
for each row execute function app_security.assign_default_dashboard_metric();
