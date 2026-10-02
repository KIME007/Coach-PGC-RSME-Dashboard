-- Step before the lock: logged-in users (Supabase Auth) get the same access as the page's anon key.
-- Nothing is taken away yet; 20261002000002_login_required.sql removes anon access afterwards.

do $$
declare t text;
begin
  foreach t in array array['dashboard_store','report_years','failure_summary','failure_4m',
                           'monthly_failures','availability','pm_compliance','incidents','daily_reports']
  loop
    execute format('drop policy if exists "auth_all_%s" on public.%I', t, t);
    execute format('create policy "auth_all_%s" on public.%I for all to authenticated using (true) with check (true)', t, t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

grant execute on function public.rsd_sync_year(int, jsonb, text) to authenticated;
grant execute on function public.rsd_sync_daily(jsonb) to authenticated;
grant execute on function public.rsd_load_all() to authenticated;
