-- Nictech Connect: security update 1
-- Run once in Supabase > SQL Editor, after supabase-setup.sql.

-- 1. Size limits, so nobody can fill the free database with huge entries
alter table public.profiles add constraint profiles_size check (
  length(full_name) <= 150 and length(organization) <= 200 and length(phone) <= 40);

alter table public.requests add constraint requests_size check (
  length(id) <= 20 and length(org) <= 200 and length(coalesce(client_type,'')) <= 50
  and length(coalesce(plan,'')) <= 60 and length(coalesce(priority,'')) <= 20
  and length(coalesce(site,'')) <= 300 and length(coalesce(equipment,'')) <= 1000
  and length(coalesce(details,'')) <= 4000 and length(coalesce(contact,'')) <= 150
  and length(coalesce(phone,'')) <= 40 and length(coalesce(email,'')) <= 200
  and length(coalesce(po,'')) <= 100 and length(tech) <= 150 and length(office_note) <= 1000
  and cardinality(services) between 1 and 11);

alter table public.work_updates add constraint work_updates_size check (
  length(tech) <= 150 and length(coalesce(service,'')) <= 30 and length(site) <= 300
  and length(ref) <= 20 and length(work) <= 4000 and length(materials) <= 1000
  and length(next_step) <= 1000 and hours between 0 and 24);

-- 2. New bookings: clients can't pre-fill office fields (status, technician,
--    office note, visit date, rating) and can send at most 10 a day
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
  end if;
  new.created_at := now();
  new.updated_at := now();
  return new;
end $$;

create trigger guard_request_insert
  before insert on public.requests
  for each row execute function public.guard_request_insert();

-- 3. Clients can rate a job only once it is completed
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

-- 4. Work posts: the name shown is always the poster's own account name,
--    the time is the real time, and only the office can edit a post later
create or replace function public.guard_work_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.author := auth.uid();
  new.tech := coalesce(nullif((select full_name from public.profiles where id = auth.uid()), ''), new.tech);
  new.ref := upper(trim(new.ref));
  new.created_at := now();
  return new;
end $$;

create trigger guard_work_update
  before insert on public.work_updates
  for each row execute function public.guard_work_update();

drop policy "author or office edits updates" on public.work_updates;
create policy "office edits updates" on public.work_updates
  for update using (public.my_role() = 'office');
