-- Notifications Stage E (NT-011 and NT-012): timezone-aware scheduled events.

create or replace function app_security.notification_can_approve_for_ou(
  p_church_member_id uuid,
  p_ou_id uuid
)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  target public.organization_units%rowtype;
  candidate record;
  nearest_approver_level integer;
begin
  select * into target
  from public.organization_units
  where id = p_ou_id and is_active and deleted_at is null;
  if target.id is null then return false; end if;

  select max(assigned.level) into nearest_approver_level
  from public.organization_units assigned
  join public.ou_members assignment
    on assignment.church_id = assigned.church_id and assignment.ou_id = assigned.id
  join public.church_members membership
    on membership.church_id = assignment.church_id
   and membership.id = assignment.church_member_id
   and membership.status = 'active'
  join public.users app_user
    on app_user.id = membership.user_id
   and app_user.is_active and app_user.deleted_at is null
  where assigned.church_id = target.church_id
    and assigned.structure_root_id = target.structure_root_id
    and (target.path = assigned.path or target.path like assigned.path || '/%')
    and assigned.is_active and assigned.deleted_at is null
    and assignment.permission = 'approver'
    and assignment.is_active and assignment.deleted_at is null;

  select
    assignment.permission,
    assignment.can_override,
    assigned.level,
    assigned.parent_id
  into candidate
  from public.organization_units assigned
  join public.ou_members assignment
    on assignment.church_id = assigned.church_id and assignment.ou_id = assigned.id
  where assigned.church_id = target.church_id
    and assigned.structure_root_id = target.structure_root_id
    and (target.path = assigned.path or target.path like assigned.path || '/%')
    and assigned.is_active and assigned.deleted_at is null
    and assignment.church_member_id = p_church_member_id
    and assignment.permission in ('admin', 'approver')
    and assignment.is_active and assignment.deleted_at is null
  order by assigned.level desc,
    case assignment.permission when 'admin' then 0 else 1 end,
    assignment.assigned_at desc
  limit 1;

  if candidate.permission is null then return false; end if;
  if candidate.permission = 'admin' then
    return nearest_approver_level is not null or candidate.parent_id is null;
  end if;
  return candidate.level = nearest_approver_level or candidate.can_override;
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
      and exists (
        select 1 from pg_catalog.pg_timezone_names timezone_name
        where timezone_name.name = church.timezone
      )
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
          and period.period_end <= local_date
        order by period.period_end desc, period.id
        limit 1
      )
      select ou.id as ou_id, ou.name as ou_name,
        period.id as period_id, period.label as period_label
      from target_period period
      join public.organization_units ou
        on ou.church_id = period.church_id
       and ou.allow_data_entry
       and ou.is_active and ou.deleted_at is null
      where period.status = 'open'
        and not exists (
        select 1
        from public.statistic_submissions submission
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
            format('กรุณาส่งรายงาน %s ของ %s', missing.period_label, missing.ou_name),
            missing.ou_id,
            format('/app/submissions?periodId=%s&ouId=%s', missing.period_id, missing.ou_id),
            jsonb_build_object(
              'periodId', missing.period_id,
              'ouId', missing.ou_id,
              'reminderDate', to_char(local_date, 'YYYY-MM-DD')
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

  return jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'tenantsScanned', tenant_count,
      'missingOus', ou_count,
      'notificationsCreated', recipient_count
    )
  );
end;
$$;

create or replace function public.run_pending_approval_digests(
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
  recipient record;
  notification_id uuid;
  schedule_event_key text;
  local_date date;
  local_hour integer;
  tenant_count integer := 0;
  notification_count integer := 0;
begin
  if p_run_at is null or p_local_hour < 0 or p_local_hour > 23 then
    raise exception 'INVALID_NOTIFICATION_SCHEDULE';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('notification:approval:' || date_trunc('hour', p_run_at)::text, 0)
  );

  for tenant in
    select church.id, church.timezone
    from public.churches church
    where church.is_active and church.deleted_at is null
      and church.status in ('trial', 'active')
      and church.approval_mode = 'approval_required'
      and (p_church_ids is null or church.id = any(p_church_ids))
      and exists (
        select 1 from pg_catalog.pg_timezone_names timezone_name
        where timezone_name.name = church.timezone
      )
    order by church.id
  loop
    local_date := (p_run_at at time zone tenant.timezone)::date;
    local_hour := extract(hour from (p_run_at at time zone tenant.timezone))::integer;
    if local_hour < p_local_hour then continue; end if;
    tenant_count := tenant_count + 1;
    schedule_event_key := format('approval-digest:window:%s', to_char(local_date, 'YYYY-MM-DD'));

    for recipient in
      select membership.user_id, count(distinct submission.id)::integer as pending_count
      from public.church_members membership
      join public.users app_user
        on app_user.id = membership.user_id
       and app_user.is_active and app_user.deleted_at is null
      join public.statistic_submissions submission
        on submission.church_id = membership.church_id
       and submission.status = 'submitted'
       and submission.deleted_at is null
      join public.organization_units ou
        on ou.church_id = submission.church_id and ou.id = submission.ou_id
       and ou.is_active and ou.deleted_at is null
      where membership.church_id = tenant.id
        and membership.status = 'active'
        and app_security.notification_can_approve_for_ou(membership.id, submission.ou_id)
      group by membership.user_id
      order by membership.user_id
    loop
      if not exists (
        select 1 from public.notifications notification
        where notification.church_id = tenant.id
          and notification.recipient_user_id = recipient.user_id
          and notification.event_key = schedule_event_key
      ) then
        notification_id := app_security.enqueue_notification(
          tenant.id, recipient.user_id, 'pending_approval_digest', schedule_event_key,
          'มีรายงานรออนุมัติ',
          format('มีรายงาน %s รายการที่รอการตรวจสอบและอนุมัติ', recipient.pending_count),
          null, '/app/approval',
          jsonb_build_object(
            'pendingCount', recipient.pending_count,
            'digestDate', to_char(local_date, 'YYYY-MM-DD')
          ),
          true
        );
        if notification_id is not null then notification_count := notification_count + 1; end if;
      end if;
    end loop;

    if not exists (
      select 1 from public.audit_logs audit
      where audit.church_id = tenant.id
        and audit.entity_type = 'notification_schedule'
        and audit.action = 'send_pending_approval_digest'
        and audit.metadata ->> 'localDate' = to_char(local_date, 'YYYY-MM-DD')
    ) then
      insert into public.audit_logs(church_id, entity_type, action, metadata)
      values (
        tenant.id, 'notification_schedule', 'send_pending_approval_digest',
        jsonb_build_object('localDate', local_date, 'localHour', local_hour)
      );
    end if;
  end loop;

  return jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'tenantsScanned', tenant_count,
      'notificationsCreated', notification_count
    )
  );
end;
$$;

revoke all on function app_security.notification_can_approve_for_ou(uuid, uuid) from public;
revoke all on function public.run_missing_submission_reminders(timestamptz, uuid[], integer) from public;
revoke all on function public.run_pending_approval_digests(timestamptz, uuid[], integer) from public;
grant execute on function public.run_missing_submission_reminders(timestamptz, uuid[], integer) to service_role;
grant execute on function public.run_pending_approval_digests(timestamptz, uuid[], integer) to service_role;
