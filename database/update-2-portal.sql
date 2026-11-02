-- Nictech Connect: update 2 (client portal: invoices and receipts)
-- Run once in Supabase > SQL Editor, after security-update-1.sql.

-- Invoice amount, currency and payment status on each job
alter table public.requests
  add column invoice_amount numeric(12,2) check (invoice_amount >= 0),
  add column invoice_currency text not null default 'USD' check (invoice_currency in ('USD','LRD')),
  add column paid boolean not null default false;

-- Clients still can't fill in office fields (now including the invoice) when they book
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
