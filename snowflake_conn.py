"""Snowflake connection helper — cached per Streamlit session."""
import streamlit as st
import snowflake.connector
import pandas as pd


@st.cache_resource(show_spinner="Connecting to Snowflake…")
def get_connection():
    cfg = st.secrets["snowflake"]
    kwargs = dict(
        account=cfg["account"],
        user=cfg["user"],
        warehouse=cfg["warehouse"],
        database=cfg["database"],
        schema=cfg.get("schema", "PUBLIC"),
        authenticator=cfg.get("authenticator", "externalbrowser"),
    )
    if "password" in cfg:
        kwargs["password"] = cfg["password"]
    return snowflake.connector.connect(**kwargs)


@st.cache_data(ttl=3600, show_spinner="Querying Snowflake…")
def run_query(sql: str) -> pd.DataFrame:
    conn = get_connection()
    cur = conn.cursor()
    cur.execute(sql)
    cols = [d[0].upper() for d in cur.description]
    rows = cur.fetchall()
    return pd.DataFrame(rows, columns=cols)
