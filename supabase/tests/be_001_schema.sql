\set ON_ERROR_STOP on

select '1..1';

begin;

do $$
declare
    actual_count integer;
begin
    select count(*)
    into actual_count
    from information_schema.tables
    where table_schema = 'public'
      and table_type = 'BASE TABLE'
      and table_name = any (array[
          'churches',
          'users',
          'church_members',
          'tenant_invitations',
          'user_preferences',
          'organization_unit_types',
          'organization_units',
          'ou_members',
          'statistic_periods',
          'metric_template_sets',
          'statistic_metrics',
          'statistic_submissions',
          'statistic_values',
          'submission_revisions',
          'api_idempotency_keys',
          'approval_logs',
          'audit_logs'
      ]);

    if actual_count <> 17 then
        raise exception 'Expected 17 BE-001 tables, found %', actual_count;
    end if;
end;
$$;

insert into public.churches (
    id,
    code,
    slug,
    name,
    status
)
values
    (
        '00000000-0000-0000-0000-000000000001',
        'TEST_A',
        'test-a',
        'Test Church A',
        'active'
    ),
    (
        '00000000-0000-0000-0000-000000000002',
        'TEST_B',
        'test-b',
        'Test Church B',
        'active'
    );

insert into public.users (
    id,
    auth_user_id,
    line_user_id,
    display_name
)
values (
    '10000000-0000-0000-0000-000000000001',
    '11000000-0000-0000-0000-000000000001',
    'line-test-user',
    'Schema Test User'
);

insert into public.organization_unit_types (
    id,
    church_id,
    code,
    name
)
values
    (
        '20000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        'ROOT',
        'Root'
    ),
    (
        '20000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000002',
        'ROOT',
        'Root'
    );

insert into public.organization_units (
    id,
    church_id,
    structure_root_id,
    parent_id,
    ou_type_id,
    code,
    name,
    path,
    level
)
values
    (
        '30000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        '30000000-0000-0000-0000-000000000001',
        null,
        '20000000-0000-0000-0000-000000000001',
        'ROOT',
        'Root A',
        '/30000000-0000-0000-0000-000000000001',
        1
    ),
    (
        '30000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000002',
        '30000000-0000-0000-0000-000000000002',
        null,
        '20000000-0000-0000-0000-000000000002',
        'ROOT',
        'Root B',
        '/30000000-0000-0000-0000-000000000002',
        1
    );

do $$
begin
    begin
        insert into public.organization_units (
            id,
            church_id,
            structure_root_id,
            parent_id,
            ou_type_id,
            code,
            name,
            path,
            level
        )
        values (
            '30000000-0000-0000-0000-000000000003',
            '00000000-0000-0000-0000-000000000001',
            '30000000-0000-0000-0000-000000000001',
            '30000000-0000-0000-0000-000000000002',
            '20000000-0000-0000-0000-000000000001',
            'INVALID_PARENT',
            'Invalid Cross-Tenant Parent',
            '/invalid-parent',
            2
        );

        raise exception 'Cross-tenant OU parent was accepted';
    exception
        when foreign_key_violation then
            null;
    end;
end;
$$;

do $$
begin
    begin
        insert into public.organization_units (
            id,
            church_id,
            structure_root_id,
            parent_id,
            ou_type_id,
            code,
            name,
            path,
            level
        )
        values (
            '30000000-0000-0000-0000-000000000004',
            '00000000-0000-0000-0000-000000000001',
            '30000000-0000-0000-0000-000000000004',
            null,
            '20000000-0000-0000-0000-000000000001',
            'SECOND_ROOT',
            'Second Root',
            '/second-root',
            1
        );

        raise exception 'A second active tenant root was accepted';
    exception
        when unique_violation then
            null;
    end;
end;
$$;

update public.churches
set name = 'Updated Church A',
    updated_at = '2000-01-01 00:00:00+00'
where id = '00000000-0000-0000-0000-000000000001';

do $$
begin
    if (
        select updated_at <= '2000-01-01 00:00:00+00'
        from public.churches
        where id = '00000000-0000-0000-0000-000000000001'
    ) then
        raise exception 'set_updated_at trigger did not replace the supplied timestamp';
    end if;
end;
$$;

insert into public.statistic_metrics (
    id,
    church_id,
    code,
    name,
    category,
    unit,
    data_type,
    input_type,
    aggregation
)
values
    (
        '40000000-0000-0000-0000-000000000001',
        '00000000-0000-0000-0000-000000000001',
        'ATTENDANCE',
        'Attendance',
        'attendance',
        'person',
        'number',
        'number',
        'sum'
    ),
    (
        '40000000-0000-0000-0000-000000000002',
        '00000000-0000-0000-0000-000000000002',
        'ATTENDANCE',
        'Attendance',
        'attendance',
        'person',
        'number',
        'number',
        'sum'
    );

insert into public.statistic_periods (
    id,
    church_id,
    year,
    week_no,
    period_start,
    period_end,
    label
)
values (
    '50000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    2026,
    30,
    date '2026-07-20',
    date '2026-07-26',
    '2026-W30'
);

insert into public.statistic_submissions (
    id,
    church_id,
    period_id,
    ou_id
)
values (
    '60000000-0000-0000-0000-000000000001',
    '00000000-0000-0000-0000-000000000001',
    '50000000-0000-0000-0000-000000000001',
    '30000000-0000-0000-0000-000000000001'
);

do $$
begin
    begin
        insert into public.statistic_values (
            church_id,
            submission_id,
            metric_id,
            text_value
        )
        values (
            '00000000-0000-0000-0000-000000000001',
            '60000000-0000-0000-0000-000000000001',
            '40000000-0000-0000-0000-000000000001',
            'wrong type'
        );

        raise exception 'A text value was accepted for a numeric metric';
    exception
        when others then
            if sqlerrm <> 'STATISTIC_VALUE_DATA_TYPE_MISMATCH' then
                raise;
            end if;
    end;
end;
$$;

insert into public.statistic_values (
    church_id,
    submission_id,
    metric_id,
    numeric_value
)
values (
    '00000000-0000-0000-0000-000000000001',
    '60000000-0000-0000-0000-000000000001',
    '40000000-0000-0000-0000-000000000001',
    42
);

do $$
begin
    begin
        insert into public.statistic_values (
            church_id,
            submission_id,
            metric_id,
            numeric_value
        )
        values (
            '00000000-0000-0000-0000-000000000001',
            '60000000-0000-0000-0000-000000000001',
            '40000000-0000-0000-0000-000000000002',
            10
        );

        raise exception 'A cross-tenant metric reference was accepted';
    exception
        when others then
            -- The BEFORE trigger rejects the tenant-mismatched metric before
            -- PostgreSQL reaches the composite foreign-key check.
            if sqlerrm <> 'STATISTIC_VALUE_DATA_TYPE_MISMATCH' then
                raise;
            end if;
    end;
end;
$$;

select 'ok 1 - BE-001 schema and constraints';
rollback;
