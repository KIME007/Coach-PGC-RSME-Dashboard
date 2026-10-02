-- Only logged-in users (Supabase Auth) can read or change the dashboard data.
-- The anon key in the page can no longer reach any table or sync function.

do $$
declare
  tbls text[] := array['dashboard_store','report_years','failure_summary','failure_4m',
                       'monthly_failures','availability','pm_compliance','incidents','daily_reports'];
  t text;
  r record;
begin
  -- remove every existing policy on these tables (including any created by hand)
  for r in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename = any(tbls)
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;

  foreach t in array tbls
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "auth_all_%s" on public.%I for all to authenticated using (true) with check (true)', t, t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

revoke execute on function public.rsd_sync_year(int, jsonb, text) from public, anon;
revoke execute on function public.rsd_sync_daily(jsonb) from public, anon;
revoke execute on function public.rsd_load_all() from public, anon;
grant execute on function public.rsd_sync_year(int, jsonb, text) to authenticated;
grant execute on function public.rsd_sync_daily(jsonb) to authenticated;
grant execute on function public.rsd_load_all() to authenticated;

-- remove the temporary account used to test the login before locking
delete from auth.users where email = 'logintest@coachpgc.example.com';
