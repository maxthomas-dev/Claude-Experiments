"""
WBR Snowflake queries — simple SELECTs from pre-built reporting table.

All heavy computation now happens in setup_snowflake.sql (wbr_brand_metrics).
n8n / Streamlit just reads from the output table — no complex joins at runtime.
"""

# ── Query 1: Full WBR brand metrics (includes cancellation projections) ──────
# Returns one row per brand + one "All Brands" total row (is_total = 1).
# Cancellation columns: lw3/lw2/lw1/lw _predict, _net_predict,
#                       _cancel_impact, _cancel_impact_pct
QUERY_WBR_MAIN = """
select *
from <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_brand_metrics
order by is_total desc, ytd_units desc nulls last, catalog_brand
"""


# ── Query 2: Cancellation projection summary (4-week view per brand) ─────────
# Subset of wbr_brand_metrics — just the cancellation columns.
# Replaces the manual Excel Daily Cancellations workbook export.
QUERY_CANCELLATIONS = """
select
  catalog_brand,
  last_completed_week_start,
  lw3_predict,      lw2_predict,      lw1_predict,      lw_predict,
  lw3_net_predict,  lw2_net_predict,  lw1_net_predict,  lw_net_predict,
  lw3_cancel_impact, lw2_cancel_impact, lw1_cancel_impact, lw_cancel_impact,
  lw3_cancel_impact_pct, lw2_cancel_impact_pct,
  lw1_cancel_impact_pct, lw_cancel_impact_pct
from <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_brand_metrics
where is_total = 0
order by catalog_brand
"""


# ── Query 3: Daily Amazon sell-through — rolling 8-week window ───────────────
QUERY_AMAZON = """
select
  order_date,
  catalog_brand,
  converted_revenue,
  quantity_sold
from <YOUR_DATABASE>.<YOUR_SCHEMA>.wbr_daily_amazon_sales
where order_date >= dateadd(week, -8, date_trunc('week', current_date))
  and order_date <  date_trunc('week', current_date)
order by catalog_brand, order_date
"""
