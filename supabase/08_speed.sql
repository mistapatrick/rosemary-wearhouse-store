-- Run ONCE after 07. Faster database lookups: indexes, and security rules that are evaluated once per query instead of once per row.
create index if not exists items_status on items(status);
create index if not exists items_batch on items(batch_id);
create index if not exists items_sourced on items(sourced_at);
create index if not exists sale_lines_sale on sale_lines(sale_id);
create index if not exists sale_lines_item on sale_lines(item_id);
create index if not exists sales_sold_at on sales(sold_at);

alter policy p_sel on profiles using (id=(select auth.uid()) or (select is_super()));
alter policy p_upd on profiles using ((select my_role())='admin');
alter policy c_sel on codes using ((select my_role()) is not null);
alter policy c_all on codes using ((select is_super())) with check ((select is_super()));
alter policy b_all on batches using ((select is_super())) with check ((select is_super()));
alter policy i_sel on items using ((select is_super()) or ((select my_role())='staff' and status<>'sourced'));
alter policy i_ins on items with check ((select is_super()) or ((select my_role())='staff' and source='local' and status='in_stock' and batch_id is null));
alter policy i_upd on items using ((select is_super())) with check ((select is_super()));
alter policy i_del on items using ((select is_super()) and status='sourced');
alter policy ic_sel on item_costs using ((select is_super()));
alter policy ic_ins on item_costs with check ((select is_super()) or exists(select 1 from items where id=item_id and created_by=(select auth.uid()) and source='local'));
alter policy ic_upd on item_costs using ((select is_super()));
alter policy s_sel on sales using ((select my_role()) is not null);
alter policy sl_sel on sale_lines using ((select my_role()) is not null);
alter policy sc_sel on sale_costs using ((select is_super()));
alter policy fx_sel on fx_rates using ((select my_role()) is not null);
alter policy st_sel on settings using ((select my_role()) is not null);
alter policy st_all on settings using ((select is_super())) with check ((select is_super()));
