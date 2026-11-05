-- Create view-only account 301537 (password stored only as a bcrypt hash; the owner can change it in SQL Editor
-- with: select set_dashboard_password('301537', 'new-password');)
do $$
begin
  if not exists (select 1 from auth.users where email = public.dashboard_email('301537')) then
    perform public.add_dashboard_user('301537', md5(random()::text));
  end if;
  update auth.users set encrypted_password = '$2a$10$7kWfml0dAauSnzhDxQQFuukYdyGXV0wPipYVCvE8luq6N1RavJJa.', updated_at = now()
   where email = public.dashboard_email('301537');
  perform public.set_dashboard_viewer('301537', true);
end $$;
