-- View-only accounts: they can log in and read everything, but cannot save.
-- Run in Supabase → SQL Editor:
--
--   select add_dashboard_viewer('301537', 'their-password');   -- new view-only account
--   select set_dashboard_viewer('301537', true);                -- make an existing ID view-only
--   select set_dashboard_viewer('301537', false);               -- give it edit rights again
--   select * from list_dashboard_users();                       -- shows who is view-only

-- true when the logged-in user is view-only (checked live, so a change applies at once)
create or replace function public.dashboard_is_viewer() returns boolean
language sql stable security definer set search_path = public, auth as $$
  select coalesce((select u.raw_app_meta_data->>'dashboard_role' = 'viewer'
                     from auth.users u where u.id = auth.uid()), false)
$$;
revoke execute on function public.dashboard_is_viewer() from public, anon;
grant execute on function public.dashboard_is_viewer() to authenticated;

-- everyone logged in may read; only non-viewers may write
do $$
declare
  tbls text[] := array['dashboard_store','report_years','failure_summary','failure_4m',
                       'monthly_failures','availability','pm_compliance','incidents','daily_reports'];
  t text;
  r record;
begin
  for r in select policyname, tablename from pg_policies
           where schemaname = 'public' and tablename = any(tbls)
  loop
    execute format('drop policy %I on public.%I', r.policyname, r.tablename);
  end loop;

  foreach t in array tbls
  loop
    execute format('create policy "read_%s" on public.%I for select to authenticated using (true)', t, t);
    execute format('create policy "insert_%s" on public.%I for insert to authenticated with check (not public.dashboard_is_viewer())', t, t);
    execute format('create policy "update_%s" on public.%I for update to authenticated using (not public.dashboard_is_viewer()) with check (not public.dashboard_is_viewer())', t, t);
    execute format('create policy "delete_%s" on public.%I for delete to authenticated using (not public.dashboard_is_viewer())', t, t);
  end loop;
end $$;

create or replace function public.set_dashboard_viewer(p_id text, p_viewer boolean)
returns text language plpgsql security definer set search_path = public, auth as $$
begin
  update auth.users
     set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
                             || jsonb_build_object('dashboard_role', case when p_viewer then 'viewer' else 'editor' end),
         updated_at = now()
   where email = public.dashboard_email(p_id);
  if not found then raise exception 'No account with ID "%"', lower(trim(p_id)); end if;
  return '"' || lower(trim(p_id)) || '" is now ' || case when p_viewer then 'VIEW ONLY' else 'able to edit' end;
end $$;

create or replace function public.add_dashboard_viewer(p_id text, p_password text)
returns text language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  perform public.add_dashboard_user(p_id, p_password);
  perform public.set_dashboard_viewer(p_id, true);
  return 'Added "' || lower(trim(p_id)) || '" as VIEW ONLY — they log in with ID ' || lower(trim(p_id));
end $$;

drop function if exists public.list_dashboard_users();
create function public.list_dashboard_users()
returns table (id text, access text, created_at timestamptz, last_login timestamptz)
language sql security definer set search_path = public, auth as $$
  select split_part(u.email, '@', 1),
         case when u.raw_app_meta_data->>'dashboard_role' = 'viewer' then 'view only' else 'edit' end,
         u.created_at, u.last_sign_in_at
    from auth.users u
   where u.email like '%@coachpgc.example.com'
   order by 1
$$;

revoke execute on function public.set_dashboard_viewer(text, boolean) from public, anon, authenticated;
revoke execute on function public.add_dashboard_viewer(text, text)    from public, anon, authenticated;
revoke execute on function public.list_dashboard_users()              from public, anon, authenticated;
