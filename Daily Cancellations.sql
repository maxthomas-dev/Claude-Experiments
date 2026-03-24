select date(convert_timezone('UTC','America/Los_Angeles',o.purchase_date::timestamp)) as order_date_pst,
       coalesce(pa.name, v.name) as partner_brand,
       os.status,
       sum(coalesce(oi.quantity,0) + case when coalesce(oi.quantity,0) = 0 then coalesce(oi.initial_quantity,0) else 0 end) as tot_quantity,
       sum(coalesce(oi.item_price,oi.initial_item_price)) as tot_item_price,
       sum(coalesce(oi.item_promotion_discount,0)) as tot_promo_discount,
       tot_item_price+tot_promo_discount as total_gross_revenue
from analytics_db.stg_threepn.stg_threepn__orders o
left join analytics_db.stg_threepn.stg_threepn__order_items oi on o.id = oi.order_id
left join analytics_db.stg_threepn.stg_threepn__seller_listings sl on oi.seller_listing_id = sl.id
left join analytics_db.stg_catalog.stg_catalog__listings l on l.listing_id = sl.catalog_listing_id
left join analytics_db.stg_catalog.stg_catalog__products p on p.id = l.product_id
left join analytics_db.stg_catalog.stg_catalog__partners pa on pa.id = p.partner_id
left join analytics_db.stg_threepn.stg_threepn__sales_channels sc on sc.id = o.sales_channel_id
left join analytics_db.stg_threepn.stg_threepn__currencies c on c.id = oi.currency_id
left join analytics_db.stg_threepn.stg_threepn__order_statuses os on os.id = o.order_status_id
left join analytics_db.stg_threepn.stg_threepn__asins a on a.id = sl.asin_id
left join analytics_db.stg_threepn.stg_threepn__vendors v on v.id = a.vendor_id
where true
and order_date_pst >= '2025-11-01'
and sc.channel = 'Amazon.com'
and v.name not in ('Bradshaw Home','LEATHERMAN')
and (pa.name is null or pa.name not in ('Bradshaw Home','LEATHERMAN'))
group by all
order by partner_brand, order_date_pst
;






select * from analytics_db.stg_threepn.stg_threepn__order_items
where cast(created_at as date) = '2025-06-09';

















