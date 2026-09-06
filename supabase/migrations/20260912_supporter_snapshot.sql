-- Day 12 of the 30-for-30 (Sept 2026): the supporter home reads real data.
--
-- One call gives the supporter everything their home screen renders: who
-- they're supporting, whether they're allowed to see the phase, and the
-- three numbers the app needs to compute it (last period start, cycle
-- length, period length). The phase itself is computed client-side with
-- the same math the tracker's own screens use.
--
-- SECURITY DEFINER, so the permission check here is the gate. It reads the
-- relationship's `permissions` JSON directly and accepts either key the
-- codebase has used for "may see the phase":
--   show_current_phase  — what the app writes on invite (PartnerManager)
--   view_phase          — what the July RLS verification script assumed
-- Day 13 (permissions) settles on one; until then both are honored so a
-- supporter is never locked out by a naming drift.
--
-- Re-runnable. Apply via the SQL editor or `supabase db push`.

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
    order by pr.accepted_at desc nulls last
    limit 1
  ),
  gated as (
    select rel.id,
           rel.tracker_user_id,
           coalesce(
             nullif(rel.permissions->>'show_current_phase', '')::boolean,
             nullif(rel.permissions->>'view_phase', '')::boolean,
             false
           ) as can_view_phase
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

-- Only signed-in users may call this. Never anon.
revoke execute on function public.supporter_snapshot() from public;
revoke execute on function public.supporter_snapshot() from anon;
grant  execute on function public.supporter_snapshot() to authenticated;
grant  execute on function public.supporter_snapshot() to service_role;
