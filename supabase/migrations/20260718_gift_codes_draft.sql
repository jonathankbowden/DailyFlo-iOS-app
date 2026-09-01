-- ============================================================
-- DailyFLO — gift codes + admin access codes (DRAFT migration)
-- Date: 2026-07-18
--
-- Architecture verified against Apple rules July 18, 2026:
--   * Purchaser buys a NON-RENEWING subscription SKU (3/6/12 mo)
--     in-app via StoreKit — money moves through Apple (3.1.1 ok).
--   * Backend mints a redemption code (delivery, not payment).
--   * Recipient redeems in-app; server grants + expires entitlement.
--   * RevenueCat will NOT expire these — fixed-term entitlement
--     state lives HERE. Two entitlement types total:
--     auto-renew (RevenueCat) + fixed-term (this table).
--   * Admin codes (Jonathan/Brittany comps) = same machinery,
--     source = 'admin', no purchase behind them.
--
-- Review before applying: column names must match app-side code
-- once the redemption client is built. _draft suffix keeps this
-- out of an accidental `supabase db push` — rename to apply.
-- ============================================================

create table gift_codes (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique,                  -- e.g. 'FLO-7K2M-9QRX'
  source           text not null check (source in ('gift_purchase', 'admin')),
  duration_months  int  check (duration_months in (3, 6, 12)),
  is_lifetime      boolean not null default false,        -- admin-only comps
  purchaser_id     uuid references auth.users(id),        -- null for admin codes
  purchase_tx_id   text,                                  -- StoreKit transaction id (audit trail for App Review)
  recipient_email  text,                                  -- optional: pre-addressed gift
  redeemed_by      uuid references auth.users(id),
  redeemed_at      timestamptz,
  access_expires_at timestamptz,                          -- set at redemption: redeemed_at + duration
  created_at       timestamptz not null default now(),
  expires_at       timestamptz not null default now() + interval '12 months',  -- unredeemed code shelf life
  revoked_at       timestamptz,
  constraint duration_or_lifetime check (is_lifetime or duration_months is not null),
  constraint purchase_has_purchaser check (source != 'gift_purchase' or purchaser_id is not null)
);

create index gift_codes_redeemed_by_idx on gift_codes (redeemed_by) where redeemed_by is not null;

alter table gift_codes enable row level security;

-- Purchaser can see codes they bought (to re-share / check status)
create policy "purchaser reads own codes"
  on gift_codes for select
  using (auth.uid() = purchaser_id);

-- Redeemer can see the code that grants their access
create policy "redeemer reads own redemption"
  on gift_codes for select
  using (auth.uid() = redeemed_by);

-- NO insert/update policies for clients: codes are minted and redeemed
-- ONLY via SECURITY DEFINER functions below (service role). A client
-- must never construct or mutate a code row directly.

-- ------------------------------------------------------------
-- Redemption: atomic, race-safe (one redeemer wins), called from
-- the app after sign-in. Returns the access expiry on success.
-- ------------------------------------------------------------
create or replace function redeem_gift_code(p_code text)
returns table (access_expires_at timestamptz, is_lifetime boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row gift_codes%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_row
  from gift_codes
  where code = upper(trim(p_code))
  for update;                       -- lock the row; concurrent redeem loses

  if not found then
    raise exception 'code_not_found';
  end if;
  if v_row.revoked_at is not null then
    raise exception 'code_revoked';
  end if;
  if v_row.redeemed_at is not null then
    raise exception 'code_already_redeemed';
  end if;
  if v_row.expires_at < now() then
    raise exception 'code_expired';
  end if;

  update gift_codes
  set redeemed_by = auth.uid(),
      redeemed_at = now(),
      access_expires_at = case when is_lifetime then null
                               else now() + (duration_months || ' months')::interval end
  where id = v_row.id;

  return query
    select g.access_expires_at, g.is_lifetime
    from gift_codes g where g.id = v_row.id;
end $$;

-- Client entitlement check: "does this user have fixed-term access
-- right now?" The app calls this alongside RevenueCat's isPro.
create or replace function has_gift_access(p_user uuid default auth.uid())
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from gift_codes
    where redeemed_by = p_user
      and revoked_at is null
      and (is_lifetime or access_expires_at > now())
  );
$$;

-- ------------------------------------------------------------
-- Minting (server-side only — call with service role from an Edge
-- Function after StoreKit purchase verification, or manually from
-- the dashboard for admin comps):
--
--   insert into gift_codes (code, source, duration_months, purchaser_id, purchase_tx_id)
--   values (generate_gift_code(), 'gift_purchase', 6, '<purchaser-uuid>', '<tx-id>');
-- ------------------------------------------------------------
create or replace function generate_gift_code()
returns text
language sql
volatile
as $$
  -- FLO-XXXX-XXXX, unambiguous alphabet (no 0/O/1/I/L)
  select 'FLO-' ||
    array_to_string(array(
      select substr('23456789ABCDEFGHJKMNPQRSTUVWXYZ', (random()*30)::int + 1, 1)
      from generate_series(1, 4)), '') || '-' ||
    array_to_string(array(
      select substr('23456789ABCDEFGHJKMNPQRSTUVWXYZ', (random()*30)::int + 1, 1)
      from generate_series(1, 4)), '');
$$;
