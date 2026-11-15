-- 20261115_delete_my_account.sql
--
-- In-app account deletion (App Store Guideline 5.1.1(v)). A SECURITY DEFINER
-- RPC the signed-in user calls to permanently erase their own account: every
-- row they own across public schema, any Storage objects they own, then the
-- auth.users record itself — all in one transaction.
--
-- Safety:
--   * Uses auth.uid() ONLY — never a passed-in id — so a caller can only ever
--     delete their own data.
--   * EXECUTE granted to `authenticated` only; revoked from public/anon.
--   * Deletes children before parents because these tables were created in the
--     SQL editor and ON DELETE CASCADE can't be assumed.
--
-- Re-runnable (CREATE OR REPLACE + idempotent grants).
--
-- NOTE: every NEW user-owned table must be added to the delete list below, or
-- deleting an account will leave its rows orphaned.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  -- Children first.
  delete from public.cycle_entries      where user_id = v_uid;
  delete from public.emotion_entries    where user_id = v_uid;
  delete from public.meditation_sessions where user_id = v_uid;
  delete from public.cycles             where user_id = v_uid;

  -- Partner graph: the caller may be on either side of a relationship, and may
  -- have accepted someone else's invitation (clear that reference, don't delete
  -- the other user's invitation).
  delete from public.partner_relationships
    where tracker_user_id = v_uid or supporter_user_id = v_uid;
  delete from public.invitations        where tracker_user_id = v_uid;
  update public.invitations set accepted_by_user_id = null
    where accepted_by_user_id = v_uid;

  -- Subscription mirror + its webhook idempotency log. The log keys on the
  -- RevenueCat app user id, which is the Supabase uid as text.
  delete from public.subscription_webhook_events where app_user_id = v_uid::text;
  delete from public.subscriptions      where user_id = v_uid;

  -- Profile (1:1 with the auth user).
  delete from public.profiles           where user_id = v_uid;

  -- Any Storage objects the caller owns (journal photos / voice notes once
  -- those move to Storage; a harmless no-op while they're still device-local).
  delete from storage.objects           where owner = v_uid;

  -- Finally the auth record. auth.identities / sessions / refresh_tokens
  -- cascade from this within the auth schema.
  delete from auth.users                where id = v_uid;
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
