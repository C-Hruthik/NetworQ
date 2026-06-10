-- Run this in the Supabase SQL editor (Dashboard → SQL Editor → New query)
-- After running, go to Authentication → Providers and optionally disable email confirmation for dev.

-- ── PROFILES ─────────────────────────────────────────────────────────────────
create table if not exists profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text,
  company     text,
  role        text,
  sector      text,
  phone       text,
  linkedin    text,
  bio         text,
  created_at  timestamptz default now()
);

alter table profiles enable row level security;

create policy "Users can read own profile"
  on profiles for select using (auth.uid() = id);

create policy "Users can insert own profile"
  on profiles for insert with check (auth.uid() = id);

create policy "Users can update own profile"
  on profiles for update using (auth.uid() = id);

-- ── CONTACTS ─────────────────────────────────────────────────────────────────
create table if not exists contacts (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid references auth.users(id) on delete cascade not null,
  name          text not null,
  title         text,
  company       text,
  email         text,
  phone         text,
  website       text,
  linkedin      text,
  event         text,
  reference     text,
  reminder      text,
  reminder_date date,
  image         text,
  added_at      timestamptz default now(),
  reminder_done boolean default false,
  email_sent    boolean default false,
  meet_link     text,
  meet_date     text
);

alter table contacts enable row level security;

create policy "Users can read own contacts"
  on contacts for select using (auth.uid() = user_id);

create policy "Users can insert own contacts"
  on contacts for insert with check (auth.uid() = user_id);

create policy "Users can update own contacts"
  on contacts for update using (auth.uid() = user_id);

create policy "Users can delete own contacts"
  on contacts for delete using (auth.uid() = user_id);

-- ── BUSINESS CARD SCANS ───────────────────────────────────────────────────────
create table if not exists business_card_scans (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid references auth.users(id) on delete cascade not null,
  contact_id     uuid references contacts(id) on delete set null,
  image_data     text,
  extracted_data jsonb,
  created_at     timestamptz default now()
);

alter table business_card_scans enable row level security;

create policy "Users can read own scans"
  on business_card_scans for select using (auth.uid() = user_id);

create policy "Users can insert own scans"
  on business_card_scans for insert with check (auth.uid() = user_id);

-- ── FOLLOW-UP EMAILS ─────────────────────────────────────────────────────────
create table if not exists follow_up_emails (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  contact_id  uuid references contacts(id) on delete cascade not null,
  draft       text,
  sent        boolean default false,
  sent_at     timestamptz,
  created_at  timestamptz default now()
);

alter table follow_up_emails enable row level security;

create policy "Users can read own emails"
  on follow_up_emails for select using (auth.uid() = user_id);

create policy "Users can insert own emails"
  on follow_up_emails for insert with check (auth.uid() = user_id);

-- ── MEETINGS ─────────────────────────────────────────────────────────────────
create table if not exists meetings (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  contact_id  uuid references contacts(id) on delete cascade not null,
  meet_link   text,
  meet_date   text,
  meet_time   text,
  notes       text,
  created_at  timestamptz default now()
);

alter table meetings enable row level security;

create policy "Users can read own meetings"
  on meetings for select using (auth.uid() = user_id);

create policy "Users can insert own meetings"
  on meetings for insert with check (auth.uid() = user_id);

-- ── AI USAGE (daily limits for email generation / card scans) ────────────────
create table if not exists ai_usage (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  action_type text not null,
  date        date not null default current_date,
  count       integer not null default 0,
  unique (user_id, action_type, date)
);

alter table ai_usage enable row level security;

create policy "Users can read own ai usage"
  on ai_usage for select using (auth.uid() = user_id);

-- Atomically checks the daily limit and increments the counter if under it.
-- Returns true if the action is allowed, false if the daily limit is reached.
create or replace function increment_ai_usage(p_user_id uuid, p_action_type text, p_limit integer)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  current_count integer;
begin
  insert into ai_usage (user_id, action_type, date, count)
  values (p_user_id, p_action_type, current_date, 0)
  on conflict (user_id, action_type, date) do nothing;

  select count into current_count from ai_usage
  where user_id = p_user_id and action_type = p_action_type and date = current_date
  for update;

  if current_count >= p_limit then
    return false;
  end if;

  update ai_usage set count = count + 1
  where user_id = p_user_id and action_type = p_action_type and date = current_date;

  return true;
end;
$$;

grant execute on function increment_ai_usage(uuid, text, integer) to authenticated;
