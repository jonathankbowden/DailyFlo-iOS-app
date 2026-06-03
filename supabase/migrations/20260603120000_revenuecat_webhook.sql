-- RevenueCat webhook support: extra columns on `subscriptions`, a normalized
-- status value set, and an idempotency log of every event we receive.
--
-- Re-runnable: every statement guards itself so this file is safe to apply
-- against an existing database that may already have part of the schema.

-- ──────────────────────────────────────────────────────────────────────────
-- 1. New columns on `subscriptions`
-- ──────────────────────────────────────────────────────────────────────────

ALTER TABLE public.subscriptions
  ADD COLUMN IF NOT EXISTS product_id       TEXT,
  ADD COLUMN IF NOT EXISTS entitlement      TEXT,
  ADD COLUMN IF NOT EXISTS store            TEXT,
  ADD COLUMN IF NOT EXISTS last_event_id    TEXT,
  ADD COLUMN IF NOT EXISTS last_event_type  TEXT;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. Normalize the status enum to (active, trial, expired, cancelled)
--    Migrates any existing rows from the original 5-value set.
-- ──────────────────────────────────────────────────────────────────────────

UPDATE public.subscriptions SET status = 'trial'     WHERE status = 'trialing';
UPDATE public.subscriptions SET status = 'cancelled' WHERE status = 'canceled';
UPDATE public.subscriptions SET status = 'cancelled' WHERE status = 'past_due';

ALTER TABLE public.subscriptions
  DROP CONSTRAINT IF EXISTS subscriptions_status_check;

ALTER TABLE public.subscriptions
  ADD CONSTRAINT subscriptions_status_check
  CHECK (status IN ('active', 'trial', 'expired', 'cancelled'));

-- ──────────────────────────────────────────────────────────────────────────
-- 3. Webhook event log — primary idempotency mechanism.
--    Unique on event_id; duplicate POSTs from RevenueCat short-circuit
--    on the unique-violation and never re-write the subscriptions row.
-- ──────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.subscription_webhook_events (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  event_id     TEXT        NOT NULL UNIQUE,
  event_type   TEXT        NOT NULL,
  app_user_id  TEXT,
  payload      JSONB       NOT NULL,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS subscription_webhook_events_received_at_idx
  ON public.subscription_webhook_events (received_at DESC);

CREATE INDEX IF NOT EXISTS subscription_webhook_events_app_user_id_idx
  ON public.subscription_webhook_events (app_user_id);

-- RLS on. No policies → only the service role (used by the Edge Function)
-- can read or write. Regular authenticated users have no access.
ALTER TABLE public.subscription_webhook_events ENABLE ROW LEVEL SECURITY;
