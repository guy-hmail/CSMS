-- Tenant-owned scheduled notification settings.
-- Platform environment flags remain the outer kill switch and canary boundary;
-- these persisted values decide whether and when each eligible Tenant runs.

alter table public.churches
  add column notification_schedule_enabled boolean not null default false,
  add column notification_schedule_days text[] not null
    default array['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']::text[],
  add column missing_reminder_local_hour smallint not null default 9,
  add column approval_digest_local_hour smallint not null default 9,
  add constraint ck_churches_notification_schedule_days check (
    cardinality(notification_schedule_days) between 1 and 7
    and notification_schedule_days <@ array['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']::text[]
    and array_position(notification_schedule_days, null) is null
    and cardinality(notification_schedule_days) =
      (case when 'MON' = any(notification_schedule_days) then 1 else 0 end)
      + (case when 'TUE' = any(notification_schedule_days) then 1 else 0 end)
      + (case when 'WED' = any(notification_schedule_days) then 1 else 0 end)
      + (case when 'THU' = any(notification_schedule_days) then 1 else 0 end)
      + (case when 'FRI' = any(notification_schedule_days) then 1 else 0 end)
      + (case when 'SAT' = any(notification_schedule_days) then 1 else 0 end)
      + (case when 'SUN' = any(notification_schedule_days) then 1 else 0 end)
  ),
  add constraint ck_churches_missing_reminder_hour check (
    missing_reminder_local_hour between 0 and 23
  ),
  add constraint ck_churches_approval_digest_hour check (
    approval_digest_local_hour between 0 and 23
  );

create or replace function public.update_tenant_notification_schedule(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  actor_membership_id uuid := app_security.current_church_member_id();
  source_assignment_id uuid := app_security.require_direct_root_admin();
  target public.churches%rowtype;
  root_ou_id uuid;
  input_enabled boolean;
  input_days text[];
  input_missing_hour smallint;
  input_digest_hour smallint;
  distinct_day_count integer;
  before_snapshot jsonb;
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'VALIDATION_ERROR';
  end if;

  select * into target
  from public.churches
  where id = app_security.current_church_id()
    and is_active and deleted_at is null
  for update;
  if target.id is null then raise exception 'TENANT_NOT_FOUND'; end if;

  select ou_id into root_ou_id
  from public.ou_members
  where id = source_assignment_id and church_id = target.id;

  if p_payload ? 'scheduleDays' and jsonb_typeof(p_payload -> 'scheduleDays') <> 'array' then
    raise exception 'VALIDATION_ERROR';
  end if;

  input_enabled := coalesce(
    nullif(p_payload ->> 'enabled', '')::boolean,
    target.notification_schedule_enabled
  );
  input_missing_hour := coalesce(
    nullif(p_payload ->> 'missingReminderLocalHour', '')::smallint,
    target.missing_reminder_local_hour
  );
  input_digest_hour := coalesce(
    nullif(p_payload ->> 'approvalDigestLocalHour', '')::smallint,
    target.approval_digest_local_hour
  );

  if p_payload ? 'scheduleDays' then
    select array_agg(upper(trim(day_value)) order by day_order),
           count(distinct upper(trim(day_value)))
      into input_days, distinct_day_count
    from jsonb_array_elements_text(p_payload -> 'scheduleDays')
      with ordinality as selected(day_value, day_order);
  else
    input_days := target.notification_schedule_days;
    distinct_day_count := cardinality(input_days);
  end if;

  if input_enabled is null
     or input_missing_hour not between 0 and 23
     or input_digest_hour not between 0 and 23
     or input_days is null
     or cardinality(input_days) not between 1 and 7
     or distinct_day_count <> cardinality(input_days)
     or not input_days <@ array['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN']::text[] then
    raise exception 'VALIDATION_ERROR';
  end if;

  before_snapshot := jsonb_build_object(
    'enabled', target.notification_schedule_enabled,
    'scheduleDays', target.notification_schedule_days,
    'missingReminderLocalHour', target.missing_reminder_local_hour,
    'approvalDigestLocalHour', target.approval_digest_local_hour
  );

  update public.churches
  set notification_schedule_enabled = input_enabled,
      notification_schedule_days = input_days,
      missing_reminder_local_hour = input_missing_hour,
      approval_digest_local_hour = input_digest_hour
  where id = target.id;

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, ou_id,
    source_ou_member_id, entity_type, entity_id, action,
    before_data, after_data
  ) values (
    target.id, actor_user_id, actor_membership_id, root_ou_id,
    source_assignment_id, 'churches', target.id, 'update_notification_schedule',
    before_snapshot,
    jsonb_build_object(
      'enabled', input_enabled,
      'scheduleDays', input_days,
      'missingReminderLocalHour', input_missing_hour,
      'approvalDigestLocalHour', input_digest_hour
    )
  );

  return jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'tenantId', target.id,
      'enabled', input_enabled,
      'scheduleDays', input_days,
      'missingReminderLocalHour', input_missing_hour,
      'approvalDigestLocalHour', input_digest_hour
    )
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception 'VALIDATION_ERROR';
end;
$$;

create or replace function app_security.notification_local_day_code(
  p_run_at timestamptz,
  p_timezone text
)
returns text
language sql
stable
set search_path = ''
as $$
  select (array['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'])[extract(isodow from (p_run_at at time zone p_timezone))::integer];
$$;

create or replace function public.run_tenant_missing_submission_reminders(
  p_run_at timestamptz default now(),
  p_church_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  tenant record;
  execution jsonb;
  tenant_count integer := 0;
  ou_count integer := 0;
  notification_count integer := 0;
begin
  if p_run_at is null then raise exception 'INVALID_NOTIFICATION_SCHEDULE'; end if;

  for tenant in
    select church.id, church.timezone, church.notification_schedule_days,
           church.missing_reminder_local_hour
    from public.churches church
    where church.is_active and church.deleted_at is null
      and church.status in ('trial', 'active')
      and church.notification_schedule_enabled
      and (p_church_ids is null or church.id = any(p_church_ids))
      and exists (
        select 1 from pg_catalog.pg_timezone_names timezone_name
        where timezone_name.name = church.timezone
      )
    order by church.id
  loop
    if not app_security.notification_local_day_code(p_run_at, tenant.timezone)
         = any(tenant.notification_schedule_days)
       or extract(hour from (p_run_at at time zone tenant.timezone))::integer
         < tenant.missing_reminder_local_hour then
      continue;
    end if;

    execution := public.run_missing_submission_reminders(
      p_run_at, array[tenant.id], tenant.missing_reminder_local_hour
    );
    tenant_count := tenant_count + coalesce((execution #>> '{data,tenantsScanned}')::integer, 0);
    ou_count := ou_count + coalesce((execution #>> '{data,missingOus}')::integer, 0);
    notification_count := notification_count
      + coalesce((execution #>> '{data,notificationsCreated}')::integer, 0);
  end loop;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'tenantsScanned', tenant_count,
    'missingOus', ou_count,
    'notificationsCreated', notification_count
  ));
end;
$$;

create or replace function public.run_tenant_pending_approval_digests(
  p_run_at timestamptz default now(),
  p_church_ids uuid[] default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  tenant record;
  execution jsonb;
  tenant_count integer := 0;
  notification_count integer := 0;
begin
  if p_run_at is null then raise exception 'INVALID_NOTIFICATION_SCHEDULE'; end if;

  for tenant in
    select church.id, church.timezone, church.notification_schedule_days,
           church.approval_digest_local_hour
    from public.churches church
    where church.is_active and church.deleted_at is null
      and church.status in ('trial', 'active')
      and church.approval_mode = 'approval_required'
      and church.notification_schedule_enabled
      and (p_church_ids is null or church.id = any(p_church_ids))
      and exists (
        select 1 from pg_catalog.pg_timezone_names timezone_name
        where timezone_name.name = church.timezone
      )
    order by church.id
  loop
    if not app_security.notification_local_day_code(p_run_at, tenant.timezone)
         = any(tenant.notification_schedule_days)
       or extract(hour from (p_run_at at time zone tenant.timezone))::integer
         < tenant.approval_digest_local_hour then
      continue;
    end if;

    execution := public.run_pending_approval_digests(
      p_run_at, array[tenant.id], tenant.approval_digest_local_hour
    );
    tenant_count := tenant_count + coalesce((execution #>> '{data,tenantsScanned}')::integer, 0);
    notification_count := notification_count
      + coalesce((execution #>> '{data,notificationsCreated}')::integer, 0);
  end loop;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'tenantsScanned', tenant_count,
    'notificationsCreated', notification_count
  ));
end;
$$;

revoke all on function public.update_tenant_notification_schedule(jsonb) from public;
revoke all on function app_security.notification_local_day_code(timestamptz, text) from public;
revoke all on function public.run_tenant_missing_submission_reminders(timestamptz, uuid[]) from public;
revoke all on function public.run_tenant_pending_approval_digests(timestamptz, uuid[]) from public;

grant execute on function public.update_tenant_notification_schedule(jsonb) to authenticated;
grant execute on function public.run_tenant_missing_submission_reminders(timestamptz, uuid[]) to service_role;
grant execute on function public.run_tenant_pending_approval_digests(timestamptz, uuid[]) to service_role;
