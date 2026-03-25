-- ============================================================
-- WBR Summary Tables + Nightly Refresh Task
-- Run this once manually to create the tables and task.
-- Replace <your_warehouse> with your actual warehouse name.
-- ============================================================


-- ── Table 1: Daily sales by brand (feeds QUERY_WBR_MAIN) ────────────────────
-- Collapses 120M hourly_sales rows to ~tens-of-thousands of daily+brand rows.
create or replace table "USER$MAX.THOMAS@PATTERN.COM".PUBLIC.wbr_daily_sales as
select
  to_date(hs.order_date) as order_date,
  case
    when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
    when pt.catalog_brand ilike 'Nutricia%'         then 'Nutricia'
    else pt.catalog_brand
  end                    as catalog_brand,
  sum(hs.converted_revenue) as revenue,
  sum(hs.quantity)          as units
from pattern_db.public.hourly_sales hs
left join analytics_db.stg_catalog.stg_catalog__listings l
  on l.listing_id = hs.listing_id
left join analytics_db.stg_catalog.stg_catalog__products p
  on p.id = l.product_id
left join pattern_db.public.product_catalog_brand_hierarchy pt
  on pt.catalog_brand_id = p.partner_id and is_terminal_level = true
where hs.country_code in ('US', 'CA', 'MX', 'BR')
group by 1, 2;


-- ── Table 2: Daily Amazon sales by brand (feeds QUERY_AMAZON) ───────────────
create or replace table "USER$MAX.THOMAS@PATTERN.COM".PUBLIC.wbr_daily_amazon_sales as
with amazon_listings as (
  select distinct l.listing_id,
    case
      when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
      when pt.catalog_brand ilike 'Nutricia%'         then 'Nutricia'
      else pt.catalog_brand
    end as catalog_brand
  from pattern_db.public.product_catalog_listing_prices lp
  inner join analytics_db.stg_catalog.stg_catalog__listings l
    on lp.l_id = l.id and l.listing_is_active = true
  left join analytics_db.stg_catalog.stg_catalog__marketplaces mp
    on lp.marketplace_id = mp.id
  left join analytics_db.stg_catalog.stg_catalog__marketplace_groups mg
    on mg.id = mp.marketplace_group_id
  left join analytics_db.stg_catalog.stg_catalog__products p
    on p.id = l.product_id
  left join pattern_db.public.product_catalog_brand_hierarchy pt
    on pt.catalog_brand_id = p.partner_id and is_terminal_level = true
  where mg.name = 'Amazon'
)
select
  hs.order_date::date       as order_date,
  al.catalog_brand,
  sum(hs.converted_revenue) as converted_revenue,
  sum(hs.quantity)          as quantity_sold
from pattern_db.public.hourly_sales hs
inner join amazon_listings al on al.listing_id = hs.listing_id
where hs.country_code = 'US'
group by 1, 2;


-- ── Nightly refresh task (runs 6am UTC = 10pm/11pm PT) ──────────────────────
create or replace task "USER$MAX.THOMAS@PATTERN.COM".PUBLIC.refresh_wbr_summary
  warehouse = <your_warehouse>
  schedule  = 'USING CRON 0 6 * * * UTC'
as
begin
  create or replace table "USER$MAX.THOMAS@PATTERN.COM".PUBLIC.wbr_daily_sales as
  select
    to_date(hs.order_date) as order_date,
    case
      when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
      when pt.catalog_brand ilike 'Nutricia%'         then 'Nutricia'
      else pt.catalog_brand
    end                    as catalog_brand,
    sum(hs.converted_revenue) as revenue,
    sum(hs.quantity)          as units
  from pattern_db.public.hourly_sales hs
  left join analytics_db.stg_catalog.stg_catalog__listings l
    on l.listing_id = hs.listing_id
  left join analytics_db.stg_catalog.stg_catalog__products p
    on p.id = l.product_id
  left join pattern_db.public.product_catalog_brand_hierarchy pt
    on pt.catalog_brand_id = p.partner_id and is_terminal_level = true
  where hs.country_code in ('US', 'CA', 'MX', 'BR')
  group by 1, 2;

  create or replace table "USER$MAX.THOMAS@PATTERN.COM".PUBLIC.wbr_daily_amazon_sales as
  with amazon_listings as (
    select distinct l.listing_id,
      case
        when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
        when pt.catalog_brand ilike 'Nutricia%'         then 'Nutricia'
        else pt.catalog_brand
      end as catalog_brand
    from pattern_db.public.product_catalog_listing_prices lp
    inner join analytics_db.stg_catalog.stg_catalog__listings l
      on lp.l_id = l.id and l.listing_is_active = true
    left join analytics_db.stg_catalog.stg_catalog__marketplaces mp
      on lp.marketplace_id = mp.id
    left join analytics_db.stg_catalog.stg_catalog__marketplace_groups mg
      on mg.id = mp.marketplace_group_id
    left join analytics_db.stg_catalog.stg_catalog__products p
      on p.id = l.product_id
    left join pattern_db.public.product_catalog_brand_hierarchy pt
      on pt.catalog_brand_id = p.partner_id and is_terminal_level = true
    where mg.name = 'Amazon'
  )
  select
    hs.order_date::date       as order_date,
    al.catalog_brand,
    sum(hs.converted_revenue) as converted_revenue,
    sum(hs.quantity)          as quantity_sold
  from pattern_db.public.hourly_sales hs
  inner join amazon_listings al on al.listing_id = hs.listing_id
  where hs.country_code = 'US'
  group by 1, 2;
end;

-- Activate the task (tasks start suspended by default)
alter task "USER$MAX.THOMAS@PATTERN.COM".PUBLIC.refresh_wbr_summary resume;
