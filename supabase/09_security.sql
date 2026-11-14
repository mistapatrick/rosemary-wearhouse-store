-- Run ONCE after 08. Database hardening: least privilege, tamper-proof sales, audit trail, stricter staff rules, optional MFA enforcement switch.

-- 1. Least privilege: the public (anonymous) key can touch nothing; sales history cannot be edited or deleted by anyone through the API.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon, authenticated;
alter default privileges in schema public revoke all on tables from anon;
alter default privileges in schema public revoke all on functions from anon;
revoke update,delete,truncate on sales,sale_lines,sale_costs,fx_rates from authenticated;

-- 2. New logins start INACTIVE until the admin ticks Active in the Users tab.
create or replace function on_signup() returns trigger language plpgsql security definer set search_path=public,pg_temp as
 $$begin insert into profiles(id,email,name,active) values(new.id,new.email,split_part(new.email,'@',1),false);return new;end$$;

-- 3. Safer function search paths.
alter function on_signup() set search_path=public,pg_temp;
alter function make_sku() set search_path=public,pg_temp;
alter function my_role() set search_path=public,pg_temp;
alter function cost_batch(uuid) set search_path=public,pg_temp;
alter function ship_batch(uuid) set search_path=public,pg_temp;
alter function confirm_receipt(uuid,integer) set search_path=public,pg_temp;
alter function sell(text,text,jsonb) set search_path=public,pg_temp;
alter function current_fx() set search_path=public,pg_temp;
alter function record_fx(numeric,text) set search_path=public,pg_temp;
alter function set_discount(uuid,numeric,text) set search_path=public,pg_temp;
alter function import_history(jsonb) set search_path=public,pg_temp;

-- 4. Staff cannot award themselves discounts, back-date records or invent dollar prices when adding a local item.
create function guard_staff_item() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if my_role()='staff' then
  new.discount_pct:=0;new.discount_by:=null;new.discount_at:=null;new.discount_note:=null;new.price_usd:=null;new.price_fx:=null;
  new.batch_id:=null;new.import_ref:=null;new.source:='local';new.status:='in_stock';new.qty_received:=new.qty;new.stock:=new.qty;
  new.created_by:=auth.uid();new.received_by:=auth.uid();new.received_at:=now();new.sourced_at:=now();
 end if;return new;end$$;
create trigger t_guard_item before insert on items for each row execute function guard_staff_item();
create function guard_staff_cost() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
begin if my_role()='staff' then new.cost_usd:=0;new.other_usd:=0;new.hold_ngn:=0;new.entry_cur:='NGN';end if;return new;end$$;
create trigger t_guard_cost before insert on item_costs for each row execute function guard_staff_cost();

-- 5. Staff cannot confirm MORE pieces than were shipped (shortages are fine; surpluses need the owner).
create or replace function confirm_receipt(i uuid,got int) returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare f numeric:=current_fx();sent int;
begin
 if my_role() not in('staff','admin') then raise exception 'Only store staff confirm receipt';end if;
 select qty into sent from items where id=i;
 if got<0 or got>coalesce(sent,0) then raise exception 'Quantity received must be between 0 and the quantity sent (%). If more arrived, tell the owner.',sent;end if;
 update items it set status=case when got>0 then 'in_stock' else 'sold_out' end,qty_received=got,stock=got,received_at=now(),received_by=auth.uid(),
  price_ngn=case when it.price_usd is not null then ceil(it.price_usd*f/coalesce((select round_to from batches where id=it.batch_id),500))*coalesce((select round_to from batches where id=it.batch_id),500) else it.price_ngn end,
  price_fx=case when it.price_usd is not null then f end
 where it.id=i and it.status='in_transit';
end$$;

-- 6. Data-quality and size limits (apply to new rows).
alter table items add constraint items_stock_nonneg check(stock>=0) not valid;
alter table items add constraint items_text_len check(char_length(name)<=120 and char_length(coalesce(brand,''))<=60 and char_length(coalesce(size,''))<=20 and char_length(coalesce(condition,''))<=60) not valid;
alter table sales add constraint sales_text_len check(char_length(coalesce(customer,''))<=100 and char_length(coalesce(payment,''))<=40) not valid;
alter table sale_lines add constraint sl_positive check(qty>0 and unit_price>=0) not valid;
alter table item_costs add constraint ic_nonneg check(coalesce(cost_usd,0)>=0 and coalesce(other_usd,0)>=0 and coalesce(other_ng,0)>=0 and coalesce(landed_ngn,0)>=0) not valid;
alter table codes add constraint codes_format check(kind='condition' or code ~ '^[A-Z0-9]{1,6}$') not valid;

-- 7. Audit trail: who changed what and when. Nobody can edit or delete it through the app.
create table audit_log(id bigserial primary key,at timestamptz not null default now(),actor uuid,actor_name text,actor_role text,tbl text,op text,ref text,changes jsonb);
alter table audit_log enable row level security;
create policy al_sel on audit_log for select using((select is_super()));
revoke all on audit_log from authenticated,anon;
grant select on audit_log to authenticated;
create function audit() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare o jsonb:='{}';n jsonb:='{}';ch jsonb:='{}';k text;r text;
begin
 if tg_op<>'DELETE' then n:=to_jsonb(new);end if;
 if tg_op<>'INSERT' then o:=to_jsonb(old);end if;
 if tg_op='UPDATE' then
  for k in select key from jsonb_each(n) loop
   if n->k is distinct from o->k then ch:=ch||jsonb_build_object(k,jsonb_build_array(o->k,n->k));end if;
  end loop;
  if ch='{}'::jsonb then return null;end if;
  if tg_table_name='items' and not (ch ?| array['price_ngn','price_usd','discount_pct','qty','qty_received','status']) then return null;end if;
 end if;
 r:=coalesce(n->>'sku',o->>'sku',n->>'email',o->>'email',n->>'key',o->>'key',n->>'name',o->>'name',n->>'id',o->>'id');
 insert into audit_log(actor,actor_name,actor_role,tbl,op,ref,changes)
 values(auth.uid(),(select coalesce(nullif(name,''),email) from profiles where id=auth.uid()),my_role(),tg_table_name,tg_op,r,ch);
 return null;end$$;
create trigger a_items after insert or update or delete on items for each row execute function audit();
create trigger a_profiles after insert or update or delete on profiles for each row execute function audit();
create trigger a_batches after insert or update or delete on batches for each row execute function audit();
create trigger a_settings after insert or update or delete on settings for each row execute function audit();
create trigger a_codes after insert or update or delete on codes for each row execute function audit();
create function log_event(ev text,note text) returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if my_role() is null then return;end if;
 if (select count(*) from audit_log where actor=auth.uid() and tbl='app' and at>now()-interval '1 minute')>20 then return;end if;
 insert into audit_log(actor,actor_name,actor_role,tbl,op,ref,changes)
 values(auth.uid(),(select coalesce(nullif(name,''),email) from profiles where id=auth.uid()),my_role(),'app',left(ev,30),left(note,200),'{}');
end$$;

-- 8. Optional two-step enforcement switch (stays OFF until 10_require_mfa.sql). Owner/admin powers then need a verified authenticator code.
insert into settings values('require_mfa','off') on conflict do nothing;
create or replace function is_super() returns boolean language sql stable security definer set search_path=public,pg_temp as $$
 select coalesce(my_role() in('admin','owner'),false)
  and (coalesce((select value from settings where key='require_mfa'),'off')<>'on' or coalesce(auth.jwt()->>'aal','')='aal2')$$;
alter policy p_upd on profiles using ((select my_role())='admin' and (select is_super()));

revoke execute on all functions in schema public from public,anon;
grant execute on function cost_batch,ship_batch,confirm_receipt,sell,my_role,is_super,current_fx,record_fx,set_discount,import_history,log_event to authenticated;
