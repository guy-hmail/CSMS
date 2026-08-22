-- Notifications Stage F (NT-014): privacy-minimized operations visibility.

create or replace function public.get_platform_notification_operations(
  p_tenant_id uuid,
  p_window_hours integer default 24
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  window_start timestamptz;
  result jsonb;
begin
  perform app_security.require_system_admin();
  if p_tenant_id is null then raise exception 'TENANT_REQUIRED'; end if;
  if p_window_hours is null or p_window_hours < 1 or p_window_hours > 720 then
    raise exception 'INVALID_OPERATIONS_WINDOW';
  end if;
  if not exists (
    select 1 from public.churches church
    where church.id = p_tenant_id and church.deleted_at is null
  ) then raise exception 'TENANT_NOT_FOUND'; end if;

  window_start := now() - make_interval(hours => p_window_hours);

  with delivery_metrics as (
    select
      count(*) filter (where delivery.status = 'pending')::integer as pending_count,
      count(*) filter (where delivery.status = 'processing')::integer as processing_count,
      count(*) filter (where delivery.status = 'failed')::integer as retryable_failed_count,
      count(*) filter (where delivery.status = 'dead_letter')::integer as dead_letter_count,
      count(*) filter (
        where delivery.status = 'processing'
          and delivery.processing_started_at < now() - interval '10 minutes'
      )::integer as stale_processing_count,
      min(delivery.created_at) filter (
        where delivery.status in ('pending', 'processing', 'failed')
      ) as oldest_queued_at,
      count(*) filter (where delivery.created_at >= window_start)::integer as deliveries_created,
      count(*) filter (
        where delivery.status = 'sent' and delivery.sent_at >= window_start
      )::integer as sent_count,
      count(*) filter (
        where delivery.status = 'dead_letter' and delivery.updated_at >= window_start
      )::integer as dead_letter_window_count
    from public.notification_deliveries delivery
    where delivery.church_id = p_tenant_id
  ), event_metrics as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'eventType', grouped.event_type,
      'notificationCount', grouped.notification_count,
      'deliveryCount', grouped.delivery_count
    ) order by grouped.notification_count desc, grouped.event_type), '[]'::jsonb) as events
    from (
      select notification.event_type,
        count(distinct notification.id)::integer as notification_count,
        count(distinct delivery.id)::integer as delivery_count
      from public.notifications notification
      left join public.notification_deliveries delivery
        on delivery.church_id = notification.church_id
       and delivery.notification_id = notification.id
      where notification.church_id = p_tenant_id
        and notification.created_at >= window_start
      group by notification.event_type
    ) grouped
  ), recent_dead_letters as (
    select coalesce(jsonb_agg(jsonb_build_object(
      'deliveryId', recent.delivery_id,
      'notificationId', recent.notification_id,
      'eventType', recent.event_type,
      'attemptCount', recent.attempt_count,
      'deliveryCycle', recent.delivery_cycle,
      'errorCode', recent.error_code,
      'updatedAt', recent.updated_at
    ) order by recent.updated_at desc), '[]'::jsonb) as deliveries
    from (
      select delivery.id as delivery_id,
        delivery.notification_id,
        notification.event_type,
        delivery.attempt_count,
        delivery.delivery_cycle,
        delivery.last_error_code as error_code,
        delivery.updated_at
      from public.notification_deliveries delivery
      join public.notifications notification
        on notification.church_id = delivery.church_id
       and notification.id = delivery.notification_id
      where delivery.church_id = p_tenant_id
        and delivery.status = 'dead_letter'
      order by delivery.updated_at desc
      limit 20
    ) recent
  ), attempt_metrics as (
    select
      count(*) filter (where attempt.outcome = 'retryable_failure')::integer as retryable_attempts,
      count(*) filter (where attempt.outcome = 'permanent_failure')::integer as permanent_attempts,
      count(*) filter (where attempt.outcome = 'stale_recovered')::integer as stale_recoveries
    from public.notification_delivery_attempts attempt
    where attempt.church_id = p_tenant_id
      and attempt.completed_at >= window_start
  )
  select jsonb_build_object(
    'tenantId', p_tenant_id,
    'windowHours', p_window_hours,
    'generatedAt', now(),
    'summary', jsonb_build_object(
      'notificationsCreated', (
        select count(*)::integer from public.notifications notification
        where notification.church_id = p_tenant_id
          and notification.created_at >= window_start
      ),
      'deliveriesCreated', delivery_metrics.deliveries_created,
      'pending', delivery_metrics.pending_count,
      'processing', delivery_metrics.processing_count,
      'retryableFailed', delivery_metrics.retryable_failed_count,
      'deadLetter', delivery_metrics.dead_letter_count,
      'staleProcessing', delivery_metrics.stale_processing_count,
      'oldestQueuedAt', delivery_metrics.oldest_queued_at,
      'sentInWindow', delivery_metrics.sent_count,
      'deadLetterInWindow', delivery_metrics.dead_letter_window_count,
      'successRate', case
        when delivery_metrics.sent_count + delivery_metrics.dead_letter_window_count = 0 then 0
        else round(
          delivery_metrics.sent_count::numeric * 100
          / (delivery_metrics.sent_count + delivery_metrics.dead_letter_window_count), 2
        )
      end,
      'failureRate', case
        when delivery_metrics.sent_count + delivery_metrics.dead_letter_window_count = 0 then 0
        else round(
          delivery_metrics.dead_letter_window_count::numeric * 100
          / (delivery_metrics.sent_count + delivery_metrics.dead_letter_window_count), 2
        )
      end,
      'retryableAttempts', attempt_metrics.retryable_attempts,
      'permanentAttempts', attempt_metrics.permanent_attempts,
      'staleRecoveries', attempt_metrics.stale_recoveries
    ),
    'events', event_metrics.events,
    'recentDeadLetters', recent_dead_letters.deliveries
  ) into result
  from delivery_metrics, event_metrics, recent_dead_letters, attempt_metrics;

  return result;
end;
$$;

revoke all on function public.get_platform_notification_operations(uuid, integer) from public;
grant execute on function public.get_platform_notification_operations(uuid, integer) to authenticated;
