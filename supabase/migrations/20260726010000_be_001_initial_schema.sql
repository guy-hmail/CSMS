-- BE-001: Initial CSMS database schema.
-- Source of truth: doc/02_Database_Design.md.
-- Security helpers and RLS policies are intentionally deferred to BE-002.

create extension if not exists "pgcrypto";
create extension if not exists "uuid-ossp";

create table public.churches (
    id uuid primary key default gen_random_uuid(),
    code varchar(50) not null,
    slug varchar(100) not null,
    name varchar(255) not null,
    description text,
    timezone varchar(100) not null default 'Asia/Bangkok',
    approval_mode varchar(30) not null default 'auto_approve',
    reporting_week_ends_on smallint not null default 0,
    primary_metric_id uuid,
    status varchar(30) not null default 'provisioning',
    trial_ends_at timestamptz,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    deleted_by uuid,
    constraint uq_churches_code unique (code),
    constraint uq_churches_slug unique (slug),
    constraint ck_churches_status
        check (status in ('provisioning', 'trial', 'active', 'suspended', 'closed')),
    constraint ck_churches_approval_mode
        check (approval_mode in ('auto_approve', 'approval_required')),
    constraint ck_churches_week_end
        check (reporting_week_ends_on between 0 and 6),
    constraint ck_churches_active_status check (
        (status in ('provisioning', 'trial', 'active') and is_active = true)
        or (status in ('suspended', 'closed') and is_active = false)
    )
);

create table public.users (
    id uuid primary key default gen_random_uuid(),
    auth_user_id uuid not null,
    last_active_church_id uuid references public.churches(id),
    line_user_id varchar(150) not null,
    display_name varchar(255) not null,
    picture_url text,
    email varchar(255),
    phone varchar(50),
    global_role varchar(30) not null default 'user',
    is_active boolean not null default true,
    last_login_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    deleted_by uuid,
    constraint uq_users_auth_user_id unique (auth_user_id),
    constraint uq_users_line_user_id unique (line_user_id),
    constraint ck_users_global_role
        check (global_role in ('system_admin', 'user'))
);

alter table public.churches
    add constraint fk_churches_deleted_by
    foreign key (deleted_by) references public.users(id);

alter table public.users
    add constraint fk_users_deleted_by
    foreign key (deleted_by) references public.users(id);

create table public.church_members (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    user_id uuid not null references public.users(id),
    status varchar(20) not null default 'active',
    joined_at timestamptz,
    created_by uuid references public.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint uq_church_member unique (church_id, user_id),
    constraint uq_church_member_church_id unique (church_id, id),
    constraint uq_church_member_actor unique (church_id, id, user_id),
    constraint ck_church_member_status
        check (status in ('invited', 'active', 'suspended', 'revoked'))
);

create table public.organization_unit_types (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    code varchar(50) not null,
    name varchar(150) not null,
    description text,
    sort_order integer not null default 0,
    default_allow_data_entry boolean not null default false,
    is_active boolean not null default true,
    created_by uuid references public.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    deleted_by uuid references public.users(id),
    constraint uq_ou_type_code_per_church unique (church_id, code),
    constraint uq_ou_type_church_id unique (church_id, id),
    constraint ck_ou_type_sort_order_nonnegative check (sort_order >= 0),
    constraint ck_ou_type_deleted_inactive
        check (deleted_at is null or is_active = false)
);

create table public.organization_units (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    structure_root_id uuid not null,
    parent_id uuid,
    ou_type_id uuid not null,
    code varchar(50) not null,
    name varchar(255) not null,
    description text,
    path text not null,
    level integer not null default 1,
    sort_order integer not null default 0,
    allow_data_entry boolean not null default false,
    is_active boolean not null default true,
    created_by uuid references public.users(id),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    deleted_by uuid references public.users(id),
    constraint uq_ou_code_per_church unique (church_id, code),
    constraint uq_ou_church_id unique (church_id, id),
    constraint ck_ou_level_positive check (level >= 1),
    constraint fk_ou_parent_same_church
        foreign key (church_id, parent_id)
        references public.organization_units(church_id, id),
    constraint fk_ou_root_same_church
        foreign key (church_id, structure_root_id)
        references public.organization_units(church_id, id),
    constraint fk_ou_type_same_church
        foreign key (church_id, ou_type_id)
        references public.organization_unit_types(church_id, id)
);

create table public.tenant_invitations (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    email varchar(255) not null,
    display_name varchar(255),
    target_ou_id uuid not null,
    permission varchar(30) not null,
    can_override boolean not null default false,
    token_hash text not null,
    status varchar(20) not null default 'pending',
    expires_at timestamptz not null,
    invited_by uuid not null references public.users(id),
    accepted_by uuid references public.users(id),
    accepted_at timestamptz,
    revoked_by uuid references public.users(id),
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint uq_tenant_invitation_token_hash unique (token_hash),
    constraint ck_tenant_invitation_permission
        check (permission in ('admin', 'manager', 'data_entry', 'approver', 'viewer')),
    constraint ck_tenant_invitation_override_role
        check (can_override = false or permission = 'approver'),
    constraint ck_tenant_invitation_status
        check (status in ('pending', 'accepted', 'expired', 'revoked')),
    constraint ck_tenant_invitation_expiry check (expires_at > created_at),
    constraint fk_tenant_invitation_ou_same_church
        foreign key (church_id, target_ou_id)
        references public.organization_units(church_id, id)
);

create unique index uq_pending_tenant_invitation
    on public.tenant_invitations (
        church_id,
        lower(email),
        target_ou_id,
        permission
    )
    where status = 'pending';

create table public.user_preferences (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    church_member_id uuid not null,
    default_ou_id uuid,
    language varchar(10) not null default 'th',
    landing_page varchar(100) not null default '/app/dashboard',
    notify_missing boolean not null default true,
    notify_submitted boolean not null default true,
    notify_approval boolean not null default true,
    notify_email boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint uq_user_preference_membership
        unique (church_id, church_member_id),
    constraint ck_user_preference_language check (language in ('th', 'en')),
    constraint ck_user_preference_landing check (
        landing_page in (
            '/app/dashboard',
            '/app/organization',
            '/app/submissions',
            '/app/reports'
        )
    ),
    constraint fk_user_preference_membership_same_church
        foreign key (church_id, church_member_id)
        references public.church_members(church_id, id),
    constraint fk_user_preference_ou_same_church
        foreign key (church_id, default_ou_id)
        references public.organization_units(church_id, id)
);

create table public.ou_members (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    ou_id uuid not null,
    church_member_id uuid not null,
    permission varchar(30) not null,
    can_override boolean not null default false,
    is_active boolean not null default true,
    assigned_by uuid references public.users(id),
    assigned_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    deleted_by uuid references public.users(id),
    constraint uq_ou_member_church_id unique (church_id, id),
    constraint uq_ou_member_authorization_source
        unique (church_id, id, church_member_id),
    constraint uq_ou_member_permission
        unique (church_id, ou_id, church_member_id, permission),
    constraint ck_ou_members_permission
        check (permission in ('admin', 'manager', 'data_entry', 'approver', 'viewer')),
    constraint ck_ou_members_override_role
        check (can_override = false or permission = 'approver'),
    constraint fk_ou_member_ou_same_church
        foreign key (church_id, ou_id)
        references public.organization_units(church_id, id),
    constraint fk_ou_member_membership_same_church
        foreign key (church_id, church_member_id)
        references public.church_members(church_id, id)
);

create table public.statistic_periods (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    period_type varchar(20) not null default 'week',
    year integer not null,
    week_no integer,
    month_no integer,
    period_start date not null,
    period_end date not null,
    label varchar(100) not null,
    status varchar(30) not null default 'open',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint ck_period_type check (period_type = 'week'),
    constraint ck_period_status check (status in ('open', 'closed', 'locked')),
    constraint ck_week_period_shape check (
        week_no between 1 and 53
        and month_no is null
        and period_end = period_start + 6
    ),
    constraint uq_period_church_id unique (church_id, id),
    constraint uq_period_per_church unique (church_id, period_start)
);

create table public.metric_template_sets (
    id uuid primary key default gen_random_uuid(),
    code varchar(80) not null,
    version integer not null,
    name varchar(255) not null,
    metric_definitions jsonb not null,
    is_active boolean not null default true,
    created_by uuid not null references public.users(id),
    created_at timestamptz not null default now(),
    constraint uq_metric_template_version unique (code, version),
    constraint ck_metric_template_version_positive check (version >= 1),
    constraint ck_metric_template_definitions_array
        check (jsonb_typeof(metric_definitions) = 'array')
);

create table public.statistic_metrics (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    source_template_set_id uuid references public.metric_template_sets(id),
    source_template_code varchar(80),
    code varchar(80) not null,
    name varchar(255) not null,
    description text,
    category varchar(80) not null,
    unit varchar(50) not null default 'count',
    data_type varchar(30) not null default 'number',
    input_type varchar(30) not null default 'number',
    aggregation varchar(30) not null default 'sum',
    default_value numeric(18,2),
    min_value numeric(18,2),
    max_value numeric(18,2),
    is_required boolean not null default false,
    sort_order integer not null default 0,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    deleted_by uuid references public.users(id),
    constraint uq_metric_code_per_church unique (church_id, code),
    constraint uq_metric_church_id unique (church_id, id),
    constraint ck_metric_data_type
        check (data_type in ('number', 'text', 'boolean')),
    constraint ck_metric_input_type check (
        input_type = case data_type
            when 'number' then 'number'
            when 'text' then 'text'
            else 'checkbox'
        end
    ),
    constraint ck_metric_aggregation
        check (aggregation in ('sum', 'avg', 'max', 'min', 'none')),
    constraint ck_metric_range
        check (min_value is null or max_value is null or min_value <= max_value),
    constraint ck_metric_default_range check (
        default_value is null
        or (
            data_type = 'number'
            and (min_value is null or default_value >= min_value)
            and (max_value is null or default_value <= max_value)
        )
    ),
    constraint ck_metric_non_numeric_aggregation
        check (data_type = 'number' or aggregation = 'none')
);

alter table public.churches
    add constraint fk_church_primary_metric_same_tenant
    foreign key (id, primary_metric_id)
    references public.statistic_metrics(church_id, id);

create table public.statistic_submissions (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    period_id uuid not null,
    ou_id uuid not null,
    status varchar(30) not null default 'draft',
    submitted_by uuid references public.users(id),
    submitted_at timestamptz,
    approved_by uuid references public.users(id),
    approved_at timestamptz,
    rejected_by uuid references public.users(id),
    rejected_at timestamptz,
    returned_by uuid references public.users(id),
    returned_at timestamptz,
    revision_no integer not null default 1,
    remarks text,
    approval_note text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    deleted_by uuid references public.users(id),
    constraint uq_submission_church_id unique (church_id, id),
    constraint uq_submission_per_period_ou
        unique (church_id, period_id, ou_id),
    constraint ck_submission_status
        check (status in ('draft', 'submitted', 'approved', 'rejected', 'returned')),
    constraint ck_revision_positive check (revision_no >= 1),
    constraint ck_submission_actor_timestamps check (
        (submitted_by is null) = (submitted_at is null)
        and (approved_by is null) = (approved_at is null)
        and (rejected_by is null) = (rejected_at is null)
        and (returned_by is null) = (returned_at is null)
    ),
    constraint ck_submission_status_timestamps check (
        (
            status = 'draft'
            and submitted_at is null
            and approved_at is null
            and rejected_at is null
            and returned_at is null
        )
        or (
            status = 'submitted'
            and submitted_at is not null
            and approved_at is null
            and rejected_at is null
            and returned_at is null
        )
        or (
            status = 'approved'
            and submitted_at is not null
            and approved_at is not null
            and rejected_at is null
            and returned_at is null
        )
        or (
            status = 'rejected'
            and submitted_at is not null
            and rejected_at is not null
            and returned_at is null
        )
        or (
            status = 'returned'
            and submitted_at is not null
            and returned_at is not null
            and rejected_at is null
        )
    ),
    constraint fk_submission_period_same_church
        foreign key (church_id, period_id)
        references public.statistic_periods(church_id, id),
    constraint fk_submission_ou_same_church
        foreign key (church_id, ou_id)
        references public.organization_units(church_id, id)
);

create table public.statistic_values (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    submission_id uuid not null,
    metric_id uuid not null,
    numeric_value numeric(18,2),
    text_value text,
    boolean_value boolean,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint uq_value_per_submission_metric
        unique (church_id, submission_id, metric_id),
    constraint ck_statistic_value_one_field check (
        num_nonnulls(numeric_value, text_value, boolean_value) = 1
    ),
    constraint fk_value_submission_same_church
        foreign key (church_id, submission_id)
        references public.statistic_submissions(church_id, id)
        on delete cascade,
    constraint fk_value_metric_same_church
        foreign key (church_id, metric_id)
        references public.statistic_metrics(church_id, id)
);

create table public.submission_revisions (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    submission_id uuid not null,
    revision_no integer not null,
    status varchar(30) not null,
    remarks text,
    values_snapshot jsonb not null,
    changed_by uuid not null references public.users(id),
    created_at timestamptz not null default now(),
    constraint uq_submission_revision
        unique (church_id, submission_id, revision_no),
    constraint ck_submission_revision_positive check (revision_no >= 1),
    constraint ck_submission_revision_status
        check (status in ('draft', 'submitted', 'approved', 'rejected', 'returned')),
    constraint ck_submission_revision_values_array
        check (jsonb_typeof(values_snapshot) = 'array'),
    constraint fk_revision_submission_same_church
        foreign key (church_id, submission_id)
        references public.statistic_submissions(church_id, id)
        on delete cascade
);

create table public.api_idempotency_keys (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    actor_user_id uuid not null references public.users(id),
    operation varchar(100) not null,
    client_request_id uuid not null,
    request_hash text not null,
    response_body jsonb,
    response_status integer,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null,
    constraint uq_api_idempotency_key
        unique (church_id, actor_user_id, operation, client_request_id),
    constraint ck_api_idempotency_expiry check (expires_at > created_at),
    constraint ck_api_response_status
        check (response_status is null or response_status between 100 and 599)
);

create table public.approval_logs (
    id uuid primary key default gen_random_uuid(),
    church_id uuid not null references public.churches(id),
    submission_id uuid not null,
    action varchar(30) not null,
    action_by uuid not null references public.users(id),
    from_status varchar(30),
    to_status varchar(30),
    is_override boolean not null default false,
    reason text,
    created_at timestamptz not null default now(),
    constraint fk_approval_submission_same_church
        foreign key (church_id, submission_id)
        references public.statistic_submissions(church_id, id)
        on delete cascade
);

create table public.audit_logs (
    id uuid primary key default gen_random_uuid(),
    church_id uuid references public.churches(id),
    user_id uuid references public.users(id),
    actor_church_member_id uuid,
    ou_id uuid,
    source_ou_member_id uuid,
    entity_type varchar(100) not null,
    entity_id uuid,
    action varchar(100) not null,
    before_data jsonb,
    after_data jsonb,
    metadata jsonb not null default '{}'::jsonb,
    request_id uuid,
    ip_address inet,
    user_agent text,
    created_at timestamptz not null default now(),
    constraint ck_audit_actor_identity check (
        (actor_church_member_id is null or user_id is not null)
        and (source_ou_member_id is null or actor_church_member_id is not null)
    ),
    constraint ck_audit_platform_scope check (
        church_id is not null
        or (
            actor_church_member_id is null
            and ou_id is null
            and source_ou_member_id is null
        )
    ),
    constraint fk_audit_actor_membership_same_church
        foreign key (church_id, actor_church_member_id, user_id)
        references public.church_members(church_id, id, user_id),
    constraint fk_audit_ou_same_church
        foreign key (church_id, ou_id)
        references public.organization_units(church_id, id),
    constraint fk_audit_source_assignment_same_church
        foreign key (church_id, source_ou_member_id, actor_church_member_id)
        references public.ou_members(church_id, id, church_member_id)
);

create index idx_church_members_user
    on public.church_members(user_id, status);
create index idx_church_members_church
    on public.church_members(church_id, status);
create index idx_tenant_invitations_expiry
    on public.tenant_invitations(status, expires_at);
create index idx_user_preferences_member
    on public.user_preferences(church_id, church_member_id);
create index idx_ou_types_church_active_order
    on public.organization_unit_types(church_id, is_active, sort_order)
    where deleted_at is null;
create index idx_ou_church_parent
    on public.organization_units(church_id, parent_id);
create unique index uq_one_active_root_per_church
    on public.organization_units(church_id)
    where parent_id is null and is_active = true and deleted_at is null;
create index idx_ou_path
    on public.organization_units(church_id, path);
create index idx_ou_members_member
    on public.ou_members(church_id, church_member_id);
create index idx_ou_members_ou
    on public.ou_members(church_id, ou_id);
create index idx_periods_church_year_week
    on public.statistic_periods(church_id, year, week_no);
create index idx_submissions_church_period
    on public.statistic_submissions(church_id, period_id);
create index idx_submissions_ou
    on public.statistic_submissions(church_id, ou_id);
create index idx_submissions_status
    on public.statistic_submissions(status);
create index idx_values_submission
    on public.statistic_values(church_id, submission_id);
create index idx_values_metric
    on public.statistic_values(metric_id);
create index idx_submission_revisions_submission
    on public.submission_revisions(church_id, submission_id, revision_no desc);
create index idx_api_idempotency_expiry
    on public.api_idempotency_keys(expires_at);
create index idx_approval_logs_submission
    on public.approval_logs(church_id, submission_id);
create index idx_audit_logs_church_created
    on public.audit_logs(church_id, created_at desc);
create index idx_audit_logs_church_ou_created
    on public.audit_logs(church_id, ou_id, created_at desc);
create index idx_audit_logs_actor_created
    on public.audit_logs(church_id, actor_church_member_id, created_at desc);
create index idx_audit_logs_entity
    on public.audit_logs(church_id, entity_type, entity_id);
create index idx_audit_logs_request
    on public.audit_logs(request_id)
    where request_id is not null;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger trg_churches_updated_at
before update on public.churches
for each row execute function public.set_updated_at();

create trigger trg_users_updated_at
before update on public.users
for each row execute function public.set_updated_at();

create trigger trg_church_members_updated_at
before update on public.church_members
for each row execute function public.set_updated_at();

create trigger trg_tenant_invitations_updated_at
before update on public.tenant_invitations
for each row execute function public.set_updated_at();

create trigger trg_user_preferences_updated_at
before update on public.user_preferences
for each row execute function public.set_updated_at();

create trigger trg_organization_unit_types_updated_at
before update on public.organization_unit_types
for each row execute function public.set_updated_at();

create trigger trg_organization_units_updated_at
before update on public.organization_units
for each row execute function public.set_updated_at();

create trigger trg_ou_members_updated_at
before update on public.ou_members
for each row execute function public.set_updated_at();

create trigger trg_statistic_periods_updated_at
before update on public.statistic_periods
for each row execute function public.set_updated_at();

create trigger trg_statistic_metrics_updated_at
before update on public.statistic_metrics
for each row execute function public.set_updated_at();

create trigger trg_statistic_submissions_updated_at
before update on public.statistic_submissions
for each row execute function public.set_updated_at();

create trigger trg_statistic_values_updated_at
before update on public.statistic_values
for each row execute function public.set_updated_at();

create or replace function public.validate_statistic_value_data_type()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    expected_data_type varchar(30);
begin
    select metric.data_type
    into expected_data_type
    from public.statistic_metrics as metric
    where metric.church_id = new.church_id
      and metric.id = new.metric_id;

    if expected_data_type is null
       or (expected_data_type = 'number' and new.numeric_value is null)
       or (expected_data_type = 'text' and new.text_value is null)
       or (expected_data_type = 'boolean' and new.boolean_value is null) then
        raise exception 'STATISTIC_VALUE_DATA_TYPE_MISMATCH';
    end if;

    return new;
end;
$$;

create trigger trg_validate_statistic_value_data_type
before insert or update on public.statistic_values
for each row execute function public.validate_statistic_value_data_type();
