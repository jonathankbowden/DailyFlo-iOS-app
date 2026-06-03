# RevenueCat → Supabase subscription webhook

Edge Function that receives RevenueCat webhook events and mirrors subscription
state into the `subscriptions` table.

## What it does

- Verifies the shared-secret `Authorization` header against `REVENUECAT_WEBHOOK_AUTH` (constant-time compare).
- Logs every event into `subscription_webhook_events` (idempotency).
- Upserts into `subscriptions` (keyed on `user_id`, populated from RC's `app_user_id`) for these event types:
  - `INITIAL_PURCHASE`, `RENEWAL` → `status = active` (or `trial` during a trial)
  - `CANCELLATION` → `status = cancelled` (access continues until `current_period_ends_at`)
  - `EXPIRATION` → `status = expired`
  - `BILLING_ISSUE` → `status = cancelled` (RC follows up with `EXPIRATION` or `RENEWAL`)
- Other event types are logged but not mirrored.

## Idempotency

`subscription_webhook_events.event_id` is `UNIQUE`. A retried webhook hits the
unique-violation, the function returns `200 {ok: true, deduped: true}`, and the
`subscriptions` row is not re-written.

## Setup

### 1. Run the migration

```sh
supabase db push
```

Or paste `supabase/migrations/20260603120000_revenuecat_webhook.sql` into the
Supabase SQL editor and run it. Adds `product_id / entitlement / store /
last_event_id / last_event_type` to `subscriptions`, normalizes the status
enum to `(active, trial, expired, cancelled)`, and creates
`subscription_webhook_events`.

### 2. Set the shared-secret env var

Pick a strong random string — this is what RevenueCat will send verbatim as the
`Authorization` header on every webhook POST.

```sh
openssl rand -hex 32
supabase secrets set REVENUECAT_WEBHOOK_AUTH=<paste-the-hex-string>
```

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are populated automatically by
Supabase — no action needed.

### 3. Deploy

```sh
supabase functions deploy revenuecat-webhook --no-verify-jwt
```

`--no-verify-jwt` is required because RevenueCat doesn't carry a Supabase JWT;
auth is handled by our shared-secret header check.

The public URL will be:

```
https://ntyxfqwrtqscmdefbyfc.supabase.co/functions/v1/revenuecat-webhook
```

### 4. Wire the RevenueCat dashboard

1. RevenueCat dashboard → **Project Settings → Integrations → Webhooks** → **+ New webhook**.
2. **Webhook URL**:
   ```
   https://ntyxfqwrtqscmdefbyfc.supabase.co/functions/v1/revenuecat-webhook
   ```
3. **Authorization header value**: paste the *same* secret you set as `REVENUECAT_WEBHOOK_AUTH`. RC sends this value in the `Authorization` header on every POST.
4. **Environment**: enable for **Production** and **Sandbox** (RC sends both — same URL, same secret is fine).
5. Save, then click **Send Test Event**. Expect `200 {"ok":true,"ignored":"TEST"}` (the TEST event is logged but doesn't write to `subscriptions`).

### 5. Map RevenueCat `app_user_id` to Supabase `auth.uid` ⚠

Until this is wired, the function will *log* events but skip the `subscriptions`
upsert because RC's anonymous IDs aren't UUIDs (they're prefixed with `$RCAnonymousID:`).

In the iOS app, after Supabase sign-in succeeds, call:

```swift
let session = try await SupabaseClient.shared.auth.session
try await Purchases.shared.logIn(session.user.id.uuidString)
```

On sign-out:

```swift
try await Purchases.shared.logOut()
```

This sets RC's `app_user_id` to the Supabase auth UUID, which is what the
webhook uses as the FK into `auth.users`.

## Local testing

```sh
supabase functions serve revenuecat-webhook --env-file ./supabase/.env.local
```

`.env.local` needs `REVENUECAT_WEBHOOK_AUTH`, `SUPABASE_URL`, and
`SUPABASE_SERVICE_ROLE_KEY`.

POST a sample event:

```sh
curl -X POST http://localhost:54321/functions/v1/revenuecat-webhook \
  -H "Authorization: <your-secret>" \
  -H "Content-Type: application/json" \
  -d '{
    "event": {
      "id": "test-event-1",
      "type": "INITIAL_PURCHASE",
      "app_user_id": "00000000-0000-0000-0000-000000000001",
      "product_id": "daily_flo_monthly",
      "entitlement_ids": ["DailyFLO Pro"],
      "period_type": "NORMAL",
      "store": "APP_STORE",
      "transaction_id": "abc-123",
      "purchased_at_ms": 1717420800000,
      "expiration_at_ms": 1720099200000
    }
  }'
```

Resend the same payload — should return `{"ok":true,"deduped":true}`.

## Founding-member cap

Not enforced. The founding tier isn't being sold yet. There's a clearly-marked
hook in `index.ts` (right before the final upsert) that names the exact query
to add when the cap goes live.
