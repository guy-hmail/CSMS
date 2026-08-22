-- Notifications Stage D (NT-009 and NT-010): bounded LINE queue delivery.

alter table public.notification_deliveries
  add column delivery_cycle integer not null default 0,
  add constraint ck_notification_delivery_cycle check (delivery_cycle >= 0),
  add constraint uq_notification_delivery_church_id unique (church_id, id);

create table public.notification_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  church_id uuid not null references public.churches(id),
  delivery_id uuid not null,
  delivery_cycle integer not null,
  attempt_no integer not null,
  outcome varchar(30) not null,
  provider_message_id varchar(255),
  error_code varchar(100),
  error_message text,
  started_at timestamptz not null,
  completed_at timestamptz not null default now(),
  constraint fk_notification_attempt_delivery_same_church
    foreign key (church_id, delivery_id)
    references public.notification_deliveries(church_id, id)
    on delete cascade,
  constraint uq_notification_delivery_attempt
    unique (delivery_id, delivery_cycle, attempt_no),
  constraint ck_notification_attempt_cycle check (delivery_cycle >= 0),
  constraint ck_notification_attempt_no check (attempt_no between 1 and 3),
  constraint ck_notification_attempt_outcome check (
    outcome in ('sent', 'retryable_failure', 'permanent_failure', 'stale_recovered')
  ),
  constraint ck_notification_attempt_error_length check (
    error_message is null or length(error_message) <= 1000
  ),
  constraint ck_notification_attempt_time check (completed_at >= started_at)
);

create index idx_notification_delivery_attempts_delivery
  on public.notification_delivery_attempts(delivery_id, delivery_cycle, attempt_no);

alter table public.notification_delivery_attempts enable row level security;
alter table public.notification_delivery_attempts force row level security;

create policy notification_delivery_attempts_select_denied
on public.notification_delivery_attempts for select to authenticated using (false);
create policy notification_delivery_attempts_insert_denied
on public.notification_delivery_attempts for insert to authenticated with check (false);
create policy notification_delivery_attempts_update_denied
on public.notification_delivery_attempts for update to authenticated using (false) with check (false);
create policy notification_delivery_attempts_delete_denied
on public.notification_delivery_attempts for delete to authenticated using (false);

create or replace function app_security.sanitize_delivery_error(p_value text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  cleaned text := nullif(trim(coalesce(p_value, '')), '');
begin
  if cleaned is null then return null; end if;
  if lower(cleaned) ~ '(authorization|bearer|access.?token|channel.?secret|line_user_id|provider_credential)' then
    return 'Provider error details redacted.';
  end if;
  return left(regexp_replace(cleaned, '[\r\n\t]+', ' ', 'g'), 1000);
end;
$$;

create or replace function public.claim_line_notification_deliveries(
  p_limit integer default 20,
  p_church_ids uuid[] default null
)
returns table (
  delivery_id uuid,
  church_id uuid,
  notification_id uuid,
  delivery_cycle integer,
  attempt_count integer,
  line_user_id text,
  title text,
  body text,
  deep_link text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  candidate record;
  resolution jsonb;
begin
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    raise exception 'INVALID_DELIVERY_CLAIM_LIMIT';
  end if;

  for candidate in
    select
      delivery.id as candidate_delivery_id,
      delivery.church_id as candidate_church_id,
      delivery.notification_id as candidate_notification_id,
      delivery.delivery_cycle as candidate_cycle,
      delivery.attempt_count as candidate_attempt_count,
      delivery.status as candidate_status,
      delivery.processing_started_at as candidate_processing_started_at,
      notification.recipient_user_id,
      notification.event_type,
      notification.ou_id,
      notification.title as notification_title,
      notification.body as notification_body,
      notification.deep_link as notification_deep_link,
      app_user.line_user_id as recipient_line_user_id
    from public.notification_deliveries delivery
    join public.notifications notification
      on notification.church_id = delivery.church_id
     and notification.id = delivery.notification_id
    join public.users app_user on app_user.id = notification.recipient_user_id
    where delivery.channel = 'line'
      and (p_church_ids is null or delivery.church_id = any(p_church_ids))
      and (
        (delivery.status in ('pending', 'failed') and delivery.next_attempt_at <= now())
        or (
          delivery.status = 'processing'
          and delivery.processing_started_at < now() - interval '10 minutes'
        )
      )
    order by delivery.next_attempt_at, delivery.created_at, delivery.id
    for update of delivery skip locked
    limit p_limit
  loop
    if candidate.candidate_status = 'processing' then
      insert into public.notification_delivery_attempts(
        church_id, delivery_id, delivery_cycle, attempt_no, outcome,
        error_code, error_message, started_at
      ) values (
        candidate.candidate_church_id,
        candidate.candidate_delivery_id,
        candidate.candidate_cycle,
        candidate.candidate_attempt_count,
        'stale_recovered',
        'WORKER_LEASE_EXPIRED',
        'The previous delivery worker lease expired.',
        candidate.candidate_processing_started_at
      ) on conflict on constraint uq_notification_delivery_attempt do nothing;

      if candidate.candidate_attempt_count >= 3 then
        update public.notification_deliveries
        set status = 'dead_letter',
            processing_started_at = null,
            last_error_code = 'WORKER_LEASE_EXPIRED',
            last_error_message = 'The final delivery worker lease expired.',
            updated_at = now()
        where id = candidate.candidate_delivery_id;
        continue;
      end if;
    end if;

    resolution := app_security.resolve_notification_recipient(
      candidate.candidate_church_id,
      candidate.recipient_user_id,
      candidate.event_type,
      candidate.ou_id
    );

    if not coalesce((resolution ->> 'eligible')::boolean, false)
       or not coalesce((resolution ->> 'lineEligible')::boolean, false)
       or nullif(trim(candidate.recipient_line_user_id), '') is null then
      update public.notification_deliveries
      set status = 'dead_letter',
          processing_started_at = null,
          last_error_code = 'RECIPIENT_INELIGIBLE',
          last_error_message = 'Recipient is no longer eligible for LINE delivery.',
          updated_at = now()
      where id = candidate.candidate_delivery_id;
      continue;
    end if;

    update public.notification_deliveries
    set status = 'processing',
        attempt_count = candidate.candidate_attempt_count + 1,
        processing_started_at = now(),
        provider_message_id = null,
        last_error_code = null,
        last_error_message = null,
        updated_at = now()
    where id = candidate.candidate_delivery_id;

    delivery_id := candidate.candidate_delivery_id;
    church_id := candidate.candidate_church_id;
    notification_id := candidate.candidate_notification_id;
    delivery_cycle := candidate.candidate_cycle;
    attempt_count := candidate.candidate_attempt_count + 1;
    line_user_id := candidate.recipient_line_user_id;
    title := candidate.notification_title;
    body := candidate.notification_body;
    deep_link := candidate.notification_deep_link;
    return next;
  end loop;
end;
$$;

create or replace function public.complete_line_notification_delivery(
  p_delivery_id uuid,
  p_delivery_cycle integer,
  p_attempt_count integer,
  p_outcome text,
  p_provider_message_id text default null,
  p_error_code text default null,
  p_error_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  delivery public.notification_deliveries%rowtype;
  next_status text;
  safe_provider_id text;
  safe_error_code text;
  safe_error_message text;
  next_attempt timestamptz;
begin
  if p_outcome not in ('sent', 'retryable_failure', 'permanent_failure') then
    raise exception 'INVALID_DELIVERY_OUTCOME';
  end if;
  if p_attempt_count is null or p_attempt_count < 1 or p_attempt_count > 3
     or p_delivery_cycle is null or p_delivery_cycle < 0 then
    raise exception 'INVALID_DELIVERY_ATTEMPT';
  end if;

  select * into delivery
  from public.notification_deliveries
  where id = p_delivery_id
  for update;

  if delivery.id is null then raise exception 'DELIVERY_NOT_FOUND'; end if;
  if delivery.status <> 'processing'
     or delivery.delivery_cycle <> p_delivery_cycle
     or delivery.attempt_count <> p_attempt_count then
    raise exception 'STALE_DELIVERY_COMPLETION';
  end if;

  safe_provider_id := nullif(left(regexp_replace(
    coalesce(p_provider_message_id, ''), '[^A-Za-z0-9._:-]+', '', 'g'
  ), 255), '');
  safe_error_code := nullif(left(upper(regexp_replace(
    coalesce(p_error_code, ''), '[^A-Za-z0-9_:-]+', '_', 'g'
  )), 100), '');
  safe_error_message := app_security.sanitize_delivery_error(p_error_message);

  if p_outcome = 'sent' then
    next_status := 'sent';
    next_attempt := delivery.next_attempt_at;
  elsif p_outcome = 'permanent_failure' or delivery.attempt_count >= 3 then
    next_status := 'dead_letter';
    next_attempt := delivery.next_attempt_at;
  else
    next_status := 'failed';
    next_attempt := case delivery.attempt_count
      when 1 then now() + interval '30 minutes'
      when 2 then now() + interval '2 hours'
      else now()
    end;
  end if;

  insert into public.notification_delivery_attempts(
    church_id, delivery_id, delivery_cycle, attempt_no, outcome,
    provider_message_id, error_code, error_message, started_at
  ) values (
    delivery.church_id,
    delivery.id,
    delivery.delivery_cycle,
    delivery.attempt_count,
    case
      when p_outcome = 'sent' then 'sent'
      when p_outcome = 'permanent_failure' then 'permanent_failure'
      else 'retryable_failure'
    end,
    safe_provider_id,
    safe_error_code,
    safe_error_message,
    delivery.processing_started_at
  ) on conflict (delivery_id, delivery_cycle, attempt_no) do update
    set outcome = excluded.outcome,
        provider_message_id = excluded.provider_message_id,
        error_code = excluded.error_code,
        error_message = excluded.error_message,
        completed_at = now();

  update public.notification_deliveries
  set status = next_status,
      next_attempt_at = next_attempt,
      processing_started_at = null,
      sent_at = case when next_status = 'sent' then now() else null end,
      provider_message_id = case when next_status = 'sent' then safe_provider_id else null end,
      last_error_code = case when next_status = 'sent' then null else coalesce(safe_error_code, 'DELIVERY_FAILED') end,
      last_error_message = case when next_status = 'sent' then null else coalesce(safe_error_message, 'LINE delivery failed.') end,
      updated_at = now()
  where id = delivery.id;

  return jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'deliveryId', delivery.id,
      'status', next_status,
      'attemptCount', delivery.attempt_count,
      'deliveryCycle', delivery.delivery_cycle,
      'nextAttemptAt', case when next_status = 'failed' then next_attempt else null end
    )
  );
end;
$$;

create or replace function public.replay_line_notification_delivery(p_delivery_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  delivery public.notification_deliveries%rowtype;
begin
  select * into delivery
  from public.notification_deliveries
  where id = p_delivery_id
  for update;

  if delivery.id is null then raise exception 'DELIVERY_NOT_FOUND'; end if;
  if delivery.status not in ('failed', 'dead_letter') then
    raise exception 'DELIVERY_NOT_REPLAYABLE';
  end if;

  update public.notification_deliveries
  set status = 'pending',
      delivery_cycle = delivery_cycle + 1,
      attempt_count = 0,
      next_attempt_at = now(),
      processing_started_at = null,
      sent_at = null,
      provider_message_id = null,
      last_error_code = null,
      last_error_message = null,
      updated_at = now()
  where id = delivery.id;

  insert into public.audit_logs(
    church_id, entity_type, entity_id, action, metadata
  ) values (
    delivery.church_id,
    'notification_deliveries',
    delivery.id,
    'replay_line_notification_delivery',
    jsonb_build_object(
      'previousStatus', delivery.status,
      'previousAttemptCount', delivery.attempt_count,
      'previousDeliveryCycle', delivery.delivery_cycle
    )
  );

  return jsonb_build_object(
    'success', true,
    'data', jsonb_build_object(
      'deliveryId', delivery.id,
      'status', 'pending',
      'deliveryCycle', delivery.delivery_cycle + 1
    )
  );
end;
$$;

revoke all on function app_security.sanitize_delivery_error(text) from public;
revoke all on function public.claim_line_notification_deliveries(integer, uuid[]) from public;
revoke all on function public.complete_line_notification_delivery(uuid, integer, integer, text, text, text, text) from public;
revoke all on function public.replay_line_notification_delivery(uuid) from public;

revoke all on public.notification_delivery_attempts from authenticated;
grant select, insert, update, delete on public.notification_delivery_attempts to service_role;
grant execute on function public.claim_line_notification_deliveries(integer, uuid[]) to service_role;
grant execute on function public.complete_line_notification_delivery(uuid, integer, integer, text, text, text, text) to service_role;
grant execute on function public.replay_line_notification_delivery(uuid) to service_role;
