DROP TABLE IF EXISTS public.dim_locations CASCADE;

CREATE TABLE public.dim_locations
 (
    location_id INT PRIMARY KEY,
    city        VARCHAR(50)  NOT NULL,
    country     VARCHAR(50)  NOT NULL,
    latitude    NUMERIC(9,6) NOT NULL,
    longitude   NUMERIC(9,6) NOT NULL
);

DROP TABLE IF EXISTS public.dim_devices CASCADE;

CREATE TABLE IF NOT EXISTS public.dim_devices
(
    device_id integer NOT NULL,
    device_type character varying(20) COLLATE pg_catalog."default" NOT NULL,
    os character varying(30) COLLATE pg_catalog."default" NOT NULL,
    browser character varying(30) COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT dim_devices_pkey PRIMARY KEY (device_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.dim_devices
    OWNER to postgres;

DROP TABLE IF EXISTS public.dim_users CASCADE;

CREATE TABLE IF NOT EXISTS public.dim_users
(
    user_id character varying(10) COLLATE pg_catalog."default" NOT NULL,
    full_name character varying(100) COLLATE pg_catalog."default" NOT NULL,
    email character varying(150) COLLATE pg_catalog."default" NOT NULL,
    department character varying(50) COLLATE pg_catalog."default" NOT NULL,
    is_vip boolean NOT NULL,
    home_location_id integer NOT NULL,
    CONSTRAINT dim_users_pkey PRIMARY KEY (user_id),
    CONSTRAINT dim_users_home_location_id_fkey FOREIGN KEY (home_location_id)
        REFERENCES public.dim_locations (location_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.dim_users
    OWNER to postgres;

DROP TABLE IF EXISTS public.fact_auth_events CASCADE;

CREATE TABLE IF NOT EXISTS public.fact_auth_events
(
    event_id character varying(12) COLLATE pg_catalog."default" NOT NULL,
    event_time timestamp without time zone NOT NULL,
    user_id character varying(10) COLLATE pg_catalog."default" NOT NULL,
    location_id integer NOT NULL,
    device_id integer NOT NULL,
    ip_address character varying(45) COLLATE pg_catalog."default" NOT NULL,
    status character varying(10) COLLATE pg_catalog."default" NOT NULL,
    mfa_status character varying(15) COLLATE pg_catalog."default" NOT NULL,
    CONSTRAINT fact_auth_events_pkey PRIMARY KEY (event_id),
    CONSTRAINT fact_auth_events_device_id_fkey FOREIGN KEY (device_id)
        REFERENCES public.dim_devices (device_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT fact_auth_events_location_id_fkey FOREIGN KEY (location_id)
        REFERENCES public.dim_locations (location_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT fact_auth_events_user_id_fkey FOREIGN KEY (user_id)
        REFERENCES public.dim_users (user_id) MATCH SIMPLE
        ON UPDATE NO ACTION
        ON DELETE NO ACTION,
    CONSTRAINT fact_auth_events_mfa_status_check CHECK (mfa_status::text = ANY (ARRAY['APPROVED'::character varying, 'DENIED'::character varying, 'BYPASSED'::character varying, 'NOT_PROMPTED'::character varying]::text[])),
    CONSTRAINT fact_auth_events_status_check CHECK (status::text = ANY (ARRAY['SUCCESS'::character varying, 'FAILED'::character varying]::text[]))
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.fact_auth_events
    OWNER to postgres;
-- Index: idx_events_user_time

-- DROP INDEX IF EXISTS public.idx_events_user_time;

CREATE INDEX IF NOT EXISTS idx_events_user_time
    ON public.fact_auth_events USING btree
    (user_id COLLATE pg_catalog."default" ASC NULLS LAST, event_time ASC NULLS LAST)
;

DROP TABLE IF EXISTS public.attack_answer_key CASCADE;

CREATE TABLE IF NOT EXISTS public.attack_answer_key
(
    event_id character varying(12) COLLATE pg_catalog."default" NOT NULL,
    event_time timestamp without time zone,
    user_id character varying(10) COLLATE pg_catalog."default",
    attack_label character varying(30) COLLATE pg_catalog."default",
    CONSTRAINT attack_answer_key_pkey PRIMARY KEY (event_id)
)

TABLESPACE pg_default;

ALTER TABLE IF EXISTS public.attack_answer_key
    OWNER to postgres;
DROP VIEW IF EXISTS public.vw_impossible_travel_events CASCADE;

CREATE OR REPLACE VIEW public.vw_impossible_travel_events
 AS
 WITH steps AS (
         SELECT fact_auth_events.event_id,
            fact_auth_events.user_id,
            fact_auth_events.event_time,
            fact_auth_events.location_id,
            lag(fact_auth_events.event_time) OVER (PARTITION BY fact_auth_events.user_id ORDER BY fact_auth_events.event_time) AS prev_time,
            lag(fact_auth_events.location_id) OVER (PARTITION BY fact_auth_events.user_id ORDER BY fact_auth_events.event_time) AS prev_location
           FROM fact_auth_events
          WHERE fact_auth_events.status::text = 'SUCCESS'::text
        ), measured AS (
         SELECT s.event_id,
            s.user_id,
            s.event_time,
            pl.city AS from_city,
            cl.city AS to_city,
            (6371 * 2)::double precision * asin(sqrt(power(sin(radians((cl.latitude - pl.latitude)::double precision) / 2::double precision), 2::double precision) + cos(radians(pl.latitude::double precision)) * cos(radians(cl.latitude::double precision)) * power(sin(radians((cl.longitude - pl.longitude)::double precision) / 2::double precision), 2::double precision))) AS distance_km,
            EXTRACT(epoch FROM s.event_time - s.prev_time) / 3600.0 AS hours
           FROM steps s
             JOIN dim_locations cl ON cl.location_id = s.location_id
             JOIN dim_locations pl ON pl.location_id = s.prev_location
        )
 SELECT event_id,
    user_id,
    event_time,
    from_city,
    to_city,
    round(distance_km::numeric, 0) AS distance_km,
    round(hours, 2) AS hours,
    round((distance_km / NULLIF(hours, 0::numeric)::double precision)::numeric, 0) AS speed_kmh
   FROM measured
  WHERE distance_km > 200::double precision AND (distance_km / NULLIF(hours, 0::numeric)::double precision) > 800::double precision;

ALTER TABLE public.vw_impossible_travel_events
    OWNER TO postgres;

DROP VIEW IF EXISTS public.vw_mfa_fatigue_events CASCADE;

CREATE OR REPLACE VIEW public.vw_mfa_fatigue_events
 AS
 WITH counted AS (
         SELECT fact_auth_events.event_id,
            fact_auth_events.user_id,
            fact_auth_events.event_time,
            fact_auth_events.mfa_status,
            fact_auth_events.ip_address,
            sum(
                CASE
                    WHEN fact_auth_events.mfa_status::text = 'DENIED'::text THEN 1
                    ELSE 0
                END) OVER (PARTITION BY fact_auth_events.user_id ORDER BY fact_auth_events.event_time RANGE BETWEEN '00:10:00'::interval PRECEDING AND CURRENT ROW) AS denied_last_10_min
           FROM fact_auth_events
        )
 SELECT event_id,
    user_id,
    event_time,
    ip_address,
    denied_last_10_min
   FROM counted
  WHERE mfa_status::text = 'APPROVED'::text AND denied_last_10_min >= 5;

ALTER TABLE public.vw_mfa_fatigue_events
    OWNER TO postgres;


DROP VIEW IF EXISTS public.vw_brute_force_events CASCADE;

CREATE OR REPLACE VIEW public.vw_brute_force_events
 AS
 WITH counted AS (
         SELECT fact_auth_events.event_id,
            fact_auth_events.user_id,
            fact_auth_events.event_time,
            fact_auth_events.ip_address,
            count(*) OVER (PARTITION BY fact_auth_events.user_id, fact_auth_events.ip_address ORDER BY fact_auth_events.event_time RANGE BETWEEN '00:05:00'::interval PRECEDING AND CURRENT ROW) AS failed_last_5_min
           FROM fact_auth_events
          WHERE fact_auth_events.status::text = 'FAILED'::text AND fact_auth_events.mfa_status::text = 'NOT_PROMPTED'::text
        )
 SELECT user_id,
    ip_address,
    min(event_time) AS first_alert_time,
    max(failed_last_5_min) AS peak_failures_in_5_min
   FROM counted
  WHERE failed_last_5_min >= 10
  GROUP BY user_id, ip_address;

ALTER TABLE public.vw_brute_force_events
    OWNER TO postgres;

DROP VIEW IF EXISTS public.vw_fact_security_feed CASCADE;

CREATE OR REPLACE VIEW public.vw_fact_security_feed
 AS
 SELECT f.event_id,
    f.event_time,
    f.user_id,
    f.location_id,
    f.device_id,
    f.ip_address,
    f.status,
    f.mfa_status,
        CASE
            WHEN it.event_id IS NOT NULL THEN 'IMPOSSIBLE_TRAVEL'::text
            WHEN mf.event_id IS NOT NULL THEN 'MFA_FATIGUE'::text
            WHEN bf.user_id IS NOT NULL THEN 'BRUTE_FORCE'::text
            ELSE 'NORMAL'::text
        END AS threat_tag,
        CASE
            WHEN it.event_id IS NOT NULL THEN 50
            WHEN mf.event_id IS NOT NULL AND f.event_id::text = mf.event_id::text THEN 90
            WHEN mf.event_id IS NOT NULL THEN 1
            WHEN bf.user_id IS NOT NULL AND f.event_time = bf.first_alert_time THEN 80
            WHEN bf.user_id IS NOT NULL THEN 1
            WHEN f.status::text = 'FAILED'::text THEN 1
            ELSE 0
        END AS base_risk_weight
   FROM fact_auth_events f
     LEFT JOIN vw_impossible_travel_events it ON it.event_id::text = f.event_id::text
     LEFT JOIN vw_mfa_fatigue_events mf ON mf.user_id::text = f.user_id::text AND f.event_time >= (mf.event_time - '00:10:00'::interval) AND f.event_time <= mf.event_time AND (f.mfa_status::text = ANY (ARRAY['DENIED'::character varying, 'APPROVED'::character varying]::text[]))
     LEFT JOIN vw_brute_force_events bf ON bf.user_id::text = f.user_id::text AND bf.ip_address::text = f.ip_address::text AND f.status::text = 'FAILED'::text AND f.mfa_status::text = 'NOT_PROMPTED'::text;

ALTER TABLE public.vw_fact_security_feed
    OWNER TO postgres;