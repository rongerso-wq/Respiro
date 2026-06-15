-- ════════════════════════════════════════════════════════════
--  Respiro — Supabase / PostgreSQL Schema
--  Paste into Supabase SQL Editor and run once.
--  Row-Level Security (RLS) is enabled on every table so each
--  user can only read/write their own data.
-- ════════════════════════════════════════════════════════════

-- ── Extensions ───────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ════════════════════════════════════════════════════════════
--  1. USERS / PROFILES
--     Extends Supabase auth.users with COPD-specific fields.
-- ════════════════════════════════════════════════════════════
create table public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  full_name     text        not null,
  date_of_birth date,
  physician     text,                       -- Doctor's name for the report
  created_at    timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Users can read own profile"
  on public.profiles for select
  using (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update
  using (auth.uid() = id);

-- ════════════════════════════════════════════════════════════
--  2. DAILY CHECK-INS  (traffic-light log)
-- ════════════════════════════════════════════════════════════
create type breathing_status as enum ('green', 'yellow', 'red');

create table public.check_ins (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references public.profiles(id) on delete cascade,
  status      breathing_status not null,
  note        text,                          -- Optional free-text from user
  logged_at   timestamptz default now()
);

alter table public.check_ins enable row level security;

create policy "Users can read own check-ins"
  on public.check_ins for select
  using (auth.uid() = user_id);

create policy "Users can insert own check-ins"
  on public.check_ins for insert
  with check (auth.uid() = user_id);

-- Index for fast 30-day report queries
create index idx_check_ins_user_date on public.check_ins (user_id, logged_at desc);

-- ════════════════════════════════════════════════════════════
--  3. MEDICATIONS  (the user's inhaler schedule)
-- ════════════════════════════════════════════════════════════
create type med_frequency as enum ('daily', 'twice_daily', 'as_needed');

create table public.medications (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  name          text          not null,      -- e.g. "Symbicort Inhaler"
  type          text          not null,      -- "Maintenance" | "Rescue"
  frequency     med_frequency not null default 'daily',
  scheduled_at  time[],                      -- e.g. {08:00, 20:00}
  tip           text,                        -- Usage tip shown in the app
  active        boolean       not null default true,
  created_at    timestamptz   default now()
);

alter table public.medications enable row level security;

create policy "Users can read own medications"
  on public.medications for select
  using (auth.uid() = user_id);

create policy "Users can manage own medications"
  on public.medications for all
  using (auth.uid() = user_id);

-- ════════════════════════════════════════════════════════════
--  4. MEDICATION LOGS  (each time a dose is marked taken)
-- ════════════════════════════════════════════════════════════
create table public.medication_logs (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  medication_id uuid not null references public.medications(id) on delete cascade,
  scheduled_for timestamptz not null,        -- Which scheduled dose this covers
  taken_at      timestamptz default now(),
  skipped       boolean not null default false
);

alter table public.medication_logs enable row level security;

create policy "Users can read own med logs"
  on public.medication_logs for select
  using (auth.uid() = user_id);

create policy "Users can insert own med logs"
  on public.medication_logs for insert
  with check (auth.uid() = user_id);

-- Index for adherence calculation queries
create index idx_med_logs_user_date on public.medication_logs (user_id, scheduled_for desc);

-- ════════════════════════════════════════════════════════════
--  5. BREATHING EXERCISES  (pacer session log)
-- ════════════════════════════════════════════════════════════
create table public.breathing_sessions (
  id            uuid primary key default uuid_generate_v4(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  cycles        smallint not null default 5, -- Number of cycles completed
  completed     boolean  not null default true,
  duration_sec  smallint,                    -- Total seconds of the session
  started_at    timestamptz default now()
);

alter table public.breathing_sessions enable row level security;

create policy "Users can read own sessions"
  on public.breathing_sessions for select
  using (auth.uid() = user_id);

create policy "Users can insert own sessions"
  on public.breathing_sessions for insert
  with check (auth.uid() = user_id);

-- ════════════════════════════════════════════════════════════
--  6. HELPER VIEW — 30-DAY REPORT
--     Used by the Doctor Report screen. Returns aggregated
--     stats for the last 30 days for the authenticated user.
-- ════════════════════════════════════════════════════════════
create or replace view public.report_30_day as
select
  p.id                                                           as user_id,
  p.full_name,
  p.date_of_birth,
  p.physician,
  -- Check-in counts
  count(ci.id) filter (where ci.logged_at >= now() - interval '30 days')
                                                                 as total_checkins,
  count(ci.id) filter (where ci.status = 'green'  and ci.logged_at >= now() - interval '30 days')
                                                                 as green_count,
  count(ci.id) filter (where ci.status = 'yellow' and ci.logged_at >= now() - interval '30 days')
                                                                 as yellow_count,
  count(ci.id) filter (where ci.status = 'red'    and ci.logged_at >= now() - interval '30 days')
                                                                 as red_count,
  -- Medication adherence %
  round(
    100.0 * count(ml.id) filter (where ml.skipped = false and ml.scheduled_for >= now() - interval '30 days')
    / nullif(count(ml.id) filter (where ml.scheduled_for >= now() - interval '30 days'), 0)
  )                                                              as med_adherence_pct,
  -- Breathing sessions
  count(bs.id) filter (where bs.started_at >= now() - interval '30 days' and bs.completed = true)
                                                                 as breathing_sessions
from public.profiles        p
left join public.check_ins  ci on ci.user_id = p.id
left join public.medication_logs ml on ml.user_id = p.id
left join public.breathing_sessions bs on bs.user_id = p.id
where p.id = auth.uid()
group by p.id, p.full_name, p.date_of_birth, p.physician;

-- ════════════════════════════════════════════════════════════
--  SEED — demo data for Dorothy (replace UUID with real one)
-- ════════════════════════════════════════════════════════════
-- insert into public.medications (user_id, name, type, frequency, scheduled_at, tip) values
--   ('<user-uuid>', 'Symbicort Inhaler', 'Maintenance', 'twice_daily', '{08:00,20:00}',
--    'Shake well. Exhale fully, inhale slowly for 3–5 seconds.'),
--   ('<user-uuid>', 'Ventolin (Rescue)', 'Rescue', 'as_needed', null,
--    'Shake, exhale, inhale slowly, hold breath 10 sec.');
