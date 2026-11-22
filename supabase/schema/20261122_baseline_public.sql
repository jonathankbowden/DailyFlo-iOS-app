--
-- PostgreSQL database dump
--

\restrict hWKgpBhR7LDYrkxK9lLKiVpEDKMO5Vkkj2BqssCmb1fYYV3F0TqXBfrqaHauAzo

-- Dumped from database version 17.11
-- Dumped by pg_dump version 19.0

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: accept_invitation(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.accept_invitation(p_code text) RETURNS TABLE(relationship_id uuid, tracker_user_id uuid, tracker_display_name text, relationship_type text, status text, permissions jsonb, accepted_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: delete_my_account(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_my_account() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  delete from public.cycle_entries       where user_id = v_uid;
  delete from public.emotion_entries     where user_id = v_uid;
  delete from public.meditation_sessions where user_id = v_uid;
  delete from public.cycles              where user_id = v_uid;

  delete from public.partner_relationships
    where tracker_user_id = v_uid or supporter_user_id = v_uid;
  delete from public.invitations         where tracker_user_id = v_uid;
  update public.invitations set accepted_by_user_id = null
    where accepted_by_user_id = v_uid;

  delete from public.subscription_webhook_events where app_user_id = v_uid::text;
  delete from public.subscriptions       where user_id = v_uid;

  delete from public.profiles            where user_id = v_uid;

  delete from auth.users                 where id = v_uid;
end;
$$;


--
-- Name: disconnect_partner(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.disconnect_partner(p_relationship_id uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.profiles (user_id, display_name, birth_date)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'display_name', ''),
    COALESCE((NEW.raw_user_meta_data->>'birth_date')::date, '2000-01-01'::date)
  );
  RETURN NEW;
END;
$$;


--
-- Name: my_partner_relationships(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_partner_relationships() RETURNS TABLE(relationship_id uuid, tracker_user_id uuid, supporter_user_id uuid, tracker_display_name text, supporter_display_name text, relationship_type text, status text, permissions jsonb, accepted_at timestamp with time zone)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: partner_has_permission(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.partner_has_permission(tracker_id uuid, supporter_id uuid, permission_key text) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1
    from partner_relationships pr
    where pr.tracker_user_id = tracker_id
      and pr.supporter_user_id = supporter_id
      and pr.status = 'active'
      and pr.ended_at is null
      and coalesce(
        (pr.permissions ->> (
          case permission_key
            when 'view_phase'         then 'show_current_phase'
            when 'view_predictions'   then 'show_phase_predictions'
            when 'view_cycle_details' then 'show_period_dates'
            when 'view_emotions'      then 'show_journal_summary'
            when 'view_journal'       then 'show_journal_full'
            when 'view_basal_temp'    then 'show_basal_temp'
            else permission_key
          end
        ))::boolean,
        false
      )
  );
$$;


--
-- Name: rls_auto_enable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.rls_auto_enable() RETURNS event_trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'pg_catalog'
    AS $$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$$;


--
-- Name: supporter_snapshot(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.supporter_snapshot() RETURNS TABLE(relationship_id uuid, tracker_user_id uuid, tracker_display_name text, can_view_phase boolean, last_period_start date, cycle_length_days integer, period_length_days integer)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: update_partner_permissions(uuid, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_partner_permissions(p_relationship_id uuid, p_permissions jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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


--
-- Name: update_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cycle_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cycle_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    cycle_id uuid,
    entry_date date NOT NULL,
    flow_level text,
    symptoms jsonb DEFAULT '[]'::jsonb NOT NULL,
    basal_temp_f numeric(4,2),
    basal_temp_taken_at time without time zone,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    CONSTRAINT cycle_entries_basal_temp_f_check CHECK (((basal_temp_f >= 95.00) AND (basal_temp_f <= 105.00))),
    CONSTRAINT cycle_entries_flow_level_check CHECK ((flow_level = ANY (ARRAY['none'::text, 'spotting'::text, 'light'::text, 'medium'::text, 'heavy'::text, 'very_heavy'::text])))
);


--
-- Name: cycles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cycles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    start_date date NOT NULL,
    predicted_end_date date,
    actual_end_date date,
    cycle_length_days integer,
    period_length_days integer,
    is_predicted boolean DEFAULT false NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone
);


--
-- Name: emotion_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.emotion_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    entry_date date NOT NULL,
    primary_emotion text NOT NULL,
    secondary_emotions jsonb DEFAULT '[]'::jsonb NOT NULL,
    intensity integer NOT NULL,
    notes text,
    voice_note_url text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    photo_path text,
    CONSTRAINT emotion_entries_intensity_check CHECK (((intensity >= 1) AND (intensity <= 5))),
    CONSTRAINT emotion_entries_primary_emotion_check CHECK ((primary_emotion = ANY (ARRAY['hurt'::text, 'lonely'::text, 'sad'::text, 'anger'::text, 'fear'::text, 'shame'::text, 'guilt'::text, 'glad'::text])))
);


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tracker_user_id uuid NOT NULL,
    invitation_code text NOT NULL,
    recipient_email text,
    recipient_phone text,
    relationship_type text NOT NULL,
    proposed_permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    expires_at timestamp with time zone DEFAULT (now() + '30 days'::interval) NOT NULL,
    accepted_at timestamp with time zone,
    accepted_by_user_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT invitations_relationship_type_check CHECK ((relationship_type = ANY (ARRAY['parent'::text, 'partner'::text, 'spouse'::text, 'friend'::text, 'other'::text])))
);


--
-- Name: meditation_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meditation_sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    meditation_id uuid NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    actual_duration_seconds integer,
    used_own_music boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: meditations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.meditations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    title text NOT NULL,
    description text NOT NULL,
    duration_seconds integer NOT NULL,
    audio_url text NOT NULL,
    category text NOT NULL,
    composer text NOT NULL,
    composer_email text,
    license_type text NOT NULL,
    license_url text,
    script_url text,
    published_at timestamp with time zone,
    is_featured boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    theme_key text,
    phase text,
    duration_minutes integer,
    image_name text,
    audio_path text,
    bundled_audio text,
    ambient_sound text,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT false NOT NULL,
    CONSTRAINT meditations_duration_seconds_check CHECK ((duration_seconds > 0)),
    CONSTRAINT meditations_license_type_check CHECK ((license_type = ANY (ARRAY['suno_pro'::text, 'work_for_hire'::text, 'licensed'::text, 'public_domain'::text, 'original_member'::text])))
);


--
-- Name: partner_relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.partner_relationships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tracker_user_id uuid NOT NULL,
    supporter_user_id uuid NOT NULL,
    relationship_type text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    permissions jsonb DEFAULT '{}'::jsonb NOT NULL,
    invited_at timestamp with time zone DEFAULT now() NOT NULL,
    accepted_at timestamp with time zone,
    ended_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT partner_relationships_relationship_type_check CHECK ((relationship_type = ANY (ARRAY['parent'::text, 'partner'::text, 'spouse'::text, 'friend'::text, 'other'::text]))),
    CONSTRAINT partner_relationships_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'paused'::text, 'ended'::text])))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    display_name text NOT NULL,
    birth_date date NOT NULL,
    role text DEFAULT 'tracker'::text NOT NULL,
    life_stage text DEFAULT 'unspecified'::text NOT NULL,
    cycle_tracking_enabled boolean DEFAULT true NOT NULL,
    onboarding_completed_at timestamp with time zone,
    avatar_image_url text,
    timezone text DEFAULT 'America/Denver'::text NOT NULL,
    temperature_unit text DEFAULT 'fahrenheit'::text NOT NULL,
    notification_preferences jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    deleted_at timestamp with time zone,
    default_cycle_length_days integer DEFAULT 28 NOT NULL,
    default_period_length_days integer DEFAULT 5 NOT NULL,
    CONSTRAINT profiles_life_stage_check CHECK ((life_stage = ANY (ARRAY['menarche'::text, 'fertile'::text, 'perimenopause'::text, 'postmenopause'::text, 'unspecified'::text]))),
    CONSTRAINT profiles_role_check CHECK ((role = ANY (ARRAY['tracker'::text, 'supporter'::text, 'both'::text]))),
    CONSTRAINT profiles_temperature_unit_check CHECK ((temperature_unit = ANY (ARRAY['fahrenheit'::text, 'celsius'::text])))
);


--
-- Name: subscription_webhook_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_webhook_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_id text NOT NULL,
    event_type text NOT NULL,
    app_user_id text,
    payload jsonb NOT NULL,
    received_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    tier text NOT NULL,
    status text NOT NULL,
    trial_ends_at timestamp with time zone,
    current_period_starts_at timestamp with time zone,
    current_period_ends_at timestamp with time zone,
    revenuecat_app_user_id text NOT NULL,
    revenuecat_subscription_id text,
    last_synced_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    product_id text,
    entitlement text,
    store text,
    last_event_id text,
    last_event_type text,
    CONSTRAINT subscriptions_status_check CHECK ((status = ANY (ARRAY['active'::text, 'trial'::text, 'expired'::text, 'cancelled'::text]))),
    CONSTRAINT subscriptions_tier_check CHECK ((tier = ANY (ARRAY['trial'::text, 'monthly'::text, 'annual'::text, 'founding'::text, 'promo'::text, 'free'::text])))
);


--
-- Name: cycle_entries cycle_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cycle_entries
    ADD CONSTRAINT cycle_entries_pkey PRIMARY KEY (id);


--
-- Name: cycles cycles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cycles
    ADD CONSTRAINT cycles_pkey PRIMARY KEY (id);


--
-- Name: emotion_entries emotion_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emotion_entries
    ADD CONSTRAINT emotion_entries_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_invitation_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_invitation_code_key UNIQUE (invitation_code);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: meditation_sessions meditation_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meditation_sessions
    ADD CONSTRAINT meditation_sessions_pkey PRIMARY KEY (id);


--
-- Name: meditations meditations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meditations
    ADD CONSTRAINT meditations_pkey PRIMARY KEY (id);


--
-- Name: meditations meditations_theme_duration_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meditations
    ADD CONSTRAINT meditations_theme_duration_key UNIQUE (theme_key, duration_minutes);


--
-- Name: partner_relationships partner_relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_relationships
    ADD CONSTRAINT partner_relationships_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_user_id_key UNIQUE (user_id);


--
-- Name: subscription_webhook_events subscription_webhook_events_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_webhook_events
    ADD CONSTRAINT subscription_webhook_events_event_id_key UNIQUE (event_id);


--
-- Name: subscription_webhook_events subscription_webhook_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_webhook_events
    ADD CONSTRAINT subscription_webhook_events_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: subscriptions subscriptions_user_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_user_id_key UNIQUE (user_id);


--
-- Name: idx_cycle_entries_cycle; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cycle_entries_cycle ON public.cycle_entries USING btree (cycle_id) WHERE (cycle_id IS NOT NULL);


--
-- Name: idx_cycle_entries_user_date_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_cycle_entries_user_date_unique ON public.cycle_entries USING btree (user_id, entry_date) WHERE (deleted_at IS NULL);


--
-- Name: idx_cycle_entries_user_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cycle_entries_user_recent ON public.cycle_entries USING btree (user_id, entry_date DESC);


--
-- Name: idx_cycles_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cycles_active ON public.cycles USING btree (user_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_cycles_user_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cycles_user_recent ON public.cycles USING btree (user_id, start_date DESC);


--
-- Name: idx_emotion_entries_user_emotion; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emotion_entries_user_emotion ON public.emotion_entries USING btree (user_id, primary_emotion);


--
-- Name: idx_emotion_entries_user_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_emotion_entries_user_recent ON public.emotion_entries USING btree (user_id, entry_date DESC);


--
-- Name: idx_invitations_tracker; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_invitations_tracker ON public.invitations USING btree (tracker_user_id);


--
-- Name: idx_meditation_sessions_user_meditation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meditation_sessions_user_meditation ON public.meditation_sessions USING btree (user_id, meditation_id);


--
-- Name: idx_meditation_sessions_user_recent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meditation_sessions_user_recent ON public.meditation_sessions USING btree (user_id, started_at DESC);


--
-- Name: idx_meditations_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meditations_category ON public.meditations USING btree (category);


--
-- Name: idx_meditations_published; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_meditations_published ON public.meditations USING btree (published_at DESC) WHERE ((published_at IS NOT NULL) AND (deleted_at IS NULL));


--
-- Name: idx_partner_rel_supporter; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partner_rel_supporter ON public.partner_relationships USING btree (supporter_user_id);


--
-- Name: idx_partner_rel_tracker; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partner_rel_tracker ON public.partner_relationships USING btree (tracker_user_id);


--
-- Name: idx_partner_rel_tracker_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_partner_rel_tracker_active ON public.partner_relationships USING btree (tracker_user_id, status);


--
-- Name: idx_partner_rel_unique_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_partner_rel_unique_active ON public.partner_relationships USING btree (tracker_user_id, supporter_user_id) WHERE (status <> 'ended'::text);


--
-- Name: idx_profiles_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_active ON public.profiles USING btree (user_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_subscriptions_revenuecat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_subscriptions_revenuecat ON public.subscriptions USING btree (revenuecat_app_user_id);


--
-- Name: subscription_webhook_events_app_user_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subscription_webhook_events_app_user_id_idx ON public.subscription_webhook_events USING btree (app_user_id);


--
-- Name: subscription_webhook_events_received_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subscription_webhook_events_received_at_idx ON public.subscription_webhook_events USING btree (received_at DESC);


--
-- Name: cycle_entries cycle_entries_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cycle_entries_updated_at BEFORE UPDATE ON public.cycle_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: cycles cycles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cycles_updated_at BEFORE UPDATE ON public.cycles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: emotion_entries emotion_entries_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER emotion_entries_updated_at BEFORE UPDATE ON public.emotion_entries FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: invitations invitations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER invitations_updated_at BEFORE UPDATE ON public.invitations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: meditations meditations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER meditations_updated_at BEFORE UPDATE ON public.meditations FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: partner_relationships partner_relationships_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER partner_relationships_updated_at BEFORE UPDATE ON public.partner_relationships FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: profiles profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: subscriptions subscriptions_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER subscriptions_updated_at BEFORE UPDATE ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();


--
-- Name: cycle_entries cycle_entries_cycle_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cycle_entries
    ADD CONSTRAINT cycle_entries_cycle_id_fkey FOREIGN KEY (cycle_id) REFERENCES public.cycles(id) ON DELETE SET NULL;


--
-- Name: cycle_entries cycle_entries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cycle_entries
    ADD CONSTRAINT cycle_entries_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: cycles cycles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cycles
    ADD CONSTRAINT cycles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: emotion_entries emotion_entries_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.emotion_entries
    ADD CONSTRAINT emotion_entries_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: invitations invitations_accepted_by_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_accepted_by_user_id_fkey FOREIGN KEY (accepted_by_user_id) REFERENCES auth.users(id);


--
-- Name: invitations invitations_tracker_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_tracker_user_id_fkey FOREIGN KEY (tracker_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: meditation_sessions meditation_sessions_meditation_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meditation_sessions
    ADD CONSTRAINT meditation_sessions_meditation_id_fkey FOREIGN KEY (meditation_id) REFERENCES public.meditations(id) ON DELETE RESTRICT;


--
-- Name: meditation_sessions meditation_sessions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.meditation_sessions
    ADD CONSTRAINT meditation_sessions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: partner_relationships partner_relationships_supporter_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_relationships
    ADD CONSTRAINT partner_relationships_supporter_user_id_fkey FOREIGN KEY (supporter_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: partner_relationships partner_relationships_tracker_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.partner_relationships
    ADD CONSTRAINT partner_relationships_tracker_user_id_fkey FOREIGN KEY (tracker_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: meditations Authenticated users can view published meditations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Authenticated users can view published meditations" ON public.meditations FOR SELECT USING (((published_at IS NOT NULL) AND (deleted_at IS NULL)));


--
-- Name: cycle_entries Partners can view tracker cycle entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Partners can view tracker cycle entries" ON public.cycle_entries FOR SELECT USING (public.partner_has_permission(user_id, auth.uid(), 'show_current_phase'::text));


--
-- Name: cycles Partners can view tracker cycles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Partners can view tracker cycles" ON public.cycles FOR SELECT USING (public.partner_has_permission(user_id, auth.uid(), 'show_current_phase'::text));


--
-- Name: emotion_entries Partners can view tracker journal if granted; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Partners can view tracker journal if granted" ON public.emotion_entries FOR SELECT USING (public.partner_has_permission(user_id, auth.uid(), 'show_journal_full'::text));


--
-- Name: profiles Partners can view tracker profile basics; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Partners can view tracker profile basics" ON public.profiles FOR SELECT USING ((EXISTS ( SELECT 1
   FROM public.partner_relationships
  WHERE ((partner_relationships.tracker_user_id = profiles.user_id) AND (partner_relationships.supporter_user_id = auth.uid()) AND (partner_relationships.status = 'active'::text)))));


--
-- Name: partner_relationships Supporters can update their accepted_at; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Supporters can update their accepted_at" ON public.partner_relationships FOR UPDATE USING ((supporter_user_id = auth.uid()));


--
-- Name: invitations Trackers can delete own invitations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Trackers can delete own invitations" ON public.invitations FOR DELETE USING ((tracker_user_id = auth.uid()));


--
-- Name: partner_relationships Trackers can delete their relationships; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Trackers can delete their relationships" ON public.partner_relationships FOR DELETE USING ((tracker_user_id = auth.uid()));


--
-- Name: invitations Trackers can insert own invitations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Trackers can insert own invitations" ON public.invitations FOR INSERT WITH CHECK ((tracker_user_id = auth.uid()));


--
-- Name: partner_relationships Trackers can insert their own relationships; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Trackers can insert their own relationships" ON public.partner_relationships FOR INSERT WITH CHECK ((tracker_user_id = auth.uid()));


--
-- Name: invitations Trackers can update own invitations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Trackers can update own invitations" ON public.invitations FOR UPDATE USING ((tracker_user_id = auth.uid()));


--
-- Name: partner_relationships Trackers can update their relationships; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Trackers can update their relationships" ON public.partner_relationships FOR UPDATE USING ((tracker_user_id = auth.uid()));


--
-- Name: invitations Trackers can view own invitations; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Trackers can view own invitations" ON public.invitations FOR SELECT USING ((tracker_user_id = auth.uid()));


--
-- Name: cycle_entries Users can delete own cycle entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete own cycle entries" ON public.cycle_entries FOR DELETE USING ((user_id = auth.uid()));


--
-- Name: cycles Users can delete own cycles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete own cycles" ON public.cycles FOR DELETE USING ((user_id = auth.uid()));


--
-- Name: emotion_entries Users can delete own emotion entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can delete own emotion entries" ON public.emotion_entries FOR DELETE USING ((user_id = auth.uid()));


--
-- Name: cycle_entries Users can insert own cycle entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own cycle entries" ON public.cycle_entries FOR INSERT WITH CHECK ((user_id = auth.uid()));


--
-- Name: cycles Users can insert own cycles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own cycles" ON public.cycles FOR INSERT WITH CHECK ((user_id = auth.uid()));


--
-- Name: emotion_entries Users can insert own emotion entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own emotion entries" ON public.emotion_entries FOR INSERT WITH CHECK ((user_id = auth.uid()));


--
-- Name: meditation_sessions Users can insert own meditation sessions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own meditation sessions" ON public.meditation_sessions FOR INSERT WITH CHECK ((user_id = auth.uid()));


--
-- Name: profiles Users can insert own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK ((user_id = auth.uid()));


--
-- Name: cycle_entries Users can update own cycle entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own cycle entries" ON public.cycle_entries FOR UPDATE USING ((user_id = auth.uid()));


--
-- Name: cycles Users can update own cycles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own cycles" ON public.cycles FOR UPDATE USING ((user_id = auth.uid()));


--
-- Name: emotion_entries Users can update own emotion entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own emotion entries" ON public.emotion_entries FOR UPDATE USING ((user_id = auth.uid()));


--
-- Name: meditation_sessions Users can update own meditation sessions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own meditation sessions" ON public.meditation_sessions FOR UPDATE USING ((user_id = auth.uid()));


--
-- Name: profiles Users can update own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING ((user_id = auth.uid()));


--
-- Name: cycle_entries Users can view own cycle entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own cycle entries" ON public.cycle_entries FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: cycles Users can view own cycles; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own cycles" ON public.cycles FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: emotion_entries Users can view own emotion entries; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own emotion entries" ON public.emotion_entries FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: meditation_sessions Users can view own meditation sessions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own meditation sessions" ON public.meditation_sessions FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: profiles Users can view own profile; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own profile" ON public.profiles FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: subscriptions Users can view own subscription; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view own subscription" ON public.subscriptions FOR SELECT USING ((user_id = auth.uid()));


--
-- Name: partner_relationships Users can view relationships they participate in; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY "Users can view relationships they participate in" ON public.partner_relationships FOR SELECT USING (((tracker_user_id = auth.uid()) OR (supporter_user_id = auth.uid())));


--
-- Name: cycle_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cycle_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: cycles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.cycles ENABLE ROW LEVEL SECURITY;

--
-- Name: emotion_entries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.emotion_entries ENABLE ROW LEVEL SECURITY;

--
-- Name: invitations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

--
-- Name: meditation_sessions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.meditation_sessions ENABLE ROW LEVEL SECURITY;

--
-- Name: meditations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.meditations ENABLE ROW LEVEL SECURITY;

--
-- Name: meditations meditations_select_active; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY meditations_select_active ON public.meditations FOR SELECT TO authenticated USING (((is_active = true) AND (deleted_at IS NULL)));


--
-- Name: partner_relationships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.partner_relationships ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: subscription_webhook_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscription_webhook_events ENABLE ROW LEVEL SECURITY;

--
-- Name: subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO postgres;
GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION accept_invitation(p_code text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.accept_invitation(p_code text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.accept_invitation(p_code text) TO authenticated;
GRANT ALL ON FUNCTION public.accept_invitation(p_code text) TO service_role;


--
-- Name: FUNCTION delete_my_account(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC;
GRANT ALL ON FUNCTION public.delete_my_account() TO authenticated;


--
-- Name: FUNCTION disconnect_partner(p_relationship_id uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.disconnect_partner(p_relationship_id uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.disconnect_partner(p_relationship_id uuid) TO authenticated;
GRANT ALL ON FUNCTION public.disconnect_partner(p_relationship_id uuid) TO service_role;


--
-- Name: FUNCTION my_partner_relationships(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.my_partner_relationships() FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_partner_relationships() TO authenticated;
GRANT ALL ON FUNCTION public.my_partner_relationships() TO service_role;


--
-- Name: FUNCTION partner_has_permission(tracker_id uuid, supporter_id uuid, permission_key text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.partner_has_permission(tracker_id uuid, supporter_id uuid, permission_key text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.partner_has_permission(tracker_id uuid, supporter_id uuid, permission_key text) TO authenticated;
GRANT ALL ON FUNCTION public.partner_has_permission(tracker_id uuid, supporter_id uuid, permission_key text) TO service_role;


--
-- Name: FUNCTION supporter_snapshot(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.supporter_snapshot() FROM PUBLIC;
GRANT ALL ON FUNCTION public.supporter_snapshot() TO authenticated;
GRANT ALL ON FUNCTION public.supporter_snapshot() TO service_role;


--
-- Name: FUNCTION update_partner_permissions(p_relationship_id uuid, p_permissions jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_partner_permissions(p_relationship_id uuid, p_permissions jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_partner_permissions(p_relationship_id uuid, p_permissions jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.update_partner_permissions(p_relationship_id uuid, p_permissions jsonb) TO service_role;


--
-- Name: TABLE cycle_entries; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.cycle_entries TO anon;
GRANT ALL ON TABLE public.cycle_entries TO authenticated;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.cycle_entries TO service_role;


--
-- Name: TABLE cycles; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.cycles TO anon;
GRANT ALL ON TABLE public.cycles TO authenticated;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.cycles TO service_role;


--
-- Name: TABLE emotion_entries; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.emotion_entries TO anon;
GRANT ALL ON TABLE public.emotion_entries TO authenticated;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.emotion_entries TO service_role;


--
-- Name: TABLE invitations; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.invitations TO anon;
GRANT ALL ON TABLE public.invitations TO authenticated;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.invitations TO service_role;


--
-- Name: TABLE meditation_sessions; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.meditation_sessions TO anon;
GRANT ALL ON TABLE public.meditation_sessions TO authenticated;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.meditation_sessions TO service_role;


--
-- Name: TABLE meditations; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.meditations TO anon;
GRANT ALL ON TABLE public.meditations TO authenticated;
GRANT ALL ON TABLE public.meditations TO service_role;


--
-- Name: TABLE partner_relationships; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.partner_relationships TO anon;
GRANT ALL ON TABLE public.partner_relationships TO authenticated;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.partner_relationships TO service_role;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.profiles TO anon;
GRANT ALL ON TABLE public.profiles TO authenticated;
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.profiles TO service_role;


--
-- Name: TABLE subscription_webhook_events; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.subscription_webhook_events TO anon;
GRANT ALL ON TABLE public.subscription_webhook_events TO authenticated;
GRANT ALL ON TABLE public.subscription_webhook_events TO service_role;


--
-- Name: TABLE subscriptions; Type: ACL; Schema: public; Owner: -
--

GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE public.subscriptions TO anon;
GRANT ALL ON TABLE public.subscriptions TO authenticated;
GRANT ALL ON TABLE public.subscriptions TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;


--
-- Name: DEFAULT PRIVILEGES FOR SEQUENCES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON SEQUENCES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO postgres;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE supabase_admin IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--

\unrestrict hWKgpBhR7LDYrkxK9lLKiVpEDKMO5Vkkj2BqssCmb1fYYV3F0TqXBfrqaHauAzo

