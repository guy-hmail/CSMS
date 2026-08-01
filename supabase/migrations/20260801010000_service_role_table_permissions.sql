-- Trusted Edge Functions use the service-role client for audited identity,
-- invitation, and tenant operations. RLS bypass alone is not sufficient:
-- PostgreSQL still requires table-level privileges.

grant select, insert, update, delete
on all tables in schema public
to service_role;

grant usage, select, update
on all sequences in schema public
to service_role;

-- Keep trusted backend access consistent for public tables and sequences added
-- by later migrations executed by the local/project migration owner.
alter default privileges in schema public
grant select, insert, update, delete on tables to service_role;

alter default privileges in schema public
grant usage, select, update on sequences to service_role;
