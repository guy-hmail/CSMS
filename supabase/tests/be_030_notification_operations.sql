\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-030 assertion: %', message; end if;
end;
$$;

insert into public.churches(id, code, slug, name, status)
values
  ('f1000000-0000-4000-8000-000000000001', 'NTF1', 'notification-stage-f-one', 'Notification Stage F One', 'active'),
  ('f1000000-0000-4000-8000-000000000002', 'NTF2', 'notification-stage-f-two', 'Notification Stage F Two', 'active');

insert into public.users(id, auth_user_id, line_user_id, display_name, global_role)
values
  ('f2000000-0000-4000-8000-000000000001', 'f3000000-0000-4000-8000-000000000001', 'U-stage-f-admin', 'Stage F System Admin', 'system_admin'),
  ('f2000000-0000-4000-8000-000000000002', 'f3000000-0000-4000-8000-000000000002', 'U-stage-f-user', 'Stage F User', 'user'),
  ('f2000000-0000-4000-8000-000000000003', 'f3000000-0000-4000-8000-000000000003', 'U-stage-f-other', 'Stage F Other Tenant', 'user');

insert into public.church_members(id, church_id, user_id, status)
values
  ('f4000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000002', 'active'),
  ('f4000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000002', 'f2000000-0000-4000-8000-000000000003', 'active');

insert into public.notifications(
  id, church_id, recipient_user_id, event_type, event_key, title, body, deep_link, payload, created_at
) values
  ('fa000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000002', 'pending_approval_digest', 'stage-f-sent', 'Sensitive title', 'Sensitive body', '/app/approval', '{}'::jsonb, now() - interval '1 hour'),
  ('fa000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000002', 'missing_submission_reminder', 'stage-f-dead', 'Secret dead title', 'Secret dead body', '/app/submissions', '{}'::jsonb, now() - interval '2 hours'),
  ('fa000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000001', 'f2000000-0000-4000-8000-000000000002', 'submission_returned', 'stage-f-stale', 'Stale title', 'Stale body', '/app/submissions', '{}'::jsonb, now() - interval '3 hours'),
  ('fa000000-0000-4000-8000-000000000004', 'f1000000-0000-4000-8000-000000000002', 'f2000000-0000-4000-8000-000000000003', 'pending_approval_digest', 'stage-f-other', 'Other title', 'Other body', '/app/approval', '{}'::jsonb, now() - interval '1 hour');

insert into public.notification_deliveries(
  id, church_id, notification_id, channel, status, attempt_count,
  next_attempt_at, processing_started_at, sent_at, last_error_code, last_error_message, created_at, updated_at
) values
  ('fb000000-0000-4000-8000-000000000001', 'f1000000-0000-4000-8000-000000000001', 'fa000000-0000-4000-8000-000000000001', 'line', 'sent', 1, now(), null, now() - interval '30 minutes', null, null, now() - interval '1 hour', now() - interval '30 minutes'),
  ('fb000000-0000-4000-8000-000000000002', 'f1000000-0000-4000-8000-000000000001', 'fa000000-0000-4000-8000-000000000002', 'line', 'dead_letter', 1, now(), null, null, 'LINE_HTTP_400', 'Bearer secret must not leave DB', now() - interval '2 hours', now() - interval '1 hour'),
  ('fb000000-0000-4000-8000-000000000003', 'f1000000-0000-4000-8000-000000000001', 'fa000000-0000-4000-8000-000000000003', 'line', 'processing', 1, now(), now() - interval '11 minutes', null, null, null, now() - interval '3 hours', now() - interval '11 minutes'),
  ('fb000000-0000-4000-8000-000000000004', 'f1000000-0000-4000-8000-000000000002', 'fa000000-0000-4000-8000-000000000004', 'line', 'dead_letter', 1, now(), null, null, 'OTHER_TENANT', 'Other error', now() - interval '1 hour', now() - interval '30 minutes');

insert into public.notification_delivery_attempts(
  church_id, delivery_id, delivery_cycle, attempt_no, outcome,
  error_code, error_message, started_at, completed_at
) values
  ('f1000000-0000-4000-8000-000000000001', 'fb000000-0000-4000-8000-000000000001', 0, 1, 'sent', null, null, now() - interval '31 minutes', now() - interval '30 minutes'),
  ('f1000000-0000-4000-8000-000000000001', 'fb000000-0000-4000-8000-000000000002', 0, 1, 'permanent_failure', 'LINE_HTTP_400', 'Provider error details redacted.', now() - interval '61 minutes', now() - interval '60 minutes');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"f3000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}', true);
create temporary table stage_f_operations as
select public.get_platform_notification_operations(
  'f1000000-0000-4000-8000-000000000001', 24
) response;

reset role;
select pg_temp.assert_true(
  (select response #>> '{summary,notificationsCreated}' = '3'
      and response #>> '{summary,sentInWindow}' = '1'
      and response #>> '{summary,deadLetter}' = '1'
      and response #>> '{summary,staleProcessing}' = '1'
      and (response #>> '{summary,successRate}')::numeric = 50
      and (response #>> '{summary,failureRate}')::numeric = 50
   from stage_f_operations),
  'operations summary calculates queue depth, stale lease, and rates for one Tenant'
);
select pg_temp.assert_true(
  (select jsonb_array_length(response -> 'recentDeadLetters') = 1
      and response #>> '{recentDeadLetters,0,errorCode}' = 'LINE_HTTP_400'
   from stage_f_operations),
  'dead-letter operations expose only bounded correlation and classification fields'
);
select pg_temp.assert_true(
  (select response::text !~* '(Sensitive title|Sensitive body|Secret dead|Bearer secret|U-stage-f|line_user_id|errorMessage|deepLink)'
   from stage_f_operations),
  'operations response excludes recipient, message, deep-link, and error-detail data'
);
select pg_temp.assert_true(
  (select response::text !~ 'OTHER_TENANT' from stage_f_operations),
  'operations response excludes another Tenant'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', 'f3000000-0000-4000-8000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"f3000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{"active_church_id":"f1000000-0000-4000-8000-000000000001"}}', true);
do $$
begin
  begin
    perform public.get_platform_notification_operations('f1000000-0000-4000-8000-000000000001', 24);
    raise exception 'regular Tenant user read platform operations';
  exception when others then
    if sqlerrm <> 'SYSTEM_ADMIN_REQUIRED' then raise; end if;
  end;
end;
$$;
reset role;

select pg_temp.assert_true(
  not has_table_privilege('authenticated', 'public.notification_deliveries', 'SELECT')
  and not has_table_privilege('authenticated', 'public.notification_delivery_attempts', 'SELECT'),
  'operations RPC does not broaden browser table access'
);

rollback;
select 'ok 1 - BE-030 notification operations are aggregate, Tenant-scoped, and privacy-minimized';
