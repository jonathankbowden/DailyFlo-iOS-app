-- Day 11 of the 30-for-30 (Sept 2026): Connect reads real state.
--
-- Returns the signed-in user's active partner relationships, from either
-- side, with both parties' display names attached. SECURITY DEFINER for the
-- same reason as accept_invitation: RLS on `profiles` only exposes your own
-- row, and the other party's name is exactly what the Connect card and the
-- supporter home need to render.
--
-- Re-runnable. Apply via the SQL editor or `supabase db push`.

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
  order by pr.accepted_at desc nulls last;
$$;

-- Only signed-in users may call this. Never anon.
revoke execute on function public.my_partner_relationships() from public;
revoke execute on function public.my_partner_relationships() from anon;
grant  execute on function public.my_partner_relationships() to authenticated;
grant  execute on function public.my_partner_relationships() to service_role;
