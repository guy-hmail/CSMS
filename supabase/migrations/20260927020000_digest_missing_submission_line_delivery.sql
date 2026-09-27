-- Keep detailed missing-submission notifications in-app, but send at most one
-- consolidated LINE reminder to each eligible recipient per local day.
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
  digest_count integer := 0;
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

    -- Detailed notifications remain available in-app for each missing OU. LINE
    -- delivery is deliberately disabled here and is enqueued as a digest below.
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
            false
          );
          if notification_id is not null then recipient_count := recipient_count + 1; end if;
        end if;
      end loop;
    end loop;

    -- Aggregate the same recipient scope so one durable LINE outbox item covers
    -- every missing OU visible to that recipient for this local day.
    for recipient in
      with target_period as (
        select period.*
        from public.statistic_periods period
        where period.church_id = tenant.id
          and period.period_end <= local_date
        order by period.period_end desc, period.id
        limit 1
      ), missing_ous as (
        select ou.id as ou_id, ou.path, ou.structure_root_id,
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
      ), recipient_missing_ous as (
        select distinct membership.user_id, missing_ou.ou_id,
          missing_ou.period_id, missing_ou.period_label
        from missing_ous missing_ou
        join public.organization_units assigned
          on assigned.church_id = tenant.id
         and assigned.structure_root_id = missing_ou.structure_root_id
         and assigned.is_active and assigned.deleted_at is null
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
        where (assignment.permission = 'data_entry' and assigned.id = missing_ou.ou_id)
           or (
             assignment.permission = 'manager'
             and (missing_ou.path = assigned.path or missing_ou.path like assigned.path || '/%')
           )
      )
      select user_id, period_id, period_label, count(*)::integer as missing_count,
        array_agg(ou_id order by ou_id) as ou_ids
      from recipient_missing_ous
      group by user_id, period_id, period_label
      order by user_id
    loop
      if coalesce((app_security.resolve_notification_recipient(
        tenant.id, recipient.user_id, 'missing_submission_reminder', null
      ) ->> 'lineEligible')::boolean, false) then
        if recipient.missing_count = 1 then
          insert into public.notification_deliveries (
            church_id, notification_id, channel, status, next_attempt_at
          )
          select tenant.id, notification.id, 'line', 'pending', now()
          from public.notifications notification
          where notification.church_id = tenant.id
            and notification.recipient_user_id = recipient.user_id
            and notification.event_key = format(
              'missing:period:%s:ou:%s:window:%s',
              recipient.period_id, (recipient.ou_ids)[1], to_char(local_date, 'YYYY-MM-DD')
            )
          on conflict (notification_id, channel) do nothing;
        else
          schedule_event_key := format(
            'missing-digest:period:%s:window:%s',
            recipient.period_id, to_char(local_date, 'YYYY-MM-DD')
          );

          if not exists (
            select 1 from public.notifications notification
            where notification.church_id = tenant.id
              and notification.recipient_user_id = recipient.user_id
              and notification.event_key = schedule_event_key
          ) then
            notification_id := app_security.enqueue_notification(
              tenant.id, recipient.user_id, 'missing_submission_reminder', schedule_event_key,
              'สรุปรายงานประจำสัปดาห์ที่ยังไม่ได้ส่ง',
              format('มี %s หน่วยงานที่ยังไม่ได้ส่งรายงาน %s', recipient.missing_count, recipient.period_label),
              null,
              format('/app/submissions?periodId=%s', recipient.period_id),
              jsonb_build_object(
                'periodId', recipient.period_id,
                'missingOuCount', recipient.missing_count,
                'reminderDate', to_char(local_date, 'YYYY-MM-DD'),
                'deliveryMode', 'digest'
              ),
              true
            );
            if notification_id is not null then digest_count := digest_count + 1; end if;
          end if;
        end if;
      end if;
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
      'notificationsCreated', recipient_count,
      'lineDigestsCreated', digest_count
    )
  );
end;
$$;

revoke all on function public.run_missing_submission_reminders(timestamptz, uuid[], integer) from public;
grant execute on function public.run_missing_submission_reminders(timestamptz, uuid[], integer) to service_role;
