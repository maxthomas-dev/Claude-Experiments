with allowed_marketplaces as (
  select column1 as marketplace_name from values
    ('Amazon.ca'), ('Amazon.com'), ('Amazon.com.br'), ('Amazon.com.mx'),
    ('Ebay US'), ('Kohl''s'), ('Kroger.com'), ('Macys.com'),
    ('Mercado Libre'), ('Shopify US'), ('Target+'), ('TikTok US'),
    ('Walmart CA'), ('Walmart US')
),
anchor as (
  select
    to_date(dateadd(day, -dayofweek(current_date), current_date)) as this_week_start,
    to_date(dateadd(week, -1, dateadd(day, -dayofweek(current_date), current_date))) as last_week_start
),
ranges as (
  select
    a.last_week_start,
    to_date(dateadd(day, 6, a.last_week_start)) as last_week_end,
    to_date(dateadd(week, -5, a.last_week_start)) as start_6w,
    to_date(dateadd(week, -52, dateadd(week, -5, a.last_week_start))) as start_6w_yoy,
    to_date(dateadd(week, -52, a.last_week_start)) as end_6w_yoy,
    to_date(date_trunc(year, dateadd(day, 6, a.last_week_start))) as ytd_start,
    to_date(dateadd(year, -1, date_trunc(year, dateadd(day, 6, a.last_week_start)))) as ytd_start_yoy,
    to_date(dateadd(year, -1, to_date(dateadd(day, 6, a.last_week_start)))) as last_week_end_yoy,
    to_date(dateadd(week, 1, a.this_week_start)) as start_13w,
    to_date(dateadd(week, 14, a.this_week_start)) as end_13w_excl
  from anchor a
),
catalog_listings as (
  select
    l.listing_id,
    case
      when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
      when pt.catalog_brand ilike 'Nutricia%' then 'Nutricia'
      else pt.catalog_brand
    end as catalog_brand
  from analytics_db.stg_catalog.stg_catalog__listings l
  left join pattern_db.public.product_catalog_listing_prices lp on lp.l_id = l.id
  left join analytics_db.stg_catalog.stg_catalog__products p on p.id = l.product_id
  left join pattern_db.public.product_catalog_brand_hierarchy pt
    on pt.catalog_brand_id = p.partner_id and is_terminal_level = true
),
actuals_sales_cte as (
  select
    to_date(hs.order_date) as order_date,
    cl.catalog_brand,
    hs.converted_revenue,
    hs.quantity
  from pattern_db.public.hourly_sales hs
  left join catalog_listings cl on hs.listing_id = cl.listing_id
  where hs.country_code in ('US','CA','MX','BR')
),
weekly_actuals as (
  select
    to_date(dateadd(day, -dayofweek(order_date), order_date)) as week_start_date,
    catalog_brand,
    sum(converted_revenue) as revenue,
    sum(quantity) as units
  from actuals_sales_cte
  group by 1, 2
),
-- UPDATED: add discrete week columns for the last 6 completed weeks
metrics_wk_brand as (
  select
    w.catalog_brand,
    r.last_week_start as last_completed_week_start,

    -- Keep existing L6W run-rate calcs (not shown in final output)
    sum(case when w.week_start_date between r.start_6w and r.last_week_start then w.revenue else 0 end)/6.0 as last_6w_rev_run_rate,
    sum(case when w.week_start_date between r.start_6w and r.last_week_start then w.units else 0 end)/6.0 as last_6w_units_run_rate,
    sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy then w.revenue else 0 end)/6.0 as last_6w_rev_run_rate_yoy,
    sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy then w.units else 0 end)/6.0 as last_6w_units_run_rate_yoy,
    nullif(
      (sum(case when w.week_start_date between r.start_6w and r.last_week_start then w.revenue else 0 end)/6.0) -
      (sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy then w.revenue else 0 end)/6.0),
    0) / nullif((sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy then w.revenue else 0 end)/6.0), 0) as last_6w_rev_run_rate_yoy_pct,
    nullif(
      (sum(case when w.week_start_date between r.start_6w and r.last_week_start then w.units else 0 end)/6.0) -
      (sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy then w.units else 0 end)/6.0),
    0) / nullif((sum(case when w.week_start_date between r.start_6w_yoy and r.end_6w_yoy then w.units else 0 end)/6.0), 0) as last_6w_units_run_rate_yoy_pct,

    -- Existing last-week summary
    sum(case when w.week_start_date = r.last_week_start then w.revenue else 0 end) as last_week_rev,
    sum(case when w.week_start_date = r.last_week_start then w.units else 0 end) as last_week_units,
    sum(case when w.week_start_date = dateadd(week, -52, r.last_week_start) then w.revenue else 0 end) as last_week_rev_yoy,
    sum(case when w.week_start_date = dateadd(week, -52, r.last_week_start) then w.units else 0 end) as last_week_units_yoy,
    nullif(
      sum(case when w.week_start_date = r.last_week_start then w.revenue else 0 end) -
      sum(case when w.week_start_date = dateadd(week, -52, r.last_week_start) then w.revenue else 0 end),
    0) / nullif(sum(case when w.week_start_date = dateadd(week, -52, r.last_week_start) then w.revenue else 0 end), 0) as last_week_rev_yoy_pct,
    nullif(
      sum(case when w.week_start_date = r.last_week_start then w.units else 0 end) -
      sum(case when w.week_start_date = dateadd(week, -52, r.last_week_start) then w.units else 0 end),
    0) / nullif(sum(case when w.week_start_date = dateadd(week, -52, r.last_week_start) then w.units else 0 end), 0) as last_week_units_yoy_pct,

    -- NEW: six discrete weeks (wk_0 = last week, wk_5 = five weeks before last)
    sum(case when w.week_start_date = dateadd(week, -5, r.last_week_start) then w.revenue else 0 end) as rev_wk_5,
    sum(case when w.week_start_date = dateadd(week, -4, r.last_week_start) then w.revenue else 0 end) as rev_wk_4,
    sum(case when w.week_start_date = dateadd(week, -3, r.last_week_start) then w.revenue else 0 end) as rev_wk_3,
    sum(case when w.week_start_date = dateadd(week, -2, r.last_week_start) then w.revenue else 0 end) as rev_wk_2,
    sum(case when w.week_start_date = dateadd(week, -1, r.last_week_start) then w.revenue else 0 end) as rev_wk_1,
    sum(case when w.week_start_date = r.last_week_start then w.revenue else 0 end) as rev_wk_0,

    sum(case when w.week_start_date = dateadd(week, -5, r.last_week_start) then w.units else 0 end) as units_wk_5,
    sum(case when w.week_start_date = dateadd(week, -4, r.last_week_start) then w.units else 0 end) as units_wk_4,
    sum(case when w.week_start_date = dateadd(week, -3, r.last_week_start) then w.units else 0 end) as units_wk_3,
    sum(case when w.week_start_date = dateadd(week, -2, r.last_week_start) then w.units else 0 end) as units_wk_2,
    sum(case when w.week_start_date = dateadd(week, -1, r.last_week_start) then w.units else 0 end) as units_wk_1,
    sum(case when w.week_start_date = r.last_week_start then w.units else 0 end) as units_wk_0

  from weekly_actuals w
  cross join ranges r
  group by 1, 2
),
ytd_daily_brand as (
  select
    s.catalog_brand,
    r.last_week_start as last_completed_week_start,
    sum(case when s.order_date between r.ytd_start and r.last_week_end then s.converted_revenue else 0 end) as ytd_rev,
    sum(case when s.order_date between r.ytd_start and r.last_week_end then s.quantity else 0 end) as ytd_units,
    sum(case when s.order_date between r.ytd_start_yoy and r.last_week_end_yoy then s.converted_revenue else 0 end) as ytd_rev_yoy,
    sum(case when s.order_date between r.ytd_start_yoy and r.last_week_end_yoy then s.quantity else 0 end) as ytd_units_yoy
  from actuals_sales_cte s
  cross join ranges r
  group by 1, 2
),
im_base_filtered as (
  select b.master_id, b.week_start, b.marketplace_id
  from pattern_db.inventory_hub.demand_forecasts b
  cross join ranges r
  where b.week_start >= r.start_13w and b.week_start < r.end_13w_excl
  group by all
),
im_all_items as (
  select b.master_id, dateadd(day, seq.seq, b.week_start) as date, b.week_start, b.marketplace_id
  from im_base_filtered b
  cross join (select 0 as seq union all select 1 union all select 2 union all select 3 union all select 4 union all select 5 union all select 6) seq
),
im_forecast as (
  select
    a.master_id,
    a.date,
    case
      when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
      when pt.catalog_brand ilike 'Nutricia%' then 'Nutricia'
      else pt.catalog_brand
    end as catalog_brand,
    (
      coalesce(df.base_rate_overwrite, df.base_rate, 0)
      + coalesce(df.promo_increase_overwrite, df.promo_increase, 0)
      + coalesce(df.seasonal_increase_overwrite, df.seasonal_increase, 0)
    ) / 7 as quantity
  from im_all_items a
  join pattern_db.inventory_hub.demand_forecasts df
    on df.master_id = a.master_id
   and df.week_start = date_trunc(week, a.date)
   and df.marketplace_id = a.marketplace_id
  left join analytics_db.stg_catalog.stg_catalog__products p on p.master_id = a.master_id
  left join pattern_db.public.product_catalog_brand_hierarchy pt on pt.catalog_brand_id = p.partner_id and is_terminal_level = true
  left join analytics_db.stg_inventory_hub.stg_inventory_hub__marketplaces mm on mm.id = a.marketplace_id
  where df.effective_end_date is null
    and exists (select 1 from allowed_marketplaces am where am.marketplace_name = mm.name)
),
im_forecast_weekly_brand as (
  select to_date(dateadd(day, -dayofweek(date), date)) as week_start_date, catalog_brand, sum(quantity) as fcst_units
  from im_forecast
  group by 1, 2
),
im_fcst_13w_brand as (
  select f.catalog_brand, sum(f.fcst_units) as fcst_units_13w_im
  from im_forecast_weekly_brand f
  cross join ranges r
  where f.week_start_date >= r.start_13w and f.week_start_date < r.end_13w_excl
  group by 1
),
act_yoy_for_fcst_13w as (
  select
    w.catalog_brand,
    sum(w.units) as units_13w_yoy_actuals
  from weekly_actuals w
  cross join ranges r
  where w.week_start_date >= dateadd(week, -52, r.start_13w)
    and w.week_start_date < dateadd(week, -52, r.end_13w_excl)
  group by 1
),
ae_bounds as (
  select
    date_trunc('month', r.start_13w) as ae_month_start,
    date_trunc('month', dateadd(day, -1, r.end_13w_excl)) as ae_last_month,
    dateadd(month, 1, date_trunc('month', dateadd(day, -1, r.end_13w_excl))) as ae_month_end_excl,
    dateadd(year, -1, date_trunc('month', r.start_13w)) as prev_month_start,
    dateadd(year, -1, dateadd(month, 1, date_trunc('month', dateadd(day, -1, r.end_13w_excl)))) as prev_month_end_excl
  from ranges r
),
ae_forecast_src as (
  select
    case
      when partner ilike 'Standard Process%' then 'Standard Process'
      when partner ilike 'Nutricia%' then 'Nutricia'
      else partner
    end as brand,
    date_trunc('month',
      coalesce(
        try_to_date(month::varchar),
        try_to_date(month::varchar, 'YYYY-MM'),
        try_to_date(month::varchar, 'YYYYMM'),
        try_to_date(month::varchar, 'MON-YYYY'),
        try_to_date(month::varchar, 'MON YYYY'),
        try_to_date(month)
      )
    ) as month_start,
    units
  from pattern_db.accounting_finance.adaptive_august_estimate_2025_units
),
ae_monthly_forecast as (
  select s.brand, s.month_start, sum(s.units) as forecast_units
  from ae_forecast_src s
  cross join ae_bounds b
  where s.month_start >= b.ae_month_start and s.month_start < b.ae_month_end_excl
  group by 1,2
),
ae_prev_daily as (
  select
    a.order_date as dt,
    a.catalog_brand as brand,
    sum(a.quantity) as qty
  from actuals_sales_cte a
  cross join ae_bounds b
  where a.order_date >= b.prev_month_start and a.order_date < b.prev_month_end_excl
  group by 1,2
),
ae_monthly_totals_prev as (
  select brand, date_trunc('month', dt) as month_start_prev, sum(qty) as month_qty
  from ae_prev_daily
  group by 1,2
),
ae_calendar_prev as (
  select s.dt
  from (
    select dateadd(day, seq4(), (select prev_month_start from ae_bounds)) as dt
    from table(generator(rowcount => 400))
  ) s
  where s.dt < (select prev_month_end_excl from ae_bounds)
),
ae_shares_brand_prev as (
  select
    mt.brand,
    date_part('month', cp.dt) as month_no,
    date_part('day', cp.dt) as day_of_month,
    case when mt.month_qty > 0 then coalesce(pd.qty, 0)::float / mt.month_qty else null end as share_brand
  from ae_monthly_totals_prev mt
  join ae_calendar_prev cp on date_trunc('month', cp.dt) = mt.month_start_prev
  left join ae_prev_daily pd on pd.brand = mt.brand and pd.dt = cp.dt
),
ae_avg_shares_prev as (
  select month_no, day_of_month, avg(share_brand) as share_all_brands
  from ae_shares_brand_prev
  where share_brand is not null
  group by 1,2
),
ae_days_horizon as (
  select
    s.d as day_yr,
    date_trunc('month', s.d) as month_start_yr,
    date_part('month', s.d) as month_no,
    date_part('day', s.d) as day_of_month,
    date_part('day', last_day(s.d)) as days_in_month_yr,
    to_date(dateadd(day, -dayofweek(s.d), s.d)) as week_start
  from (
    select dateadd(day, seq4(), (select start_13w from ranges)) as d
    from table(generator(rowcount => 120))
  ) s
  where s.d < (select end_13w_excl from ranges)
),
ae_daily_alloc as (
  select
    mf.brand,
    dh.week_start,
    mf.forecast_units * coalesce(sb.share_brand, av.share_all_brands, 1.0 / dh.days_in_month_yr) as daily_forecast_units
  from ae_days_horizon dh
  join ae_monthly_forecast mf on dh.month_start_yr = mf.month_start
  left join ae_shares_brand_prev sb
    on sb.brand = mf.brand and sb.month_no = dh.month_no and sb.day_of_month = dh.day_of_month
  left join ae_avg_shares_prev av
    on av.month_no = dh.month_no and av.day_of_month = dh.day_of_month
),
ae_weekly_forecast as (
  select brand as catalog_brand, week_start, sum(daily_forecast_units) as weekly_forecast_units
  from ae_daily_alloc
  group by 1,2
),
ae_fcst_13w_brand as (
  select w.catalog_brand, sum(w.weekly_forecast_units) as fcst_units_13w_ae
  from ae_weekly_forecast w
  cross join ranges r
  where w.week_start >= r.start_13w and w.week_start < r.end_13w_excl
  group by 1
),
inv_max as (
  select max(date) as inv_date
  from pattern_db.inventory_hub.daily_item_inventories
  where region in ('US','CA') and date <= current_date
),
inventory_base as (
  select
    i.date,
    case
      when pt.catalog_brand ilike 'Standard Process%' then 'Standard Process'
      when pt.catalog_brand ilike 'Nutricia%' then 'Nutricia'
      else pt.catalog_brand
    end as catalog_brand,
    i.quantity,
    i.inventory_value_usd
  from pattern_db.inventory_hub.daily_item_inventories i
  join inv_max m on i.date = m.inv_date
  join analytics_db.stg_catalog.stg_catalog__products pr on pr.master_id = i.master_id
  join pattern_db.public.product_catalog_brand_hierarchy pt
    on pt.catalog_brand_id = pr.partner_id and is_terminal_level = true
  left join analytics_db.stg_inventory_hub.stg_inventory_hub__subsidiaries su on su.id = i.subsidiary_id
  left join analytics_db.stg_inventory_hub.stg_inventory_hub__availability_detail_statuses ad on ad.id = i.availability_detail_status_id
  where i.region in ('US','CA')
    and su.entity not ilike '%no%ownership%'
    and ad.condition not ilike '%on%order%'
    and (i.virtual is distinct from true)
),
inventory_brand as (
  select catalog_brand, date as inv_asof_date, sum(quantity) as inv_units, sum(inventory_value_usd) as inv_value_usd
  from inventory_base
  group by 1,2
),
brands_universe as (
  select distinct catalog_brand from weekly_actuals
  union
  select distinct catalog_brand from im_forecast
  union
  select distinct brand as catalog_brand from ae_forecast_src
  union
  select distinct catalog_brand from inventory_base
),
combined_brand as (
  select
    b.catalog_brand,
    coalesce(m.last_completed_week_start, y.last_completed_week_start) as last_completed_week_start,

    coalesce(m.last_6w_rev_run_rate, 0) as last_6w_rev_run_rate,
    coalesce(m.last_6w_units_run_rate, 0) as last_6w_units_run_rate,
    coalesce(m.last_6w_rev_run_rate_yoy, 0) as last_6w_rev_run_rate_yoy,
    coalesce(m.last_6w_units_run_rate_yoy, 0) as last_6w_units_run_rate_yoy,
    m.last_6w_rev_run_rate_yoy_pct,
    m.last_6w_units_run_rate_yoy_pct,

    coalesce(m.last_week_rev, 0) as last_week_rev,
    coalesce(m.last_week_units, 0) as last_week_units,
    coalesce(m.last_week_rev_yoy, 0) as last_week_rev_yoy,
    coalesce(m.last_week_units_yoy, 0) as last_week_units_yoy,
    m.last_week_rev_yoy_pct,
    m.last_week_units_yoy_pct,

    -- NEW: discrete weeks
    coalesce(m.rev_wk_5, 0) as rev_wk_5,
    coalesce(m.rev_wk_4, 0) as rev_wk_4,
    coalesce(m.rev_wk_3, 0) as rev_wk_3,
    coalesce(m.rev_wk_2, 0) as rev_wk_2,
    coalesce(m.rev_wk_1, 0) as rev_wk_1,
    coalesce(m.rev_wk_0, 0) as rev_wk_0,
    coalesce(m.units_wk_5, 0) as units_wk_5,
    coalesce(m.units_wk_4, 0) as units_wk_4,
    coalesce(m.units_wk_3, 0) as units_wk_3,
    coalesce(m.units_wk_2, 0) as units_wk_2,
    coalesce(m.units_wk_1, 0) as units_wk_1,
    coalesce(m.units_wk_0, 0) as units_wk_0,

    coalesce(y.ytd_rev, 0) as ytd_rev,
    coalesce(y.ytd_units, 0) as ytd_units,
    coalesce(y.ytd_rev_yoy, 0) as ytd_rev_yoy,
    coalesce(y.ytd_units_yoy, 0) as ytd_units_yoy,
    case when y.ytd_rev_yoy is null or y.ytd_rev_yoy = 0 then null else (y.ytd_rev - y.ytd_rev_yoy) / y.ytd_rev_yoy end as ytd_rev_yoy_pct,
    case when y.ytd_units_yoy is null or y.ytd_units_yoy = 0 then null else (y.ytd_units - y.ytd_units_yoy) / y.ytd_units_yoy end as ytd_units_yoy_pct,

    coalesce(im.fcst_units_13w_im, 0) as fcst_units_13w_im,
    coalesce(im.fcst_units_13w_im, 0)/13.0 as fcst_units_run_rate_13w_im,
    case when a.units_13w_yoy_actuals is null then null else a.units_13w_yoy_actuals/13.0 end as fcst_units_run_rate_yoy_13w_im,
    case when a.units_13w_yoy_actuals is null or a.units_13w_yoy_actuals = 0 then null else (coalesce(im.fcst_units_13w_im,0) - a.units_13w_yoy_actuals) / a.units_13w_yoy_actuals end as fcst_units_run_rate_yoy_pct_13w_im,

    coalesce(ae.fcst_units_13w_ae, 0) as fcst_units_13w_ae,
    coalesce(ae.fcst_units_13w_ae, 0)/13.0 as fcst_units_run_rate_13w_ae,
    case when a.units_13w_yoy_actuals is null then null else a.units_13w_yoy_actuals/13.0 end as fcst_units_run_rate_yoy_13w_ae,
    case when a.units_13w_yoy_actuals is null or a.units_13w_yoy_actuals = 0 then null else (coalesce(ae.fcst_units_13w_ae,0) - a.units_13w_yoy_actuals) / a.units_13w_yoy_actuals end as fcst_units_run_rate_yoy_pct_13w_ae,

    inv.inv_asof_date,
    coalesce(inv.inv_units, 0) as inv_units,
    coalesce(inv.inv_value_usd, 0) as inv_value_usd,
    case when (coalesce(im.fcst_units_13w_im,0)/13.0) = 0 then null else coalesce(inv.inv_units,0) / (coalesce(im.fcst_units_13w_im,0)/13.0) end as wos_weeks_im,
    case when (coalesce(ae.fcst_units_13w_ae,0)/13.0) = 0 then null else coalesce(inv.inv_units,0) / (coalesce(ae.fcst_units_13w_ae,0)/13.0) end as wos_weeks_ae
  from brands_universe b
  left join metrics_wk_brand m on m.catalog_brand = b.catalog_brand
  left join ytd_daily_brand y on y.catalog_brand = b.catalog_brand
  left join im_fcst_13w_brand im on im.catalog_brand = b.catalog_brand
  left join ae_fcst_13w_brand ae on ae.catalog_brand = b.catalog_brand
  left join act_yoy_for_fcst_13w a on a.catalog_brand = b.catalog_brand
  left join inventory_brand inv on inv.catalog_brand = b.catalog_brand
),
combined_total as (
  select
    'All Brands' as catalog_brand,
    max(last_completed_week_start) as last_completed_week_start,

    sum(last_6w_rev_run_rate) as last_6w_rev_run_rate,
    sum(last_6w_units_run_rate) as last_6w_units_run_rate,
    sum(last_6w_rev_run_rate_yoy) as last_6w_rev_run_rate_yoy,
    sum(last_6w_units_run_rate_yoy) as last_6w_units_run_rate_yoy,
    case when sum(last_6w_rev_run_rate_yoy) = 0 then null else (sum(last_6w_rev_run_rate) - sum(last_6w_rev_run_rate_yoy)) / sum(last_6w_rev_run_rate_yoy) end as last_6w_rev_run_rate_yoy_pct,
    case when sum(last_6w_units_run_rate_yoy) = 0 then null else (sum(last_6w_units_run_rate) - sum(last_6w_units_run_rate_yoy)) / sum(last_6w_units_run_rate_yoy) end as last_6w_units_run_rate_yoy_pct,

    sum(last_week_rev) as last_week_rev,
    sum(last_week_units) as last_week_units,
    sum(last_week_rev_yoy) as last_week_rev_yoy,
    sum(last_week_units_yoy) as last_week_units_yoy,
    case when sum(last_week_rev_yoy) = 0 then null else (sum(last_week_rev) - sum(last_week_rev_yoy)) / sum(last_week_rev_yoy) end as last_week_rev_yoy_pct,
    case when sum(last_week_units_yoy) = 0 then null else (sum(last_week_units) - sum(last_week_units_yoy)) / sum(last_week_units_yoy) end as last_week_units_yoy_pct,

    -- NEW: discrete weeks aggregated
    sum(rev_wk_5) as rev_wk_5,
    sum(rev_wk_4) as rev_wk_4,
    sum(rev_wk_3) as rev_wk_3,
    sum(rev_wk_2) as rev_wk_2,
    sum(rev_wk_1) as rev_wk_1,
    sum(rev_wk_0) as rev_wk_0,
    sum(units_wk_5) as units_wk_5,
    sum(units_wk_4) as units_wk_4,
    sum(units_wk_3) as units_wk_3,
    sum(units_wk_2) as units_wk_2,
    sum(units_wk_1) as units_wk_1,
    sum(units_wk_0) as units_wk_0,

    sum(ytd_rev) as ytd_rev,
    sum(ytd_units) as ytd_units,
    sum(ytd_rev_yoy) as ytd_rev_yoy,
    sum(ytd_units_yoy) as ytd_units_yoy,
    case when sum(ytd_rev_yoy) = 0 then null else (sum(ytd_rev) - sum(ytd_rev_yoy)) / sum(ytd_rev_yoy) end as ytd_rev_yoy_pct,
    case when sum(ytd_units_yoy) = 0 then null else (sum(ytd_units) - sum(ytd_units_yoy)) / sum(ytd_units_yoy) end as ytd_units_yoy_pct,

    sum(fcst_units_13w_im) as fcst_units_13w_im,
    sum(fcst_units_13w_im)/13.0 as fcst_units_run_rate_13w_im,
    sum(coalesce(fcst_units_run_rate_yoy_13w_im,0)) as fcst_units_run_rate_yoy_13w_im,
    case when sum(coalesce(fcst_units_run_rate_yoy_13w_im,0)) = 0 then null else ( (sum(fcst_units_13w_im)/13.0) - sum(coalesce(fcst_units_run_rate_yoy_13w_im,0)) ) / sum(coalesce(fcst_units_run_rate_yoy_13w_im,0)) end as fcst_units_run_rate_yoy_pct_13w_im,

    sum(fcst_units_13w_ae) as fcst_units_13w_ae,
    sum(fcst_units_13w_ae)/13.0 as fcst_units_run_rate_13w_ae,
    sum(coalesce(fcst_units_run_rate_yoy_13w_ae,0)) as fcst_units_run_rate_yoy_13w_ae,
    case when sum(coalesce(fcst_units_run_rate_yoy_13w_ae,0)) = 0 then null else ( (sum(fcst_units_13w_ae)/13.0) - sum(coalesce(fcst_units_run_rate_yoy_13w_ae,0)) ) / sum(coalesce(fcst_units_run_rate_yoy_13w_ae,0)) end as fcst_units_run_rate_yoy_pct_13w_ae,

    sum(inv_units) as inv_units,
    sum(inv_value_usd) as inv_value_usd,
    case when sum(fcst_units_13w_im)/13.0 = 0 then null else sum(inv_units) / (sum(fcst_units_13w_im)/13.0) end as wos_weeks_im,
    case when sum(fcst_units_13w_ae)/13.0 = 0 then null else sum(inv_units) / (sum(fcst_units_13w_ae)/13.0) end as wos_weeks_ae
  from combined_brand
),
final_numeric as (
  select
    catalog_brand,
    last_completed_week_start,

    -- L6W run-rate fields still available but not shown later
    last_6w_rev_run_rate,
    last_6w_units_run_rate,
    last_6w_rev_run_rate_yoy,
    last_6w_units_run_rate_yoy,
    last_6w_rev_run_rate_yoy_pct,
    last_6w_units_run_rate_yoy_pct,

    last_week_rev,
    last_week_units,
    last_week_rev_yoy,
    last_week_units_yoy,
    last_week_rev_yoy_pct,
    last_week_units_yoy_pct,

    -- NEW: discrete week numerics passthrough
    rev_wk_5, rev_wk_4, rev_wk_3, rev_wk_2, rev_wk_1, rev_wk_0,
    units_wk_5, units_wk_4, units_wk_3, units_wk_2, units_wk_1, units_wk_0,

    ytd_rev,
    ytd_units,
    ytd_rev_yoy,
    ytd_units_yoy,
    ytd_rev_yoy_pct,
    ytd_units_yoy_pct,
    fcst_units_13w_im,
    fcst_units_run_rate_13w_im,
    fcst_units_run_rate_yoy_13w_im,
    fcst_units_run_rate_yoy_pct_13w_im,
    fcst_units_13w_ae,
    fcst_units_run_rate_13w_ae,
    fcst_units_run_rate_yoy_13w_ae,
    fcst_units_run_rate_yoy_pct_13w_ae,
    inv_units,
    inv_value_usd,
    wos_weeks_im,
    wos_weeks_ae,
    0 as is_total,
    ytd_units as ytd_units_for_sort
  from combined_brand

  union all

  select
    catalog_brand,
    last_completed_week_start,

    -- L6W run-rate fields still available but not shown later
    last_6w_rev_run_rate,
    last_6w_units_run_rate,
    last_6w_rev_run_rate_yoy,
    last_6w_units_run_rate_yoy,
    last_6w_rev_run_rate_yoy_pct,
    last_6w_units_run_rate_yoy_pct,

    last_week_rev,
    last_week_units,
    last_week_rev_yoy,
    last_week_units_yoy,
    last_week_rev_yoy_pct,
    last_week_units_yoy_pct,

    -- NEW: discrete week numerics passthrough
    rev_wk_5, rev_wk_4, rev_wk_3, rev_wk_2, rev_wk_1, rev_wk_0,
    units_wk_5, units_wk_4, units_wk_3, units_wk_2, units_wk_1, units_wk_0,

    ytd_rev,
    ytd_units,
    ytd_rev_yoy,
    ytd_units_yoy,
    ytd_rev_yoy_pct,
    ytd_units_yoy_pct,
    fcst_units_13w_im,
    fcst_units_run_rate_13w_im,
    fcst_units_run_rate_yoy_13w_im,
    fcst_units_run_rate_yoy_pct_13w_im,
    fcst_units_13w_ae,
    fcst_units_run_rate_13w_ae,
    fcst_units_run_rate_yoy_13w_ae,
    fcst_units_run_rate_yoy_pct_13w_ae,
    inv_units,
    inv_value_usd,
    wos_weeks_im,
    wos_weeks_ae,
    1 as is_total,
    ytd_units as ytd_units_for_sort
  from combined_total
)
select
  catalog_brand,
  last_completed_week_start,

  -- NEW: six discrete weeks, revenue then units (wk_5 = oldest, wk_0 = last week)
  to_char(round(rev_wk_5), 'FM999,999,999,999,999') as rev_wk_5,
  to_char(round(rev_wk_4), 'FM999,999,999,999,999') as rev_wk_4,
  to_char(round(rev_wk_3), 'FM999,999,999,999,999') as rev_wk_3,
  to_char(round(rev_wk_2), 'FM999,999,999,999,999') as rev_wk_2,
  to_char(round(rev_wk_1), 'FM999,999,999,999,999') as rev_wk_1,
  to_char(round(rev_wk_0), 'FM999,999,999,999,999') as rev_wk_0,

  to_char(round(units_wk_5), 'FM999,999,999,999,999') as units_wk_5,
  to_char(round(units_wk_4), 'FM999,999,999,999,999') as units_wk_4,
  to_char(round(units_wk_3), 'FM999,999,999,999,999') as units_wk_3,
  to_char(round(units_wk_2), 'FM999,999,999,999,999') as units_wk_2,
  to_char(round(units_wk_1), 'FM999,999,999,999,999') as units_wk_1,
  to_char(round(units_wk_0), 'FM999,999,999,999,999') as units_wk_0,

  -- Keep the rest of your existing columns
  to_char(round(last_week_rev) , 'FM999,999,999,999,999') as last_week_rev,
  to_char(round(last_week_units) , 'FM999,999,999,999,999') as last_week_units,
  to_char(round(last_week_rev_yoy) , 'FM999,999,999,999,999') as last_week_rev_yoy,
  to_char(round(last_week_units_yoy), 'FM999,999,999,999,999') as last_week_units_yoy,
  case when last_week_rev_yoy is null or last_week_rev_yoy = 0
    then null
    else to_char(round(100*(last_week_rev - last_week_rev_yoy)/last_week_rev_yoy), 'FM999,999,990') || '%' end
    as last_week_rev_yoy_pct,
  case when last_week_units_yoy is null or last_week_units_yoy = 0
    then null
    else to_char(round(100*(last_week_units - last_week_units_yoy)/last_week_units_yoy), 'FM999,999,990') || '%' end
    as last_week_units_yoy_pct,

  to_char(round(ytd_rev) , 'FM999,999,999,999,999') as ytd_rev,
  to_char(round(ytd_units) , 'FM999,999,999,999,999') as ytd_units,
  to_char(round(ytd_rev_yoy) , 'FM999,999,999,999,999') as ytd_rev_yoy,
  to_char(round(ytd_units_yoy), 'FM999,999,999,999,999') as ytd_units_yoy,
  case when ytd_rev_yoy is null or ytd_rev_yoy = 0
    then null
    else to_char(round(100*(ytd_rev - ytd_rev_yoy)/ytd_rev_yoy), 'FM999,999,990') || '%' end
    as ytd_rev_yoy_pct,
  case when ytd_units_yoy is null or ytd_units_yoy = 0
    then null
    else to_char(round(100*(ytd_units - ytd_units_yoy)/ytd_units_yoy), 'FM999,999,990') || '%' end
    as ytd_units_yoy_pct,

  to_char(round(fcst_units_13w_im) , 'FM999,999,999,999,999') as fcst_13w_units_total_im,
  to_char(round(fcst_units_run_rate_13w_im) , 'FM999,999,999,999,999') as fcst_13w_units_run_rate_im,
  to_char(round(fcst_units_run_rate_yoy_13w_im), 'FM999,999,999,999,999') as fcst_13w_units_run_rate_yoy_im,
  case when fcst_units_run_rate_yoy_13w_im is null or fcst_units_run_rate_yoy_13w_im = 0
    then null
    else to_char(round(100*(fcst_units_run_rate_13w_im - fcst_units_run_rate_yoy_13w_im)/fcst_units_run_rate_yoy_13w_im), 'FM999,999,990') || '%' end
    as fcst_13w_units_run_rate_yoy_pct_im,

  to_char(round(fcst_units_13w_ae) , 'FM999,999,999,999,999') as fcst_13w_units_total_ae,
  to_char(round(fcst_units_run_rate_13w_ae) , 'FM999,999,999,999,999') as fcst_13w_units_run_rate_ae,
  to_char(round(fcst_units_run_rate_yoy_13w_ae), 'FM999,999,999,999,999') as fcst_13w_units_run_rate_yoy_ae,
  case when fcst_units_run_rate_yoy_13w_ae is null or fcst_units_run_rate_yoy_13w_ae = 0
    then null
    else to_char(round(100*(fcst_units_run_rate_13w_ae - fcst_units_run_rate_yoy_13w_ae)/fcst_units_run_rate_yoy_13w_ae), 'FM999,999,990') || '%' end
    as fcst_13w_units_run_rate_yoy_pct_ae,

  to_char(round(inv_units) , 'FM999,999,999,999,999') as inventory_units,
  to_char(round(inv_value_usd), 'FM999,999,999,999,999') as inventory_value_usd,
  to_char(round(wos_weeks_im) , 'FM999,999,999,999,999') as wos_weeks_im,
  to_char(round(wos_weeks_ae) , 'FM999,999,999,999,999') as wos_weeks_ae
from final_numeric
order by
  is_total desc,
  ytd_units_for_sort desc nulls last,
  catalog_brand;