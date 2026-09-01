-- Grant the Edge Function's role access to the subscription tables.
--
-- On this project the default privileges that normally grant service_role
-- access to new tables did not apply to the tables created by
-- 20260603120000_revenuecat_webhook.sql. The revenuecat-webhook function
-- runs as service_role and was failing with
-- "permission denied for table subscription_webhook_events".
--
-- Applied to production via the SQL editor on 2026-09-01. Re-runnable.

GRANT ALL ON TABLE public.subscription_webhook_events TO service_role;
GRANT ALL ON TABLE public.subscriptions TO service_role;
