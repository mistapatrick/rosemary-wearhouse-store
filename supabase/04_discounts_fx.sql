-- Run ONCE in SQL Editor (after 01, 02, 03). Adds: owner-authorised discounts, exchange-rate tracking, USD/NGN support.
alter table items add column discount_pct numeric not null default 0 check(discount_pct>=0 and discount_pct<=90),
  add column discount_by uuid, add column discount_at timestamptz, add column discount_note text;
alter table sales add column fx numeric;
alter table sale_lines add column list_price numeric, add column disc_pct numeric default 0, add column auth_by uuid;
alter table item_costs add column entry_cur text, add column entry_amt numeric;

create table fx_rates(day date primary key default current_date,rate numeric not null check(rate>0),source text,fetched_at timestamptz default now());
create table settings(key text primary key,value text);
insert into settings values('fx_mode','auto'),('fx_manual','1500'),('fx_buffer','0') on conflict do nothing;
alter table fx_rates enable row level security;alter table settings enable row level security;
create policy fx_sel on fx_rates for select using(my_role() is not null);
create policy st_sel on settings for select using(my_role() is not null);
create policy st_all on settings for all using(is_super()) with check(is_super());

-- the rate the whole app uses (manual rate, or latest automatic rate plus optional buffer %)
create function current_fx() returns numeric language sql stable security definer set search_path=public as $$
 select case when (select value from settings where key='fx_mode')='manual' then (select value::numeric from settings where key='fx_manual')
  else coalesce((select rate from fx_rates order by day desc limit 1),(select value::numeric from settings where key='fx_manual'))
   *(1+coalesce((select value::numeric from settings where key='fx_buffer'),0)/100) end $$;

create function record_fx(r numeric,src text) returns void language plpgsql security definer set search_path=public as $$
begin
 if not is_super() then raise exception 'forbidden';end if;
 if r<100 or r>20000 then raise exception 'Rate looks wrong: %',r;end if;
 insert into fx_rates(day,rate,source,fetched_at) values(current_date,r,src,now())
 on conflict(day) do update set rate=excluded.rate,source=excluded.source,fetched_at=now();
end$$;

create function set_discount(i uuid,pct numeric,note text) returns void language plpgsql security definer set search_path=public as $$
begin
 if not is_super() then raise exception 'forbidden';end if;
 if pct<0 or pct>90 then raise exception 'Discount must be between 0 and 90 percent';end if;
 update items set discount_pct=pct,discount_by=case when pct>0 then auth.uid() end,discount_at=case when pct>0 then now() end,
   discount_note=case when pct>0 then note end where id=i and status='in_stock';
 if not found then raise exception 'Only in-stock items can be discounted';end if;
end$$;

-- POS: staff can only sell at or above the authorised price; every sale records list price, discount and the rate used
create or replace function sell(cust text,pay text,lines jsonb) returns text language plpgsql security definer set search_path=public as $$
declare s uuid;rc text;l jsonb;it items;lid uuid;t numeric:=0;eff numeric;pr numeric;q int;rl text:=my_role();
begin
 if rl is null then raise exception 'forbidden';end if;
 rc:='RWH-'||lpad(nextval('receipt_seq')::text,4,'0');
 insert into sales(receipt,customer,payment,sold_by,fx) values(rc,nullif(cust,''),pay,auth.uid(),current_fx()) returning id into s;
 for l in select * from jsonb_array_elements(lines) loop
  q:=(l->>'qty')::int;pr:=(l->>'price')::numeric;
  select * into it from items where id=(l->>'item_id')::uuid and status='in_stock' for update;
  if not found or q<1 or it.stock<q or pr<0 then raise exception 'Not enough stock or bad price for %',coalesce(it.sku,'item');end if;
  eff:=case when it.price_ngn is null then null else round(it.price_ngn*(1-it.discount_pct/100)) end;
  if rl='staff' and (eff is null or pr<eff) then raise exception 'Price is below the authorised price for %',it.sku;end if;
  update items set stock=stock-q,status=case when stock-q=0 then 'sold_out' else status end where id=it.id;
  insert into sale_lines(sale_id,item_id,sku,name,qty,unit_price,list_price,disc_pct,auth_by)
   values(s,it.id,it.sku,it.name,q,pr,it.price_ngn,it.discount_pct,it.discount_by) returning id into lid;
  insert into sale_costs select lid,landed_ngn from item_costs where item_id=it.id;
  t:=t+q*pr;
 end loop;
 update sales set total=t where id=s;return rc;end$$;

grant select,insert,update,delete on fx_rates,settings to authenticated;
revoke execute on all functions in schema public from public,anon;
grant execute on function cost_batch,ship_batch,confirm_receipt,sell,my_role,is_super,current_fx,record_fx,set_discount to authenticated;
