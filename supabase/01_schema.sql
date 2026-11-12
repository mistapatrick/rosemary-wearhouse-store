-- Rosemary's Wear House — run this whole file once in Supabase → SQL Editor.
create table profiles(id uuid primary key references auth.users on delete cascade,email text,name text,
  role text not null default 'staff' check(role in('admin','owner','staff')),active boolean not null default true);
create table codes(kind text,name text,code text,primary key(kind,name));
create table batches(id uuid primary key default gen_random_uuid(),name text not null,
  ship_date date not null default current_date,status text not null default 'open' check(status in('open','shipped')),
  ship_cost_ngn numeric not null default 0,fx numeric not null default 1500,split text not null default 'equal',
  mode text not null default 'markup',pct numeric not null default 100,hold_pct numeric not null default 2,
  round_to numeric not null default 500,created_by uuid default auth.uid());
create table items(id uuid primary key default gen_random_uuid(),sku text unique,serial int,
  batch_id uuid references batches,name text not null,category text not null,gender text not null,colour text not null,
  brand text,size text,condition text,qty int not null check(qty>0),qty_received int,stock int not null default 0,
  status text not null default 'sourced' check(status in('sourced','in_transit','in_stock','sold_out')),
  source text not null default 'us' check(source in('us','local')),price_ngn numeric,
  sourced_at timestamptz not null default now(),received_at timestamptz,received_by uuid,created_by uuid default auth.uid());
create table item_costs(item_id uuid primary key references items on delete cascade,cost_usd numeric not null default 0,
  other_usd numeric not null default 0,other_ng numeric not null default 0,hold_ngn numeric default 0,landed_ngn numeric);
create sequence receipt_seq;
create table sales(id uuid primary key default gen_random_uuid(),receipt text unique,customer text,payment text,
  total numeric,sold_by uuid,sold_at timestamptz default now());
create table sale_lines(id uuid primary key default gen_random_uuid(),sale_id uuid references sales,item_id uuid references items,
  sku text,name text,qty int,unit_price numeric);
create table sale_costs(line_id uuid primary key references sale_lines on delete cascade,unit_cost numeric);

-- helpers
create function my_role() returns text language sql security definer stable set search_path=public as
 $$select role from profiles where id=auth.uid() and active$$;
create function is_super() returns boolean language sql stable as $$select coalesce(my_role() in('admin','owner'),false)$$;

-- new auth users become staff; promote with 03_promote.sql
create function on_signup() returns trigger language plpgsql security definer set search_path=public as
 $$begin insert into profiles(id,email,name) values(new.id,new.email,split_part(new.email,'@',1));return new;end$$;
create trigger t_signup after insert on auth.users for each row execute function on_signup();

-- SKU: CATEGORY-GENDER-COLOUR-MMYY(shipped)-SERIAL
create function make_sku() returns trigger language plpgsql security definer set search_path=public as $$
declare c text;g text;k text;m text;p text;n int;
begin
 select code into c from codes where kind='category' and name=new.category;
 select code into g from codes where kind='gender' and name=new.gender;
 select code into k from codes where kind='colour' and name=new.colour;
 if c is null or g is null or k is null then raise exception 'Unknown category/gender/colour code'; end if;
 select to_char(coalesce((select ship_date from batches where id=new.batch_id),current_date),'MMYY') into m;
 p:=c||'-'||g||'-'||k||'-'||m;
 perform pg_advisory_xact_lock(hashtext(p));
 select coalesce(max(serial),0)+1 into n from items where sku like p||'-%';
 new.serial:=n;new.sku:=p||'-'||lpad(n::text,3,'0');return new;end$$;
create trigger t_sku before insert on items for each row execute function make_sku();

-- costing (single source of truth for preview, shipping and pricing)
create function cost_batch(b uuid) returns table(item_id uuid,sku text,name text,qty int,sourcing numeric,share numeric,hold numeric,landed numeric,suggested numeric)
language plpgsql stable security definer set search_path=public as $$
declare bt batches;units numeric;tot numeric;
begin
 if not is_super() then raise exception 'forbidden';end if;
 select * into bt from batches where id=b;
 select sum(i.qty),sum(i.qty*(c.cost_usd+c.other_usd)*bt.fx) into units,tot from items i join item_costs c on c.item_id=i.id where i.batch_id=b;
 return query select x.id,x.sku,x.name,x.qty,x.s,x.sh,x.h,x.s+x.sh+x.h+x.o,
  ceil((case when bt.mode='margin' then (x.s+x.sh+x.h+x.o)/(1-least(bt.pct,99)/100) else (x.s+x.sh+x.h+x.o)*(1+bt.pct/100) end)/bt.round_to)*bt.round_to
 from(select i.id,i.sku,i.name,i.qty,(c.cost_usd+c.other_usd)*bt.fx s,
   coalesce(case when bt.split='cost' and tot>0 then bt.ship_cost_ngn*((c.cost_usd+c.other_usd)*bt.fx)/tot else bt.ship_cost_ngn/nullif(units,0) end,0) sh,
   (c.cost_usd+c.other_usd)*bt.fx*bt.hold_pct/100*greatest(0,(case when bt.status='open' then current_date else bt.ship_date end)-i.sourced_at::date)/30.0 h,
   c.other_ng o from items i join item_costs c on c.item_id=i.id where i.batch_id=b) x;
end$$;

create function ship_batch(b uuid) returns void language plpgsql security definer set search_path=public as $$
begin
 if not is_super() then raise exception 'forbidden';end if;
 if exists(select 1 from batches where id=b and status='shipped') then raise exception 'Already shipped';end if;
 update item_costs c set landed_ngn=r.landed,hold_ngn=r.hold from cost_batch(b) r where c.item_id=r.item_id;
 update items i set price_ngn=coalesce(i.price_ngn,r.suggested),status='in_transit' from cost_batch(b) r where i.id=r.item_id;
 update batches set status='shipped' where id=b;
end$$;

-- staff confirm physical receipt (owner cannot)
create function confirm_receipt(i uuid,got int) returns void language plpgsql security definer set search_path=public as $$
begin
 if my_role() not in('staff','admin') then raise exception 'Only store staff confirm receipt';end if;
 update items set status=case when got>0 then 'in_stock' else 'sold_out' end,qty_received=got,stock=got,received_at=now(),received_by=auth.uid()
 where id=i and status='in_transit';
end$$;

-- POS checkout, atomic
create function sell(cust text,pay text,lines jsonb) returns text language plpgsql security definer set search_path=public as $$
declare s uuid;rc text;l jsonb;it items;lid uuid;t numeric:=0;
begin
 if my_role() is null then raise exception 'forbidden';end if;
 rc:='RWH-'||lpad(nextval('receipt_seq')::text,4,'0');
 insert into sales(receipt,customer,payment,sold_by) values(rc,nullif(cust,''),pay,auth.uid()) returning id into s;
 for l in select * from jsonb_array_elements(lines) loop
  select * into it from items where id=(l->>'item_id')::uuid and status='in_stock' for update;
  if not found or it.stock<(l->>'qty')::int or (l->>'qty')::int<1 then raise exception 'Not enough stock for %',coalesce(it.sku,'item');end if;
  update items set stock=stock-(l->>'qty')::int,status=case when stock-(l->>'qty')::int=0 then 'sold_out' else status end where id=it.id;
  insert into sale_lines(sale_id,item_id,sku,name,qty,unit_price) values(s,it.id,it.sku,it.name,(l->>'qty')::int,(l->>'price')::numeric) returning id into lid;
  insert into sale_costs select lid,landed_ngn from item_costs where item_id=it.id;
  t:=t+(l->>'qty')::int*(l->>'price')::numeric;
 end loop;
 update sales set total=t where id=s;return rc;end$$;

-- row level security
alter table profiles enable row level security;alter table codes enable row level security;alter table batches enable row level security;
alter table items enable row level security;alter table item_costs enable row level security;alter table sales enable row level security;
alter table sale_lines enable row level security;alter table sale_costs enable row level security;
create policy p_sel on profiles for select using(id=auth.uid() or is_super());
create policy p_upd on profiles for update using(my_role()='admin');
create policy c_sel on codes for select using(my_role() is not null);
create policy c_all on codes for all using(is_super()) with check(is_super());
create policy b_all on batches for all using(is_super()) with check(is_super());
create policy i_sel on items for select using(is_super() or (my_role()='staff' and status<>'sourced'));
create policy i_ins on items for insert with check(is_super() or (my_role()='staff' and source='local' and status='in_stock' and batch_id is null));
create policy i_upd on items for update using(is_super()) with check(is_super());
create policy i_del on items for delete using(is_super() and status='sourced');
create policy ic_sel on item_costs for select using(is_super());
create policy ic_ins on item_costs for insert with check(is_super() or exists(select 1 from items where id=item_id and created_by=auth.uid() and source='local'));
create policy ic_upd on item_costs for update using(is_super());
create policy s_sel on sales for select using(my_role() is not null);
create policy sl_sel on sale_lines for select using(my_role() is not null);
create policy sc_sel on sale_costs for select using(is_super());
revoke execute on all functions in schema public from public,anon;
grant execute on function cost_batch,ship_batch,confirm_receipt,sell,my_role,is_super to authenticated;
