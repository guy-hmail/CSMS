\set ON_ERROR_STOP on
select '1..1';
begin;

insert into public.churches (id, code, slug, name, status)
values ('00000000-0000-0000-0000-000000000071', 'AUD', 'aud', 'Audit Test', 'active');
insert into public.users (id, auth_user_id, line_user_id, display_name)
values
('10000000-0000-0000-0000-000000000071', 'a7000000-0000-4000-8000-000000000071', 'audit-admin', 'Audit Admin'),
('10000000-0000-0000-0000-000000000072', 'a7000000-0000-4000-8000-000000000072', 'audit-viewer', 'Audit Viewer');
insert into public.church_members (id, church_id, user_id, status)
values
('20000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000071', 'active'),
('20000000-0000-0000-0000-000000000072', '00000000-0000-0000-0000-000000000071', '10000000-0000-0000-0000-000000000072', 'active');
insert into public.organization_unit_types (id, church_id, code, name)
values ('30000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-000000000071', 'ROOT', 'Root');
insert into public.organization_units (
    id, church_id, structure_root_id, ou_type_id, code, name, path, level
)
values ('40000000-0000-0000-0000-000000000071', '00000000-0000-0000-0000-000000000071', '40000000-0000-0000-0000-000000000071', '30000000-0000-0000-0000-000000000071', 'ROOT', 'Root', '/audit-root', 1);
insert into public.ou_members (church_id, ou_id, church_member_id, permission)
values
('00000000-0000-0000-0000-000000000071', '40000000-0000-0000-0000-000000000071', '20000000-0000-0000-0000-000000000071', 'admin'),
('00000000-0000-0000-0000-000000000071', '40000000-0000-0000-0000-000000000071', '20000000-0000-0000-0000-000000000072', 'viewer');
insert into public.audit_logs (
    id, church_id, ou_id, entity_type, action, metadata
)
values (
    '50000000-0000-0000-0000-000000000071',
    '00000000-0000-0000-0000-000000000071',
    null, 'churches', 'update_settings',
    '{"token":"secret-value","nested":{"email":"person@example.test","safe":"visible"}}'
);

create function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin if condition is not true then raise exception 'BE-007 assertion: %', message; end if; end;
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a7000000-0000-4000-8000-000000000071', true);
select set_config('request.jwt.claims', '{"sub":"a7000000-0000-4000-8000-000000000071","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000071"}}', true);
select pg_temp.assert_true(
    public.get_audit_logs('{}') #>> '{data,total}' = '1',
    'Root admin tenant-wide audit visibility'
);
select pg_temp.assert_true(
    public.get_audit_logs('{}') #>> '{data,items,0,metadata,token}' = '[REDACTED]'
    and public.get_audit_logs('{}') #>> '{data,items,0,metadata,nested,email}' = '[REDACTED]'
    and public.get_audit_logs('{}') #>> '{data,items,0,metadata,nested,safe}' = 'visible',
    'recursive sensitive-data redaction'
);

select set_config('request.jwt.claim.sub', 'a7000000-0000-4000-8000-000000000072', true);
select set_config('request.jwt.claims', '{"sub":"a7000000-0000-4000-8000-000000000072","app_metadata":{"active_church_id":"00000000-0000-0000-0000-000000000071"}}', true);
select pg_temp.assert_true(
    public.get_audit_logs('{}') #>> '{data,total}' = '0',
    'viewer has no general audit access'
);
reset role;

do $$
begin
    begin
        update public.audit_logs
        set action = 'tampered'
        where id = '50000000-0000-0000-0000-000000000071';
        raise exception 'audit update was accepted';
    exception when others then
        if sqlerrm <> 'AUDIT_LOG_IMMUTABLE' then raise; end if;
    end;
end;
$$;

select 'ok 1 - BE-007 audit logging';
rollback;
