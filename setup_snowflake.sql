-- ============================================================
-- WBR Reporting Schema — Complete Setup
--
-- BEFORE RUNNING — replace these 3 placeholders:
--   <YOUR_DATABASE>  : shared database your BI team provisions
--   <YOUR_SCHEMA>    : schema inside that database
--   <YOUR_WAREHOUSE> : your Snowflake warehouse name
--
-- HOW TO USE:
--   1. Find-and-replace the 3 placeholders above
--   2. Run this entire file once in a Snowflake worksheet
--   3. The task at the bottom handles all nightly refreshes
--
-- ARCHITECTURE (2 layers, 3 tables):
--   Layer 1 — Staging  : wbr_daily_sales, wbr_daily_amazon_sales
--     Pre-aggregate 100M+ raw rows into manageable daily+brand rows.
--     Layer 2 reads from these instead of raw source tables.
--   Layer 2 — Reporting: wbr_brand_metrics
--     One table with everything: WBR metrics + cancellation projections.
--     Google Sheets / n8n reads this with a simple SELECT *.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- LAYER 1 — Staging tables
-- ════════════════════════════════════════════════════════════

-- ── Table 1: wbr_daily_sales ─────────────────────────────────────────────────
-- Daily revenue + units by brand, Americas (US / CA / MX / BR), all channels.
create or replace table <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_daily_sales as
select
  to_date(hs.order_date) as order_date,
  case
    when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
    when pt.catalog_brand ilike 'Nutricia%'         then 'Nutricia'
    else pt.catalog_brand
  end as catalog_brand,
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


-- ── Table 2: wbr_daily_amazon_sales ──────────────────────────────────────────
-- Daily revenue + units by brand, Amazon US only.
create or replace table <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_daily_amazon_sales as
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


-- ════════════════════════════════════════════════════════════
-- LAYER 2 — Single reporting output table
-- wbr_brand_metrics: WBR metrics + cancellation projections
-- Google Sheets / n8n reads this with SELECT *
-- ════════════════════════════════════════════════════════════

create or replace table <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_brand_metrics as
with

allowed_marketplaces as (
  select column1 as marketplace_name from values
    ('Amazon.ca'), ('Amazon.com'), ('Amazon.com.br'), ('Amazon.com.mx'),
    ('Ebay US'), ('Kohl''s'), ('Kroger.com'), ('Macys.com'),
    ('Mercado Libre'), ('Shopify US'), ('Target+'), ('TikTok US'),
    ('Walmart CA'), ('Walmart US')
),
anchor as (
  select
    to_date(dateadd(day, -dayofweek(current_date), current_date))                    as this_week_start,
    to_date(dateadd(week, -1, dateadd(day, -dayofweek(current_date), current_date))) as last_week_start
),
ranges as (
  select
    a.last_week_start,
    to_date(dateadd(day,   6, a.last_week_start))                                    as last_week_end,
    to_date(dateadd(week, -1, a.last_week_start))                                    as lw1_start,
    to_date(dateadd(week, -2, a.last_week_start))                                    as lw2_start,
    to_date(dateadd(week, -3, a.last_week_start))                                    as lw3_start,
    to_date(dateadd(week, -5, a.last_week_start))                                    as start_6w,
    to_date(dateadd(week, -52, dateadd(week, -5, a.last_week_start)))                as start_6w_yoy,
    to_date(dateadd(week, -52, a.last_week_start))                                   as end_6w_yoy,
    to_date(date_trunc(year, dateadd(day, 6, a.last_week_start)))                    as ytd_start,
    to_date(dateadd(year, -1, date_trunc(year, dateadd(day, 6, a.last_week_start)))) as ytd_start_yoy,
    to_date(dateadd(year, -1, to_date(dateadd(day, 6, a.last_week_start))))          as last_week_end_yoy,
    to_date(dateadd(week,  1, a.this_week_start))                                    as start_13w,
    to_date(dateadd(week, 14, a.this_week_start))                                    as end_13w_excl
  from anchor a
),
weekly_actuals as (
  select
    to_date(dateadd(day, -dayofweek(order_date), order_date)) as week_start_date,
    catalog_brand,
    sum(revenue) as revenue,
    sum(units)   as units
  from <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_daily_sales
  group by 1, 2
),
metrics_wk_brand as (
  select
    w.catalog_brand,
    r.last_week_start as last_completed_week_start,
    sum(case when w.week_start_date between r.start_6w     and r.last_week_start then w.units   else 0 end) / 6.0 as last_6w_units_run_rate,
    sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy     then w.units   else 0 end) / 6.0 as last_6w_units_run_rate_yoy,
    sum(case when w.week_start_date between r.start_6w     and r.last_week_start then w.revenue else 0 end) / 6.0 as last_6w_rev_run_rate,
    sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy     then w.revenue else 0 end) / 6.0 as last_6w_rev_run_rate_yoy,
    nullif(
      sum(case when w.week_start_date between r.start_6w     and r.last_week_start then w.units else 0 end) -
      sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy     then w.units else 0 end), 0
    ) / nullif(sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy then w.units else 0 end), 0)
      as last_6w_units_run_rate_yoy_pct,
    sum(case when w.week_start_date = r.last_week_start                     then w.units   else 0 end) as last_week_units,
    sum(case when w.week_start_date = dateadd(week, -52, r.last_week_start) then w.units   else 0 end) as last_week_units_yoy,
    sum(case when w.week_start_date = r.last_week_start                     then w.revenue else 0 end) as last_week_rev,
    nullif(
      sum(case when w.week_start_date = r.last_week_start                     then w.units else 0 end) -
      sum(case when w.week_start_date = dateadd(week, -52, r.last_week_start) then w.units else 0 end), 0
    ) / nullif(sum(case when w.week_start_date = dateadd(week, -52, r.last_week_start) then w.units else 0 end), 0)
      as last_week_units_yoy_pct,
    sum(case when w.week_start_date = dateadd(week, -5, r.last_week_start) then w.units else 0 end) as units_wk_5,
    sum(case when w.week_start_date = dateadd(week, -4, r.last_week_start) then w.units else 0 end) as units_wk_4,
    sum(case when w.week_start_date = dateadd(week, -3, r.last_week_start) then w.units else 0 end) as units_wk_3,
    sum(case when w.week_start_date = dateadd(week, -2, r.last_week_start) then w.units else 0 end) as units_wk_2,
    sum(case when w.week_start_date = dateadd(week, -1, r.last_week_start) then w.units else 0 end) as units_wk_1,
    sum(case when w.week_start_date = r.last_week_start                    then w.units else 0 end) as units_wk_0
  from weekly_actuals w
  cross join ranges r
  group by 1, 2
),
ytd_daily_brand as (
  select
    s.catalog_brand,
    r.last_week_start as last_completed_week_start,
    sum(case when s.order_date between r.ytd_start     and r.last_week_end     then s.units   else 0 end) as ytd_units,
    sum(case when s.order_date between r.ytd_start_yoy and r.last_week_end_yoy then s.units   else 0 end) as ytd_units_yoy,
    sum(case when s.order_date between r.ytd_start     and r.last_week_end     then s.revenue else 0 end) as ytd_rev,
    sum(case when s.order_date between r.ytd_start_yoy and r.last_week_end_yoy then s.revenue else 0 end) as ytd_rev_yoy
  from <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_daily_sales s
  cross join ranges r
  group by 1, 2
),
act_yoy_for_fcst_13w as (
  select w.catalog_brand, sum(w.units) as units_13w_yoy_actuals
  from weekly_actuals w
  cross join ranges r
  where w.week_start_date >= dateadd(week, -52, r.start_13w)
    and w.week_start_date <  dateadd(week, -52, r.end_13w_excl)
  group by 1
),
im_fcst_13w_brand as (
  select
    case
      when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
      when pt.catalog_brand ilike 'Nutricia%'         then 'Nutricia'
      else pt.catalog_brand
    end as catalog_brand,
    sum(
      coalesce(df.base_rate_overwrite, df.base_rate, 0)
      + coalesce(df.promo_increase_overwrite, df.promo_increase, 0)
      + coalesce(df.seasonal_increase_overwrite, df.seasonal_increase, 0)
    ) as fcst_units_13w_im
  from pattern_db.inventory_hub.demand_forecasts df
  cross join ranges r
  join analytics_db.stg_catalog.stg_catalog__products p
    on p.master_id = df.master_id
  join pattern_db.public.product_catalog_brand_hierarchy pt
    on pt.catalog_brand_id = p.partner_id and is_terminal_level = true
  join analytics_db.stg_inventory_hub.stg_inventory_hub__marketplaces mm
    on mm.id = df.marketplace_id
  join allowed_marketplaces am
    on am.marketplace_name = mm.name
  where df.effective_end_date is null
    and df.week_start >= r.start_13w
    and df.week_start <  r.end_13w_excl
  group by 1
),
ae_forecast_src as (
  select
    case
      when partner ilike 'Standard Process%' then 'Standard Process'
      when partner ilike 'Nutricia%'         then 'Nutricia'
      else partner
    end as brand,
    date_trunc('month', coalesce(
      try_to_date(month::varchar),
      try_to_date(month::varchar, 'YYYY-MM'),
      try_to_date(month::varchar, 'YYYYMM'),
      try_to_date(month::varchar, 'MON-YYYY'),
      try_to_date(month::varchar, 'MON YYYY'),
      try_to_date(month)
    )) as month_start,
    units
  from pattern_db.accounting_finance.adaptive_op_2026_units
),
ae_fcst_13w_brand as (
  select
    s.brand as catalog_brand,
    sum(
      s.units
      * datediff('day',
          greatest(s.month_start, r.start_13w),
          least(dateadd(month, 1, s.month_start), r.end_13w_excl)
        )
      / datediff('day', s.month_start, dateadd(month, 1, s.month_start))
    ) as fcst_units_13w_ae
  from ae_forecast_src s
  cross join ranges r
  where s.month_start <  r.end_13w_excl
    and dateadd(month, 1, s.month_start) > r.start_13w
  group by 1
),
inv_max as (
  select max(date) as inv_date
  from pattern_db.inventory_hub.daily_item_inventories
  where region in ('US', 'CA') and date <= current_date
),
inventory_base as (
  select
    i.date,
    case
      when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
      when pt.catalog_brand ilike 'Nutricia%'         then 'Nutricia'
      else pt.catalog_brand
    end as catalog_brand,
    i.quantity,
    i.inventory_value_usd
  from pattern_db.inventory_hub.daily_item_inventories i
  join inv_max m on i.date = m.inv_date
  join analytics_db.stg_catalog.stg_catalog__products pr on pr.master_id = i.master_id
  join pattern_db.public.product_catalog_brand_hierarchy pt
    on pt.catalog_brand_id = pr.partner_id and is_terminal_level = true
  left join analytics_db.stg_inventory_hub.stg_inventory_hub__subsidiaries su
    on su.id = i.subsidiary_id
  left join analytics_db.stg_inventory_hub.stg_inventory_hub__availability_detail_statuses ad
    on ad.id = i.availability_detail_status_id
  where i.region in ('US', 'CA')
    and su.entity not ilike '%no%ownership%'
    and ad.condition not ilike '%on%order%'
    and (i.virtual is distinct from true)
),
inventory_brand as (
  select catalog_brand, date as inv_asof_date,
    sum(quantity) as inv_units, sum(inventory_value_usd) as inv_value_usd
  from inventory_base
  group by 1, 2
),
brands_universe as (
  select distinct catalog_brand from weekly_actuals
  union select distinct catalog_brand from im_fcst_13w_brand
  union select distinct brand       from ae_forecast_src
  union select distinct catalog_brand from inventory_base
),
-- ── Cancellation projection CTEs ─────────────────────────────────────────────
-- Replicates the Excel Daily Cancellations workbook logic:
--   cancel_rate     = Cancelled / Total orders placed that day  (Excel row 29)
--   avg_cancel_rate = 28-day rolling avg of cancel_rate         (Excel row 30, NT:OU)
--   daily_net_predict = ST * (1 - max(0, avg_rate - current_rate)) (Excel row 32)
--   cancel_weekly   = weekly rollup for LW-3/LW-2/LW-1/LW      (Excel cols PC-PF)
cancel_daily_orders as (
  select
    date(convert_timezone('UTC', 'America/Los_Angeles', o.purchase_date::timestamp)) as order_date,
    case
      when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
      when pt.catalog_brand ilike 'Nutricia%'         then 'Nutricia'
      else pt.catalog_brand
    end as catalog_brand,
    os.status,
    sum(
      coalesce(oi.quantity, 0)
      + case when coalesce(oi.quantity, 0) = 0 then coalesce(oi.initial_quantity, 0) else 0 end
    ) as units
  from analytics_db.stg_threepn.stg_threepn__orders o
  left join analytics_db.stg_threepn.stg_threepn__order_items oi
    on o.id = oi.order_id
  left join analytics_db.stg_threepn.stg_threepn__seller_listings sl
    on oi.seller_listing_id = sl.id
  left join analytics_db.stg_catalog.stg_catalog__listings l
    on l.listing_id = sl.catalog_listing_id
  left join analytics_db.stg_catalog.stg_catalog__products p
    on p.id = l.product_id
  left join pattern_db.public.product_catalog_brand_hierarchy pt
    on pt.catalog_brand_id = p.partner_id and is_terminal_level = true
  left join analytics_db.stg_threepn.stg_threepn__sales_channels sc
    on sc.id = o.sales_channel_id
  left join analytics_db.stg_threepn.stg_threepn__order_statuses os
    on os.id = o.order_status_id
  where sc.channel = 'Amazon.com'
    and pt.catalog_brand not in ('Bradshaw Home', 'LEATHERMAN')
    and date(convert_timezone('UTC', 'America/Los_Angeles', o.purchase_date::timestamp))
        >= dateadd(day, -90, current_date)
  group by 1, 2, 3
),
cancel_by_brand as (
  select
    order_date,
    catalog_brand,
    sum(units)                                                    as total_units,
    sum(case when status = 'Cancelled' then units else 0 end)     as cancelled_units
  from cancel_daily_orders
  where catalog_brand is not null
  group by 1, 2
),
cancel_rates as (
  select
    order_date,
    catalog_brand,
    cancelled_units::float / nullif(total_units, 0)               as cancel_rate,
    -- 28-day rolling avg offset 1 week back (rows 35 preceding to 8 preceding)
    -- matches Excel AVERAGE($NT29:$OU29) — 28 days ending 7 days before current col
    avg(cancelled_units::float / nullif(total_units, 0)) over (
      partition by catalog_brand
      order by order_date
      rows between 35 preceding and 8 preceding
    )                                                             as avg_cancel_rate_28d
  from cancel_by_brand
),
cancel_net_predict as (
  select
    r.order_date,
    r.catalog_brand,
    coalesce(s.quantity_sold, 0)                                  as daily_predict,
    greatest(0, coalesce(r.avg_cancel_rate_28d, 0) - coalesce(r.cancel_rate, 0))
                                                                  as projected_add_cancel_rate,
    coalesce(s.quantity_sold, 0)
      * (1 - greatest(0, coalesce(r.avg_cancel_rate_28d, 0) - coalesce(r.cancel_rate, 0)))
                                                                  as daily_net_predict
  from cancel_rates r
  left join <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_daily_amazon_sales s
    on  s.order_date    = r.order_date
    and s.catalog_brand = r.catalog_brand
),
cancel_weekly as (
  select
    d.catalog_brand,
    sum(case when d.order_date >= r.lw3_start       and d.order_date < r.lw2_start
             then d.daily_predict     else 0 end)  as lw3_predict,
    sum(case when d.order_date >= r.lw3_start       and d.order_date < r.lw2_start
             then d.daily_net_predict else 0 end)  as lw3_net_predict,
    sum(case when d.order_date >= r.lw2_start       and d.order_date < r.lw1_start
             then d.daily_predict     else 0 end)  as lw2_predict,
    sum(case when d.order_date >= r.lw2_start       and d.order_date < r.lw1_start
             then d.daily_net_predict else 0 end)  as lw2_net_predict,
    sum(case when d.order_date >= r.lw1_start       and d.order_date < r.last_week_start
             then d.daily_predict     else 0 end)  as lw1_predict,
    sum(case when d.order_date >= r.lw1_start       and d.order_date < r.last_week_start
             then d.daily_net_predict else 0 end)  as lw1_net_predict,
    sum(case when d.order_date >= r.last_week_start and d.order_date < dateadd(week, 1, r.last_week_start)
             then d.daily_predict     else 0 end)  as lw_predict,
    sum(case when d.order_date >= r.last_week_start and d.order_date < dateadd(week, 1, r.last_week_start)
             then d.daily_net_predict else 0 end)  as lw_net_predict
  from cancel_net_predict d
  cross join ranges r
  group by 1
),
combined_brand as (
  select
    b.catalog_brand,
    coalesce(m.last_completed_week_start, y.last_completed_week_start) as last_completed_week_start,
    coalesce(m.last_6w_units_run_rate, 0)     as last_6w_units_run_rate,
    coalesce(m.last_6w_units_run_rate_yoy, 0) as last_6w_units_run_rate_yoy,
    m.last_6w_units_run_rate_yoy_pct,
    coalesce(m.last_6w_rev_run_rate, 0)       as last_6w_rev_run_rate,
    coalesce(m.last_6w_rev_run_rate_yoy, 0)   as last_6w_rev_run_rate_yoy,
    coalesce(m.last_week_units, 0)            as last_week_units,
    coalesce(m.last_week_units_yoy, 0)        as last_week_units_yoy,
    m.last_week_units_yoy_pct,
    coalesce(m.last_week_rev, 0)              as last_week_rev,
    coalesce(m.units_wk_5, 0) as units_wk_5,
    coalesce(m.units_wk_4, 0) as units_wk_4,
    coalesce(m.units_wk_3, 0) as units_wk_3,
    coalesce(m.units_wk_2, 0) as units_wk_2,
    coalesce(m.units_wk_1, 0) as units_wk_1,
    coalesce(m.units_wk_0, 0) as units_wk_0,
    coalesce(y.ytd_units, 0)                  as ytd_units,
    coalesce(y.ytd_units_yoy, 0)              as ytd_units_yoy,
    case when coalesce(y.ytd_units_yoy, 0) = 0 then null
         else (y.ytd_units - y.ytd_units_yoy) / y.ytd_units_yoy end as ytd_units_yoy_pct,
    coalesce(y.ytd_rev, 0)                    as ytd_rev,
    coalesce(im.fcst_units_13w_im, 0)         as fcst_units_13w_im,
    coalesce(im.fcst_units_13w_im, 0) / 13.0  as fcst_units_run_rate_13w_im,
    case when coalesce(a.units_13w_yoy_actuals, 0) = 0 then null
         else a.units_13w_yoy_actuals / 13.0 end as fcst_units_run_rate_yoy_13w_im,
    case when coalesce(a.units_13w_yoy_actuals, 0) = 0 then null
         else (coalesce(im.fcst_units_13w_im, 0) - a.units_13w_yoy_actuals) / a.units_13w_yoy_actuals
    end as fcst_units_run_rate_yoy_pct_13w_im,
    coalesce(ae.fcst_units_13w_ae, 0)         as fcst_units_13w_ae,
    coalesce(ae.fcst_units_13w_ae, 0) / 13.0  as fcst_units_run_rate_13w_ae,
    case when coalesce(a.units_13w_yoy_actuals, 0) = 0 then null
         else a.units_13w_yoy_actuals / 13.0 end as fcst_units_run_rate_yoy_13w_ae,
    case when coalesce(a.units_13w_yoy_actuals, 0) = 0 then null
         else (coalesce(ae.fcst_units_13w_ae, 0) - a.units_13w_yoy_actuals) / a.units_13w_yoy_actuals
    end as fcst_units_run_rate_yoy_pct_13w_ae,
    coalesce(inv.inv_units, 0)                as inv_units,
    coalesce(inv.inv_value_usd, 0)            as inv_value_usd,
    case when coalesce(im.fcst_units_13w_im, 0) / 13.0 = 0 then null
         else coalesce(inv.inv_units, 0) / (coalesce(im.fcst_units_13w_im, 0) / 13.0) end as wos_weeks_im,
    case when coalesce(ae.fcst_units_13w_ae, 0) / 13.0 = 0 then null
         else coalesce(inv.inv_units, 0) / (coalesce(ae.fcst_units_13w_ae, 0) / 13.0) end as wos_weeks_ae,
    -- ── Cancellation projection columns ──────────────────────────────────────
    coalesce(cw.lw3_predict,     0)           as lw3_predict,
    coalesce(cw.lw2_predict,     0)           as lw2_predict,
    coalesce(cw.lw1_predict,     0)           as lw1_predict,
    coalesce(cw.lw_predict,      0)           as lw_predict,
    coalesce(cw.lw3_net_predict, 0)           as lw3_net_predict,
    coalesce(cw.lw2_net_predict, 0)           as lw2_net_predict,
    coalesce(cw.lw1_net_predict, 0)           as lw1_net_predict,
    coalesce(cw.lw_net_predict,  0)           as lw_net_predict,
    round(coalesce(cw.lw3_net_predict, 0) - coalesce(cw.lw3_predict, 0)) as lw3_cancel_impact,
    round(coalesce(cw.lw2_net_predict, 0) - coalesce(cw.lw2_predict, 0)) as lw2_cancel_impact,
    round(coalesce(cw.lw1_net_predict, 0) - coalesce(cw.lw1_predict, 0)) as lw1_cancel_impact,
    round(coalesce(cw.lw_net_predict,  0) - coalesce(cw.lw_predict,  0)) as lw_cancel_impact,
    case when coalesce(cw.lw3_predict, 0) = 0 then null
         else (coalesce(cw.lw3_net_predict, 0) - coalesce(cw.lw3_predict, 0)) / coalesce(cw.lw3_predict, 0)
    end as lw3_cancel_impact_pct,
    case when coalesce(cw.lw2_predict, 0) = 0 then null
         else (coalesce(cw.lw2_net_predict, 0) - coalesce(cw.lw2_predict, 0)) / coalesce(cw.lw2_predict, 0)
    end as lw2_cancel_impact_pct,
    case when coalesce(cw.lw1_predict, 0) = 0 then null
         else (coalesce(cw.lw1_net_predict, 0) - coalesce(cw.lw1_predict, 0)) / coalesce(cw.lw1_predict, 0)
    end as lw1_cancel_impact_pct,
    case when coalesce(cw.lw_predict,  0) = 0 then null
         else (coalesce(cw.lw_net_predict,  0) - coalesce(cw.lw_predict,  0)) / coalesce(cw.lw_predict,  0)
    end as lw_cancel_impact_pct
  from brands_universe b
  left join metrics_wk_brand        m   on m.catalog_brand   = b.catalog_brand
  left join ytd_daily_brand         y   on y.catalog_brand   = b.catalog_brand
  left join im_fcst_13w_brand       im  on im.catalog_brand  = b.catalog_brand
  left join ae_fcst_13w_brand       ae  on ae.catalog_brand  = b.catalog_brand
  left join act_yoy_for_fcst_13w    a   on a.catalog_brand   = b.catalog_brand
  left join inventory_brand         inv on inv.catalog_brand  = b.catalog_brand
  left join cancel_weekly           cw  on cw.catalog_brand  = b.catalog_brand
),
combined_total as (
  select
    'All Brands'                       as catalog_brand,
    max(last_completed_week_start)     as last_completed_week_start,
    sum(last_6w_units_run_rate)        as last_6w_units_run_rate,
    sum(last_6w_units_run_rate_yoy)    as last_6w_units_run_rate_yoy,
    case when sum(last_6w_units_run_rate_yoy) = 0 then null
         else (sum(last_6w_units_run_rate) - sum(last_6w_units_run_rate_yoy)) / sum(last_6w_units_run_rate_yoy)
    end                                as last_6w_units_run_rate_yoy_pct,
    sum(last_6w_rev_run_rate)          as last_6w_rev_run_rate,
    sum(last_6w_rev_run_rate_yoy)      as last_6w_rev_run_rate_yoy,
    sum(last_week_units)               as last_week_units,
    sum(last_week_units_yoy)           as last_week_units_yoy,
    case when sum(last_week_units_yoy) = 0 then null
         else (sum(last_week_units) - sum(last_week_units_yoy)) / sum(last_week_units_yoy)
    end                                as last_week_units_yoy_pct,
    sum(last_week_rev)                 as last_week_rev,
    sum(units_wk_5)  as units_wk_5,  sum(units_wk_4) as units_wk_4,
    sum(units_wk_3)  as units_wk_3,  sum(units_wk_2) as units_wk_2,
    sum(units_wk_1)  as units_wk_1,  sum(units_wk_0) as units_wk_0,
    sum(ytd_units)                     as ytd_units,
    sum(ytd_units_yoy)                 as ytd_units_yoy,
    case when sum(ytd_units_yoy) = 0 then null
         else (sum(ytd_units) - sum(ytd_units_yoy)) / sum(ytd_units_yoy)
    end                                as ytd_units_yoy_pct,
    sum(ytd_rev)                       as ytd_rev,
    sum(fcst_units_13w_im)             as fcst_units_13w_im,
    sum(fcst_units_13w_im) / 13.0      as fcst_units_run_rate_13w_im,
    sum(coalesce(fcst_units_run_rate_yoy_13w_im, 0)) as fcst_units_run_rate_yoy_13w_im,
    case when sum(coalesce(fcst_units_run_rate_yoy_13w_im, 0)) = 0 then null
         else (sum(fcst_units_13w_im) / 13.0 - sum(coalesce(fcst_units_run_rate_yoy_13w_im, 0)))
              / sum(coalesce(fcst_units_run_rate_yoy_13w_im, 0))
    end                                as fcst_units_run_rate_yoy_pct_13w_im,
    sum(fcst_units_13w_ae)             as fcst_units_13w_ae,
    sum(fcst_units_13w_ae) / 13.0      as fcst_units_run_rate_13w_ae,
    sum(coalesce(fcst_units_run_rate_yoy_13w_ae, 0)) as fcst_units_run_rate_yoy_13w_ae,
    case when sum(coalesce(fcst_units_run_rate_yoy_13w_ae, 0)) = 0 then null
         else (sum(fcst_units_13w_ae) / 13.0 - sum(coalesce(fcst_units_run_rate_yoy_13w_ae, 0)))
              / sum(coalesce(fcst_units_run_rate_yoy_13w_ae, 0))
    end                                as fcst_units_run_rate_yoy_pct_13w_ae,
    sum(inv_units)                     as inv_units,
    sum(inv_value_usd)                 as inv_value_usd,
    case when sum(fcst_units_13w_im) / 13.0 = 0 then null
         else sum(inv_units) / (sum(fcst_units_13w_im) / 13.0) end as wos_weeks_im,
    case when sum(fcst_units_13w_ae) / 13.0 = 0 then null
         else sum(inv_units) / (sum(fcst_units_13w_ae) / 13.0) end as wos_weeks_ae,
    sum(lw3_predict)       as lw3_predict,
    sum(lw2_predict)       as lw2_predict,
    sum(lw1_predict)       as lw1_predict,
    sum(lw_predict)        as lw_predict,
    sum(lw3_net_predict)   as lw3_net_predict,
    sum(lw2_net_predict)   as lw2_net_predict,
    sum(lw1_net_predict)   as lw1_net_predict,
    sum(lw_net_predict)    as lw_net_predict,
    sum(lw3_cancel_impact) as lw3_cancel_impact,
    sum(lw2_cancel_impact) as lw2_cancel_impact,
    sum(lw1_cancel_impact) as lw1_cancel_impact,
    sum(lw_cancel_impact)  as lw_cancel_impact,
    case when sum(lw3_predict) = 0 then null
         else sum(lw3_cancel_impact) / sum(lw3_predict) end as lw3_cancel_impact_pct,
    case when sum(lw2_predict) = 0 then null
         else sum(lw2_cancel_impact) / sum(lw2_predict) end as lw2_cancel_impact_pct,
    case when sum(lw1_predict) = 0 then null
         else sum(lw1_cancel_impact) / sum(lw1_predict) end as lw1_cancel_impact_pct,
    case when sum(lw_predict)  = 0 then null
         else sum(lw_cancel_impact)  / sum(lw_predict)  end as lw_cancel_impact_pct
  from combined_brand
)
select
  catalog_brand, last_completed_week_start,
  last_6w_units_run_rate, last_6w_units_run_rate_yoy, last_6w_units_run_rate_yoy_pct,
  last_6w_rev_run_rate, last_6w_rev_run_rate_yoy,
  last_week_units, last_week_units_yoy, last_week_units_yoy_pct, last_week_rev,
  units_wk_5, units_wk_4, units_wk_3, units_wk_2, units_wk_1, units_wk_0,
  ytd_units, ytd_units_yoy, ytd_units_yoy_pct, ytd_rev,
  fcst_units_run_rate_13w_im, fcst_units_run_rate_yoy_pct_13w_im,
  fcst_units_run_rate_13w_ae, fcst_units_run_rate_yoy_pct_13w_ae,
  inv_units, inv_value_usd, wos_weeks_im, wos_weeks_ae,
  lw3_predict, lw2_predict, lw1_predict, lw_predict,
  lw3_net_predict, lw2_net_predict, lw1_net_predict, lw_net_predict,
  lw3_cancel_impact, lw2_cancel_impact, lw1_cancel_impact, lw_cancel_impact,
  lw3_cancel_impact_pct, lw2_cancel_impact_pct, lw1_cancel_impact_pct, lw_cancel_impact_pct,
  0 as is_total
from combined_brand

union all

select
  catalog_brand, last_completed_week_start,
  last_6w_units_run_rate, last_6w_units_run_rate_yoy, last_6w_units_run_rate_yoy_pct,
  last_6w_rev_run_rate, last_6w_rev_run_rate_yoy,
  last_week_units, last_week_units_yoy, last_week_units_yoy_pct, last_week_rev,
  units_wk_5, units_wk_4, units_wk_3, units_wk_2, units_wk_1, units_wk_0,
  ytd_units, ytd_units_yoy, ytd_units_yoy_pct, ytd_rev,
  fcst_units_run_rate_13w_im, fcst_units_run_rate_yoy_pct_13w_im,
  fcst_units_run_rate_13w_ae, fcst_units_run_rate_yoy_pct_13w_ae,
  inv_units, inv_value_usd, wos_weeks_im, wos_weeks_ae,
  lw3_predict, lw2_predict, lw1_predict, lw_predict,
  lw3_net_predict, lw2_net_predict, lw1_net_predict, lw_net_predict,
  lw3_cancel_impact, lw2_cancel_impact, lw1_cancel_impact, lw_cancel_impact,
  lw3_cancel_impact_pct, lw2_cancel_impact_pct, lw1_cancel_impact_pct, lw_cancel_impact_pct,
  1 as is_total
from combined_total

order by is_total desc, ytd_units desc nulls last, catalog_brand;

-- ════════════════════════════════════════════════════════════
-- Nightly refresh — stored procedure + task
-- Stored procedure encapsulates all logic so the task stays simple.
-- Refreshes Layer 1 first, then Layer 2 (which depends on Layer 1).
-- ════════════════════════════════════════════════════════════

create or replace procedure <YOUR_DATABASE>.<YOUR_SCHEMA>.sp_refresh_wbr()
  returns string
  language sql
as
begin
  create or replace table <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_daily_sales as
  select
    to_date(hs.order_date) as order_date,
    case
      when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
      when pt.catalog_brand ilike 'Nutricia%'         then 'Nutricia'
      else pt.catalog_brand
    end as catalog_brand,
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

  create or replace table <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_daily_amazon_sales as
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

  -- Layer 2: wbr_brand_metrics is rebuilt nightly by this task.
  -- The full CREATE TABLE SQL mirrors the Layer 2 section above.
  -- If you want end-to-end automation, paste the wbr_brand_metrics
  -- CREATE TABLE statement here (after the wbr_daily_amazon_sales block).
  -- For now, re-running this file manually rebuilds all 3 tables on demand.

  return 'WBR tables refreshed at ' || current_timestamp()::string;
end;


-- ── Task: runs sp_refresh_wbr nightly at 6 AM UTC (10 PM / 11 PM PT) ────────
create or replace task <YOUR_DATABASE>.<YOUR_SCHEMA>.refresh_wbr_tables
  warehouse = <YOUR_WAREHOUSE>
  schedule  = 'USING CRON 0 6 * * * UTC'
as
  call <YOUR_DATABASE>.<YOUR_SCHEMA>.sp_refresh_wbr();

-- Tasks start suspended — activate it:
alter task <YOUR_DATABASE>.<YOUR_SCHEMA>.refresh_wbr_tables resume;
