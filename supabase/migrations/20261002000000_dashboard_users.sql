-- Dashboard accounts with a simple ID + password (no email anywhere).
-- Supabase Auth needs an email internally, so ID "ali" is stored as ali@coachpgc.example.com;
-- people only ever type the ID. Run these in Supabase → SQL Editor:
--
--   select add_dashboard_user('ali', 'pass123');         -- new account
--   select set_dashboard_password('ali', 'newpass456');  -- change / reset a password
--   select remove_dashboard_user('ali');                 -- delete an account
--   select * from list_dashboard_users();                -- who has an account
--
-- Only the SQL Editor (database owner) can run them; the dashboard page cannot.

create or replace function public.dashboard_email(p_id text) returns text
language sql immutable as $$ select lower(trim(p_id)) || '@coachpgc.example.com' $$;

create or replace function public.add_dashboard_user(p_id text, p_password text)
returns text language plpgsql security definer set search_path = public, extensions, auth as $$
declare
  v_id    text := lower(trim(p_id));
  v_email text := public.dashboard_email(p_id);
  v_uid   uuid := gen_random_uuid();
begin
  if v_id !~ '^[a-z0-9][a-z0-9._-]{1,39}$' then
    raise exception 'ID must be 2-40 letters or numbers (. _ - allowed), no spaces';
  end if;
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  if exists (select 1 from auth.users where email = v_email) then
    raise exception 'ID "%" already exists — use set_dashboard_password to change its password', v_id;
  end if;

  insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                          raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                          confirmation_token, recovery_token, email_change_token_new, email_change)
  values ('00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated', v_email,
          extensions.crypt(p_password, extensions.gen_salt('bf')), now(),
          '{"provider":"email","providers":["email"]}', jsonb_build_object('dashboard_id', v_id),
          now(), now(), '', '', '', '');

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), v_uid, v_uid::text,
          jsonb_build_object('sub', v_uid::text, 'email', v_email, 'email_verified', true),
          'email', now(), now(), now());

  return 'Added "' || v_id || '" — they log in with ID ' || v_id;
end $$;

create or replace function public.set_dashboard_password(p_id text, p_password text)
returns text language plpgsql security definer set search_path = public, extensions, auth as $$
begin
  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Password must be at least 6 characters';
  end if;
  update auth.users
     set encrypted_password = extensions.crypt(p_password, extensions.gen_salt('bf')), updated_at = now()
   where email = public.dashboard_email(p_id);
  if not found then raise exception 'No account with ID "%"', lower(trim(p_id)); end if;
  return 'Password changed for "' || lower(trim(p_id)) || '"';
end $$;

create or replace function public.remove_dashboard_user(p_id text)
returns text language plpgsql security definer set search_path = public, auth as $$
begin
  delete from auth.users where email = public.dashboard_email(p_id);
  if not found then raise exception 'No account with ID "%"', lower(trim(p_id)); end if;
  return 'Removed "' || lower(trim(p_id)) || '"';
end $$;

create or replace function public.list_dashboard_users()
returns table (id text, created_at timestamptz, last_login timestamptz)
language sql security definer set search_path = public, auth as $$
  select split_part(u.email, '@', 1), u.created_at, u.last_sign_in_at
    from auth.users u
   where u.email like '%@coachpgc.example.com'
   order by 1
$$;

-- nobody but the database owner (SQL Editor) may run the account functions
revoke execute on function public.add_dashboard_user(text, text)     from public, anon, authenticated;
revoke execute on function public.set_dashboard_password(text, text) from public, anon, authenticated;
revoke execute on function public.remove_dashboard_user(text)         from public, anon, authenticated;
revoke execute on function public.list_dashboard_users()              from public, anon, authenticated;
