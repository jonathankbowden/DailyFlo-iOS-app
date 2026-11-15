-- 20261114_meditation_catalog.sql
--
-- Turns `meditations` into the Pause catalog source of truth: one row per
-- theme × duration (5 / 10 / 60 min), so adding a row adds a track with no new
-- app build. Additive and re-runnable — ADD COLUMN IF NOT EXISTS, no drops.
--
-- The table already carries NOT NULL legacy columns (description,
-- duration_seconds, audio_url, category, composer, license_type); the seed
-- fills each. `audio_url` holds a `bundled:` placeholder until Storage
-- streaming lands (tomorrow) and the real path moves into the new `audio_path`.
--
-- Per the Sept 1 lesson (CLAUDE.md): new/altered tables need explicit
-- service_role GRANTs or Edge Functions hit "permission denied".

-- 1. New columns (additive) ---------------------------------------------------
alter table public.meditations add column if not exists theme_key       text;
alter table public.meditations add column if not exists phase           text;
alter table public.meditations add column if not exists duration_minutes int;
alter table public.meditations add column if not exists image_name       text;
alter table public.meditations add column if not exists audio_path       text;    -- Supabase Storage path (streaming, later)
alter table public.meditations add column if not exists bundled_audio    text;    -- bundled MP3 resource name (today)
alter table public.meditations add column if not exists ambient_sound    text;    -- AmbientAudioEngine synth fallback
alter table public.meditations add column if not exists sort_order       int     not null default 0;
-- Default FALSE so any pre-existing legacy rows stay out of the catalog; the
-- seed below flips the 30 Mozier slots to TRUE.
alter table public.meditations add column if not exists is_active        boolean not null default false;

-- 2. One slot per (theme, duration) -------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'meditations_theme_duration_key'
  ) then
    alter table public.meditations
      add constraint meditations_theme_duration_key unique (theme_key, duration_minutes);
  end if;
end $$;

-- 3. RLS: authenticated may read active rows; no client writes ----------------
alter table public.meditations enable row level security;

drop policy if exists "meditations_select_active" on public.meditations;
create policy "meditations_select_active"
  on public.meditations
  for select
  to authenticated
  using (is_active = true and deleted_at is null);

-- No INSERT/UPDATE/DELETE policy → client writes stay denied (admin-only).

-- 4. Grants (re-run if the DB is ever rebuilt) --------------------------------
grant select on public.meditations to authenticated;
grant select, insert, update, delete on public.meditations to service_role;

-- 5. Seed the 30 slots (upsert) ----------------------------------------------
-- Image variants map to the duration tabs by index: 5 → _a, 10 → _b, 60 → _c
-- (matches MeditationDuration order in the app). One looping track per theme
-- today, so bundled_audio is the same across a theme's three rows.
with themes(theme_key, title, phase, image_base, bundled_base, ambient_sound, sort_order) as (
  values
    ('mist',       'MIST',        'menstrual',  'medbg_mist',       'mist_05min',       'gentleRain',     1),
    ('nightsky',   'NIGHT SKY',   'menstrual',  'medbg_nightsky',   'nightsky_05min',   'nightAmbience',  2),
    ('stillwater', 'STILLWATER',  'menstrual',  'medbg_stillwater', 'stillwater_05min', 'warmDrone',      3),
    ('canopy',     'CANOPY',      'follicular', 'medbg_canopy',     'canopy_05min',     'forestBreeze',   4),
    ('openhills',  'OPEN HILLS',  'follicular', 'medbg_openhills',  'openhills_05min',  'forestBreeze',   5),
    ('goldenhour', 'GOLDEN HOUR', 'ovulation',  'medbg_goldenhour', 'goldenhour_05min', 'softChimes',     6),
    ('ocean',      'OCEAN',       'ovulation',  'medbg_ocean',      'ocean_05min',      'oceanWaves',     7),
    ('storm',      'STORM',       'luteal',     'medbg_storm',      'storm_05min',      'gentleRain',     8),
    ('forest',     'FOREST',      'luteal',     'medbg_forest',     'forest_05min',     'forestBreeze',   9),
    ('solitude',   'SOLITUDE',    'luteal',     'medbg_solitude',   'solitude_05min',   'warmDrone',     10)
),
durations(duration_minutes, variant) as (
  values (5, '_a'), (10, '_b'), (60, '_c')
)
insert into public.meditations as m (
  theme_key, title, phase, duration_minutes, image_name,
  audio_path, bundled_audio, ambient_sound,
  description, duration_seconds, audio_url, category,
  composer, license_type, sort_order, is_active, published_at
)
select
  t.theme_key,
  t.title,
  t.phase,
  d.duration_minutes,
  t.image_base || d.variant                       as image_name,
  null                                            as audio_path,     -- filled when streaming lands
  t.bundled_base                                  as bundled_audio,
  t.ambient_sound,
  t.title                                         as description,    -- placeholder; admin can enrich
  d.duration_minutes * 60                         as duration_seconds,
  'bundled:' || t.bundled_base                    as audio_url,      -- legacy NOT NULL placeholder
  'cycle_' || t.phase                             as category,
  'Mozier'                                        as composer,
  'work_for_hire'                                 as license_type,   -- confirm provenance w/ Brittany
  t.sort_order                                    as sort_order,
  true                                            as is_active,
  now()                                           as published_at
from themes t
cross join durations d
on conflict (theme_key, duration_minutes) do update set
  title            = excluded.title,
  phase            = excluded.phase,
  image_name       = excluded.image_name,
  bundled_audio    = excluded.bundled_audio,
  ambient_sound    = excluded.ambient_sound,
  duration_seconds = excluded.duration_seconds,
  category         = excluded.category,
  composer         = excluded.composer,
  license_type     = excluded.license_type,
  sort_order       = excluded.sort_order,
  is_active        = excluded.is_active,
  updated_at       = now();
  -- Intentionally NOT overwritten on re-run: audio_path, audio_url,
  -- description, published_at — so Storage paths and admin edits survive.
