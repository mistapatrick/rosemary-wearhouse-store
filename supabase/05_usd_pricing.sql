-- Run ONCE after 04. US items are priced in dollars; the naira price is fixed when staff confirm receipt in Kaduna.
alter table items add column price_usd numeric check(price_usd>=0), add column price_fx numeric;

create or replace function ship_batch(b uuid) returns void language plpgsql security definer set search_path=public as $$
declare f numeric;
begin
 if not is_super() then raise exception 'forbidden';end if;
 if exists(select 1 from batches where id=b and status='shipped') then raise exception 'Already shipped';end if;
 select fx into f from batches where id=b;
 update item_costs c set landed_ngn=r.landed,hold_ngn=r.hold from cost_batch(b) r where c.item_id=r.item_id;
 -- dollar price: keep the owner's price, otherwise use the batch suggestion converted at the batch rate
 update items i set price_usd=coalesce(i.price_usd,round(r.suggested/f,2)),status='in_transit' from cost_batch(b) r where i.id=r.item_id;
 update batches set status='shipped' where id=b;
end$$;

create or replace function confirm_receipt(i uuid,got int) returns void language plpgsql security definer set search_path=public as $$
declare f numeric:=current_fx();
begin
 if my_role() not in('staff','admin') then raise exception 'Only store staff confirm receipt';end if;
 update items it set status=case when got>0 then 'in_stock' else 'sold_out' end,qty_received=got,stock=got,received_at=now(),received_by=auth.uid(),
  price_ngn=case when it.price_usd is not null then ceil(it.price_usd*f/coalesce((select round_to from batches where id=it.batch_id),500))*coalesce((select round_to from batches where id=it.batch_id),500) else it.price_ngn end,
  price_fx=case when it.price_usd is not null then f end
 where it.id=i and it.status='in_transit';
end$$;
