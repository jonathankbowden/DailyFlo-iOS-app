-- 20261115_meditations_storage_read.sql
--
-- Lets signed-in users read objects in the private `meditations` Storage
-- bucket, so the app can mint signed URLs and stream the tracks. Re-runnable
-- (drop policy if exists → create). SELECT only — no insert/update/delete, so
-- clients can read but never write the bucket (admin uploads via dashboard).
--
-- Storage objects live in storage.objects; `bucket_id` is the bucket name.

drop policy if exists "meditations_read_authenticated" on storage.objects;
create policy "meditations_read_authenticated"
  on storage.objects
  for select
  to authenticated
  using (bucket_id = 'meditations');
