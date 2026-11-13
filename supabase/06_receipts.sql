-- Run ONCE after 05. Stores the cashier's name on every sale so receipts can be reprinted exactly.
alter table sales add column cashier text;

create or replace function sell(cust text,pay text,lines jsonb) returns text language plpgsql security definer set search_path=public as $$
declare s uuid;rc text;l jsonb;it items;lid uuid;t numeric:=0;eff numeric;pr numeric;q int;rl text:=my_role();
begin
 if rl is null then raise exception 'forbidden';end if;
 rc:='RWH-'||lpad(nextval('receipt_seq')::text,4,'0');
 insert into sales(receipt,customer,payment,sold_by,fx,cashier)
  values(rc,nullif(cust,''),pay,auth.uid(),current_fx(),(select coalesce(nullif(name,''),email) from profiles where id=auth.uid())) returning id into s;
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
