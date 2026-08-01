-- Task 7: persisted personal profile and tenant-scoped user preferences.

create or replace function public.get_my_preferences()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  ignored_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  membership_id uuid := app_security.current_church_member_id();
  preference public.user_preferences%rowtype;
begin
  if tenant_id is null or membership_id is null then raise exception 'TENANT_CONTEXT_REQUIRED'; end if;
  select * into preference from public.user_preferences
  where church_id = tenant_id and church_member_id = membership_id;

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'defaultOuId', preference.default_ou_id,
    'language', coalesce(preference.language, 'th'),
    'landingPage', coalesce(preference.landing_page, '/app/dashboard'),
    'notifyMissing', coalesce(preference.notify_missing, true),
    'notifySubmitted', coalesce(preference.notify_submitted, true),
    'notifyApproval', coalesce(preference.notify_approval, true),
    'notifyEmail', coalesce(preference.notify_email, false),
    'updatedAt', preference.updated_at
  ));
end;
$$;

create or replace function public.update_my_preferences(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  membership_id uuid := app_security.current_church_member_id();
  input_default_ou_id uuid;
  input_language text := coalesce(nullif(trim(p_payload ->> 'language'), ''), 'th');
  input_landing_page text := coalesce(nullif(trim(p_payload ->> 'landingPage'), ''), '/app/dashboard');
  before_data jsonb;
  saved public.user_preferences%rowtype;
begin
  if tenant_id is null or membership_id is null then raise exception 'TENANT_CONTEXT_REQUIRED'; end if;
  if input_language not in ('th', 'en') then raise exception 'INVALID_LANGUAGE'; end if;
  if input_landing_page not in ('/app/dashboard', '/app/organization', '/app/submissions', '/app/reports') then
    raise exception 'INVALID_LANDING_PAGE';
  end if;
  if nullif(p_payload ->> 'defaultOuId', '') is not null then
    begin input_default_ou_id := (p_payload ->> 'defaultOuId')::uuid;
    exception when invalid_text_representation then raise exception 'INVALID_DEFAULT_OU'; end;
    if not exists (
      select 1 from public.organization_units ou
      where ou.id = input_default_ou_id and ou.church_id = tenant_id
        and ou.is_active and ou.deleted_at is null and app_security.can_view_ou(ou.id)
    ) then raise exception 'INVALID_DEFAULT_OU'; end if;
  end if;

  select to_jsonb(preference) - 'id' - 'created_at' into before_data
  from public.user_preferences preference
  where preference.church_id = tenant_id and preference.church_member_id = membership_id;

  insert into public.user_preferences (
    church_id, church_member_id, default_ou_id, language, landing_page,
    notify_missing, notify_submitted, notify_approval, notify_email
  ) values (
    tenant_id, membership_id, input_default_ou_id, input_language, input_landing_page,
    coalesce((p_payload ->> 'notifyMissing')::boolean, true),
    coalesce((p_payload ->> 'notifySubmitted')::boolean, true),
    coalesce((p_payload ->> 'notifyApproval')::boolean, true),
    coalesce((p_payload ->> 'notifyEmail')::boolean, false)
  )
  on conflict (church_id, church_member_id) do update set
    default_ou_id = excluded.default_ou_id,
    language = excluded.language,
    landing_page = excluded.landing_page,
    notify_missing = excluded.notify_missing,
    notify_submitted = excluded.notify_submitted,
    notify_approval = excluded.notify_approval,
    notify_email = excluded.notify_email
  returning * into saved;

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, entity_type, entity_id,
    action, before_data, after_data
  ) values (
    tenant_id, actor_user_id, membership_id, 'user_preferences', saved.id,
    'update_my_preferences', before_data,
    to_jsonb(saved) - 'id' - 'created_at'
  );

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'defaultOuId', saved.default_ou_id, 'language', saved.language,
    'landingPage', saved.landing_page, 'notifyMissing', saved.notify_missing,
    'notifySubmitted', saved.notify_submitted, 'notifyApproval', saved.notify_approval,
    'notifyEmail', saved.notify_email, 'updatedAt', saved.updated_at
  ));
exception when invalid_text_representation then
  raise exception 'INVALID_PREFERENCE_PAYLOAD';
end;
$$;

create or replace function public.update_my_profile(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_user_id uuid := app_security.require_current_user_id();
  tenant_id uuid := app_security.current_church_id();
  membership_id uuid := app_security.current_church_member_id();
  app_user public.users%rowtype;
  input_display_name text := trim(coalesce(p_payload ->> 'displayName', ''));
  input_email text := nullif(lower(trim(coalesce(p_payload ->> 'email', ''))), '');
  input_phone text := nullif(trim(coalesce(p_payload ->> 'phone', '')), '');
  before_data jsonb;
begin
  if length(input_display_name) < 2 or length(input_display_name) > 255 then raise exception 'INVALID_DISPLAY_NAME'; end if;
  if input_email is not null and input_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'INVALID_EMAIL'; end if;
  if input_phone is not null and (length(input_phone) > 50 or input_phone !~ '^[0-9+() .-]+$') then raise exception 'INVALID_PHONE'; end if;

  select * into app_user from public.users where id = actor_user_id for update;
  before_data := jsonb_build_object('displayName', app_user.display_name, 'email', app_user.email, 'phone', app_user.phone);
  update public.users set display_name = input_display_name, email = input_email, phone = input_phone
  where id = actor_user_id returning * into app_user;

  insert into public.audit_logs (
    church_id, user_id, actor_church_member_id, entity_type, entity_id,
    action, before_data, after_data
  ) values (
    tenant_id, actor_user_id, membership_id, 'users', actor_user_id,
    'update_my_profile', before_data,
    jsonb_build_object('displayName', app_user.display_name, 'email', app_user.email, 'phone', app_user.phone)
  );

  return jsonb_build_object('success', true, 'data', jsonb_build_object(
    'userId', app_user.id, 'displayName', app_user.display_name,
    'email', app_user.email, 'phone', app_user.phone
  ));
end;
$$;

revoke all on function public.get_my_preferences() from public;
revoke all on function public.update_my_preferences(jsonb) from public;
revoke all on function public.update_my_profile(jsonb) from public;
grant execute on function public.get_my_preferences() to authenticated;
grant execute on function public.update_my_preferences(jsonb) to authenticated;
grant execute on function public.update_my_profile(jsonb) to authenticated;
