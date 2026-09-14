-- Day 10 of the 30-for-30 (Sept 2026): accept a partner invite code.
--
-- The supporter types the FLO-XXXXXX code they were sent. Everything that
-- must happen atomically lives here, server-side, as one SECURITY DEFINER
-- function: look the code up, validate it, create the partner_relationships
-- row, stamp the invitation as accepted, and settle the supporter's role.
--
-- Why an RPC instead of client-side writes:
--   * RLS on `invitations` only lets the tracker who minted a code read it.
--     A supporter can't (and shouldn't) SELECT other people's invitations.
--   * One transaction: no half-accepted state if the app dies mid-way.
--   * The row lock means two phones racing on the same code can't both win.
--
-- Error contract (raised as P0001 with these exact messages; the app maps
-- them to copy in PartnerManager.swift):
--   not_authenticated, invitation_not_found, invitation_expired,
--   invitation_already_accepted, own_invitation
--
-- Re-runnable. Apply via the SQL editor or `supabase db push`.

create or replace function public.accept_invitation(p_code text)
returns table (
  relationship_id      uuid,
  tracker_user_id      uuid,
  tracker_display_name text,
  relationship_type    text,
  status               text,
  permissions          jsonb,
  accepted_at          timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code        text;
  v_invite      invitations%rowtype;
  v_supporter   uuid := auth.uid();
  v_rel_id      uuid;
  v_has_cycles  boolean;
begin
  if v_supporter is null then
    raise exception 'not_authenticated';
  end if;

  -- Normalize what a human typed: case, whitespace, and a missing FLO- prefix.
  v_code := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
  if v_code !~ '^FLO-' then
    v_code := 'FLO-' || v_code;
  end if;

  select * into v_invite
  from invitations
  where invitation_code = v_code
  for update;                       -- lock the row; a concurrent accept waits, then fails below

  if not found then
    raise exception 'invitation_not_found';
  end if;
  if v_invite.tracker_user_id = v_supporter then
    raise exception 'own_invitation';
  end if;
  if v_invite.accepted_at is not null then
    raise exception 'invitation_already_accepted';
  end if;
  if v_invite.expires_at <= now() then
    raise exception 'invitation_expired';
  end if;

  -- Idempotent for an already-connected pair: reuse the active relationship
  -- rather than creating a duplicate.
  select pr.id into v_rel_id
  from partner_relationships pr
  where pr.tracker_user_id = v_invite.tracker_user_id
    and pr.supporter_user_id = v_supporter
    and pr.status = 'active'
  limit 1;

  if v_rel_id is null then
    insert into partner_relationships
      (tracker_user_id, supporter_user_id, relationship_type, status,
       permissions, invited_at, accepted_at)
    values
      (v_invite.tracker_user_id, v_supporter, v_invite.relationship_type, 'active',
       coalesce(v_invite.proposed_permissions, '{}'::jsonb), v_invite.created_at, now())
    returning id into v_rel_id;
  end if;

  update invitations
  set accepted_at = now()
  where id = v_invite.id;

  -- Settle the supporter's role so the app routes them to the right home.
  -- A profile that never logged a cycle is a supporter; one that has is
  -- now both. Roles already set to supporter/both are left alone.
  select exists (
    select 1 from cycles c
    where c.user_id = v_supporter and c.deleted_at is null
  ) into v_has_cycles;

  -- Plain literals on purpose: they coerce to the column's type whether
  -- `role` is an enum or text, where a CASE expression would resolve to text.
  if v_has_cycles then
    update profiles p set role = 'both'
    where p.user_id = v_supporter and p.role = 'tracker';
  else
    update profiles p set role = 'supporter'
    where p.user_id = v_supporter and p.role = 'tracker';
  end if;

  return query
    select pr.id,
           pr.tracker_user_id,
           coalesce(tp.display_name, ''),
           pr.relationship_type::text,
           pr.status::text,
           pr.permissions,
           pr.accepted_at
    from partner_relationships pr
    left join profiles tp on tp.user_id = pr.tracker_user_id
    where pr.id = v_rel_id;
end $$;

-- Only signed-in users may call this. Never anon.
revoke execute on function public.accept_invitation(text) from public;
revoke execute on function public.accept_invitation(text) from anon;
grant  execute on function public.accept_invitation(text) to authenticated;
grant  execute on function public.accept_invitation(text) to service_role;
