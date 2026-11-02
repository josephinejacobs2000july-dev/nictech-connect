-- Nictech Connect: database setup
-- Paste all of this into Supabase > SQL Editor > New query, then click Run (once).

-- 1. People and their access level
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  full_name text not null default '',
  organization text not null default '',
  phone text not null default '',
  role text not null default 'client' check (role in ('client','worker','office')),
  created_at timestamptz not null default now()
);

create or replace function public.my_role() returns text
language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

-- every new sign-up gets a profile as a client
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, full_name, organization, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'organization', ''),
    coalesce(new.raw_user_meta_data->>'phone', '')
  );
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

alter table public.profiles enable row level security;
create policy "read own profile, office reads all" on public.profiles
  for select using (id = auth.uid() or public.my_role() = 'office');
create policy "edit own profile but not own role" on public.profiles
  for update using (id = auth.uid())
  with check (id = auth.uid() and role = public.my_role());
create policy "office edits anyone" on public.profiles
  for update using (public.my_role() = 'office');

-- 2. Service requests and contracts
create table public.requests (
  id text primary key,
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  org text not null,
  client_type text,
  services text[] not null default '{}',
  plan text,
  priority text,
  site text,
  preferred_date date,
  equipment text default '',
  details text default '',
  contact text,
  phone text,
  email text default '',
  po text default '',
  status text not null default 'new'
    check (status in ('new','approved','scheduled','progress','done','cancelled')),
  tech text not null default '',
  scheduled_date date,
  office_note text not null default '',
  rating int not null default 0 check (rating between 0 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- clients may only change their rating; the office may change everything
create or replace function public.guard_request_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare r int := new.rating;
begin
  if public.my_role() is distinct from 'office' then
    new := old;
    new.rating := r;
  else
    new.updated_at := now();
  end if;
  return new;
end $$;

create trigger guard_request_update
  before update on public.requests
  for each row execute function public.guard_request_update();

alter table public.requests enable row level security;
create policy "clients create their own requests" on public.requests
  for insert with check (owner = auth.uid() and status = 'new');
create policy "clients see their own, staff see all" on public.requests
  for select using (owner = auth.uid() or public.my_role() in ('office','worker'));
create policy "office updates requests" on public.requests
  for update using (public.my_role() = 'office');
create policy "clients rate their own" on public.requests
  for update using (owner = auth.uid()) with check (owner = auth.uid());
create policy "office deletes requests" on public.requests
  for delete using (public.my_role() = 'office');

-- 3. Technicians' daily work log
create table public.work_updates (
  id bigint generated always as identity primary key,
  author uuid not null default auth.uid() references auth.users on delete cascade,
  tech text not null,
  service text,
  status text not null default 'track' check (status in ('track','done','parts','delayed')),
  site text not null,
  ref text not null default '',
  hours numeric not null default 0,
  work text not null,
  materials text not null default '',
  next_step text not null default '',
  created_at timestamptz not null default now()
);

alter table public.work_updates enable row level security;
create policy "staff post updates" on public.work_updates
  for insert with check (author = auth.uid() and public.my_role() in ('worker','office'));
create policy "staff read all updates" on public.work_updates
  for select using (public.my_role() in ('worker','office'));
create policy "clients read updates on their jobs" on public.work_updates
  for select using (
    ref <> '' and exists (
      select 1 from public.requests r where r.id = work_updates.ref and r.owner = auth.uid()
    )
  );
create policy "author or office edits updates" on public.work_updates
  for update using (author = auth.uid() or public.my_role() = 'office');
create policy "office deletes updates" on public.work_updates
  for delete using (public.my_role() = 'office');

-- 4. Live updates in the app
alter publication supabase_realtime add table public.requests, public.work_updates;
