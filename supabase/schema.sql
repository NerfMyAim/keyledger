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

-- Mapping explicite : chaque variante SellAuth ne peut délivrer que le type de clé prévu.
create table if not exists public.sellauth_variant_mappings (
  variant_id text primary key,
  variant_name text not null,
  license_type text not null,
  duration_days integer check (duration_days is null or duration_days > 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.sellauth_deliveries (
  id uuid primary key default gen_random_uuid(),
  unique_id text not null,
  item_id text not null,
  invoice_id text not null default '',
  variant_id text not null,
  customer_email text not null,
  key_id uuid not null references public.inventory_keys(id) on delete restrict,
  assignment_id uuid not null references public.assignments(id) on delete restrict,
  delivered_at timestamptz not null default now(),
  unique (unique_id, item_id)
);

create table if not exists public.inventory_events (
  id uuid primary key default gen_random_uuid(),
  key_id uuid not null references public.inventory_keys(id) on delete restrict,
  event_type text not null check (event_type in ('manual_add', 'manual_release')),
  note text not null default '',
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where user_id = auth.uid() and is_admin = true);
$$;

alter table public.profiles enable row level security;
alter table public.inventory_keys enable row level security;
alter table public.assignments enable row level security;
alter table public.inventory_events enable row level security;

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
  p_assigned_at timestamptz default null,
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
  insert into public.assignments (key_id, discord_name, discord_id, email, assigned_at, ends_at, notes)
    values (chosen_key.id, p_discord_name, p_discord_id, p_email, coalesce(p_assigned_at, now()), p_ends_at, p_notes)
    returning * into created_assignment;
  return created_assignment;
end;
$$;

-- Version utilisée par KeyLedger : attribue précisément la clé choisie dans l'inventaire.
create or replace function public.assign_inventory_key(
  p_key_id uuid,
  p_discord_name text,
  p_discord_id text default '',
  p_email text default '',
  p_assigned_at timestamptz default null,
  p_ends_at timestamptz default null,
  p_notes text default ''
) returns public.assignments
language plpgsql security definer set search_path = public as $$
declare chosen_key public.inventory_keys; created_assignment public.assignments;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select * into chosen_key from public.inventory_keys where id = p_key_id for update;
  if chosen_key.id is null then raise exception 'Key not found'; end if;
  if chosen_key.state <> 'available' then raise exception 'Key is no longer available'; end if;
  update public.inventory_keys set state = 'assigned', updated_at = now() where id = chosen_key.id;
  insert into public.assignments (key_id, discord_name, discord_id, email, assigned_at, ends_at, notes)
    values (chosen_key.id, p_discord_name, p_discord_id, p_email, coalesce(p_assigned_at, now()), p_ends_at, p_notes)
    returning * into created_assignment;
  return created_assignment;
end;
$$;

create or replace function public.finish_assignment(p_assignment_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare assignment_key_id uuid;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select key_id into assignment_key_id from public.assignments where id = p_assignment_id and status <> 'archived' for update;
  if assignment_key_id is null then raise exception 'Assignment not found'; end if;
  update public.assignments set status = 'archived', archived_at = now() where id = p_assignment_id;
  update public.inventory_keys set state = 'review', updated_at = now() where id = assignment_key_id;
end;
$$;

create or replace function public.update_key_note(p_key_id uuid, p_note text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  update public.inventory_keys set note = p_note, updated_at = now() where id = p_key_id;
end;
$$;

create or replace function public.release_inventory_key(p_key_id uuid, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
declare current_state text;
begin
  if not public.is_admin() then raise exception 'Not authorized'; end if;
  select state into current_state from public.inventory_keys where id = p_key_id for update;
  if current_state is null then raise exception 'Key not found'; end if;
  if current_state <> 'review' then raise exception 'Only reviewed keys can be made available'; end if;
  update public.inventory_keys set state = 'available', updated_at = now() where id = p_key_id;
  insert into public.inventory_events (key_id, event_type, note) values (p_key_id, 'manual_release', p_note);
end;
$$;

-- Appelée uniquement par la fonction Netlify SellAuth avec la clé serveur.
-- Si SellAuth réessaie le même item, la même clé est retournée sans nouvelle attribution.
create or replace function public.deliver_sellauth_item(
  p_unique_id text,
  p_item_id text,
  p_invoice_id text,
  p_variant_id text,
  p_customer_email text
) returns text
language plpgsql security definer set search_path = public as $$
declare existing_key text; selected_key public.inventory_keys; mapping public.sellauth_variant_mappings; created_assignment public.assignments;
begin
  select inventory_keys.key_value into existing_key
  from public.sellauth_deliveries
  join public.inventory_keys on inventory_keys.id = sellauth_deliveries.key_id
  where unique_id = p_unique_id and item_id = p_item_id;
  if existing_key is not null then return existing_key; end if;

  select * into mapping from public.sellauth_variant_mappings where variant_id = p_variant_id and active = true;
  if mapping.variant_id is null then raise exception 'Product variant is not configured'; end if;

  select * into selected_key from public.inventory_keys
  where state = 'available' and license_type = mapping.license_type
  order by created_at for update skip locked limit 1;
  if selected_key.id is null then raise exception 'No compatible key available'; end if;

  update public.inventory_keys set state = 'assigned', updated_at = now() where id = selected_key.id;
  insert into public.assignments (key_id, discord_name, email, assigned_at, ends_at, status, notes)
  values (
    selected_key.id,
    coalesce(p_customer_email, 'SellAuth customer'),
    coalesce(p_customer_email, ''),
    now(),
    case when mapping.duration_days is null then null else now() + make_interval(days => mapping.duration_days) end,
    'active',
    'SellAuth Dynamic Delivery · invoice ' || p_invoice_id
  ) returning * into created_assignment;

  insert into public.sellauth_deliveries (unique_id, item_id, invoice_id, variant_id, customer_email, key_id, assignment_id)
  values (p_unique_id, p_item_id, p_invoice_id, p_variant_id, coalesce(p_customer_email, ''), selected_key.id, created_assignment.id);
  return selected_key.key_value;
end;
$$;

revoke all on function public.deliver_sellauth_item(text, text, text, text, text) from public;
grant execute on function public.deliver_sellauth_item(text, text, text, text, text) to service_role;

-- Variantes SellAuth actuelles. Ce bloc est relançable sans erreur de doublon.
-- Le produit mensuel délivre ici une clé « 1 Mois Pro » ; remplace par « 1 Mois Lite »
-- uniquement si c'est réellement le produit vendu.
insert into public.sellauth_variant_mappings (variant_id, variant_name, license_type, duration_days, active) values
  ('95060', '1 Semaine', '1 Semaine', 7, true),
  ('95061', '1 Mois', '1 Mois', 30, true),
  ('466215', '1 Ans', '1 An Pro', 365, true),
  ('436705', 'Lifetime', 'Lifetime', null, true)
on conflict (variant_id) do update set
  variant_name = excluded.variant_name,
  license_type = excluded.license_type,
  duration_days = excluded.duration_days,
  active = excluded.active;

-- Après ta première connexion Supabase, promouvoir ton propre compte une seule fois :
-- update public.profiles set is_admin = true where user_id = 'TON-UUID-AUTH';
