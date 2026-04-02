"""Pattern WBR — Streamlit Dashboard"""
import streamlit as st
import pandas as pd
import plotly.graph_objects as go
from datetime import datetime, timedelta

from snowflake_conn import run_query
from queries import QUERY_WBR_MAIN, QUERY_CANCELLATIONS, QUERY_AMAZON

# ── page config ───────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="Pattern WBR",
    page_icon="📦",
    layout="wide",
    initial_sidebar_state="expanded",
)

st.markdown("""
<style>
  [data-testid="stMetricValue"] { font-size: 1.6rem; }
  [data-testid="stMetricDelta"] { font-size: 0.85rem; }
  .block-container { padding-top: 1.5rem; }
</style>
""", unsafe_allow_html=True)

# ── helpers ───────────────────────────────────────────────────────────────────
def fmt_units(n):
    if pd.isna(n): return "—"
    n = float(n)
    if abs(n) >= 1_000_000: return f"{n/1_000_000:.2f}M"
    if abs(n) >= 1_000:     return f"{n/1_000:.1f}K"
    return f"{int(n):,}"

def fmt_dollars(n):
    if pd.isna(n): return "—"
    n = float(n)
    if abs(n) >= 1_000_000: return f"${n/1_000_000:.1f}M"
    if abs(n) >= 1_000:     return f"${n/1_000:.0f}K"
    return f"${n:,.0f}"

def fmt_pct(n):
    if pd.isna(n): return None
    return f"{float(n)*100:+.1f}%"

def delta_color(n):
    """Return 'normal' (green up) or 'inverse' (red up) — both handled by st.metric."""
    return "normal"

def wos_color(n):
    if pd.isna(n): return "🟡"
    n = float(n)
    if n < 6:  return "🔴"
    if n > 16: return "🟡"
    return "🟢"

CHART_COLORS = {
    "primary": "#6366f1",
    "blue":    "#38bdf8",
    "red":     "#ef4444",
    "green":   "#22c55e",
    "muted":   "#64748b",
}

PLOTLY_LAYOUT = dict(
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    font=dict(color="#e2e8f0", size=11),
    margin=dict(l=10, r=10, t=30, b=10),
    xaxis=dict(gridcolor="#2a2d3a", tickfont=dict(size=10)),
    yaxis=dict(gridcolor="#2a2d3a", tickfont=dict(size=10)),
    showlegend=False,
    height=200,
)

# ── sidebar filters ───────────────────────────────────────────────────────────
with st.sidebar:
    st.title("Pattern WBR")

    if st.button("🔄  Refresh data", use_container_width=True):
        run_query.clear()
        st.rerun()

    st.divider()
    st.subheader("Filters")

    lookback_days = st.slider(
        "Daily charts — lookback (days)", min_value=14, max_value=84, value=28, step=7
    )
    brand_filter_input = st.text_input("Search brands", placeholder="e.g. Nike, Adidas…")
    top_n = st.selectbox("Show top N brands", [10, 25, 50, 100, "All"], index=1)

# ── load data ─────────────────────────────────────────────────────────────────
with st.spinner("Loading WBR data…"):
    wbr_raw  = run_query(QUERY_WBR_MAIN)
    canc_raw = run_query(QUERY_CANCELLATIONS)
    amz_raw  = run_query(QUERY_AMAZON)

# ── parse / type-cast ─────────────────────────────────────────────────────────
numeric_cols = [
    "LAST_6W_UNITS_RUN_RATE", "LAST_6W_UNITS_RUN_RATE_YOY", "LAST_6W_UNITS_RUN_RATE_YOY_PCT",
    "LAST_6W_REV_RUN_RATE",
    "LAST_WEEK_UNITS", "LAST_WEEK_UNITS_YOY", "LAST_WEEK_UNITS_YOY_PCT", "LAST_WEEK_REV",
    "UNITS_WK_5","UNITS_WK_4","UNITS_WK_3","UNITS_WK_2","UNITS_WK_1","UNITS_WK_0",
    "YTD_UNITS","YTD_UNITS_YOY","YTD_UNITS_YOY_PCT","YTD_REV",
    "FCST_UNITS_RUN_RATE_13W_IM","FCST_UNITS_RUN_RATE_YOY_PCT_13W_IM",
    "FCST_UNITS_RUN_RATE_13W_AE","FCST_UNITS_RUN_RATE_YOY_PCT_13W_AE",
    "INV_UNITS","INV_VALUE_USD","WOS_WEEKS_IM","WOS_WEEKS_AE",
]
for col in numeric_cols:
    if col in wbr_raw.columns:
        wbr_raw[col] = pd.to_numeric(wbr_raw[col], errors="coerce")

wbr_raw["LAST_COMPLETED_WEEK_START"] = pd.to_datetime(
    wbr_raw["LAST_COMPLETED_WEEK_START"], errors="coerce"
)

canc_raw["ORDER_DATE_PST"] = pd.to_datetime(canc_raw["ORDER_DATE_PST"], errors="coerce")
canc_raw["TOT_QUANTITY"]   = pd.to_numeric(canc_raw["TOT_QUANTITY"], errors="coerce")

amz_raw["ORDER_DATE"]        = pd.to_datetime(amz_raw["ORDER_DATE"], errors="coerce")
amz_raw["QUANTITY_SOLD"]     = pd.to_numeric(amz_raw["QUANTITY_SOLD"], errors="coerce")
amz_raw["CONVERTED_REVENUE"] = pd.to_numeric(amz_raw["CONVERTED_REVENUE"], errors="coerce")

# ── split All Brands vs brand rows ────────────────────────────────────────────
totals = wbr_raw[wbr_raw["CATALOG_BRAND"] == "All Brands"].iloc[0]

brands_df = wbr_raw[wbr_raw["CATALOG_BRAND"] != "All Brands"].copy()

# brand search filter
if brand_filter_input.strip():
    terms = [t.strip().lower() for t in brand_filter_input.split(",") if t.strip()]
    mask = brands_df["CATALOG_BRAND"].str.lower().apply(
        lambda x: any(t in x for t in terms)
    )
    brands_df = brands_df[mask]

# top-N filter
if top_n != "All":
    brands_df = brands_df.nlargest(int(top_n), "YTD_UNITS")

# ── week label ────────────────────────────────────────────────────────────────
week_dt = totals["LAST_COMPLETED_WEEK_START"]
week_label = f"Week of {week_dt.strftime('%b %-d, %Y')}" if pd.notna(week_dt) else "N/A"

# ── header ────────────────────────────────────────────────────────────────────
st.header(f"Pattern — Weekly Business Review")
st.caption(f"{week_label}  ·  Americas Units  ·  Data refreshed {datetime.now().strftime('%Y-%m-%d %H:%M')}")
st.divider()

# ── KPI row ───────────────────────────────────────────────────────────────────
k1, k2, k3, k4, k5, k6 = st.columns(6)

k1.metric("Last Week Units",    fmt_units(totals["LAST_WEEK_UNITS"]),
          delta=fmt_pct(totals["LAST_WEEK_UNITS_YOY_PCT"]))
k2.metric("L6W Run Rate",       fmt_units(totals["LAST_6W_UNITS_RUN_RATE"]),
          delta=fmt_pct(totals["LAST_6W_UNITS_RUN_RATE_YOY_PCT"]))
k3.metric("YTD Units",          fmt_units(totals["YTD_UNITS"]),
          delta=fmt_pct(totals["YTD_UNITS_YOY_PCT"]))
k4.metric("IM Forecast 13W RR", fmt_units(totals["FCST_UNITS_RUN_RATE_13W_IM"]),
          delta=fmt_pct(totals["FCST_UNITS_RUN_RATE_YOY_PCT_13W_IM"]))
k5.metric("AE Forecast 13W RR", fmt_units(totals["FCST_UNITS_RUN_RATE_13W_AE"]),
          delta=fmt_pct(totals["FCST_UNITS_RUN_RATE_YOY_PCT_13W_AE"]))

# cancel rate from canc data
max_canc_date = canc_raw["ORDER_DATE_PST"].max()
l4w_canc = canc_raw[canc_raw["ORDER_DATE_PST"] >= max_canc_date - timedelta(days=27)]
shipped   = l4w_canc[l4w_canc["STATUS"] == "Shipped"]["TOT_QUANTITY"].sum()
cancelled = l4w_canc[l4w_canc["STATUS"] == "Cancelled"]["TOT_QUANTITY"].sum()
cancel_rate = cancelled / (shipped + cancelled) if (shipped + cancelled) > 0 else 0
k6.metric("L4W Cancel Rate", f"{cancel_rate:.1%}", delta=None)

st.divider()

# ── charts row ────────────────────────────────────────────────────────────────
c1, c2, c3 = st.columns(3)

# ── chart 1: weekly units trend ──
with c1:
    st.markdown("**Weekly Units — Last 6 Weeks**")
    if pd.notna(week_dt):
        w_labels, w_units = [], []
        for i in range(5, -1, -1):
            col = f"UNITS_WK_{i}"
            dt  = week_dt - timedelta(weeks=i)
            w_labels.append(dt.strftime("%-m/%-d"))
            w_units.append(float(totals[col]) if col in totals.index and pd.notna(totals[col]) else 0)

        fig = go.Figure(go.Bar(
            x=w_labels, y=w_units,
            marker_color=CHART_COLORS["primary"],
            marker_line_width=0,
        ))
        fig.update_layout(**PLOTLY_LAYOUT)
        st.plotly_chart(fig, use_container_width=True)

# ── chart 2: Amazon daily units ──
with c2:
    st.markdown("**Amazon Daily Units**")
    amz_cutoff = amz_raw["ORDER_DATE"].max() - timedelta(days=lookback_days - 1)
    amz_daily  = (
        amz_raw[amz_raw["ORDER_DATE"] >= amz_cutoff]
        .groupby("ORDER_DATE")
        .agg(QUANTITY_SOLD=("QUANTITY_SOLD", "sum"))
        .reset_index()
        .sort_values("ORDER_DATE")
    )
    fig2 = go.Figure(go.Scatter(
        x=amz_daily["ORDER_DATE"],
        y=amz_daily["QUANTITY_SOLD"],
        mode="lines",
        fill="tozeroy",
        line=dict(color=CHART_COLORS["blue"], width=2),
        fillcolor="rgba(56,189,248,0.1)",
    ))
    fig2.update_layout(**PLOTLY_LAYOUT)
    st.plotly_chart(fig2, use_container_width=True)

# ── chart 3: daily cancel rate ──
with c3:
    st.markdown("**Daily Cancel Rate**")
    canc_cutoff = max_canc_date - timedelta(days=lookback_days - 1)
    daily = (
        canc_raw[canc_raw["ORDER_DATE_PST"] >= canc_cutoff]
        .groupby(["ORDER_DATE_PST", "STATUS"])["TOT_QUANTITY"]
        .sum()
        .unstack(fill_value=0)
        .reset_index()
    )
    if "Shipped" in daily.columns and "Cancelled" in daily.columns:
        daily["rate"] = daily["Cancelled"] / (daily["Shipped"] + daily["Cancelled"])
        fig3 = go.Figure(go.Scatter(
            x=daily["ORDER_DATE_PST"],
            y=daily["rate"] * 100,
            mode="lines",
            fill="tozeroy",
            line=dict(color=CHART_COLORS["red"], width=2),
            fillcolor="rgba(239,68,68,0.1)",
        ))
        fig3.update_layout(**{
            **PLOTLY_LAYOUT,
            "yaxis": {**PLOTLY_LAYOUT["yaxis"], "ticksuffix": "%"},
        })
        st.plotly_chart(fig3, use_container_width=True)

st.divider()

# ── brand filter UI (above table) ────────────────────────────────────────────
with st.expander("⚙️  Table options", expanded=False):
    col_a, col_b = st.columns(2)
    sort_col = col_a.selectbox(
        "Sort by",
        ["YTD_UNITS", "LAST_WEEK_UNITS", "LAST_6W_UNITS_RUN_RATE",
         "FCST_UNITS_RUN_RATE_13W_IM", "WOS_WEEKS_IM"],
        index=0,
    )
    show_rev = col_b.checkbox("Show revenue columns", value=False)

brands_sorted = brands_df.sort_values(sort_col, ascending=False, na_position="last")

# ── brand table ───────────────────────────────────────────────────────────────
st.markdown(f"**Brand Performance — {len(brands_sorted)} brands**")

table_cols = {
    "Brand":         "CATALOG_BRAND",
    "LW Units":      "LAST_WEEK_UNITS",
    "LW YoY":        "LAST_WEEK_UNITS_YOY_PCT",
    "L6W Run Rate":  "LAST_6W_UNITS_RUN_RATE",
    "L6W YoY":       "LAST_6W_UNITS_RUN_RATE_YOY_PCT",
    "YTD Units":     "YTD_UNITS",
    "YTD YoY":       "YTD_UNITS_YOY_PCT",
    "IM F13W RR":    "FCST_UNITS_RUN_RATE_13W_IM",
    "IM Fcst YoY":   "FCST_UNITS_RUN_RATE_YOY_PCT_13W_IM",
    "AE F13W RR":    "FCST_UNITS_RUN_RATE_13W_AE",
    "AE Fcst YoY":   "FCST_UNITS_RUN_RATE_YOY_PCT_13W_AE",
    "Inventory $":   "INV_VALUE_USD",
    "WOS (IM)":      "WOS_WEEKS_IM",
}
if show_rev:
    table_cols["LW Rev"]   = "LAST_WEEK_REV"
    table_cols["L6W Rev"]  = "LAST_6W_REV_RUN_RATE"
    table_cols["YTD Rev"]  = "YTD_REV"

display = brands_sorted[[c for c in table_cols.values() if c in brands_sorted.columns]].copy()
display.columns = [k for k, v in table_cols.items() if v in brands_sorted.columns]

# format for display
pct_cols  = [c for c in display.columns if "YoY" in c]
unit_cols = [c for c in display.columns if "Units" in c or "Run Rate" in c or "RR" in c]
dollar_cols = [c for c in display.columns if "$" in c or "Rev" in c]

def style_table(df):
    styled = df.style

    for col in pct_cols:
        styled = styled.map(
            lambda v: (
                "color: #22c55e" if isinstance(v, str) and v.startswith("+")
                else "color: #ef4444" if isinstance(v, str) and v.startswith("-")
                else ""
            ),
            subset=[col],
        )
    return styled

# format columns
for col in pct_cols:
    if col in display.columns:
        display[col] = display[col].apply(lambda x: fmt_pct(x) if pd.notna(x) else "—")
for col in unit_cols:
    if col in display.columns:
        display[col] = display[col].apply(fmt_units)
for col in dollar_cols:
    if col in display.columns:
        display[col] = display[col].apply(fmt_dollars)
if "WOS (IM)" in display.columns:
    def fmt_wos(x):
        if pd.isna(x): return "—"
        icon = wos_color(x)
        return f"{icon} {int(float(x))}"
    display["WOS (IM)"] = brands_sorted["WOS_WEEKS_IM"].apply(fmt_wos)

st.dataframe(
    display,
    use_container_width=True,
    hide_index=True,
    height=min(600, 38 + 35 * len(display)),
)

st.divider()

# ── cancellation drill-down ───────────────────────────────────────────────────
with st.expander("🔍  Cancellation detail by brand"):
    canc_brands = sorted(canc_raw["PARTNER_BRAND"].dropna().unique())
    sel_brands  = st.multiselect("Filter brands", canc_brands, default=[])
    canc_view   = canc_raw if not sel_brands else canc_raw[canc_raw["PARTNER_BRAND"].isin(sel_brands)]

    canc_cutoff2 = max_canc_date - timedelta(days=lookback_days - 1)
    canc_view    = canc_view[canc_view["ORDER_DATE_PST"] >= canc_cutoff2]

    pivot = (
        canc_view.groupby(["PARTNER_BRAND", "STATUS"])["TOT_QUANTITY"]
        .sum().unstack(fill_value=0).reset_index()
    )
    if "Shipped" in pivot.columns and "Cancelled" in pivot.columns:
        pivot["Cancel Rate"] = (
            pivot["Cancelled"] / (pivot["Shipped"] + pivot["Cancelled"])
        ).map(lambda x: f"{x:.1%}")
    st.dataframe(pivot, use_container_width=True, hide_index=True)

# ── Amazon drill-down ─────────────────────────────────────────────────────────
with st.expander("🛒  Amazon detail by brand"):
    amz_brands  = sorted(amz_raw["CATALOG_BRAND"].dropna().unique())
    sel_amz     = st.multiselect("Filter brands ", amz_brands, default=[])
    amz_view    = amz_raw if not sel_amz else amz_raw[amz_raw["CATALOG_BRAND"].isin(sel_amz)]

    amz_brand_daily = (
        amz_view[amz_view["ORDER_DATE"] >= amz_raw["ORDER_DATE"].max() - timedelta(days=lookback_days - 1)]
        .groupby(["ORDER_DATE", "CATALOG_BRAND"])
        .agg(Units=("QUANTITY_SOLD", "sum"), Revenue=("CONVERTED_REVENUE", "sum"))
        .reset_index()
    )
    fig_amz = go.Figure()
    for brand in amz_brand_daily["CATALOG_BRAND"].unique()[:20]:  # cap at 20 lines
        sub = amz_brand_daily[amz_brand_daily["CATALOG_BRAND"] == brand]
        fig_amz.add_trace(go.Scatter(
            x=sub["ORDER_DATE"], y=sub["Units"],
            mode="lines", name=brand, line=dict(width=1.5),
        ))
    fig_amz.update_layout(
        **{**PLOTLY_LAYOUT, "height": 300, "showlegend": True,
           "legend": dict(font=dict(size=9), orientation="v")},
    )
    st.plotly_chart(fig_amz, use_container_width=True)
