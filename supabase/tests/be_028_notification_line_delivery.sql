\set ON_ERROR_STOP on
select '1..1';
begin;

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is not true then raise exception 'BE-028 assertion: %', message; end if;
end;
$$;

insert into public.churches(id, code, slug, name, status)
values ('d1000000-0000-4000-8000-000000000001', 'NTD', 'notification-stage-d', 'Notification Stage D', 'active');

insert into public.users(id, auth_user_id, line_user_id, display_name)
values
  ('d2000000-0000-4000-8000-000000000001', 'd3000000-0000-4000-8000-000000000001', 'U-stage-d-active', 'Stage D Active'),
  ('d2000000-0000-4000-8000-000000000002', 'd3000000-0000-4000-8000-000000000002', 'U-stage-d-revoked', 'Stage D Revoked');

insert into public.church_members(id, church_id, user_id, status)
values
  ('d4000000-0000-4000-8000-000000000001', 'd1000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001', 'active'),
  ('d4000000-0000-4000-8000-000000000002', 'd1000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000002', 'active');

select app_security.enqueue_notification(
  'd1000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001',
  'pending_approval_digest', 'stage-d-retry', 'Retry title', 'Retry body',
  null, '/app/approval', '{}'::jsonb, true
);

create temporary table stage_d_claim_1 as
select * from public.claim_line_notification_deliveries(
  20, array['d1000000-0000-4000-8000-000000000001'::uuid]
);
select pg_temp.assert_true(
  (select count(*) = 1 and min(attempt_count) = 1 from stage_d_claim_1),
  'first due delivery is claimed as attempt 1'
);
select pg_temp.assert_true(
  (select count(*) = 0 from public.claim_line_notification_deliveries(
    20, array['d1000000-0000-4000-8000-000000000001'::uuid]
  )),
  'processing delivery cannot be claimed by another worker'
);

select public.complete_line_notification_delivery(
  delivery_id, delivery_cycle, attempt_count, 'retryable_failure', null,
  'LINE_HTTP_429', 'Bearer top-secret should never be stored'
) from stage_d_claim_1;
select pg_temp.assert_true(
  (select delivery.status = 'failed'
      and delivery.next_attempt_at between now() + interval '29 minutes' and now() + interval '31 minutes'
      and delivery.last_error_message = 'Provider error details redacted.'
   from public.notification_deliveries delivery
   join stage_d_claim_1 claim on claim.delivery_id = delivery.id),
  'attempt 1 schedules 30-minute retry and redacts secrets'
);

update public.notification_deliveries set next_attempt_at = now()
where id = (select delivery_id from stage_d_claim_1);
create temporary table stage_d_claim_2 as
select * from public.claim_line_notification_deliveries(
  20, array['d1000000-0000-4000-8000-000000000001'::uuid]
);
select public.complete_line_notification_delivery(
  delivery_id, delivery_cycle, attempt_count, 'retryable_failure', null,
  'LINE_HTTP_503', 'LINE provider temporarily unavailable'
) from stage_d_claim_2;
select pg_temp.assert_true(
  (select delivery.status = 'failed'
      and claim.attempt_count = 2
      and delivery.next_attempt_at between now() + interval '119 minutes' and now() + interval '121 minutes'
   from public.notification_deliveries delivery
   join stage_d_claim_2 claim on claim.delivery_id = delivery.id),
  'attempt 2 schedules a 2-hour retry'
);

update public.notification_deliveries set next_attempt_at = now()
where id = (select delivery_id from stage_d_claim_1);
create temporary table stage_d_claim_3 as
select * from public.claim_line_notification_deliveries(
  20, array['d1000000-0000-4000-8000-000000000001'::uuid]
);
select public.complete_line_notification_delivery(
  delivery_id, delivery_cycle, attempt_count, 'retryable_failure', null,
  'LINE_HTTP_503', 'Final provider failure'
) from stage_d_claim_3;
select pg_temp.assert_true(
  (select delivery.status = 'dead_letter' and delivery.attempt_count = 3
   from public.notification_deliveries delivery
   join stage_d_claim_3 claim on claim.delivery_id = delivery.id),
  'third retryable failure enters dead letter'
);
select pg_temp.assert_true(
  (select count(*) = 3 from public.notification_delivery_attempts attempt
   where attempt.delivery_id = (select delivery_id from stage_d_claim_1)
     and attempt.delivery_cycle = 0),
  'bounded attempt history records exactly three failures'
);

select public.replay_line_notification_delivery((select delivery_id from stage_d_claim_1));
select pg_temp.assert_true(
  (select status = 'pending' and attempt_count = 0 and delivery_cycle = 1
   from public.notification_deliveries
   where id = (select delivery_id from stage_d_claim_1)),
  'manual replay starts a new delivery cycle'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.audit_logs
   where entity_id = (select delivery_id from stage_d_claim_1)
     and action = 'replay_line_notification_delivery'
     and metadata ? 'previousAttemptCount'
     and metadata::text !~* '(line_user_id|U-stage-d|token|secret|authorization)'),
  'manual replay is audited without recipient or secret data'
);
create temporary table stage_d_replay_claim as
select * from public.claim_line_notification_deliveries(
  20, array['d1000000-0000-4000-8000-000000000001'::uuid]
);
select public.complete_line_notification_delivery(
  delivery_id, delivery_cycle, attempt_count, 'sent', 'request-id-1', null, null
) from stage_d_replay_claim;
select pg_temp.assert_true(
  (select status = 'sent' and attempt_count = 1 and delivery_cycle = 1
   from public.notification_deliveries
   where id = (select delivery_id from stage_d_claim_1)),
  'replayed cycle can complete successfully'
);

select app_security.enqueue_notification(
  'd1000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001',
  'pending_approval_digest', 'stage-d-permanent', 'Permanent title', 'Permanent body',
  null, '/app/approval', '{}'::jsonb, true
);
create temporary table stage_d_permanent_claim as
select * from public.claim_line_notification_deliveries(
  20, array['d1000000-0000-4000-8000-000000000001'::uuid]
);
select public.complete_line_notification_delivery(
  delivery_id, delivery_cycle, attempt_count, 'permanent_failure', null,
  'LINE_HTTP_400', 'LINE rejected the request'
) from stage_d_permanent_claim;
select pg_temp.assert_true(
  (select status = 'dead_letter' and attempt_count = 1
   from public.notification_deliveries
   where id = (select delivery_id from stage_d_permanent_claim)),
  'permanent 4xx failure enters dead letter immediately'
);

select app_security.enqueue_notification(
  'd1000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001',
  'pending_approval_digest', 'stage-d-stale', 'Stale title', 'Stale body',
  null, '/app/approval', '{}'::jsonb, true
);
create temporary table stage_d_stale_claim_1 as
select * from public.claim_line_notification_deliveries(
  20, array['d1000000-0000-4000-8000-000000000001'::uuid]
);
update public.notification_deliveries
set processing_started_at = now() - interval '11 minutes'
where id = (select delivery_id from stage_d_stale_claim_1);
create temporary table stage_d_stale_claim_2 as
select * from public.claim_line_notification_deliveries(
  20, array['d1000000-0000-4000-8000-000000000001'::uuid]
);
select pg_temp.assert_true(
  (select count(*) = 1 and min(attempt_count) = 2 from stage_d_stale_claim_2),
  'expired worker lease is recovered as the next bounded attempt'
);
select pg_temp.assert_true(
  (select count(*) = 1 from public.notification_delivery_attempts
   where delivery_id = (select delivery_id from stage_d_stale_claim_1)
     and attempt_no = 1 and outcome = 'stale_recovered'),
  'stale lease recovery is retained in attempt history'
);
select public.complete_line_notification_delivery(
  delivery_id, delivery_cycle, attempt_count, 'sent', 'request-id-stale', null, null
) from stage_d_stale_claim_2;

select app_security.enqueue_notification(
  'd1000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000001',
  'pending_approval_digest', 'stage-d-canary', 'Canary title', 'Canary body',
  null, '/app/approval', '{}'::jsonb, true
);
select pg_temp.assert_true(
  (select count(*) = 0 from public.claim_line_notification_deliveries(
    20, array['eeeeeeee-0000-4000-8000-000000000001'::uuid]
  )),
  'tenant outside canary scope is not claimed'
);
create temporary table stage_d_canary_claim as
select * from public.claim_line_notification_deliveries(
  20, array['d1000000-0000-4000-8000-000000000001'::uuid]
);
select public.complete_line_notification_delivery(
  delivery_id, delivery_cycle, attempt_count, 'sent', 'request-id-canary', null, null
) from stage_d_canary_claim;

select app_security.enqueue_notification(
  'd1000000-0000-4000-8000-000000000001', 'd2000000-0000-4000-8000-000000000002',
  'pending_approval_digest', 'stage-d-revoked', 'Revoked title', 'Revoked body',
  null, '/app/approval', '{}'::jsonb, true
);
update public.church_members set status = 'revoked'
where id = 'd4000000-0000-4000-8000-000000000002';
select pg_temp.assert_true(
  (select count(*) = 0 from public.claim_line_notification_deliveries(
    20, array['d1000000-0000-4000-8000-000000000001'::uuid]
  )),
  'recipient eligibility is rechecked immediately before delivery'
);
select pg_temp.assert_true(
  (select delivery.status = 'dead_letter' and delivery.attempt_count = 0
   from public.notification_deliveries delivery
   join public.notifications notification on notification.id = delivery.notification_id
   where notification.event_key = 'stage-d-revoked'),
  'revoked recipient is dead-lettered without sending'
);

select pg_temp.assert_true(
  not has_function_privilege('authenticated', 'public.claim_line_notification_deliveries(integer,uuid[])', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.complete_line_notification_delivery(uuid,integer,integer,text,text,text,text)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'public.replay_line_notification_delivery(uuid)', 'EXECUTE')
  and not has_table_privilege('authenticated', 'public.notification_delivery_attempts', 'SELECT'),
  'browser role cannot claim, complete, replay, or read attempt history'
);

rollback;
select 'ok 1 - BE-028 LINE delivery worker is bounded, recoverable, scoped, and secret-safe';
