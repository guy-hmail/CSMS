-- A future reporting period may already exist (for example, provisioned by an
-- operator). When rollover starts, move its opening time earlier instead of
-- preserving the later pre-created timestamp.

do $$
declare
  function_definition text;
begin
  select pg_get_functiondef('public.get_weekly_submission_context()'::regprocedure)
  into function_definition;

  if position(
    'submission_opens_at = coalesce(existing_period.submission_opens_at, excluded.submission_opens_at)'
    in function_definition
  ) = 0 then
    raise exception 'Expected submission rollover function definition was not found';
  end if;

  function_definition := replace(
    function_definition,
    'submission_opens_at = coalesce(existing_period.submission_opens_at, excluded.submission_opens_at)',
    'submission_opens_at = least(existing_period.submission_opens_at, excluded.submission_opens_at)'
  );

  execute function_definition;
end;
$$;

