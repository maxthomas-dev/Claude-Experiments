"""
WBR Snowflake queries — simple SELECTs from wbr_brand_metrics.

All heavy computation (WBR metrics, cancellation projections, forecasts,
inventory) happens nightly in setup_snowflake.sql.
n8n / Streamlit reads from the single output table — no complex joins at runtime.

Daily Amazon sell-through (wbr_daily_amazon_sales) is used internally by the
cancellation projection logic in setup_snowflake.sql and is no longer queried
separately — everything needed is already in wbr_brand_metrics.
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
