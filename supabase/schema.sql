-- KeyLedger: exécuter ce script dans Supabase > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

-- Chaque nouvel utilisateur Supabase reçoit un profil non administrateur.
-- Tu promouvras ensuite uniquement ton propre compte à la fin du script.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute procedure public.handle_new_user();

create table if not exists public.inventory_keys (
  id uuid primary key default gen_random_uuid(),
  key_value text not null unique,
  license_type text not null default '',
  source_date text not null default '',
  state text not null default 'available' check (state in ('available', 'assigned', 'review')),
  note text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  source_id text unique,
  key_id uuid not null references public.inventory_keys(id) on delete restrict,
  discord_id text not null default '',
  discord_name text not null,
  email text not null default '',
  assigned_at timestamptz not null default now(),
  ends_at timestamptz,
  status text not null default 'active' check (status in ('active', 'paused', 'archived')),
  notes text not null default '',
  archived_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.assignments add column if not exists source_id text;
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'assignments_source_id_key'
  ) then
    alter table public.assignments add constraint assignments_source_id_key unique (source_id);
  end if;
end $$;

create index if not exists inventory_keys_state_idx on public.inventory_keys(state);
create index if not exists assignments_key_id_idx on public.assignments(key_id);
create index if not exists assignments_status_idx on public.assignments(status);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and is_admin = true);
$$;

alter table public.profiles enable row level security;
alter table public.inventory_keys enable row level security;
alter table public.assignments enable row level security;

drop policy if exists "Admins read profiles" on public.profiles;
create policy "Admins read profiles" on public.profiles for select using (public.is_admin());
drop policy if exists "Admins read inventory" on public.inventory_keys;
create policy "Admins read inventory" on public.inventory_keys for select using (public.is_admin());
drop policy if exists "Admins read assignments" on public.assignments;
create policy "Admins read assignments" on public.assignments for select using (public.is_admin());

-- Atomic assignment: two simultaneous Discord requests cannot receive the same available key.
create or replace function public.assign_available_key(
  p_discord_name text,
  p_discord_id text default '',
  p_email text default '',
  p_ends_at timestamptz default null,
  p_notes text default ''
) returns public.assignments
language plpgsql security definer set search_path = public as $$
declare chosen_key public.inventory_keys; created_assignment public.assignments;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select * into chosen_key from public.inventory_keys
    where state = 'available'
    order by created_at
    for update skip locked limit 1;
  if chosen_key.id is null then raise exception 'No available key'; end if;
  update public.inventory_keys set state = 'assigned', updated_at = now() where id = chosen_key.id;
  insert into public.assignments (key_id, discord_name, discord_id, email, ends_at, notes)
    values (chosen_key.id, p_discord_name, p_discord_id, p_email, p_ends_at, p_notes)
    returning * into created_assignment;
  return created_assignment;
end;
$$;

-- Après ta première connexion Supabase, promouvoir ton propre compte une seule fois :
-- update public.profiles set is_admin = true where user_id = 'TON-UUID-AUTH';
