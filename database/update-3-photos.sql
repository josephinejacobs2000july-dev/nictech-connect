-- Nictech Connect: update 3 (technicians' work photos)
-- Run once in Supabase > SQL Editor, after update-2-portal.sql.

-- 1. Each work post can carry up to 6 photos (stored as file paths)
alter table public.work_updates
  add column photos text[] not null default '{}' check (cardinality(photos) <= 6);

-- 2. A private photo store: only images, at most 5 MB each
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('work-photos', 'work-photos', false, 5242880, array['image/jpeg','image/png','image/webp']);

-- 3. Who can do what with photos
--    Technicians and office upload into their own folder
create policy "staff upload work photos" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'work-photos'
    and public.my_role() in ('worker','office')
    and (storage.foldername(name))[1] = auth.uid()::text
  );

--    Staff see every photo; a client sees only photos posted on their own jobs
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

--    Only the office deletes photos (and a technician can remove an upload that failed to post)
create policy "delete work photos" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'work-photos'
    and (public.my_role() = 'office' or (storage.foldername(name))[1] = auth.uid()::text)
  );

-- 4. A post can only point at photos in the poster's own folder
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
