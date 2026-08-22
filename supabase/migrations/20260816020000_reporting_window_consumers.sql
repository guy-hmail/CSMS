-- Propagate reporting-window settings through platform administration and
-- ensure scheduled missing reminders run only while the target period is open.

create or replace function public.create_platform_tenant(payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid;
  tenant_id uuid;
  deadline_days smallint := coalesce(
    nullif(payload ->> 'submissionDeadlineDaysAfterPeriodEnd', '')::smallint,
    1
  );
begin
  actor_user_id := app_security.require_system_admin();
  if deadline_days not between 1 and 6 then
    raise exception using errcode = '22023', message = 'SUBMISSION_DEADLINE_INVALID';
  end if;
  tenant_id := public.create_platform_tenant_base(payload);

  update public.churches
  set submission_deadline_days_after_period_end = deadline_days
  where id = tenant_id;

  insert into public.organization_unit_types (
    id, church_id, code, name, sort_order,
    default_allow_data_entry, is_active, created_by
  ) values (
    gen_random_uuid(), tenant_id, 'CARE', 'แคร์', 50,
    true, true, actor_user_id
  );
  return tenant_id;
end;
$$;

create or replace function public.get_platform_tenant_detail(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare result jsonb;
begin
  perform app_security.require_system_admin();
  select jsonb_build_object(
    'id', church.id,
    'code', church.code,
    'name', church.name,
    'slug', church.slug,
    'description', church.description,
    'timezone', church.timezone,
    'approvalMode', church.approval_mode,
    'weekEndsOn', case church.reporting_week_ends_on when 6 then 'saturday' else 'sunday' end,
    'submissionDeadlineDaysAfterPeriodEnd', church.submission_deadline_days_after_period_end,
    'status', church.status,
    'trialEndsAt', church.trial_ends_at,
    'createdAt', church.created_at,
    'updatedAt', church.updated_at,
    'provisioning', jsonb_build_object(
      'rootOuCount', (select count(*) from public.organization_units ou where ou.church_id = church.id and ou.parent_id is null and ou.is_active and ou.deleted_at is null),
      'ouTypeCount', (select count(*) from public.organization_unit_types t where t.church_id = church.id and t.is_active),
      'metricCount', (select count(*) from public.statistic_metrics m where m.church_id = church.id and m.is_active),
      'memberCount', (select count(*) from public.church_members cm where cm.church_id = church.id and cm.status = 'active'),
      'ready', (select count(*) = 1 from public.organization_units ou where ou.church_id = church.id and ou.parent_id is null and ou.is_active and ou.deleted_at is null)
        and (select count(*) >= 4 from public.organization_unit_types t where t.church_id = church.id and t.is_active)
        and (select count(*) >= 9 from public.statistic_metrics m where m.church_id = church.id and m.is_active)
    )
  ) into result
  from public.churches church
  where church.id = p_tenant_id and church.deleted_at is null;
  if result is null then raise exception using errcode = 'P0002', message = 'TENANT_NOT_FOUND'; end if;
  return result;
end;
$$;

create or replace function public.update_platform_tenant(p_tenant_id uuid, payload jsonb)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_system_admin();
  previous public.churches%rowtype;
  next_name text := btrim(coalesce(payload ->> 'name', ''));
  next_slug text := lower(btrim(coalesce(payload ->> 'slug', '')));
  next_timezone text := btrim(coalesce(payload ->> 'timezone', ''));
  next_approval text := btrim(coalesce(payload ->> 'approvalMode', ''));
  next_week smallint;
  next_deadline_days smallint;
begin
  select * into previous from public.churches where id = p_tenant_id and deleted_at is null for update;
  if previous.id is null then raise exception using errcode = 'P0002', message = 'TENANT_NOT_FOUND'; end if;
  if previous.status = 'closed' then raise exception using errcode = '55000', message = 'TENANT_CLOSED'; end if;
  if next_name = '' or length(next_name) > 255 then raise exception using errcode = '22023', message = 'TENANT_NAME_INVALID'; end if;
  if next_slug !~ '^[a-z0-9]+(?:-[a-z0-9]+)*$' or length(next_slug) > 100 then raise exception using errcode = '22023', message = 'TENANT_SLUG_INVALID'; end if;
  if exists (select 1 from public.churches where slug = next_slug and id <> p_tenant_id and deleted_at is null) then raise exception using errcode = '23505', message = 'TENANT_SLUG_EXISTS'; end if;
  if next_timezone = '' or length(next_timezone) > 100 or not exists (
    select 1 from pg_catalog.pg_timezone_names where name = next_timezone
  ) then raise exception using errcode = '22023', message = 'TIMEZONE_INVALID'; end if;
  if next_approval not in ('auto_approve', 'approval_required') then raise exception using errcode = '22023', message = 'APPROVAL_MODE_INVALID'; end if;
  next_week := case lower(payload ->> 'weekEndsOn') when 'sunday' then 0 when 'saturday' then 6 else null end;
  if next_week is null then raise exception using errcode = '22023', message = 'WEEK_END_INVALID'; end if;
  next_deadline_days := coalesce(
    nullif(payload ->> 'submissionDeadlineDaysAfterPeriodEnd', '')::smallint,
    previous.submission_deadline_days_after_period_end
  );
  if next_deadline_days not between 1 and 6 then raise exception using errcode = '22023', message = 'SUBMISSION_DEADLINE_INVALID'; end if;

  update public.churches set
    name = next_name,
    slug = next_slug,
    description = nullif(btrim(coalesce(payload ->> 'description', '')), ''),
    timezone = next_timezone,
    approval_mode = next_approval,
    reporting_week_ends_on = next_week,
    submission_deadline_days_after_period_end = next_deadline_days,
    updated_at = now()
  where id = p_tenant_id;

  insert into public.audit_logs(church_id, user_id, entity_type, entity_id, action, before_data, after_data)
  values (
    p_tenant_id, actor_user_id, 'churches', p_tenant_id, 'update_platform_tenant',
    jsonb_build_object(
      'name', previous.name, 'slug', previous.slug, 'timezone', previous.timezone,
      'approvalMode', previous.approval_mode, 'weekEndsOn', previous.reporting_week_ends_on,
      'submissionDeadlineDaysAfterPeriodEnd', previous.submission_deadline_days_after_period_end
    ),
    jsonb_build_object(
      'name', next_name, 'slug', next_slug, 'timezone', next_timezone,
      'approvalMode', next_approval, 'weekEndsOn', next_week,
      'submissionDeadlineDaysAfterPeriodEnd', next_deadline_days
    )
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode = '22023', message = 'SUBMISSION_DEADLINE_INVALID';
end;
$$;

create or replace function public.run_missing_submission_reminders(
  p_run_at timestamptz default now(),
  p_church_ids uuid[] default null,
  p_local_hour integer default 9
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  tenant record;
  missing record;
  recipient record;
  notification_id uuid;
  schedule_event_key text;
  local_date date;
  local_hour integer;
  tenant_count integer := 0;
  ou_count integer := 0;
  recipient_count integer := 0;
begin
  if p_run_at is null or p_local_hour < 0 or p_local_hour > 23 then
    raise exception 'INVALID_NOTIFICATION_SCHEDULE';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('notification:missing:' || date_trunc('hour', p_run_at)::text, 0)
  );

  for tenant in
    select church.id, church.timezone
    from public.churches church
    where church.is_active and church.deleted_at is null
      and church.status in ('trial', 'active')
      and (p_church_ids is null or church.id = any(p_church_ids))
      and exists (select 1 from pg_catalog.pg_timezone_names timezone_name where timezone_name.name = church.timezone)
    order by church.id
  loop
    local_date := (p_run_at at time zone tenant.timezone)::date;
    local_hour := extract(hour from (p_run_at at time zone tenant.timezone))::integer;
    if local_hour < p_local_hour then continue; end if;
    tenant_count := tenant_count + 1;

    for missing in
      with target_period as (
        select period.*
        from public.statistic_periods period
        where period.church_id = tenant.id
          and period.submission_opens_at is not null
          and period.submission_due_at is not null
          and period.submission_opens_at <= p_run_at
          and period.submission_due_at >= p_run_at
        order by period.period_end desc, period.id
        limit 1
      )
      select ou.id as ou_id, ou.name as ou_name,
        period.id as period_id, period.label as period_label,
        period.submission_due_at
      from target_period period
      join public.organization_units ou
        on ou.church_id = period.church_id
       and ou.allow_data_entry
       and ou.is_active and ou.deleted_at is null
      where period.status = 'open'
        and not exists (
          select 1 from public.statistic_submissions submission
          where submission.church_id = tenant.id
            and submission.period_id = period.id
            and submission.ou_id = ou.id
            and submission.deleted_at is null
        )
      order by ou.path, ou.id
    loop
      ou_count := ou_count + 1;
      schedule_event_key := format(
        'missing:period:%s:ou:%s:window:%s',
        missing.period_id, missing.ou_id, to_char(local_date, 'YYYY-MM-DD')
      );

      for recipient in
        select distinct membership.user_id
        from public.organization_units assigned
        join public.ou_members assignment
          on assignment.church_id = assigned.church_id
         and assignment.ou_id = assigned.id
         and assignment.permission in ('data_entry', 'manager')
         and assignment.is_active and assignment.deleted_at is null
        join public.church_members membership
          on membership.church_id = assignment.church_id
         and membership.id = assignment.church_member_id
         and membership.status = 'active'
        join public.users app_user
          on app_user.id = membership.user_id
         and app_user.is_active and app_user.deleted_at is null
        join public.organization_units target
          on target.church_id = assigned.church_id and target.id = missing.ou_id
        where assigned.church_id = tenant.id
          and assigned.structure_root_id = target.structure_root_id
          and assigned.is_active and assigned.deleted_at is null
          and (
            (assignment.permission = 'data_entry' and assigned.id = target.id)
            or (
              assignment.permission = 'manager'
              and (target.path = assigned.path or target.path like assigned.path || '/%')
            )
          )
      loop
        if not exists (
          select 1 from public.notifications notification
          where notification.church_id = tenant.id
            and notification.recipient_user_id = recipient.user_id
            and notification.event_key = schedule_event_key
        ) then
          notification_id := app_security.enqueue_notification(
            tenant.id, recipient.user_id, 'missing_submission_reminder', schedule_event_key,
            'ยังไม่ได้ส่งรายงานประจำสัปดาห์',
            format(
              'กรุณาส่งรายงาน %s ของ %s ภายใน %s',
              missing.period_label,
              missing.ou_name,
              to_char(missing.submission_due_at at time zone tenant.timezone, 'DD/MM/YYYY HH24:MI')
            ),
            missing.ou_id,
            format('/app/submissions?periodId=%s&ouId=%s', missing.period_id, missing.ou_id),
            jsonb_build_object(
              'periodId', missing.period_id,
              'ouId', missing.ou_id,
              'reminderDate', to_char(local_date, 'YYYY-MM-DD'),
              'submissionDueAt', missing.submission_due_at
            ),
            true
          );
          if notification_id is not null then recipient_count := recipient_count + 1; end if;
        end if;
      end loop;
    end loop;

    if not exists (
      select 1 from public.audit_logs audit
      where audit.church_id = tenant.id
        and audit.entity_type = 'notification_schedule'
        and audit.action = 'scan_missing_submissions'
        and audit.metadata ->> 'localDate' = to_char(local_date, 'YYYY-MM-DD')
    ) then
      insert into public.audit_logs(church_id, entity_type, action, metadata)
      values (
        tenant.id, 'notification_schedule', 'scan_missing_submissions',
        jsonb_build_object('localDate', local_date, 'localHour', local_hour)
      );
    end if;
  end loop;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'tenantsScanned', tenant_count,
    'missingOus', ou_count,
    'notificationsCreated', recipient_count
  ));
end;
$$;

revoke all on function public.create_platform_tenant(jsonb) from public;
revoke all on function public.get_platform_tenant_detail(uuid) from public;
revoke all on function public.update_platform_tenant(uuid, jsonb) from public;
revoke all on function public.run_missing_submission_reminders(timestamptz, uuid[], integer) from public;
grant execute on function public.create_platform_tenant(jsonb) to authenticated;
grant execute on function public.get_platform_tenant_detail(uuid) to authenticated;
grant execute on function public.update_platform_tenant(uuid, jsonb) to authenticated;
grant execute on function public.run_missing_submission_reminders(timestamptz, uuid[], integer) to service_role;
