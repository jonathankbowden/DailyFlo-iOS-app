// RevenueCat → Supabase webhook.
//
// Receives RC webhook POSTs, verifies the shared-secret Authorization header,
// records every event in `subscription_webhook_events` for idempotency, and
// mirrors the current subscription state into `subscriptions`.
//
// Two write paths:
//   1. Lifecycle events (INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION,
//      BILLING_ISSUE) carry full transaction detail → we upsert directly from
//      the payload, keyed on the event's `app_user_id` (must be a real UUID).
//   2. TRANSFER events carry NO transaction detail (only transferred_from /
//      transferred_to). They fire when an anonymous purchase is merged into an
//      identified user (purchase-then-sign-in) or when a sub moves between
//      accounts. Since the payload can't build a row — and the anonymous source
//      never had one (non-UUID ids are skipped) — we fetch the destination
//      user's CURRENT state from the RevenueCat REST API and upsert from that.
//      This also self-heals any earlier skipped/missed lifecycle event.
//
// Idempotency: `subscription_webhook_events.event_id` is UNIQUE. A retried
// webhook hits the unique-violation, returns 200, and never re-processes. The
// TRANSFER path (fetch-then-upsert) is itself idempotent, so re-processing is
// safe when the log row is cleared for a deliberate replay.
//
// Run via Supabase Edge Functions (Deno).
// Deploy:  supabase functions deploy revenuecat-webhook --no-verify-jwt

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const WEBHOOK_AUTH = Deno.env.get("REVENUECAT_WEBHOOK_AUTH") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

// Secret RevenueCat REST API key (sk_…). Used only for TRANSFER re-sync.
// A secret key is required: it resolves the canonical customer + aliases,
// where the public SDK key auto-creates empty subscribers for aliased ids.
const RC_API_KEY = Deno.env.get("REVENUECAT_API_KEY") ?? "";
const RC_API_BASE = "https://api.revenuecat.com/v1";

// Entitlement that grants Pro — mirrors RevenueCatConfig.proEntitlementID.
const PRO_ENTITLEMENT = "DailyFLO Pro";

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
    // event_id means we've already processed this webhook → 200, no re-write.
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

    // TRANSFER: no transaction detail in the payload → re-sync destination(s)
    // from the RevenueCat REST API. Handled before the HANDLED_EVENTS gate
    // because TRANSFER is deliberately not a direct-upsert event type.
    if (eventType === "TRANSFER") {
        return await handleTransfer(event, eventId);
    }

    if (!HANDLED_EVENTS.has(eventType)) {
        return json({ ok: true, ignored: eventType });
    }

    if (!appUserId || !UUID_REGEX.test(appUserId)) {
        // Anonymous RC user or pre-login purchase. Logged for audit; can't FK
        // to auth.users without a real UUID, so no upsert. A later TRANSFER
        // (fired when this customer signs in) re-syncs the identified user.
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

// ── TRANSFER handling ───────────────────────────────────────────────────────

/// Re-sync every UUID touched by a TRANSFER from RevenueCat's authoritative
/// state. Destinations (`transferred_to`) get their current entitlement upserted
/// (falling back to re-keying a source row if the REST read yields nothing);
/// sources (`transferred_from`) that no longer hold the entitlement are
/// downgraded. Anonymous ids ($RCAnonymousID:…) are ignored — they can't key
/// `subscriptions.user_id` (uuid, FK to auth.users).
async function handleTransfer(
    event: RcEvent,
    eventId: string,
): Promise<Response> {
    if (!RC_API_KEY) {
        // Config gap, not a client error. Logged for audit; return 200 so RC
        // doesn't enter a retry storm. Set REVENUECAT_API_KEY to enable.
        return json({ ok: true, transfer: "skipped_no_api_key" });
    }

    const toUuids = uuidsOnly(event.transferred_to);
    const fromUuids = uuidsOnly(event.transferred_from);
    const synced: Array<Record<string, unknown>> = [];

    // Destinations: authoritative RC fetch → upsert; else re-key a source row.
    for (const uuid of toUuids) {
        const row = await syncSubscriberFromRC(uuid, eventId);
        if (row) {
            const { error } = await supabase
                .from("subscriptions")
                .upsert(row, { onConflict: "user_id" });
            if (error) {
                return json(
                    { error: "transfer_upsert_failed", detail: error.message },
                    500,
                );
            }
            synced.push({ user_id: uuid, via: "rc_rest", status: row.status });
            continue;
        }
        const rekeyed = await rekeyFromSource(fromUuids, uuid, eventId);
        synced.push({ user_id: uuid, via: rekeyed ? "rekey" : "no_data" });
    }

    // Sources that gave up the entitlement: downgrade an existing row.
    for (const uuid of fromUuids) {
        if (toUuids.includes(uuid)) continue;
        await downgradeSource(uuid, eventId);
    }

    return json({ ok: true, transfer: "processed", synced });
}

/// Fetch a subscriber's current state from RevenueCat and map it to a
/// `subscriptions` row, or null when the subscriber has no entitlement data.
async function syncSubscriberFromRC(
    uuid: string,
    eventId: string,
): Promise<SubscriptionRow | null> {
    let res: Response;
    try {
        res = await fetch(
            `${RC_API_BASE}/subscribers/${encodeURIComponent(uuid)}`,
            { headers: { Authorization: `Bearer ${RC_API_KEY}` } },
        );
    } catch {
        return null;
    }
    if (!res.ok) return null;

    let data: RcSubscriberResponse;
    try {
        data = await res.json();
    } catch {
        return null;
    }
    const subscriber = data?.subscriber;
    if (!subscriber) return null;

    return mapSubscriberToRow(uuid, subscriber, eventId);
}

/// Build a row from RC's subscriber payload. Prefers the Pro entitlement,
/// falling back to any entitlement present. Returns null when there is nothing
/// to represent (no entitlements at all).
function mapSubscriberToRow(
    uuid: string,
    subscriber: RcSubscriber,
    eventId: string,
): SubscriptionRow | null {
    const entitlements = subscriber.entitlements ?? {};
    const entKey = PRO_ENTITLEMENT in entitlements
        ? PRO_ENTITLEMENT
        : Object.keys(entitlements)[0];
    if (!entKey) return null;

    const ent = entitlements[entKey];
    const productId = ent.product_identifier ?? null;
    const sub = productId
        ? (subscriber.subscriptions ?? {})[productId]
        : undefined;

    const expiresIso = isoOrNull(ent.expires_date ?? sub?.expires_date);
    const startsIso = isoOrNull(sub?.purchase_date ?? ent.purchase_date);
    const periodType = sub?.period_type ?? null;
    const status = deriveStatus(expiresIso, periodType, sub);
    const tier = deriveTier(productId, periodType);

    return {
        user_id: uuid,
        revenuecat_app_user_id: uuid,
        revenuecat_subscription_id: sub?.store_transaction_id ?? null,
        tier,
        status,
        product_id: productId,
        entitlement: entKey,
        store: sub?.store ? sub.store.toUpperCase() : null,
        current_period_starts_at: startsIso,
        current_period_ends_at: expiresIso,
        trial_ends_at: periodType === "trial" ? expiresIso : null,
        last_event_id: eventId,
        last_event_type: "TRANSFER",
        last_synced_at: new Date().toISOString(),
    };
}

/// Fallback when the REST read yields nothing: move an existing row from a
/// source UUID onto the destination. Best-effort — skipped if the destination
/// already has a row (unique violation) or no source row exists.
async function rekeyFromSource(
    fromUuids: string[],
    dest: string,
    eventId: string,
): Promise<boolean> {
    for (const src of fromUuids) {
        const { data } = await supabase
            .from("subscriptions")
            .select("user_id")
            .eq("user_id", src)
            .maybeSingle();
        if (!data) continue;

        const { error } = await supabase
            .from("subscriptions")
            .update({
                user_id: dest,
                revenuecat_app_user_id: dest,
                last_event_id: eventId,
                last_event_type: "TRANSFER",
                last_synced_at: new Date().toISOString(),
            })
            .eq("user_id", src);
        if (!error) return true;
    }
    return false;
}

/// A source UUID that lost its entitlement in a transfer. If RC still shows it
/// active (multi-alias edge case) keep it synced; otherwise mark an existing
/// row expired. Never creates a row for a source that never had one.
async function downgradeSource(uuid: string, eventId: string): Promise<void> {
    const row = await syncSubscriberFromRC(uuid, eventId);
    if (row && (row.status === "active" || row.status === "trial")) {
        await supabase.from("subscriptions").upsert(row, {
            onConflict: "user_id",
        });
        return;
    }
    await supabase
        .from("subscriptions")
        .update({
            status: "expired",
            last_event_id: eventId,
            last_event_type: "TRANSFER",
            last_synced_at: new Date().toISOString(),
        })
        .eq("user_id", uuid);
}

// ── Mapping helpers ─────────────────────────────────────────────────────────

function uuidsOnly(ids?: string[] | null): string[] {
    if (!Array.isArray(ids)) return [];
    return ids.filter((id) => typeof id === "string" && UUID_REGEX.test(id));
}

/// Status from RC subscriber fields. Mirrors the lifecycle-event mapping:
/// still-valid + auto-renew-off or billing-issue → cancelled (has access, gated
/// as not-paying); trial period → trial; past expiry → expired.
function deriveStatus(
    expiresIso: string | null,
    periodType: string | null,
    sub: RcSubscription | undefined,
): string {
    const expiresMs = expiresIso ? Date.parse(expiresIso) : NaN;
    const active = Number.isFinite(expiresMs) && expiresMs > Date.now();
    if (!active) return "expired";
    if (sub?.billing_issues_detected_at) return "cancelled";
    if (sub?.unsubscribe_detected_at) return "cancelled";
    if (periodType === "trial") return "trial";
    return "active";
}

function deriveTier(
    productId: string | null,
    periodType: string | null,
): string {
    if (periodType === "trial") return "trial";
    const p = (productId ?? "").toLowerCase();
    if (p.includes("annual") || p.includes("yearly")) return "annual";
    if (p.includes("month")) return "monthly";
    return "monthly";
}

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

function isoOrNull(s: string | null | undefined): string | null {
    if (!s) return null;
    const t = Date.parse(s);
    return Number.isFinite(t) ? new Date(t).toISOString() : null;
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
    // TRANSFER only: app user ids losing / receiving the entitlements.
    transferred_from?: string[];
    transferred_to?: string[];
}

interface RcWebhookBody {
    event: RcEvent;
    api_version?: string;
}

// Subset of the RevenueCat REST `GET /v1/subscribers/{id}` response we read.
// https://www.revenuecat.com/docs/api-v1#tag/customers
interface RcSubscriberResponse {
    subscriber?: RcSubscriber;
}

interface RcSubscriber {
    original_app_user_id?: string;
    entitlements?: Record<string, RcEntitlement>;
    subscriptions?: Record<string, RcSubscription>;
}

interface RcEntitlement {
    expires_date?: string | null;
    purchase_date?: string | null;
    product_identifier?: string;
}

interface RcSubscription {
    expires_date?: string | null;
    purchase_date?: string | null;
    store?: string;
    period_type?: string;
    unsubscribe_detected_at?: string | null;
    billing_issues_detected_at?: string | null;
    store_transaction_id?: string | null;
}

// Shape upserted into `public.subscriptions`.
interface SubscriptionRow {
    user_id: string;
    revenuecat_app_user_id: string;
    revenuecat_subscription_id: string | null;
    tier: string;
    status: string;
    product_id: string | null;
    entitlement: string | null;
    store: string | null;
    current_period_starts_at: string | null;
    current_period_ends_at: string | null;
    trial_ends_at: string | null;
    last_event_id: string;
    last_event_type: string;
    last_synced_at: string;
}
