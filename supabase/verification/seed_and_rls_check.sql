-- ============================================================
-- DailyFLO — seed data + RLS verification
-- Run in: Supabase Dashboard → SQL Editor
-- Date: 2026-07-18
--
-- PREREQ (do in dashboard first, not SQL):
--   Authentication → Users → Add user (×2):
--     tracker:   test-tracker@dailyfloapp.com
--     supporter: test-supporter@dailyfloapp.com
--   The signup trigger auto-creates their profiles rows.
--   Then paste their UUIDs below, replacing the placeholders.
-- ============================================================

-- ------------------------------------------------------------
-- SECTION 0 — introspection: confirm actual columns before
-- seeding. If any column names differ from what Sections 1-2
-- assume, adjust there before running.
-- ------------------------------------------------------------
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
order by table_name, ordinal_position;

select tablename, policyname, cmd, roles
from pg_policies
where schemaname = 'public'
order by tablename;

-- Confirm RLS is enabled on every table (relrowsecurity must be true):
select relname, relrowsecurity
from pg_class
where relnamespace = 'public'::regnamespace and relkind = 'r';

-- ------------------------------------------------------------
-- SECTION 1 — seed. Replace the two placeholder UUIDs first.
-- Runs as postgres (bypasses RLS) — that's fine for seeding.
-- ------------------------------------------------------------
do $$
declare
  tracker   uuid := 'REPLACE-WITH-TRACKER-UUID';
  supporter uuid := 'REPLACE-WITH-SUPPORTER-UUID';
  cycle_id  uuid;
begin
  -- One real cycle for the tracker, started 10 days ago
  insert into cycles (user_id, start_date, cycle_length_days)
  values (tracker, current_date - 10, 28)
  returning id into cycle_id;

  -- 5 daily cycle entries (start date + optional BBT only — per
  -- locked May 26 decision, flow/symptoms stay unused)
  insert into cycle_entries (user_id, cycle_id, date, basal_temp_f)
  select tracker, cycle_id, current_date - offs, 97.4 + (offs * 0.1)
  from generate_series(6, 10) as offs;

  -- 3 emotion entries (Chip Dodd 8-core set)
  insert into emotion_entries (user_id, date, primary_emotion, intensity, notes)
  values
    (tracker, current_date - 2, 'glad',  4, 'seed: good day'),
    (tracker, current_date - 1, 'fear',  2, 'seed: nervous about launch'),
    (tracker, current_date,     'sad',   3, 'seed: quiet morning');

  -- Partner relationship: supporter may see cycle phase only
  insert into partner_relationships
    (tracker_user_id, supporter_user_id, relationship_type, status, permissions, invited_at, accepted_at)
  values
    (tracker, supporter, 'partner', 'active',
     '{"view_phase": true, "view_emotions": false, "view_cycle_details": false}'::jsonb,
     now() - interval '1 day', now());
end $$;

-- 3 meditations (admin catalog — not user-owned)
insert into meditations (title, description, duration_seconds, audio_url, category, composer, license_type, published_at)
values
  ('Stillwater',  'seed', 600, 'https://example.com/a.mp3', 'calm',  'Suno', 'ai_generated', now()),
  ('Open Hills',  'seed', 480, 'https://example.com/b.mp3', 'calm',  'Suno', 'ai_generated', now()),
  ('Golden Hour', 'seed', 540, 'https://example.com/c.mp3', 'sleep', 'Suno', 'ai_generated', now());

-- ------------------------------------------------------------
-- SECTION 2 — RLS verification. Each block simulates a signed-in
-- user. Run each block SEPARATELY and check the noted expectation.
-- rollback at the end so nothing sticks.
-- ------------------------------------------------------------

-- 2a. TRACKER sees own data (EXPECT: 1 cycle, 5 entries, 3 emotions)
begin;
  set local role authenticated;
  select set_config('request.jwt.claims',
    json_build_object('sub', 'REPLACE-WITH-TRACKER-UUID', 'role', 'authenticated')::text, true);
  select count(*) as my_cycles   from cycles;
  select count(*) as my_entries  from cycle_entries;
  select count(*) as my_emotions from emotion_entries;
rollback;

-- 2b. SUPPORTER's direct visibility
-- EXPECT: cycles visible ONLY if partner_has_permission grants view_phase
-- via policy; emotion_entries MUST be 0 (view_emotions = false).
-- If my_partner_emotions returns anything but 0, STOP: the partner RLS
-- leaks journal data — highest-severity finding possible here.
begin;
  set local role authenticated;
  select set_config('request.jwt.claims',
    json_build_object('sub', 'REPLACE-WITH-SUPPORTER-UUID', 'role', 'authenticated')::text, true);
  select count(*) as partner_visible_cycles   from cycles;
  select count(*) as my_partner_emotions      from emotion_entries;
  select count(*) as visible_relationships    from partner_relationships;
rollback;

-- 2c. SUPPORTER attempts to WRITE into tracker's data (EXPECT: 0 rows /
-- error on both — a supporter must never write tracker rows)
begin;
  set local role authenticated;
  select set_config('request.jwt.claims',
    json_build_object('sub', 'REPLACE-WITH-SUPPORTER-UUID', 'role', 'authenticated')::text, true);
  insert into emotion_entries (user_id, date, primary_emotion, intensity)
  values ('REPLACE-WITH-TRACKER-UUID', current_date, 'anger', 5);
rollback;

-- 2d. Anonymous (EXPECT: 0 rows everywhere except perhaps meditations,
-- if the catalog is deliberately public-read)
begin;
  set local role anon;
  select count(*) as anon_cycles      from cycles;
  select count(*) as anon_emotions    from emotion_entries;
  select count(*) as anon_meditations from meditations;
rollback;

-- ------------------------------------------------------------
-- SECTION 3 — permission function direct test
-- EXPECT: true, then false
-- ------------------------------------------------------------
select partner_has_permission('REPLACE-WITH-TRACKER-UUID'::uuid,
                              'REPLACE-WITH-SUPPORTER-UUID'::uuid,
                              'view_phase')    as should_be_true,
       partner_has_permission('REPLACE-WITH-TRACKER-UUID'::uuid,
                              'REPLACE-WITH-SUPPORTER-UUID'::uuid,
                              'view_emotions') as should_be_false;
