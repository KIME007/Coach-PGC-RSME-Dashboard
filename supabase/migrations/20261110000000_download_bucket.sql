-- Private storage folder used only to hand big files (e.g. the presentation) back to Safari as a named download.
-- Each logged-in user can only touch files under their own folder (<user id>/...). Files are removed after download.
insert into storage.buckets (id, name, public, file_size_limit)
values ('downloads', 'downloads', false, 52428800)
on conflict (id) do nothing;

drop policy if exists "downloads own select" on storage.objects;
drop policy if exists "downloads own insert" on storage.objects;
drop policy if exists "downloads own update" on storage.objects;
drop policy if exists "downloads own delete" on storage.objects;

create policy "downloads own select" on storage.objects for select to authenticated
  using (bucket_id = 'downloads' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "downloads own insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'downloads' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "downloads own update" on storage.objects for update to authenticated
  using (bucket_id = 'downloads' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'downloads' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "downloads own delete" on storage.objects for delete to authenticated
  using (bucket_id = 'downloads' and (storage.foldername(name))[1] = auth.uid()::text);
