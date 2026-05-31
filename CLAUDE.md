# DailyFLO — Project Context for Claude

This file gives you (Claude) the context you need to be immediately useful in this iOS project. Read it on every session. Treat the planning docs referenced at the bottom as the source of truth for anything not covered here.

## Project location & hygiene (read first, enforce every session)

On May 20, 2026 this project nearly lost untracked work because two out-of-sync copies existed (one in Dropbox, one in `~/Developer/DailyFlo`) and tooling wrote to different copies. These rules exist to prevent a recurrence. **Follow and reinforce them.**

1. **Canonical location is `~/Developer/DailyFlo/` ONLY.** Never create, edit, or open a copy of this project inside any cloud-synced folder (Dropbox, iCloud Drive, OneDrive, Google Drive). Cloud sync corrupts `.xcodeproj` files and silently spawns duplicate copies. If you ever detect the project running from a synced path, STOP and flag it to Jonathan immediately — do not write files.

2. **At the start of every session,** verify you're operating on `~/Developer/DailyFlo/` and run `git status` so you and Jonathan both know what's uncommitted before making changes. If something looks like it's in a different location, surface it before proceeding.

3. **Git is the source of truth; GitHub is the backup.** Remote: `github.com/jonathankbowden/DailyFlo-iOS-app`. Commit often. Untracked files are the only files that can truly vanish — so when you create or substantially edit Swift files, remind Jonathan to commit them (even to a WIP branch) rather than leaving them untracked.

4. **End-of-session ritual.** After any meaningful work, prompt Jonathan to commit and push:
   ```
   git status
   git add -A
   git commit -m "..."
   git push
   ```
   The goal: never end a session with hard-to-recreate work uncommitted. Worst case should be losing the current session, never days.

5. **No lingering duplicate copies.** There should be exactly one working copy of this project. If a second copy appears, consolidate to `~/Developer/DailyFlo/` and archive/delete the other — don't leave two live copies that can drift.

6. **`.gitignore` must keep build artifacts and secrets out of git.** `SupabaseConfig.xcconfig` (real credentials) is gitignored; `SupabaseConfig.xcconfig.example` is committed. DerivedData, build products, and `.DS_Store` stay ignored.


## What DailyFLO is

A subscription iOS app for women across a wide age range (teens through women in long marriages, including post-menopause as a v1.x audience). Combines cycle tracking, daily emotion journaling, integrated meditation with music, and a partner/parent share loop. Faith-informed in tone and worldview, not explicitly evangelical. Visual identity is soft neutrals and nature tones — no pinks/purples, no body imagery.

Founded May 2026 by Jonathan Bowden and his wife Brittany Bowden (50/50). Bootstrapped. **Target: public App Store launch July 1, 2026** (slip 1–2 weeks acceptable rather than cutting partner share).

The Bowdens also operate a separate design partnership called **Kreathaus**. Keep DailyFLO IP cleanly separated from Kreathaus work.

## Stack

- **iOS app:** Swift, SwiftUI (iOS 17+ idioms — `@Observable`, modern concurrency)
- **Backend:** Supabase (Postgres, Auth, Storage)
- **Subscriptions:** RevenueCat + Apple StoreKit
- **Analytics:** PostHog
- **Crash reporting:** Sentry
- **Future:** Cloudflare R2 for audio CDN (post-launch)
- **Music for meditations:** Suno Pro generated + originals from a church musician (hybrid model)

## Current build state (as of May 19, 2026)

### What's done

- **UI shell is polished and mostly complete.** Splash → onboarding → signIn → 5-tab main (Home, Calendar, Journal, Profile, Meditation) with custom FAB for journal entries
- **Design system is mature.** `DesignSystem.swift` contains `FloSpacing`, `FloRadius`, `FloHaptics`, `FloAnimation`, color tokens (`floCream`, `floSage`, `floCharcoal`, `floGray`, `floMint`, phase colors), typography styles, and the custom `lunary-free.otf` font. Use these tokens; don't hardcode design values.
- **Cycle math works.** `CycleManager` calculates phases (menstrual/follicular/ovulation/luteal), next-period prediction, day-of-cycle, month calendar generation — all currently backed by UserDefaults
- **Journal works locally.** `JournalManager` has full CRUD with UserDefaults persistence
- **Voice entry exists.** `VoiceEntryView` + `SpeechRecognizer` — feature flag candidate if it gets flaky
- **`ConnectView` UI exists for partner share** across three states (not connected / pending / connected) — fully designed but **all mocked, no backend wiring**
- **Supabase backend is complete.** 10 tables with RLS on every one (see schema section below)

### What's fake or missing

- **`SignInView.signIn()` is fake.** It's `DispatchQueue.asyncAfter(1.5s) { isSignedIn = true }`. Google button just flips a flag. Apple Sign In button displays but discards the credential. **This is the first thing to replace.**
- **No Supabase SDK added to Xcode yet.** Needs to be added via Swift Package Manager.
- **No networking layer anywhere.** Everything reads/writes locally.
- **No RevenueCat / Sentry / PostHog SDKs added** to the iOS project. Accounts exist; SDKs not yet integrated.
- **`ConnectView` invitation logic is fake.** Random local codes, "Demo: Skip to Connected" button, no real send/accept.

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

## Planned UI changes (locked May 26, 2026 — designed, not yet built)

Build these honoring the locked design constraints above (no symptoms, no flow/heaviness, no pinks/purples).

- **Tab bar restructure.** New bottom nav, left→right: **Profile, Calendar, [+] FAB (new journal entry), Journal, Pause (Meditation)**. Profile becomes the far-left, **default-selected** tab on launch, and its landing view IS the current Home dashboard (`HomeView` content moves into the Profile tab). The existing account/settings (`ProfileMainView`: sign-out, stats) lives lower in the same Profile tab as a scroll/section, not a separate tab. Touches `ContentView.swift`: tab order, tag indices, default `selectedTab`, and the icon row.
- **Journal "view all" base view (the Journal tab's base screen — NOT the cycle calendar).** A 2D day-card grid: each day is a full-screen card whose face = that day's **most-recent** entry (tap expands to all entries via `JournalEntryDetailView`); empty days show a calm empty-state. **Horizontal paging = ±1 day** (left=prev, right=next); **vertical paging = ±7 days**, same weekday (up=prev week, down=next week) — i.e. the calendar grid navigated one day at a time. Reuse `SingleDayView` (day card + `journalManager.entries(for:)`). Build with iOS-17 paging `ScrollView`s (`.scrollTargetBehavior(.paging)`), NOT nested `TabView`s. Client-side only, no schema change.

## Supabase schema (live as of May 19)

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

**Full schema spec:** `/Users/jonathanbowden/Documents/Claude/Projects/Daily flow app/dailyflo-supabase-schema.md`

## Supabase credentials

- **Project URL:** `https://ntyxfqwrtqscmdefbyfc.supabase.co`
- **Publishable key:** Stored in 1Password / locked Notes labeled "DailyFLO Supabase credentials". Safe to use in iOS client code.
- **Secret key:** Stored in locked Notes. **Never use in iOS code, never commit to git.** Server-side only.

When integrating the SDK, read credentials from a `.xcconfig` file or `Info.plist` that is gitignored — never hardcode them in source files.

## Next engineering work (in priority order)

1. **Add Supabase Swift SDK** via Swift Package Manager: `https://github.com/supabase/supabase-swift` — add to DailyFlo target
2. **Create `SupabaseClient.swift`** that initializes a shared client with the project URL + publishable key
3. **Replace fake `signIn()` in `SignInView.swift`** with real Supabase Auth. v1 supports **four auth methods: Sign in with Apple, Google, Meta (Facebook Login), and email/password**. Apple Sign In is required by App Store Guideline 4.8 since other social options are offered. Phone OTP was considered but deferred to v1.x.

**UI design: Patreon-style social-first layout.** Social provider buttons stacked vertically at the top in this order (Apple, Google, Meta) — Apple first because of privacy positioning and App Store guideline. "OR" divider. Email + password form below as the secondary path. This is a deliberate departure from the current email-first layout — social is the primary path, email is the backup.

Build Apple Sign In + email first (highest priority), stub Google and Meta buttons with TODO comments, then layer in Google and Meta as their Supabase provider configs are completed.
4. **Migrate `JournalManager`** from UserDefaults → `emotion_entries` table. Keep UserDefaults as an offline cache layer.
5. **Migrate `CycleManager`** cycle data from UserDefaults → `profiles` + `cycles` tables. Onboarding answers (name, last period date, cycle length, period length) should populate `profiles` and create an initial `cycles` row (with `is_predicted = true`).
6. **Wire `ConnectView` to the real backend.** Replace mock invitation generation with `invitations` table writes + email send (via Supabase Edge Function or Resend).
7. **Then RevenueCat** (Week 3 calendar work)

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
