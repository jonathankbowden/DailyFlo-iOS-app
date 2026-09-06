-- Day 13 of the 30-for-30 (Sept 2026): permissions + disconnect, and the
-- permission-key naming settled for good.
--
-- 1. `ended_at` on partner_relationships. Disconnect is a soft end, never a
--    delete (CLAUDE.md). "Active" now means status = 'active' AND
--    ended_at IS NULL everywhere below.
-- 2. `partner_has_permission` — the function the RLS policies on cycles,
--    cycle_entries and emotion_entries call — is redefined to read the
--    app's canonical keys (the ones PartnerManager writes on invite:
--    show_current_phase, show_period_dates, ...). Policies that were
--    written against the July script's spellings (view_phase, ...) keep
--    working through an alias map, so nothing has to be re-authored.
-- 3. `update_partner_permissions` (tracker only) and `disconnect_partner`
--    (either side) RPCs.
-- 4. accept_invitation / my_partner_relationships / supporter_snapshot are
--    re-issued to honor ended_at; supporter_snapshot drops the dual-key
--    shim now that the canonical key is settled.
--
-- Re-runnable. Apply via the SQL editor or `supabase db push`.

-- ──────────────────────────────────────────────────────────────────────────
-- 1. Soft end
-- ──────────────────────────────────────────────────────────────────────────

alter table public.partner_relationships
  add column if not exists ended_at timestamptz;

-- ──────────────────────────────────────────────────────────────────────────
-- 2. The permission gate the RLS policies use. Unnamed parameters on purpose:
--    CREATE OR REPLACE forbids renaming parameters, and the original names
--    aren't in version control.
-- ──────────────────────────────────────────────────────────────────────────

create or replace function public.partner_has_permission(uuid, uuid, text)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1
    from partner_relationships pr
    where pr.tracker_user_id = $1
      and pr.supporter_user_id = $2
      and pr.status = 'active'
      and pr.ended_at is null
      and coalesce(
        (pr.permissions ->> (
          case $3
            when 'view_phase'         then 'show_current_phase'
            when 'view_predictions'   then 'show_phase_predictions'
            when 'view_cycle_details' then 'show_period_dates'
            when 'view_emotions'      then 'show_journal_summary'
            when 'view_journal'       then 'show_journal_full'
            when 'view_basal_temp'    then 'show_basal_temp'
            else $3
          end
        ))::boolean,
        false
      )
  );
$$;

revoke execute on function public.partner_has_permission(uuid, uuid, text) from public;
grant  execute on function public.partner_has_permission(uuid, uuid, text) to authenticated;
grant  execute on function public.partner_has_permission(uuid, uuid, text) to service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 3a. Tracker updates what they share. Merges the given keys into the
--     stored JSON so untouched keys survive. Returns the merged JSON.
--     Errors: not_authenticated, invalid_permissions, relationship_not_found
-- ──────────────────────────────────────────────────────────────────────────

create or replace function public.update_partner_permissions(p_relationship_id uuid, p_permissions jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_perms jsonb;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;
  if p_permissions is null or jsonb_typeof(p_permissions) <> 'object' then
    raise exception 'invalid_permissions';
  end if;

  update partner_relationships pr
  set permissions = coalesce(pr.permissions, '{}'::jsonb) || p_permissions
  where pr.id = p_relationship_id
    and pr.tracker_user_id = auth.uid()
    and pr.status = 'active'
    and pr.ended_at is null
  returning pr.permissions into v_perms;

  if not found then
    raise exception 'relationship_not_found';
  end if;

  return v_perms;
end $$;

revoke execute on function public.update_partner_permissions(uuid, jsonb) from public;
revoke execute on function public.update_partner_permissions(uuid, jsonb) from anon;
grant  execute on function public.update_partner_permissions(uuid, jsonb) to authenticated;
grant  execute on function public.update_partner_permissions(uuid, jsonb) to service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 3b. Either side ends the relationship. Sets ended_at (the source of truth)
--     and, when the schema's status type allows it, status = 'disconnected'.
--     Errors: not_authenticated, relationship_not_found
-- ──────────────────────────────────────────────────────────────────────────

create or replace function public.disconnect_partner(p_relationship_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated';
  end if;

  select pr.id into v_id
  from partner_relationships pr
  where pr.id = p_relationship_id
    and (pr.tracker_user_id = auth.uid() or pr.supporter_user_id = auth.uid())
    and pr.ended_at is null
  for update;

  if not found then
    raise exception 'relationship_not_found';
  end if;

  begin
    update partner_relationships
    set status = 'disconnected', ended_at = now()
    where id = v_id;
  exception
    when check_violation or invalid_text_representation then
      -- status is constrained to a set that lacks 'disconnected';
      -- ended_at alone carries the meaning.
      update partner_relationships
      set ended_at = now()
      where id = v_id;
  end;
end $$;

revoke execute on function public.disconnect_partner(uuid) from public;
revoke execute on function public.disconnect_partner(uuid) from anon;
grant  execute on function public.disconnect_partner(uuid) to authenticated;
grant  execute on function public.disconnect_partner(uuid) to service_role;

-- ──────────────────────────────────────────────────────────────────────────
-- 4a. accept_invitation: an ended relationship must not be reused; a fresh
--     accept after a disconnect creates a new row.
-- ──────────────────────────────────────────────────────────────────────────

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

  v_code := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
  if v_code !~ '^FLO-' then
    v_code := 'FLO-' || v_code;
  end if;

  select * into v_invite
  from invitations
  where invitation_code = v_code
  for update;

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

  select pr.id into v_rel_id
  from partner_relationships pr
  where pr.tracker_user_id = v_invite.tracker_user_id
    and pr.supporter_user_id = v_supporter
    and pr.status = 'active'
    and pr.ended_at is null
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

  select exists (
    select 1 from cycles c
    where c.user_id = v_supporter and c.deleted_at is null
  ) into v_has_cycles;

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

-- ──────────────────────────────────────────────────────────────────────────
-- 4b. my_partner_relationships: exclude ended rows.
-- ──────────────────────────────────────────────────────────────────────────

create or replace function public.my_partner_relationships()
returns table (
  relationship_id        uuid,
  tracker_user_id        uuid,
  supporter_user_id      uuid,
  tracker_display_name   text,
  supporter_display_name text,
  relationship_type      text,
  status                 text,
  permissions            jsonb,
  accepted_at            timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select pr.id,
         pr.tracker_user_id,
         pr.supporter_user_id,
         coalesce(tp.display_name, ''),
         coalesce(sp.display_name, ''),
         pr.relationship_type::text,
         pr.status::text,
         pr.permissions,
         pr.accepted_at
  from partner_relationships pr
  left join profiles tp on tp.user_id = pr.tracker_user_id
  left join profiles sp on sp.user_id = pr.supporter_user_id
  where auth.uid() is not null
    and (pr.tracker_user_id = auth.uid() or pr.supporter_user_id = auth.uid())
    and pr.status = 'active'
    and pr.ended_at is null
  order by pr.accepted_at desc nulls last;
$$;

-- ──────────────────────────────────────────────────────────────────────────
-- 4c. supporter_snapshot: canonical key only, exclude ended rows.
-- ──────────────────────────────────────────────────────────────────────────

create or replace function public.supporter_snapshot()
returns table (
  relationship_id      uuid,
  tracker_user_id      uuid,
  tracker_display_name text,
  can_view_phase       boolean,
  last_period_start    date,
  cycle_length_days    integer,
  period_length_days   integer
)
language sql
security definer
set search_path = public
stable
as $$
  with rel as (
    select pr.id, pr.tracker_user_id, pr.permissions
    from partner_relationships pr
    where auth.uid() is not null
      and pr.supporter_user_id = auth.uid()
      and pr.status = 'active'
      and pr.ended_at is null
    order by pr.accepted_at desc nulls last
    limit 1
  ),
  gated as (
    select rel.id,
           rel.tracker_user_id,
           coalesce(nullif(rel.permissions->>'show_current_phase', '')::boolean, false) as can_view_phase
    from rel
  )
  select g.id,
         g.tracker_user_id,
         coalesce(tp.display_name, ''),
         g.can_view_phase,
         case when g.can_view_phase then (
           select c.start_date::date
           from cycles c
           where c.user_id = g.tracker_user_id and c.deleted_at is null
           order by c.start_date desc
           limit 1
         ) end,
         case when g.can_view_phase then coalesce(tp.default_cycle_length_days, 28)::integer end,
         case when g.can_view_phase then coalesce(tp.default_period_length_days, 5)::integer end
  from gated g
  left join profiles tp on tp.user_id = g.tracker_user_id;
$$;
