# DailyFLO — Project Context for Claude

This file gives you (Claude) the context you need to be immediately useful in this iOS project. Read it on every session. Treat the planning docs referenced at the bottom as the source of truth for anything not covered here.

## Project location & hygiene (read first, enforce every session)

On May 20, 2026 this project nearly lost untracked work because two out-of-sync copies existed (one in Dropbox, one in `~/Developer/DailyFlo`) and tooling wrote to different copies. These rules exist to prevent a recurrence. **Follow and reinforce them.**

1. **Canonical location is `~/Developer/Personal/DailyFlo/` ONLY.** (Moved from `~/Developer/DailyFlo/` in July 2026 when the folder was split into Personal/ and Ninety/.) Never create, edit, or open a copy of this project inside any cloud-synced folder (Dropbox, iCloud Drive, OneDrive, Google Drive). Cloud sync corrupts `.xcodeproj` files and silently spawns duplicate copies. If you ever detect the project running from a synced path, STOP and flag it to Jonathan immediately — do not write files.

2. **At the start of every session,** verify you're operating on `~/Developer/Personal/DailyFlo/` and run `git status` so you and Jonathan both know what's uncommitted before making changes. If something looks like it's in a different location, surface it before proceeding.

3. **Git is the source of truth; GitHub is the backup.** Remote: `github.com/jonathankbowden/DailyFlo-iOS-app`. Commit often. Untracked files are the only files that can truly vanish — so when you create or substantially edit Swift files, remind Jonathan to commit them (even to a WIP branch) rather than leaving them untracked.

4. **End-of-session ritual.** After any meaningful work, prompt Jonathan to commit and push:
   ```
   git status
   git add -A
   git commit -m "..."
   git push
   ```
   The goal: never end a session with hard-to-recreate work uncommitted. Worst case should be losing the current session, never days.

5. **No lingering duplicate copies.** There should be exactly one working copy of this project. If a second copy appears, consolidate to `~/Developer/Personal/DailyFlo/` and archive/delete the other — don't leave two live copies that can drift.

6. **`.gitignore` must keep build artifacts and secrets out of git.** `SupabaseConfig.xcconfig` (real credentials) is gitignored; `SupabaseConfig.xcconfig.example` is committed. DerivedData, build products, and `.DS_Store` stay ignored.


## What DailyFLO is

A subscription iOS app for women across a wide age range (teens through women in long marriages, including post-menopause as a v1.x audience). Combines cycle tracking, daily emotion journaling, integrated meditation with music, and a partner/parent share loop. Faith-informed in tone and worldview, not explicitly evangelical. Visual identity is soft neutrals and nature tones — no pinks/purples, no body imagery.

Founded May 2026 by Jonathan Bowden and his wife Brittany Bowden (50/50). Bootstrapped. **Current target: submit to App Review September 29, 2026** via the "30 for 30" cadence (30 min/day, Sept 1–30; TestFlight build at the end of each week — builds 16–19). The original July 1 target passed during a capacity crunch; the September plan is the active one.

The Bowdens also operate a separate design partnership called **Kreathaus**. Keep DailyFLO IP cleanly separated from Kreathaus work.

## Stack

- **iOS app:** Swift, SwiftUI (iOS 17+ idioms — `@Observable`, modern concurrency)
- **Backend:** Supabase (Postgres, Auth, Storage)
- **Subscriptions:** RevenueCat + Apple StoreKit
- **Analytics:** PostHog
- **Crash reporting:** Sentry
- **Future:** Cloudflare R2 for audio CDN (post-launch)
- **Music for meditations:** Suno Pro generated + originals from a church musician (hybrid model)

## Current build state (as of September 1, 2026 — build 15)

### What's real and wired

- **Auth is real.** Sign in with Apple (native button + direct ASAuthorizationController), Google, and email — email is **passwordless OTP** via `signInWithOtp` (June 10 decision; the password path is kept hidden for App Review). All sign-in methods flow through one central auth loop. Apple full name persisted; revoked/existing-account cases handled; display_name never derived from email.
- **Cycle and journal sync to Supabase.** `CycleManager` → `profiles` + `cycles`; `JournalManager` → `emotion_entries` (one entry per day enforced). UserDefaults remains the local cache layer. Onboarding persists via deferred write on first authed launch. 13+ age gate enforced with a birth-date onboarding page.
- **RevenueCat is live end to end.** SDK integrated, purchases work, `linkUser`/`unlinkUser` in `SubscriptionManager` tie the RevenueCat customer to the Supabase auth UUID from the central auth loop. The `revenuecat-webhook` Supabase Edge Function is **deployed and verified** (first 200 received Sept 1); webhook wired in the RevenueCat dashboard for both environments.
- **UI shell is polished and complete.** Splash → onboarding → signIn → 5-tab main with custom FAB. Design system (`DesignSystem.swift`) is mature — use its tokens, never hardcode design values.
- **Cycle math works.** Phases, next-period prediction, day-of-cycle, month calendar generation.
- **Voice entry exists.** `VoiceEntryView` + `SpeechRecognizer` — feature flag candidate if it gets flaky.
- **Supabase backend is complete.** 10 tables with RLS on every one; migrations live in `supabase/migrations/` (see schema section).

### What's still fake or missing (the 30-for-30 punch list)

- **Partner share is fully mocked.** `ConnectView` UI is complete across all three states, but invitation logic is random local codes + a "Demo: Skip to Connected" button. Real backend wiring is Week 2 of the September plan.
- **No privacy manifest** (`PrivacyInfo.xcprivacy`) — required for App Review.
- **No Sentry, no PostHog.** Accounts exist; SDKs not integrated (Week 3).
- **No tests.**
- **No offline write queue** for failed Supabase writes (journal first, Week 3).
- **Fake journal content seeds on fresh install** and dev tools aren't gated out of Release builds — both being removed early in Week 1.

## Locked product decisions (Week 1, May 18–19, 2026)

These are settled — don't re-litigate them in suggestions:

- **Partner share ships in v1.** Not deferred. It's the core differentiator and the growth loop.
- **Single parameterized onboarding flow**, not branched by age. Captures age early, adapts subsequent screens.
- **13+ age gate.** No parental consent flow for v1. Under-13 use case revisits in v1.x.
- **BBT (basal body temperature) is in v1** as an optional simple field on `cycle_entries`. Framed as body literacy, not fertility tracking. No fertile-window predictions from it.
- **Never ask for symptoms (locked May 26).** No symptom picker, chips, or physical-symptom inputs anywhere. The `Symptom`/`SymptomCategory`/`SymptomPickerSheet` machinery in `LogCycleView.swift` is being removed. The `cycle_entries.symptoms` column becomes vestigial — leave it unused.
- **Never ask for cycle flow / "heaviness" (locked May 26).** No light/medium/heavy selector. The `FlowLevel` enum + `FlowLevelButton` in `LogCycleView.swift` are being removed. The `cycle_entries.flow` column becomes vestigial. Net effect: v1 cycle logging = **period start date + optional BBT only**. This deliberately differentiates DailyFLO from clinical trackers (Flo, Clue).
- **No pinks or purples (reinforced May 26).** They read as stereotypically "female." Reject pink/purple even as accents. Palette stays soft neutrals + nature tones (floCream / floSage / floCharcoal / floGray / floMint + phase colors).
- **Legal entity:** DailyFLO LLC (Colorado, formed May 18). Apple Developer Program Individual → Organization conversion pending DUNS.
- **Music approach:** Suno Pro for the library + a church musician for signature originals (hybrid). Suno Pro plan required for commercial rights.
- **Emotion framework:** Currently scoped to Chip Dodd's 8 Core Emotions (hurt, lonely, sad, anger, fear, shame, guilt, glad). Brittany is deciding whether to ask permission or build a distinct framework — schema is framework-agnostic so the CHECK constraint can swap if needed.

## UI decisions since May

- **Journal base view (locked June): simple vertical feed, "Option B."** The omni-scroll 2D day-card calendar grid ("Option A") is **parked to v2 — do not re-pitch it.** v1 journal is a straightforward vertical feed of entries.
- **Tab bar restructure (designed May 26):** Profile, Calendar, [+] FAB, Journal, Pause (Meditation), with Profile as the default-selected landing tab absorbing the Home dashboard. **Verify against `ContentView.swift` before assuming built or unbuilt** — don't trust this doc for its current state.
- All UI work honors the locked design constraints: no symptoms, no flow/heaviness, no pinks/purples.

## Supabase schema (live; migrations in `supabase/migrations/`)

All 10 tables exist in the live Supabase project with full RLS:

- `profiles` — one per auth.users, with `life_stage` enum, timezone, temperature_unit, notification_preferences
- `cycles` — one per menstrual cycle
- `cycle_entries` — daily logs (flow, symptoms, **basal_temp_f**, notes)
- `emotion_entries` — daily Chip Dodd journal entries (primary_emotion, intensity 1–5, voice_note_url)
- `meditations` — admin-managed catalog (composer, license_type for hybrid music model)
- `meditation_sessions` — playback history
- `partner_relationships` — tracker ↔ supporter with JSONB permissions
- `invitations` — pending invites with short codes
- `subscriptions` — local mirror of RevenueCat data
- `auth.users` — Supabase-managed

Plus a `partner_has_permission(tracker_id, supporter_id, permission_key)` SQL function used by RLS policies on cycles, cycle_entries, emotion_entries. And a trigger on `auth.users` that auto-creates a `profiles` row on signup.

Since June: `subscription_webhook_events` table + five webhook columns on `subscriptions` (June 3 migration, applied to prod Sept 1). The `revenuecat-webhook` Edge Function lives in `supabase/functions/` and is deployed.

**⚠️ Hard-won lesson (Sept 1):** on this Supabase project, **new tables do NOT automatically get `service_role` access.** Every migration that creates a table must include explicit `GRANT` lines for `service_role` (see `20260901_grant_service_role_subscriptions.sql`), or Edge Functions will fail with "permission denied."

**Full schema spec:** `/Users/jonathanbowden/Documents/Claude/Projects/Daily flow app/dailyflo-supabase-schema.md`

## Supabase credentials

- **Project URL:** `https://ntyxfqwrtqscmdefbyfc.supabase.co`
- **Publishable key:** Stored in 1Password / locked Notes labeled "DailyFLO Supabase credentials". Safe to use in iOS client code.
- **Secret key:** Stored in locked Notes. **Never use in iOS code, never commit to git.** Server-side only.

When integrating the SDK, read credentials from a `.xcconfig` file or `Info.plist` that is gitignored — never hardcode them in source files.

## Auth decisions (current)

- **v1 auth = Sign in with Apple, Google, and passwordless email OTP** on a unified "Continue with" screen. Apple listed first (privacy positioning + App Store Guideline 4.8).
- **Meta (Facebook Login) is OUT for v1** (decided Sept 1, 2026). Remove or keep-hidden any Meta button stubs; don't build the provider config.
- Email is `signInWithOtp` — no password at signup. A password path exists but stays hidden for App Review. Phone OTP deferred to v1.x.

## Next engineering work — the 30-for-30 plan (Sept 1–30, 2026)

One finishable ~30-minute task per day; day N = September N. The authoritative day-by-day list lives in Jonathan's Cowork "dailyflo-30-for-30" tracker. Shape of the month:

1. **Week 1 — clear the blockers:** rotate webhook secret + prove sandbox purchase chain (row lands in `subscriptions`), privacy manifest, remove fake journal seed + gate dev tools out of Release, this doc rewrite, **ship build 16**.
2. **Week 2 — partner share, for real:** real invite codes → `invitations`, share sheet, accept flow → `partner_relationships`, ConnectView reads real state, supporter home reads real data, permissions + disconnect, **ship build 17** (tested on two phones).
3. **Week 3 — instrument & finish:** Sentry, PostHog, BBT field, offline journal write queue, meditation sessions → cloud, photos → Storage, **ship build 18**.
4. **Week 4 — submit:** remaining schema into version control, first tests, store listing, App Review prep, fresh-phone walkthrough, fix what testers hit, **ship build 19, submit for App Review Day 29**, retro Day 30.

## Conventions

- **SwiftUI everywhere.** No UIKit unless absolutely necessary.
- **`@Observable` for ViewModels** (iOS 17+ pattern, not the older `ObservableObject`).
- **Use design tokens** from `DesignSystem.swift`. Never hardcode spacing, radius, colors, or animation values.
- **Custom font:** Display text uses `lunary-free.otf` — exposed via `Font.floSerif(size:)` helpers in DesignSystem.
- **Haptics:** Use `FloHaptics.light()`, `.medium()`, `.success()`, `.selection()`, etc. — don't call `UIImpactFeedbackGenerator` directly.
- **One FAB pattern.** The centered green FAB in the tab bar is the journal entry trigger. Don't add more FABs.
- **Soft delete in DB:** When migrating to Supabase, use `deleted_at` patterns, not hard deletes. Schema is set up for it.
- **Don't commingle with Kreathaus.** Any code or content for DailyFLO is owned by DailyFLO LLC (per the Operating Agreement). If you find yourself writing something that could belong to either business, flag it for Jonathan.

## Working principles (locked May 27, 2026)

- **"Functional" is NOT the quality bar.** Finished work must look right and feel right, not just compile. "Works with a misalignment that snaps on scroll," "works with a flicker," "works but…" — that's a bug to fix, not a stopping point.
- **When a bug points at a structural cause, fix it structurally on the FIRST attempt.** Nested ScrollViews, gesture conflicts, LazyVStack + scrollPosition layout races, or any known-unreliable SwiftUI combo: do the architecturally-correct rewrite from the start. Do NOT iterate one-line patches hoping they land.
- **One failed patch = stop and reassess.** After the first patch attempt that doesn't fully fix the issue, STOP. Name the structural root cause. Propose the rewrite. Then execute. Do not try another speculative patch.
- **Respect Jonathan's tokens and time.** He can see the trail of attempts and the token spend. Past the first failed patch, the only acceptable next message is "here is the root cause and the correct fix" — not "let me try X."

## Where to find more

For anything not covered here, these planning docs in the workspace folder have the full context:

- `/Users/jonathanbowden/Documents/Claude/Projects/Daily flow app/dailyflo-knockout-list.md` — week-by-week checklist for the rest of the sprint
- `/Users/jonathanbowden/Documents/Claude/Projects/Daily flow app/dailyflo-weekly-calendar.md` — narrative version of the sprint plan
- `/Users/jonathanbowden/Documents/Claude/Projects/Daily flow app/dailyflo-supabase-schema.md` — full schema design with reasoning
- `/Users/jonathanbowden/Documents/Claude/Projects/Daily flow app/dailyflo-week1-decisions.md` — all six week-1 decisions with rationale
- The Google Doc "DailyFLO – PLAN – May 2026" — canonical business plan, decisions log, launch checklist

## Important non-obvious facts

- Brittany handles music evaluation, brand voice, and is a co-decision-maker on product
- The two named audience segments are teen-and-mom pairs and married couples seeking attunement
- Mercury is the LLC's bank (online-only, no cash deposits — there are none to deposit)
- DUNS request was submitted via Apple's developer portal May 18; awaiting D&B issuance
- App Store seller name will currently be "Jonathan Bowden" (Individual account) until Org conversion completes (~3 weeks out)
- Chip Dodd outreach is in Brittany's hands — she may ask permission, may build a distinct framework, or may use his work as private inspiration. Schema is framework-agnostic.

---

If anything in this file is wrong or out of date when you read it, surface that to Jonathan rather than acting on stale information.
