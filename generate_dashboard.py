#!/usr/bin/env python3
"""
Pattern WBR Dashboard Generator
Reads 4 CSV exports and generates a self-contained HTML dashboard.
"""

import pandas as pd
import json
from datetime import datetime, timedelta
import os
import glob

# ── helpers ────────────────────────────────────────────────────────────────────

def load_csv(pattern):
    """Load the most recent CSV matching a glob pattern."""
    files = sorted(glob.glob(pattern))
    if not files:
        raise FileNotFoundError(f"No file found matching: {pattern}")
    return pd.read_csv(files[-1])

def clean_num(series):
    """Strip commas/percent signs and coerce to float."""
    if series.dtype == object or hasattr(series, 'str'):
        return pd.to_numeric(
            series.astype(str).str.replace(',', '', regex=False)
                              .str.replace('%', '', regex=False)
                              .str.strip(),
            errors='coerce'
        )
    return pd.to_numeric(series, errors='coerce')

def clean_df(df):
    """Clean all columns in a DataFrame."""
    for col in df.columns:
        if col in ('CATALOG_BRAND', 'PARTNER_BRAND', 'ORDER_DATE', 'ORDER_DATE_PST',
                   'STATUS', 'LAST_COMPLETED_WEEK_START'):
            continue
        df[col] = clean_num(df[col])
    return df

def fmt_units(n):
    if pd.isna(n): return '—'
    n = int(n)
    if abs(n) >= 1_000_000: return f'{n/1_000_000:.2f}M'
    if abs(n) >= 1_000: return f'{n/1_000:.1f}K'
    return f'{n:,}'

def fmt_dollars(n):
    if pd.isna(n): return '—'
    n = float(n)
    if abs(n) >= 1_000_000: return f'${n/1_000_000:.1f}M'
    if abs(n) >= 1_000: return f'${n/1_000:.0f}K'
    return f'${n:,.0f}'

def fmt_pct(n, already_pct=False):
    """Format a YOY pct value. If already_pct=True, n is like 41 (meaning 41%)."""
    if pd.isna(n): return '—'
    n = float(n)
    # Values in CSV are like 41 meaning 41% or 0.41 meaning 41%
    if not already_pct and abs(n) <= 5:
        n = n * 100
    return f'{n:+.0f}%'

def yoy_class(n, already_pct=False):
    if pd.isna(n): return 'neutral'
    n = float(n)
    if not already_pct and abs(n) <= 5:
        n = n * 100
    if n > 0: return 'positive'
    if n < 0: return 'negative'
    return 'neutral'

def wos_class(n):
    if pd.isna(n): return 'neutral'
    n = float(n)
    if n < 6: return 'negative'
    if n > 16: return 'warning'
    return 'positive'

# ── load & clean data ──────────────────────────────────────────────────────────

BASE = os.path.dirname(os.path.abspath(__file__))

fin_raw      = load_csv(os.path.join(BASE, 'Fin Data_*.csv'))
kurt_raw     = load_csv(os.path.join(BASE, 'Kurt SQL 2_*.csv'))
canc_raw     = load_csv(os.path.join(BASE, 'Daily Cancellations_*.csv'))
amazon_raw   = load_csv(os.path.join(BASE, 'Daily Amazon Sell through_*.csv'))

fin   = clean_df(fin_raw.copy())
kurt  = clean_df(kurt_raw.copy())
canc  = canc_raw.copy()
amz   = amazon_raw.copy()

canc['ORDER_DATE_PST'] = pd.to_datetime(canc['ORDER_DATE_PST'], errors='coerce')
canc['TOT_QUANTITY']   = clean_num(canc['TOT_QUANTITY'])
amz['ORDER_DATE']      = pd.to_datetime(amz['ORDER_DATE'], errors='coerce')
amz['QUANTITY_SOLD']   = clean_num(amz['QUANTITY_SOLD'])
amz['CONVERTED_REVENUE'] = clean_num(amz['CONVERTED_REVENUE'])

# ── summary metrics ────────────────────────────────────────────────────────────

all_brands = fin[fin['CATALOG_BRAND'] == 'All Brands'].iloc[0]
week_str = all_brands['LAST_COMPLETED_WEEK_START'] if 'LAST_COMPLETED_WEEK_START' in fin.columns else 'N/A'
try:
    week_dt = datetime.strptime(str(week_str), '%Y-%m-%d')
    week_label = f"Week of {week_dt.strftime('%b %-d, %Y')}"
except:
    week_label = str(week_str)

lw_units        = all_brands['LAST_WEEK_UNITS']
lw_yoy          = all_brands['LAST_WEEK_UNITS_YOY_PCT']
l6w_rr          = all_brands['LAST_6W_UNITS_RUN_RATE']
l6w_yoy         = all_brands['LAST_6W_UNITS_RUN_RATE_YOY_PCT']
ytd_units       = all_brands['YTD_UNITS']
ytd_yoy         = all_brands['YTD_UNITS_YOY_PCT']
fcst_im         = all_brands['FCST_13W_UNITS_RUN_RATE_IM']
fcst_im_yoy     = all_brands['FCST_13W_UNITS_RUN_RATE_YOY_PCT_IM']
fcst_ae         = all_brands['FCST_13W_UNITS_RUN_RATE_AE']
fcst_ae_yoy     = all_brands['FCST_13W_UNITS_RUN_RATE_YOY_PCT_AE']
inv_value       = all_brands['INVENTORY_VALUE_USD']
wos_im          = all_brands['WOS_WEEKS_IM']

# ── 6-week trend (All Brands) ──────────────────────────────────────────────────

kurt_all = kurt[kurt['CATALOG_BRAND'] == 'All Brands'].iloc[0]
week_start = datetime.strptime(str(kurt_all['LAST_COMPLETED_WEEK_START']), '%Y-%m-%d')
week_labels = []
week_units  = []
for i in range(5, -1, -1):
    col = f'UNITS_WK_{i}'
    dt = week_start - timedelta(weeks=i)
    week_labels.append(dt.strftime('%-m/%-d'))
    week_units.append(int(kurt_all[col]) if not pd.isna(kurt_all[col]) else 0)

# ── cancellation data ──────────────────────────────────────────────────────────

# Last 28 days for overall cancel rate
max_date = canc['ORDER_DATE_PST'].max()
l4w_canc = canc[canc['ORDER_DATE_PST'] >= max_date - timedelta(days=27)]
shipped_total   = l4w_canc[l4w_canc['STATUS'] == 'Shipped']['TOT_QUANTITY'].sum()
cancelled_total = l4w_canc[l4w_canc['STATUS'] == 'Cancelled']['TOT_QUANTITY'].sum()
cancel_rate = cancelled_total / (shipped_total + cancelled_total) if (shipped_total + cancelled_total) > 0 else 0

# Daily cancel rate for chart (last 28 days, all brands)
daily = canc.groupby(['ORDER_DATE_PST', 'STATUS'])['TOT_QUANTITY'].sum().unstack(fill_value=0)
daily = daily[daily.index >= max_date - timedelta(days=27)].copy()
if 'Shipped' in daily.columns and 'Cancelled' in daily.columns:
    daily['rate'] = daily['Cancelled'] / (daily['Shipped'] + daily['Cancelled'])
    canc_dates = [d.strftime('%-m/%-d') for d in daily.index]
    canc_rates = [round(float(r)*100, 1) for r in daily['rate']]
else:
    canc_dates = []
    canc_rates = []

# ── Amazon sell-through trend (last 28 days all brands) ───────────────────────

amz_daily = amz.groupby('ORDER_DATE').agg(
    QUANTITY_SOLD=('QUANTITY_SOLD', 'sum'),
    CONVERTED_REVENUE=('CONVERTED_REVENUE', 'sum')
).reset_index().sort_values('ORDER_DATE')
amz_max = amz_daily['ORDER_DATE'].max()
amz_recent = amz_daily[amz_daily['ORDER_DATE'] >= amz_max - timedelta(days=27)]
amz_dates  = [d.strftime('%-m/%-d') for d in amz_recent['ORDER_DATE']]
amz_units  = [int(v) for v in amz_recent['QUANTITY_SOLD']]

# ── brand table ───────────────────────────────────────────────────────────────

brands_df = fin[fin['CATALOG_BRAND'] != 'All Brands'].copy()
brands_df = brands_df.dropna(subset=['LAST_6W_UNITS_RUN_RATE'])
brands_df = brands_df.nlargest(25, 'LAST_6W_UNITS_RUN_RATE')

brand_rows = []
for _, row in brands_df.iterrows():
    brand_rows.append({
        'brand':        row['CATALOG_BRAND'],
        'lw_units':     fmt_units(row['LAST_WEEK_UNITS']),
        'lw_yoy':       fmt_pct(row['LAST_WEEK_UNITS_YOY_PCT']),
        'lw_cls':       yoy_class(row['LAST_WEEK_UNITS_YOY_PCT']),
        'l6w_rr':       fmt_units(row['LAST_6W_UNITS_RUN_RATE']),
        'l6w_yoy':      fmt_pct(row['LAST_6W_UNITS_RUN_RATE_YOY_PCT']),
        'l6w_cls':      yoy_class(row['LAST_6W_UNITS_RUN_RATE_YOY_PCT']),
        'fcst_im':      fmt_units(row['FCST_13W_UNITS_RUN_RATE_IM']),
        'fcst_yoy':     fmt_pct(row['FCST_13W_UNITS_RUN_RATE_YOY_PCT_IM']),
        'fcst_cls':     yoy_class(row['FCST_13W_UNITS_RUN_RATE_YOY_PCT_IM']),
        'inv':          fmt_dollars(row['INVENTORY_VALUE_USD']),
        'wos':          f"{int(row['WOS_WEEKS_IM'])}" if not pd.isna(row['WOS_WEEKS_IM']) else '—',
        'wos_cls':      wos_class(row['WOS_WEEKS_IM']),
    })

# ── build HTML ─────────────────────────────────────────────────────────────────

week_labels_js  = json.dumps(week_labels)
week_units_js   = json.dumps(week_units)
canc_dates_js   = json.dumps(canc_dates)
canc_rates_js   = json.dumps(canc_rates)
amz_dates_js    = json.dumps(amz_dates)
amz_units_js    = json.dumps(amz_units)

brand_rows_html = ''
for r in brand_rows:
    brand_rows_html += f"""
        <tr>
          <td class="brand-name">{r['brand']}</td>
          <td class="num">{r['lw_units']}</td>
          <td class="num yoy {r['lw_cls']}">{r['lw_yoy']}</td>
          <td class="num">{r['l6w_rr']}</td>
          <td class="num yoy {r['l6w_cls']}">{r['l6w_yoy']}</td>
          <td class="num">{r['fcst_im']}</td>
          <td class="num yoy {r['fcst_cls']}">{r['fcst_yoy']}</td>
          <td class="num">{r['inv']}</td>
          <td class="num wos {r['wos_cls']}">{r['wos']}</td>
        </tr>"""

html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Pattern WBR — {week_label}</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  :root {{
    --bg: #0f1117;
    --card: #1a1d27;
    --border: #2a2d3a;
    --text: #e2e8f0;
    --muted: #64748b;
    --accent: #6366f1;
    --green: #22c55e;
    --red: #ef4444;
    --yellow: #f59e0b;
    --blue: #38bdf8;
  }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ background: var(--bg); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 14px; }}
  .header {{ padding: 24px 32px 16px; border-bottom: 1px solid var(--border); display: flex; align-items: baseline; gap: 16px; }}
  .header h1 {{ font-size: 20px; font-weight: 700; letter-spacing: -0.3px; }}
  .header .week {{ color: var(--muted); font-size: 13px; }}
  .main {{ padding: 24px 32px; max-width: 1400px; }}

  /* KPI cards */
  .kpi-grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; margin-bottom: 28px; }}
  .kpi {{ background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 18px 20px; }}
  .kpi .label {{ color: var(--muted); font-size: 11px; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 6px; }}
  .kpi .value {{ font-size: 26px; font-weight: 700; letter-spacing: -0.5px; }}
  .kpi .sub {{ margin-top: 4px; font-size: 12px; }}

  /* charts row */
  .charts-row {{ display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 16px; margin-bottom: 28px; }}
  .chart-card {{ background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 18px 20px; }}
  .chart-card h3 {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; color: var(--muted); margin-bottom: 14px; }}
  .chart-card canvas {{ width: 100% !important; height: 150px !important; }}

  /* forecast strip */
  .forecast-strip {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-bottom: 28px; }}
  .fcst-card {{ background: var(--card); border: 1px solid var(--border); border-radius: 10px; padding: 18px 20px; }}
  .fcst-card h3 {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; color: var(--muted); margin-bottom: 12px; }}
  .fcst-row {{ display: flex; justify-content: space-between; align-items: baseline; padding: 8px 0; border-bottom: 1px solid var(--border); }}
  .fcst-row:last-child {{ border-bottom: none; }}
  .fcst-row .fcst-label {{ color: var(--muted); font-size: 12px; }}
  .fcst-row .fcst-val {{ font-weight: 600; }}

  /* brand table */
  .table-card {{ background: var(--card); border: 1px solid var(--border); border-radius: 10px; overflow: hidden; margin-bottom: 28px; }}
  .table-card h3 {{ font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; color: var(--muted); padding: 16px 20px 12px; border-bottom: 1px solid var(--border); }}
  table {{ width: 100%; border-collapse: collapse; }}
  th {{ font-size: 11px; text-transform: uppercase; letter-spacing: 0.4px; color: var(--muted); padding: 10px 14px; text-align: right; font-weight: 600; background: var(--card); border-bottom: 1px solid var(--border); }}
  th:first-child {{ text-align: left; }}
  td {{ padding: 9px 14px; border-bottom: 1px solid var(--border); font-size: 13px; text-align: right; }}
  td:first-child {{ text-align: left; }}
  tr:last-child td {{ border-bottom: none; }}
  tr:hover td {{ background: rgba(255,255,255,0.03); }}
  .brand-name {{ font-weight: 500; max-width: 200px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
  .num {{ font-variant-numeric: tabular-nums; }}
  .yoy.positive {{ color: var(--green); }}
  .yoy.negative {{ color: var(--red); }}
  .yoy.neutral  {{ color: var(--muted); }}
  .wos.positive {{ color: var(--green); font-weight: 600; }}
  .wos.negative {{ color: var(--red); font-weight: 700; }}
  .wos.warning  {{ color: var(--yellow); font-weight: 600; }}

  /* badges */
  .badge {{ display: inline-block; padding: 2px 8px; border-radius: 20px; font-size: 11px; font-weight: 600; }}
  .badge.positive {{ background: rgba(34,197,94,0.15); color: var(--green); }}
  .badge.negative {{ background: rgba(239,68,68,0.15); color: var(--red); }}

  .footer {{ padding: 16px 32px; color: var(--muted); font-size: 11px; border-top: 1px solid var(--border); }}
</style>
</head>
<body>

<div class="header">
  <h1>Pattern — Weekly Business Review</h1>
  <span class="week">{week_label} &nbsp;·&nbsp; Americas Units</span>
</div>

<div class="main">

  <!-- KPI Cards -->
  <div class="kpi-grid">
    <div class="kpi">
      <div class="label">Last Week Units</div>
      <div class="value">{fmt_units(lw_units)}</div>
      <div class="sub"><span class="badge {yoy_class(lw_yoy)}">{fmt_pct(lw_yoy)} YoY</span></div>
    </div>
    <div class="kpi">
      <div class="label">L6W Run Rate</div>
      <div class="value">{fmt_units(l6w_rr)}</div>
      <div class="sub"><span class="badge {yoy_class(l6w_yoy)}">{fmt_pct(l6w_yoy)} YoY</span></div>
    </div>
    <div class="kpi">
      <div class="label">YTD Units</div>
      <div class="value">{fmt_units(ytd_units)}</div>
      <div class="sub"><span class="badge {yoy_class(ytd_yoy)}">{fmt_pct(ytd_yoy)} YoY</span></div>
    </div>
    <div class="kpi">
      <div class="label">IM Forecast (13W RR)</div>
      <div class="value">{fmt_units(fcst_im)}</div>
      <div class="sub"><span class="badge {yoy_class(fcst_im_yoy)}">{fmt_pct(fcst_im_yoy)} YoY</span></div>
    </div>
    <div class="kpi">
      <div class="label">Total Inventory</div>
      <div class="value">{fmt_dollars(inv_value)}</div>
      <div class="sub" style="color:var(--muted)">{int(wos_im) if not pd.isna(wos_im) else '—'} WOS (IM)</div>
    </div>
    <div class="kpi">
      <div class="label">L4W Cancel Rate</div>
      <div class="value">{cancel_rate:.1%}</div>
      <div class="sub" style="color:var(--muted)">{fmt_units(cancelled_total)} cancelled units</div>
    </div>
  </div>

  <!-- Charts Row -->
  <div class="charts-row">
    <div class="chart-card">
      <h3>Weekly Units — Last 6 Weeks</h3>
      <canvas id="weeklyChart"></canvas>
    </div>
    <div class="chart-card">
      <h3>Amazon Daily Units — Last 28 Days</h3>
      <canvas id="amzChart"></canvas>
    </div>
    <div class="chart-card">
      <h3>Daily Cancel Rate — Last 28 Days</h3>
      <canvas id="cancChart"></canvas>
    </div>
  </div>

  <!-- Forecast Strip -->
  <div class="forecast-strip">
    <div class="fcst-card">
      <h3>IM Forecast — 13 Week Run Rate</h3>
      <div class="fcst-row">
        <span class="fcst-label">F13W Units RR</span>
        <span class="fcst-val">{fmt_units(fcst_im)} <span class="badge {yoy_class(fcst_im_yoy)}">{fmt_pct(fcst_im_yoy)}</span></span>
      </div>
      <div class="fcst-row">
        <span class="fcst-label">L6W Run Rate</span>
        <span class="fcst-val">{fmt_units(l6w_rr)} <span class="badge {yoy_class(l6w_yoy)}">{fmt_pct(l6w_yoy)}</span></span>
      </div>
      <div class="fcst-row">
        <span class="fcst-label">Last Week</span>
        <span class="fcst-val">{fmt_units(lw_units)} <span class="badge {yoy_class(lw_yoy)}">{fmt_pct(lw_yoy)}</span></span>
      </div>
    </div>
    <div class="fcst-card">
      <h3>AE Forecast vs IM Forecast</h3>
      <div class="fcst-row">
        <span class="fcst-label">AE F13W Units RR</span>
        <span class="fcst-val">{fmt_units(fcst_ae)} <span class="badge {yoy_class(fcst_ae_yoy)}">{fmt_pct(fcst_ae_yoy)}</span></span>
      </div>
      <div class="fcst-row">
        <span class="fcst-label">IM F13W Units RR</span>
        <span class="fcst-val">{fmt_units(fcst_im)} <span class="badge {yoy_class(fcst_im_yoy)}">{fmt_pct(fcst_im_yoy)}</span></span>
      </div>
      <div class="fcst-row">
        <span class="fcst-label">YTD Units</span>
        <span class="fcst-val">{fmt_units(ytd_units)} <span class="badge {yoy_class(ytd_yoy)}">{fmt_pct(ytd_yoy)}</span></span>
      </div>
    </div>
  </div>

  <!-- Brand Table -->
  <div class="table-card">
    <h3>Brand Performance — Top 25 by L6W Run Rate</h3>
    <table>
      <thead>
        <tr>
          <th>Brand</th>
          <th>LW Units</th>
          <th>LW YoY</th>
          <th>L6W Run Rate</th>
          <th>L6W YoY</th>
          <th>IM F13W RR</th>
          <th>Fcst YoY</th>
          <th>Inventory</th>
          <th>WOS</th>
        </tr>
      </thead>
      <tbody>
        {brand_rows_html}
      </tbody>
    </table>
  </div>

</div><!-- /main -->

<div class="footer">
  Generated {datetime.now().strftime('%Y-%m-%d %H:%M')} &nbsp;·&nbsp; Data as of {week_label}
</div>

<script>
const chartDefaults = {{
  responsive: true,
  maintainAspectRatio: false,
  plugins: {{ legend: {{ display: false }} }},
  scales: {{
    x: {{ grid: {{ color: '#2a2d3a' }}, ticks: {{ color: '#64748b', font: {{ size: 10 }} }} }},
    y: {{ grid: {{ color: '#2a2d3a' }}, ticks: {{ color: '#64748b', font: {{ size: 10 }} }} }}
  }}
}};

// Weekly units chart
new Chart(document.getElementById('weeklyChart'), {{
  type: 'bar',
  data: {{
    labels: {week_labels_js},
    datasets: [{{
      data: {week_units_js},
      backgroundColor: '#6366f1',
      borderRadius: 4,
    }}]
  }},
  options: {{ ...chartDefaults }}
}});

// Amazon daily units
new Chart(document.getElementById('amzChart'), {{
  type: 'line',
  data: {{
    labels: {amz_dates_js},
    datasets: [{{
      data: {amz_units_js},
      borderColor: '#38bdf8',
      backgroundColor: 'rgba(56,189,248,0.1)',
      borderWidth: 2,
      fill: true,
      tension: 0.3,
      pointRadius: 0,
    }}]
  }},
  options: {{ ...chartDefaults }}
}});

// Cancellation rate chart
new Chart(document.getElementById('cancChart'), {{
  type: 'line',
  data: {{
    labels: {canc_dates_js},
    datasets: [{{
      data: {canc_rates_js},
      borderColor: '#ef4444',
      backgroundColor: 'rgba(239,68,68,0.1)',
      borderWidth: 2,
      fill: true,
      tension: 0.3,
      pointRadius: 0,
    }}]
  }},
  options: {{
    ...chartDefaults,
    scales: {{
      ...chartDefaults.scales,
      y: {{
        ...chartDefaults.scales.y,
        ticks: {{
          color: '#64748b',
          font: {{ size: 10 }},
          callback: v => v + '%'
        }}
      }}
    }}
  }}
}});
</script>
</body>
</html>
"""

out_path = os.path.join(BASE, 'wbr_dashboard.html')
with open(out_path, 'w') as f:
    f.write(html)

print(f"Dashboard written to: {out_path}")
