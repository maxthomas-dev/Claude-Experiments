with catalog_listings as(
select
pt.catalog_brand_id,
pt.catalog_brand,
p.master_id as master_product_id,
p.name as product_name,
l.listing_id,
l.listing_mp_page_id,
iff(mp.id = 1, 'Amazon', concat('Amazon ', mp.country_code)) as catalog_marketplace_name,
s.account_id,
mg.name as marketplace,
mp.country_code,
l.listing_mp_primary_id,
ba.ecommerce_manager,
ba.ecommerce_manager_email,
ba.director_of_ecommerce,
ba.director_of_ecommerce_email
from pattern_db.public.product_catalog_listing_prices as lp
inner join analytics_db.stg_catalog.stg_catalog__listings as l
on lp.l_id = l.id
and l.listing_is_active = True
left join analytics_db.stg_catalog.stg_catalog__marketplaces as mp
on lp.marketplace_id = mp.id
left join analytics_db.stg_catalog.stg_catalog__marketplace_groups mg
on mg.id = mp.marketplace_group_id
join analytics_db.stg_catalog.stg_catalog__sellers as s
on lp.seller_id = s.id
left join analytics_db.stg_catalog.stg_catalog__products as p
on p.id = l.product_id
left join pattern_db.public.product_catalog_brand_hierarchy PT
on pt.catalog_brand_id = p.partner_id
and is_terminal_level = true
left join analytics_db.core.brand_assignments_2 ba
on pt.id = ba.vendor_id
and mp.country_code = ba.country_code
)
Select
ORDER_DATE,
cl.catalog_brand,
sum(hs.converted_revenue) as converted_revenue,
sum(hs.quantity) as quantity_sold
from pattern_db.public.hourly_sales hs
left join catalog_listings cl on hs.listing_id = cl.listing_id
where hs.country_code = 'US'
and cl.marketplace = 'Amazon'
and order_date >='2025-11-01'
group by 1,2
order by 2,1;




--------------------------------------------------------------------------------------------------------------
with catalog_listings as(
    select
        pt.catalog_brand_id,
        pt.catalog_brand,
        p.master_id as master_product_id,
        p.name as product_name,
        l.listing_id,
        l.listing_mp_page_id,
        iff(mp.id = 1, 'Amazon', concat('Amazon ', mp.country_code)) as catalog_marketplace_name,
        s.account_id,
        mg.name as marketplace,
        mp.country_code,
        l.listing_mp_primary_id,
        ba.ecommerce_manager,
        ba.ecommerce_manager_email,
        ba.director_of_ecommerce,
        ba.director_of_ecommerce_email
    from pattern_db.public.product_catalog_listing_prices as lp
    inner join analytics_db.stg_catalog.stg_catalog__listings as l
        on lp.l_id = l.id
        and l.listing_is_active = True
    left join analytics_db.stg_catalog.stg_catalog__marketplaces as mp
        on lp.marketplace_id = mp.id
    left join analytics_db.stg_catalog.stg_catalog__marketplace_groups mg
        on mg.id = mp.marketplace_group_id
    join analytics_db.stg_catalog.stg_catalog__sellers as s
        on lp.seller_id = s.id
    left join analytics_db.stg_catalog.stg_catalog__products as p
        on p.id = l.product_id
    left join pattern_db.public.product_catalog_brand_hierarchy PT
        on pt.catalog_brand_id = p.partner_id
        and is_terminal_level = true
    left join analytics_db.core.brand_assignments_2 ba
        on pt.id = ba.vendor_id
        and mp.country_code = ba.country_code
)
    Select
        ORDER_DATE,
        cl.catalog_brand,
        sum(hs.converted_revenue) as converted_revenue,
        sum(hs.quantity) as quantity_sold
    from pattern_db.public.hourly_sales hs
    left join catalog_listings cl on hs.listing_id = cl.listing_id
    where hs.country_code = 'US'
    and cl.marketplace = 'Amazon'
    and hs.order_date::date >= dateadd(week, -7, date_trunc('week', current_date()))
    and hs.order_date::date <  date_trunc('week', current_date())
    group by 1,2
    order by 2,1;




















