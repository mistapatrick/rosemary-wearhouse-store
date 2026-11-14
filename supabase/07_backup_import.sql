-- Run ONCE after 06. Adds: safe historical import (idempotent), backup reminder settings.
alter table items add column import_ref text;
alter table sales add column import_ref text;
create unique index items_import_ref on items(import_ref) where import_ref is not null;
create unique index sales_import_ref on sales(import_ref) where import_ref is not null;
create sequence import_seq;
insert into settings values('backup_days','14') on conflict do nothing;

-- SKU month for items without a batch (local purchases) now follows their purchase date, so old records get the right month.
create or replace function make_sku() returns trigger language plpgsql security definer set search_path=public as $$
declare c text;g text;k text;m text;p text;n int;
begin
 select code into c from codes where kind='category' and name=new.category;
 select code into g from codes where kind='gender' and name=new.gender;
 select code into k from codes where kind='colour' and name=new.colour;
 if c is null or g is null or k is null then raise exception 'Unknown category/gender/colour code'; end if;
 select to_char(coalesce((select ship_date from batches where id=new.batch_id),new.sourced_at::date),'MMYY') into m;
 p:=c||'-'||g||'-'||k||'-'||m;
 perform pg_advisory_xact_lock(hashtext(p));
 select coalesce(max(serial),0)+1 into n from items where sku like p||'-%';
 new.serial:=n;new.sku:=p||'-'||lpad(n::text,3,'0');return new;end$$;

-- Historical import. Owner/admin only. Re-running the same file is safe: rows already imported are skipped.
create function import_history(payload jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare x jsonb;l jsonb;bid uuid;iid uuid;sid uuid;lid uuid;it items;t numeric;q int;pr numeric;
 ni int:=0;si int:=0;ns int:=0;ss int:=0;
begin
 if not is_super() then raise exception 'forbidden';end if;
 for x in select * from jsonb_array_elements(coalesce(payload->'codes','[]')) loop
  insert into codes(kind,name,code) values(x->>'kind',x->>'name',x->>'code') on conflict do nothing;
 end loop;
 for x in select * from jsonb_array_elements(coalesce(payload->'items','[]')) loop
  if exists(select 1 from items where import_ref=x->>'ref') then si:=si+1;continue;end if;
  bid:=null;
  if x->>'batch_name' is not null then
   select id into bid from batches where name=x->>'batch_name' limit 1;
   if bid is null then
    insert into batches(name,ship_date,status,fx,ship_cost_ngn)
     values(x->>'batch_name',(x->>'ship_date')::date,'shipped',coalesce((x->>'fx')::numeric,current_fx()),0) returning id into bid;
   end if;
  end if;
  insert into items(batch_id,name,category,gender,colour,brand,size,condition,qty,qty_received,stock,status,source,price_ngn,price_usd,sourced_at,received_at,import_ref)
  values(bid,x->>'name',x->>'category',x->>'gender',x->>'colour',x->>'brand',x->>'size',x->>'condition',(x->>'qty')::int,(x->>'qty')::int,(x->>'stock')::int,x->>'status',x->>'source',
   (x->>'price_ngn')::numeric,(x->>'price_usd')::numeric,(x->>'sourced_at')::timestamptz,(x->>'received_at')::timestamptz,x->>'ref') returning id into iid;
  insert into item_costs(item_id,cost_usd,other_usd,other_ng,landed_ngn,entry_cur)
  values(iid,coalesce((x->>'cost_usd')::numeric,0),coalesce((x->>'other_usd')::numeric,0),coalesce((x->>'other_ng')::numeric,0),(x->>'landed_ngn')::numeric,'IMPORT');
  ni:=ni+1;
 end loop;
 for x in select * from jsonb_array_elements(coalesce(payload->'sales','[]')) loop
  if exists(select 1 from sales where import_ref=x->>'key') then ss:=ss+1;continue;end if;
  insert into sales(receipt,customer,payment,cashier,fx,sold_at,import_ref)
  values(case when x->>'receipt' is not null then 'OLD-'||(x->>'receipt') else 'IMP-'||lpad(nextval('import_seq')::text,6,'0') end,
   x->>'customer',x->>'payment',coalesce(x->>'cashier','Imported'),coalesce((x->>'fx')::numeric,current_fx()),(x->>'sold_at')::timestamptz,x->>'key') returning id into sid;
  t:=0;
  for l in select * from jsonb_array_elements(x->'lines') loop
   select * into it from items where import_ref=l->>'ref';
   if not found then raise exception 'Unknown item ref %',l->>'ref';end if;
   q:=(l->>'qty')::int;pr:=(l->>'price')::numeric;
   insert into sale_lines(sale_id,item_id,sku,name,qty,unit_price,list_price,disc_pct) values(sid,it.id,it.sku,it.name,q,pr,it.price_ngn,0) returning id into lid;
   insert into sale_costs select lid,landed_ngn from item_costs where item_id=it.id;
   t:=t+q*pr;
  end loop;
  update sales set total=t where id=sid;ns:=ns+1;
 end loop;
 return jsonb_build_object('items',ni,'items_skipped',si,'sales',ns,'sales_skipped',ss);
end$$;

revoke execute on all functions in schema public from public,anon;
grant execute on function cost_batch,ship_batch,confirm_receipt,sell,my_role,is_super,current_fx,record_fx,set_discount,import_history to authenticated;
