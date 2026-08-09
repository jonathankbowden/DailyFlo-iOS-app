-- 20260809_display_name_no_email_fallback.sql
--
-- Context
-- -------
-- After Apple Sign In with Hide-My-Email, profiles.display_name was being
-- populated with the private-relay email local-part (e.g. "7hcwmfhmfb"), and
-- the app then greeted the user by that string. An email local-part is NEVER
-- an acceptable display name — for private-relay addresses or any provider.
--
-- The source is the signup trigger on auth.users that seeds the profiles row.
-- Per the schema doc, all triggers were run interactively in the Supabase SQL
-- editor and are not otherwise in version control, so this file:
--   (a) dumps the current function for review,
--   (b) cleans the already-affected rows (safe to run now), and
--   (c) documents the recommended trigger change to apply AFTER reviewing (a).
--
-- Note: profiles.display_name is TEXT NOT NULL, so "empty" means '' (not NULL).
-- The iOS client (SignInView.persistAppleFullNameIfNeeded) writes the Apple
-- full name into display_name only while it is still '', so seeding '' here is
-- exactly what lets the once-only Apple name — and otherwise onboarding — fill
-- it in without being clobbered.


-- (a) INSPECT the current signup trigger/function BEFORE changing anything.
--     Run this first and read the returned definition:
select p.proname, pg_get_functiondef(p.oid) as definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where p.proname in ('handle_new_user', 'handle_new_auth_user', 'create_profile_for_user')
   or pg_get_functiondef(p.oid) ilike '%insert into%profiles%';


-- (b) CLEANUP (safe to run now). Clear email-derived display names so the
--     Apple-name path / onboarding can set a real one. Scoped precisely to the
--     junk pattern: display_name equals the email local-part. This matches the
--     private-relay case ("7hcwmfhmfb") and any other provider seeded the same
--     way, and won't touch names a user actually chose.
update public.profiles p
set display_name = ''
from auth.users u
where u.id = p.user_id
  and p.display_name is not null
  and p.display_name <> ''
  and p.display_name = split_part(u.email, '@', 1);

--     If you'd rather clear only your own test row, use your user id instead:
-- update public.profiles set display_name = '' where user_id = '<YOUR-UUID>';


-- (c) RECOMMENDED TRIGGER CHANGE — apply after reviewing the (a) output; MERGE
--     into the real function body, do not run this shape blind. In the signup
--     function, seed display_name with a literal empty string instead of
--     deriving it from the email, e.g.:
--
--       -- was (illustrative): coalesce(new.raw_user_meta_data->>'full_name',
--       --                              split_part(new.email, '@', 1))
--       -- now:
--       insert into public.profiles (user_id, display_name /* , …other cols… */)
--       values (new.id, '' /* , …unchanged… */);
--
--     Keep every other column the current function sets (role default, etc.)
--     exactly as-is — only the display_name seed expression changes.
