-- 20261117_journal_photos.sql
--
-- Backs journal entry photos up to Supabase Storage so they survive
-- delete/reinstall and a new phone. Re-runnable.
--
-- MANUAL STEP (once, in the dashboard): create a PRIVATE Storage bucket named
-- `journal-photos`. This file only adds the column + the RLS policies.
--
-- Layout: journal-photos/<uid>/<entryId>.jpg — the first path segment is the
-- owner's auth uid, which the policies below enforce. `emotion_entries.photo_path`
-- stores the object key ("<uid>/<entryId>.jpg"); emotion_entries rows (and thus
-- photo_path) are already erased by delete_my_account(), and the Storage objects
-- themselves are removed via the Storage API before that RPC runs.

-- 1. Column for the Storage object key (nullable; null = no backed-up photo).
alter table public.emotion_entries
  add column if not exists photo_path text;

-- 2. Per-user access to the private bucket. `storage.foldername(name)` splits the
--    object key on '/'; element [1] (Postgres arrays are 1-indexed) is the first
--    folder, which must equal the caller's uid. SELECT/INSERT/UPDATE/DELETE only
--    within your own folder; no cross-user access, no public read.
drop policy if exists "journal_photos_select_own" on storage.objects;
create policy "journal_photos_select_own"
  on storage.objects for select to authenticated
  using (bucket_id = 'journal-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "journal_photos_insert_own" on storage.objects;
create policy "journal_photos_insert_own"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'journal-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "journal_photos_update_own" on storage.objects;
create policy "journal_photos_update_own"
  on storage.objects for update to authenticated
  using (bucket_id = 'journal-photos' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'journal-photos' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "journal_photos_delete_own" on storage.objects;
create policy "journal_photos_delete_own"
  on storage.objects for delete to authenticated
  using (bucket_id = 'journal-photos' and (storage.foldername(name))[1] = auth.uid()::text);
