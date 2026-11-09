create or replace function app_security.report_ratio_result(
 p_metric_id uuid, p_scope_ou_id uuid, p_from_date date, p_to_date date, p_include_descendants boolean
)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
 tenant_id uuid := app_security.current_church_id();
 target_metric public.statistic_metrics%rowtype;
 scope_ou public.organization_units%rowtype;
 a numeric; b numeric;
begin
 select * into target_metric from public.statistic_metrics where id = p_metric_id and church_id = tenant_id
   and is_active and deleted_at is null and calculation_operator = 'ratio';
 select * into scope_ou from public.organization_units where id = p_scope_ou_id and church_id = tenant_id
   and is_active and deleted_at is null;
 if target_metric.id is null or scope_ou.id is null or not app_security.can_view_ou(scope_ou.id) then
   return app_security.ratio_result(null, null);
 end if;
 -- A side is present when at least one selected field has a numeric value.
 -- Require both sides in each approved submission before aggregating the scope.
 select case when count(sides.numerator) = count(*) then sum(sides.numerator) end,
        case when count(sides.denominator) = count(*) then sum(sides.denominator) end
 into a, b
 from (
   select sum(v.numeric_value) filter (where operand.pos <= target_metric.ratio_numerator_count) as numerator,
          sum(v.numeric_value) filter (where operand.pos > target_metric.ratio_numerator_count) as denominator
 from public.statistic_submissions submission
 join public.statistic_periods period on period.id = submission.period_id and period.church_id = tenant_id
   and period.period_end between p_from_date and p_to_date
 join public.organization_units ou on ou.id = submission.ou_id and ou.church_id = tenant_id
   and ou.structure_root_id = scope_ou.structure_root_id and ou.is_active and ou.deleted_at is null
   and ou.allow_data_entry and app_security.can_view_ou(ou.id)
   and (ou.id = scope_ou.id or (p_include_descendants and ou.path like scope_ou.path || '/%'))
 cross join unnest(target_metric.calculation_source_metric_ids) with ordinality operand(id, pos)
 left join public.statistic_values v on v.church_id = tenant_id and v.submission_id = submission.id and v.metric_id = operand.id
 where submission.church_id = tenant_id and submission.status = 'approved' and submission.deleted_at is null
 group by submission.id
 ) sides;
 return app_security.ratio_result(a, b);
end;
$$;
