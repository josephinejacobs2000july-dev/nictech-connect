-- Nictech Connect: ALL updates in one (security + invoices + photos)
-- Paste everything into Supabase > SQL Editor and click Run.
-- Safe to run more than once.

-- ===== 1. Security: size limits =====
alter table public.profiles drop constraint if exists profiles_size;
alter table public.profiles add constraint profiles_size check (
  length(full_name) <= 150 and length(organization) <= 200 and length(phone) <= 40);

alter table public.requests drop constraint if exists requests_size;
alter table public.requests add constraint requests_size check (
  length(id) <= 20 and length(org) <= 200 and length(coalesce(client_type,'')) <= 50
  and length(coalesce(plan,'')) <= 60 and length(coalesce(priority,'')) <= 20
  and length(coalesce(site,'')) <= 300 and length(coalesce(equipment,'')) <= 1000
  and length(coalesce(details,'')) <= 4000 and length(coalesce(contact,'')) <= 150
  and length(coalesce(phone,'')) <= 40 and length(coalesce(email,'')) <= 200
  and length(coalesce(po,'')) <= 100 and length(tech) <= 150 and length(office_note) <= 1000
  and cardinality(services) between 1 and 11);

alter table public.work_updates drop constraint if exists work_updates_size;
alter table public.work_updates add constraint work_updates_size check (
  length(tech) <= 150 and length(coalesce(service,'')) <= 30 and length(site) <= 300
  and length(ref) <= 20 and length(work) <= 4000 and length(materials) <= 1000
  and length(next_step) <= 1000 and hours between 0 and 24);

-- ===== 2. Invoices and payment status =====
alter table public.requests add column if not exists invoice_amount numeric(12,2) check (invoice_amount >= 0);
alter table public.requests add column if not exists invoice_currency text not null default 'USD' check (invoice_currency in ('USD','LRD'));
alter table public.requests add column if not exists paid boolean not null default false;

-- ===== 3. Photos on work posts =====
alter table public.work_updates add column if not exists photos text[] not null default '{}' check (cardinality(photos) <= 6);

-- ===== 4. New bookings: clients can't fill in office fields; max 10 a day =====
create or replace function public.guard_request_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.my_role() is distinct from 'office' then
    if (select count(*) from public.requests
        where owner = auth.uid() and created_at > now() - interval '1 day') >= 10 then
      raise exception 'Too many requests today';
    end if;
    new.owner := auth.uid();
    new.status := 'new';
    new.tech := '';
    new.scheduled_date := null;
    new.office_note := '';
    new.rating := 0;
    new.invoice_amount := null;
    new.invoice_currency := 'USD';
    new.paid := false;
  end if;
  new.created_at := now();
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists guard_request_insert on public.requests;
create trigger guard_request_insert
  before insert on public.requests
  for each row execute function public.guard_request_insert();

-- ===== 5. Clients can only rate a job once it's completed =====
create or replace function public.guard_request_update() returns trigger
language plpgsql security definer set search_path = public as $$
declare r int := new.rating;
begin
  if public.my_role() is distinct from 'office' then
    new := old;
    if old.status = 'done' then new.rating := r; end if;
  else
    new.updated_at := now();
  end if;
  return new;
end $$;

-- ===== 6. Work posts: real name, real time, own photos only =====
create or replace function public.guard_work_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.author := auth.uid();
  new.tech := coalesce(nullif((select full_name from public.profiles where id = auth.uid()), ''), new.tech);
  new.ref := upper(trim(new.ref));
  new.created_at := now();
  if exists (select 1 from unnest(new.photos) p where p not like auth.uid()::text || '/%') then
    raise exception 'Photos must be your own uploads';
  end if;
  return new;
end $$;

drop trigger if exists guard_work_update on public.work_updates;
create trigger guard_work_update
  before insert on public.work_updates
  for each row execute function public.guard_work_update();

drop policy if exists "author or office edits updates" on public.work_updates;
drop policy if exists "office edits updates" on public.work_updates;
create policy "office edits updates" on public.work_updates
  for update using (public.my_role() = 'office');

-- ===== 7. Private photo storage =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('work-photos', 'work-photos', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "staff upload work photos" on storage.objects;
create policy "staff upload work photos" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'work-photos'
    and public.my_role() in ('worker','office')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "view work photos" on storage.objects;
create policy "view work photos" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'work-photos'
    and (
      public.my_role() in ('worker','office')
      or exists (
        select 1 from public.work_updates w
        join public.requests r on r.id = w.ref
        where name = any (w.photos) and r.owner = auth.uid()
      )
    )
  );

drop policy if exists "delete work photos" on storage.objects;
create policy "delete work photos" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'work-photos'
    and (public.my_role() = 'office' or (storage.foldername(name))[1] = auth.uid()::text)
  );
