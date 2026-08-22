-- Notifications Stage A (NT-002 through NT-005): tenant-safe in-app source of truth.
-- LINE provider access is intentionally absent from this migration.

create or replace function app_security.notification_payload_is_safe(p_payload jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  entry record;
begin
  if p_payload is null then return false; end if;
  if jsonb_typeof(p_payload) = 'object' then
    for entry in select key, value from jsonb_each(p_payload)
    loop
      if lower(entry.key) ~ '(token|secret|password|authorization|line_user_id|provider_credential)' then
        return false;
      end if;
      if not app_security.notification_payload_is_safe(entry.value) then return false; end if;
    end loop;
  elsif jsonb_typeof(p_payload) = 'array' then
    for entry in select value from jsonb_array_elements(p_payload)
    loop
      if not app_security.notification_payload_is_safe(entry.value) then return false; end if;
    end loop;
  end if;
  return true;
end;
$$;

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  church_id uuid not null references public.churches(id),
  recipient_user_id uuid not null references public.users(id),
  ou_id uuid,
  event_type varchar(80) not null,
  event_key varchar(255) not null,
  title text not null,
  body text not null,
  deep_link text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  archived_at timestamptz,
  constraint uq_notification_church_id unique (church_id, id),
  constraint uq_notification_event_recipient unique (church_id, recipient_user_id, event_key),
  constraint fk_notification_recipient_membership
    foreign key (church_id, recipient_user_id)
    references public.church_members(church_id, user_id),
  constraint fk_notification_ou_same_church
    foreign key (church_id, ou_id)
    references public.organization_units(church_id, id),
  constraint ck_notification_event_type check (event_type in (
    'submission_submitted', 'submission_approved', 'submission_returned',
    'edit_request_created', 'edit_request_resolved', 'ou_assignment_created',
    'missing_submission_reminder', 'pending_approval_digest'
  )),
  constraint ck_notification_event_key check (
    length(trim(event_key)) between 3 and 255
    and event_key ~ '^[a-z0-9][a-z0-9:_./-]+$'
  ),
  constraint ck_notification_title check (length(trim(title)) between 1 and 200),
  constraint ck_notification_body check (length(trim(body)) between 1 and 2000),
  constraint ck_notification_deep_link check (
    deep_link is null
    or (deep_link ~ '^/app(/|$)' and deep_link !~ '://' and length(deep_link) <= 500)
  ),
  constraint ck_notification_payload_object check (
    jsonb_typeof(payload) = 'object'
    and app_security.notification_payload_is_safe(payload)
  ),
  constraint ck_notification_read_time check (read_at is null or read_at >= created_at),
  constraint ck_notification_archive_time check (archived_at is null or archived_at >= created_at)
);

create table public.notification_deliveries (
  id uuid primary key default gen_random_uuid(),
  church_id uuid not null references public.churches(id),
  notification_id uuid not null,
  channel varchar(20) not null,
  status varchar(20) not null default 'pending',
  attempt_count integer not null default 0,
  next_attempt_at timestamptz not null default now(),
  processing_started_at timestamptz,
  sent_at timestamptz,
  provider_message_id varchar(255),
  last_error_code varchar(100),
  last_error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint uq_notification_delivery_channel unique (notification_id, channel),
  constraint fk_notification_delivery_same_church
    foreign key (church_id, notification_id)
    references public.notifications(church_id, id)
    on delete cascade,
  constraint ck_notification_delivery_channel check (channel = 'line'),
  constraint ck_notification_delivery_status check (
    status in ('pending', 'processing', 'sent', 'failed', 'dead_letter')
  ),
  constraint ck_notification_delivery_attempts check (attempt_count between 0 and 3),
  constraint ck_notification_delivery_sent check (
    (status = 'sent' and sent_at is not null) or (status <> 'sent' and sent_at is null)
  ),
  constraint ck_notification_delivery_error_length check (
    last_error_message is null or length(last_error_message) <= 1000
  )
);

create index idx_notifications_recipient_feed
  on public.notifications(church_id, recipient_user_id, created_at desc, id desc)
  where archived_at is null;
create index idx_notifications_recipient_unread
  on public.notifications(church_id, recipient_user_id, created_at desc)
  where read_at is null and archived_at is null;
create index idx_notifications_ou
  on public.notifications(church_id, ou_id, created_at desc)
  where ou_id is not null;
create index idx_notification_deliveries_claim
  on public.notification_deliveries(status, next_attempt_at, created_at)
  where status in ('pending', 'failed');
create index idx_notification_deliveries_stale_processing
  on public.notification_deliveries(processing_started_at)
  where status = 'processing';

alter table public.notifications enable row level security;
alter table public.notification_deliveries enable row level security;
alter table public.notifications force row level security;
alter table public.notification_deliveries force row level security;

create policy notifications_select_own_active_tenant
on public.notifications for select to authenticated
using (
  church_id = app_security.current_church_id()
  and recipient_user_id = app_security.current_user_id()
);
create policy notifications_insert_denied
on public.notifications for insert to authenticated with check (false);
create policy notifications_update_denied
on public.notifications for update to authenticated using (false) with check (false);
create policy notifications_delete_denied
on public.notifications for delete to authenticated using (false);

create policy notification_deliveries_select_denied
on public.notification_deliveries for select to authenticated using (false);
create policy notification_deliveries_insert_denied
on public.notification_deliveries for insert to authenticated with check (false);
create policy notification_deliveries_update_denied
on public.notification_deliveries for update to authenticated using (false) with check (false);
create policy notification_deliveries_delete_denied
on public.notification_deliveries for delete to authenticated using (false);

-- Internal recipient resolver. It never returns the LINE user ID and is not
-- executable by browser roles. OU scope is validated against active assignments.
create or replace function app_security.resolve_notification_recipient(
  p_church_id uuid,
  p_recipient_user_id uuid,
  p_event_type text,
  p_ou_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  membership_id uuid;
  preference public.user_preferences%rowtype;
  preference_key text;
  preference_enabled boolean := true;
  scoped boolean := true;
  has_line_identity boolean := false;
begin
  if p_event_type is null or p_event_type not in (
    'submission_submitted', 'submission_approved', 'submission_returned',
    'edit_request_created', 'edit_request_resolved', 'ou_assignment_created',
    'missing_submission_reminder', 'pending_approval_digest'
  ) then raise exception 'INVALID_NOTIFICATION_EVENT'; end if;

  select membership.id, nullif(trim(app_user.line_user_id), '') is not null
  into membership_id, has_line_identity
  from public.church_members membership
  join public.users app_user on app_user.id = membership.user_id
  join public.churches church on church.id = membership.church_id
  where membership.church_id = p_church_id
    and membership.user_id = p_recipient_user_id
    and membership.status = 'active'
    and app_user.is_active and app_user.deleted_at is null
    and church.is_active and church.deleted_at is null
  limit 1;

  if membership_id is null then
    return jsonb_build_object('eligible', false, 'lineEligible', false, 'reason', 'inactive_membership');
  end if;

  if p_ou_id is not null then
    select exists (
      select 1
      from public.organization_units target
      join public.ou_members assignment
        on assignment.church_id = target.church_id
       and assignment.church_member_id = membership_id
       and assignment.is_active and assignment.deleted_at is null
      join public.organization_units assigned
        on assigned.church_id = assignment.church_id and assigned.id = assignment.ou_id
       and assigned.is_active and assigned.deleted_at is null
      where target.church_id = p_church_id and target.id = p_ou_id
        and target.is_active and target.deleted_at is null
        and (target.path = assigned.path or target.path like assigned.path || '/%')
    ) into scoped;
  end if;

  if not scoped then
    return jsonb_build_object('eligible', false, 'lineEligible', false, 'reason', 'recipient_out_of_scope');
  end if;

  select * into preference from public.user_preferences
  where church_id = p_church_id and church_member_id = membership_id;

  case
    when p_event_type = 'submission_submitted' then
      preference_key := 'notify_submitted';
      preference_enabled := coalesce(preference.notify_submitted, true);
    when p_event_type = 'missing_submission_reminder' then
      preference_key := 'notify_missing';
      preference_enabled := coalesce(preference.notify_missing, true);
    when p_event_type in (
      'submission_approved', 'submission_returned', 'edit_request_created',
      'edit_request_resolved', 'pending_approval_digest'
    ) then
      preference_key := 'notify_approval';
      preference_enabled := coalesce(preference.notify_approval, true);
    else
      preference_key := null;
      preference_enabled := true;
  end case;

  return jsonb_build_object(
    'eligible', true,
    'lineEligible', preference_enabled and has_line_identity,
    'preferenceKey', preference_key,
    'preferenceEnabled', preference_enabled
  );
end;
$$;

-- Internal transactional enqueue/outbox helper. Calling business RPCs supply
-- server-resolved tenant/recipient values. Stage A callers keep p_enqueue_line=false.
create or replace function app_security.enqueue_notification(
  p_church_id uuid,
  p_recipient_user_id uuid,
  p_event_type text,
  p_event_key text,
  p_title text,
  p_body text,
  p_ou_id uuid default null,
  p_deep_link text default null,
  p_payload jsonb default '{}'::jsonb,
  p_enqueue_line boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  resolution jsonb;
  saved_notification_id uuid;
begin
  if p_church_id is null or p_recipient_user_id is null then raise exception 'NOTIFICATION_SCOPE_REQUIRED'; end if;
  if p_event_key is null or p_title is null or p_body is null then raise exception 'INVALID_NOTIFICATION_PAYLOAD'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object'
     or not app_security.notification_payload_is_safe(p_payload) then
    raise exception 'UNSAFE_NOTIFICATION_PAYLOAD';
  end if;
  if p_deep_link is not null and (p_deep_link !~ '^/app(/|$)' or p_deep_link ~ '://' or length(p_deep_link) > 500) then
    raise exception 'INVALID_NOTIFICATION_DEEP_LINK';
  end if;

  resolution := app_security.resolve_notification_recipient(
    p_church_id, p_recipient_user_id, p_event_type, p_ou_id
  );
  if not coalesce((resolution ->> 'eligible')::boolean, false) then return null; end if;

  insert into public.notifications (
    church_id, recipient_user_id, ou_id, event_type, event_key,
    title, body, deep_link, payload
  ) values (
    p_church_id, p_recipient_user_id, p_ou_id, p_event_type, trim(p_event_key),
    trim(p_title), trim(p_body), p_deep_link, p_payload
  )
  on conflict (church_id, recipient_user_id, event_key) do nothing
  returning id into saved_notification_id;

  if saved_notification_id is null then
    select id into saved_notification_id from public.notifications
    where church_id = p_church_id
      and recipient_user_id = p_recipient_user_id
      and event_key = trim(p_event_key);
  end if;

  if p_enqueue_line and coalesce((resolution ->> 'lineEligible')::boolean, false) then
    insert into public.notification_deliveries (
      church_id, notification_id, channel, status, next_attempt_at
    ) values (p_church_id, saved_notification_id, 'line', 'pending', now())
    on conflict (notification_id, channel) do nothing;
  end if;

  return saved_notification_id;
end;
$$;

create or replace function public.list_notifications(
  p_limit integer default 20,
  p_cursor_created_at timestamptz default null,
  p_cursor_id uuid default null,
  p_include_archived boolean default false
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  items jsonb;
  next_created_at timestamptz;
  next_id uuid;
begin
  if tenant_id is null then raise exception 'TENANT_CONTEXT_REQUIRED'; end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then raise exception 'INVALID_PAGE_LIMIT'; end if;
  if (p_cursor_created_at is null) <> (p_cursor_id is null) then raise exception 'INVALID_NOTIFICATION_CURSOR'; end if;

  with page as (
    select notification.*
    from public.notifications notification
    where notification.church_id = tenant_id
      and notification.recipient_user_id = actor_user_id
      and (p_include_archived or notification.archived_at is null)
      and (p_cursor_created_at is null or (notification.created_at, notification.id) < (p_cursor_created_at, p_cursor_id))
    order by notification.created_at desc, notification.id desc
    limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', id, 'eventType', event_type, 'title', title, 'body', body,
    'ouId', ou_id, 'deepLink', deep_link, 'payload', payload,
    'createdAt', created_at, 'readAt', read_at, 'archivedAt', archived_at
  ) order by created_at desc, id desc), '[]'::jsonb),
  (array_agg(created_at order by created_at desc, id desc))[p_limit],
  (array_agg(id order by created_at desc, id desc))[p_limit]
  into items, next_created_at, next_id
  from page;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'items', items,
    'nextCursor', case when jsonb_array_length(items) = p_limit then
      jsonb_build_object('createdAt', next_created_at, 'id', next_id)
      else null end
  ));
end;
$$;

create or replace function public.get_unread_notification_count()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  unread_count integer;
begin
  if tenant_id is null then raise exception 'TENANT_CONTEXT_REQUIRED'; end if;
  select count(*) into unread_count from public.notifications
  where church_id = tenant_id and recipient_user_id = actor_user_id
    and read_at is null and archived_at is null;
  return jsonb_build_object('success', true, 'data', jsonb_build_object('count', unread_count));
end;
$$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  membership_id uuid := app_security.current_church_member_id();
  saved public.notifications%rowtype;
begin
  if tenant_id is null then raise exception 'TENANT_CONTEXT_REQUIRED'; end if;
  update public.notifications set read_at = coalesce(read_at, now())
  where id = p_notification_id and church_id = tenant_id
    and recipient_user_id = actor_user_id and archived_at is null
  returning * into saved;
  if saved.id is null then raise exception 'NOTIFICATION_NOT_FOUND'; end if;

  insert into public.audit_logs(church_id, user_id, actor_church_member_id, entity_type, entity_id, action, metadata)
  values (tenant_id, actor_user_id, membership_id, 'notifications', saved.id, 'mark_notification_read', '{}'::jsonb);
  return jsonb_build_object('success', true, 'data', jsonb_build_object('id', saved.id, 'readAt', saved.read_at));
end;
$$;

create or replace function public.mark_all_notifications_read()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  membership_id uuid := app_security.current_church_member_id();
  affected integer;
begin
  if tenant_id is null then raise exception 'TENANT_CONTEXT_REQUIRED'; end if;
  update public.notifications set read_at = now()
  where church_id = tenant_id and recipient_user_id = actor_user_id
    and read_at is null and archived_at is null;
  get diagnostics affected = row_count;
  insert into public.audit_logs(church_id, user_id, actor_church_member_id, entity_type, action, metadata)
  values (tenant_id, actor_user_id, membership_id, 'notifications', 'mark_all_notifications_read', jsonb_build_object('count', affected));
  return jsonb_build_object('success', true, 'data', jsonb_build_object('count', affected));
end;
$$;

create or replace function public.archive_notification(p_notification_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  membership_id uuid := app_security.current_church_member_id();
  saved public.notifications%rowtype;
begin
  if tenant_id is null then raise exception 'TENANT_CONTEXT_REQUIRED'; end if;
  update public.notifications
  set archived_at = coalesce(archived_at, now()), read_at = coalesce(read_at, now())
  where id = p_notification_id and church_id = tenant_id and recipient_user_id = actor_user_id
  returning * into saved;
  if saved.id is null then raise exception 'NOTIFICATION_NOT_FOUND'; end if;
  insert into public.audit_logs(church_id, user_id, actor_church_member_id, entity_type, entity_id, action, metadata)
  values (tenant_id, actor_user_id, membership_id, 'notifications', saved.id, 'archive_notification', '{}'::jsonb);
  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'id', saved.id, 'readAt', saved.read_at, 'archivedAt', saved.archived_at
  ));
end;
$$;

revoke all on function app_security.notification_payload_is_safe(jsonb) from public;
revoke all on function app_security.resolve_notification_recipient(uuid, uuid, text, uuid) from public;
revoke all on function app_security.enqueue_notification(uuid, uuid, text, text, text, text, uuid, text, jsonb, boolean) from public;
revoke all on function public.list_notifications(integer, timestamptz, uuid, boolean) from public;
revoke all on function public.get_unread_notification_count() from public;
revoke all on function public.mark_notification_read(uuid) from public;
revoke all on function public.mark_all_notifications_read() from public;
revoke all on function public.archive_notification(uuid) from public;

grant select on public.notifications to authenticated;
revoke insert, update, delete on public.notifications from authenticated;
revoke all on public.notification_deliveries from authenticated;
grant execute on function public.list_notifications(integer, timestamptz, uuid, boolean) to authenticated;
grant execute on function public.get_unread_notification_count() to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;
grant execute on function public.mark_all_notifications_read() to authenticated;
grant execute on function public.archive_notification(uuid) to authenticated;

grant select, insert, update, delete on public.notifications to service_role;
grant select, insert, update, delete on public.notification_deliveries to service_role;
