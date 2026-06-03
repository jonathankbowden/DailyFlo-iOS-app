// RevenueCat → Supabase webhook.
//
// Receives RC webhook POSTs, verifies the shared-secret Authorization header,
// records every event in `subscription_webhook_events` for idempotency, and
// mirrors the current subscription state into `subscriptions` for the five
// event types we care about (INITIAL_PURCHASE, RENEWAL, CANCELLATION,
// EXPIRATION, BILLING_ISSUE).
//
// Idempotency: `subscription_webhook_events.event_id` is UNIQUE. A retried
// webhook hits the unique-violation, returns 200, and never touches
// `subscriptions` again.
//
// Run via Supabase Edge Functions (Deno).
// Deploy:  supabase functions deploy revenuecat-webhook --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const WEBHOOK_AUTH = Deno.env.get("REVENUECAT_WEBHOOK_AUTH") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const HANDLED_EVENTS = new Set([
    "INITIAL_PURCHASE",
    "RENEWAL",
    "CANCELLATION",
    "EXPIRATION",
    "BILLING_ISSUE",
]);

const UUID_REGEX =
    /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const supabase = createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req) => {
    if (req.method !== "POST") {
        return json({ error: "method_not_allowed" }, 405);
    }
    if (!WEBHOOK_AUTH || !SUPABASE_URL || !SERVICE_ROLE) {
        return json({ error: "server_misconfigured" }, 500);
    }

    // Shared-secret auth. RC dashboard puts the configured value verbatim
    // in the Authorization header on every POST. Constant-time compare.
    const provided = req.headers.get("authorization") ?? "";
    if (!timingSafeEqual(provided, WEBHOOK_AUTH)) {
        return json({ error: "unauthorized" }, 401);
    }

    let body: RcWebhookBody;
    try {
        body = await req.json();
    } catch {
        return json({ error: "invalid_json" }, 400);
    }

    const event = body?.event;
    const eventId = event?.id;
    const eventType = event?.type;
    // `app_user_id` is the current alias (post-login); `original_app_user_id`
    // is the very first id RC saw for this customer. Prefer the current one.
    const appUserId = event?.app_user_id ?? event?.original_app_user_id ?? null;

    if (!eventId || !eventType) {
        return json({ error: "missing_event_fields" }, 400);
    }

    // Idempotency: insert into the event log first. A unique violation on
    // event_id means we've already processed this webhook → 200, no upsert.
    const { error: logErr } = await supabase
        .from("subscription_webhook_events")
        .insert({
            event_id: eventId,
            event_type: eventType,
            app_user_id: appUserId,
            payload: body,
        });

    if (logErr) {
        if (logErr.code === "23505") {
            return json({ ok: true, deduped: true });
        }
        return json(
            { error: "log_insert_failed", detail: logErr.message },
            500,
        );
    }

    if (!HANDLED_EVENTS.has(eventType)) {
        return json({ ok: true, ignored: eventType });
    }

    if (!appUserId || !UUID_REGEX.test(appUserId)) {
        // Anonymous RC user or pre-login purchase. Logged for audit;
        // can't FK to auth.users without a real UUID, so no upsert.
        return json({ ok: true, skipped: "non_uuid_app_user_id" });
    }

    // ── Founding-member cap hook ───────────────────────────────────────────
    // When the founding tier launches: if tier === 'founding', SELECT
    //   count(*) FROM subscriptions WHERE tier = 'founding'
    //                                 AND status IN ('active','trial')
    // against the cap, and return 200 (logged, no upsert) when exceeded.
    // Not enforced yet — founding tier isn't being sold.
    // ───────────────────────────────────────────────────────────────────────

    const tier = mapTier(event);
    const status = mapStatus(eventType, event);

    const row = {
        user_id: appUserId,
        revenuecat_app_user_id: appUserId,
        revenuecat_subscription_id: event.transaction_id ?? null,
        tier,
        status,
        product_id: event.product_id ?? null,
        entitlement: pickEntitlement(event),
        store: event.store ?? null,
        current_period_starts_at: msToIso(event.purchased_at_ms),
        current_period_ends_at: msToIso(event.expiration_at_ms),
        trial_ends_at: event.period_type === "TRIAL"
            ? msToIso(event.expiration_at_ms)
            : null,
        last_event_id: eventId,
        last_event_type: eventType,
        last_synced_at: new Date().toISOString(),
    };

    const { error: upsertErr } = await supabase
        .from("subscriptions")
        .upsert(row, { onConflict: "user_id" });

    if (upsertErr) {
        return json(
            { error: "upsert_failed", detail: upsertErr.message },
            500,
        );
    }

    return json({ ok: true });
});

function pickEntitlement(event: RcEvent): string | null {
    if (Array.isArray(event.entitlement_ids) && event.entitlement_ids.length) {
        return event.entitlement_ids[0];
    }
    return event.entitlement_id ?? null;
}

function mapTier(event: RcEvent): string {
    if (event.period_type === "TRIAL") return "trial";
    if (event.store === "PROMOTIONAL") return "promo";
    const productId = (event.product_id ?? "").toLowerCase();
    if (productId.includes("annual") || productId.includes("yearly")) {
        return "annual";
    }
    if (productId.includes("month")) return "monthly";
    return "monthly";
}

function mapStatus(eventType: string, event: RcEvent): string {
    switch (eventType) {
        case "INITIAL_PURCHASE":
        case "RENEWAL":
            return event.period_type === "TRIAL" ? "trial" : "active";
        case "CANCELLATION":
            // Auto-renew was turned off. User still has access until
            // expiration_at_ms; RC fires EXPIRATION when access lapses.
            return "cancelled";
        case "EXPIRATION":
            return "expired";
        case "BILLING_ISSUE":
            // No `past_due` in the requested status set. Surface as cancelled
            // so the client gates as not-paying; RC follows up with either
            // EXPIRATION (still cancelled) or RENEWAL (back to active).
            return "cancelled";
        default:
            return "active";
    }
}

function msToIso(ms: number | string | null | undefined): string | null {
    if (ms == null) return null;
    const n = typeof ms === "string" ? Number(ms) : ms;
    if (!Number.isFinite(n)) return null;
    return new Date(n).toISOString();
}

function timingSafeEqual(a: string, b: string): boolean {
    if (a.length !== b.length) return false;
    let diff = 0;
    for (let i = 0; i < a.length; i++) {
        diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return diff === 0;
}

function json(payload: unknown, status = 200): Response {
    return new Response(JSON.stringify(payload), {
        status,
        headers: { "content-type": "application/json" },
    });
}

// Minimal shapes for the RC webhook payload fields we touch. Full schema:
// https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields
interface RcEvent {
    id: string;
    type: string;
    app_user_id?: string;
    original_app_user_id?: string;
    product_id?: string;
    entitlement_id?: string | null;
    entitlement_ids?: string[] | null;
    period_type?: "NORMAL" | "TRIAL" | "INTRO" | "PROMOTIONAL";
    store?: string;
    transaction_id?: string;
    purchased_at_ms?: number;
    expiration_at_ms?: number;
}

interface RcWebhookBody {
    event: RcEvent;
    api_version?: string;
}
