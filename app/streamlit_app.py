"""Olist analytics dashboard.

Every number shown here is read from a CSV produced by a SQL query in sql/ (see
scripts/export_dashboard_data.py) or from the ML results in ml/results/. Nothing is
typed in by hand, so the dashboard cannot drift away from the pipeline.

Run:  streamlit run app/streamlit_app.py
"""

from __future__ import annotations

import json
import os
from pathlib import Path

import altair as alt
import pandas as pd
import streamlit as st

ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = Path(os.environ.get("OLIST_DASH_DATA", ROOT / "dashboard" / "data"))
ML_DIR = Path(os.environ.get("OLIST_ML_RESULTS", ROOT / "ml" / "results"))

st.set_page_config(page_title="Olist E-Commerce Analytics", layout="wide")


@st.cache_data
def load_csv(name: str, base: str) -> pd.DataFrame | None:
    path = Path(base) / f"{name}.csv"
    return pd.read_csv(path) if path.exists() else None


def data(name: str) -> pd.DataFrame | None:
    return load_csv(name, str(DATA_DIR))


def need(df: pd.DataFrame | None, name: str) -> bool:
    """Show a helpful message when an export has not been generated yet."""
    if df is None:
        st.info(f"`{name}.csv` not found. Run `python scripts/export_dashboard_data.py` first.")
        return False
    return True


st.title("Olist E-Commerce Analytics")
st.caption(
    "Built on BigQuery from the Olist Brazilian e-commerce dataset. "
    "Revenue means item price (no freight), for orders that were not canceled or unavailable."
)

tab_rev, tab_cust, tab_del, tab_sell, tab_ml = st.tabs(
    ["Revenue", "Customers", "Delivery", "Sellers", "Late-delivery model"]
)

# ------------------------------------------------------------------ revenue
with tab_rev:
    monthly = data("monthly_revenue")
    if need(monthly, "monthly_revenue"):
        monthly["purchase_month"] = pd.to_datetime(monthly["purchase_month"])
        period = f"{monthly['purchase_month'].min():%b %Y} to {monthly['purchase_month'].max():%b %Y}"
        c1, c2, c3 = st.columns(3)
        c1.metric(f"Revenue ({period})", f"{monthly['revenue'].sum():,.0f}")
        c2.metric("Orders", f"{monthly['orders'].sum():,}")
        c3.metric("Average order value", f"{monthly['revenue'].sum() / monthly['orders'].sum():,.2f}")

        st.subheader("Monthly revenue")
        st.altair_chart(
            alt.Chart(monthly)
            .mark_bar()
            .encode(
                x=alt.X("purchase_month:T", title="Month"),
                y=alt.Y("revenue:Q", title="Revenue"),
                tooltip=["purchase_month:T", "revenue", "orders", "avg_order_value", "mom_growth_pct"],
            )
            .properties(height=320),
            width="stretch",
        )
        st.caption(
            "Only months with at least 500 orders are shown. 2016 and Sep 2018 have too few orders for meaningful trends."
        )

    left, right = st.columns(2)
    with left:
        cat = data("revenue_by_category")
        if need(cat, "revenue_by_category"):
            st.subheader("Top categories by revenue")
            st.altair_chart(
                alt.Chart(cat)
                .mark_bar()
                .encode(
                    y=alt.Y("category:N", sort="-x", title=None),
                    x=alt.X("revenue:Q", title="Revenue"),
                    tooltip=["category", "revenue", "orders", "avg_item_price"],
                )
                .properties(height=440),
                width="stretch",
            )
    with right:
        state = data("revenue_by_state")
        if need(state, "revenue_by_state"):
            st.subheader("Revenue by customer state")
            st.altair_chart(
                alt.Chart(state)
                .mark_bar()
                .encode(
                    y=alt.Y("customer_state:N", sort="-x", title=None),
                    x=alt.X("revenue:Q", title="Revenue"),
                    tooltip=["customer_state", "revenue", "orders", "avg_order_value"],
                )
                .properties(height=440),
                width="stretch",
            )

# ------------------------------------------------------------------ customers
with tab_cust:
    rep = data("repeat_purchase_rate")
    if need(rep, "repeat_purchase_rate"):
        row = rep.iloc[0]
        c1, c2, c3 = st.columns(3)
        c1.metric("Customers", f"{int(row['customers']):,}")
        c2.metric("Repeat customers", f"{int(row['repeat_customers']):,}")
        c3.metric("Repeat rate", f"{row['repeat_rate_pct']:.2f}%")
        st.caption("A customer is a unique person (customer_unique_id), not a customer_id, which is new for every order.")

    coh = data("cohort_retention")
    if need(coh, "cohort_retention"):
        st.subheader("Cohort retention (percent of each cohort that ordered again)")
        min_size = st.slider("Hide cohorts smaller than", 0, 1000, 100, step=50)
        coh = coh[coh["cohort_customers"] >= min_size].copy()
        coh["cohort"] = pd.to_datetime(coh["cohort_month"]).dt.strftime("%Y-%m")
        later = coh[coh["month_offset"] > 0]
        st.altair_chart(
            alt.Chart(later)
            .mark_rect()
            .encode(
                x=alt.X("month_offset:O", title="Months since first purchase"),
                y=alt.Y("cohort:O", title="Cohort (month of first purchase)"),
                color=alt.Color("retention_pct:Q", title="Retention %", scale=alt.Scale(scheme="blues")),
                tooltip=["cohort", "cohort_customers", "month_offset", "active_customers", "retention_pct"],
            )
            .properties(height=420),
            width="stretch",
        )
        st.caption(
            "Month 0 is omitted because it is always 100 percent. "
            "Compare cohorts at the same month offset, since newer cohorts have had less time to return."
        )

# ------------------------------------------------------------------ delivery
with tab_del:
    dstate = data("delivery_by_state")
    if need(dstate, "delivery_by_state"):
        st.subheader("Late-delivery rate by customer state")
        st.altair_chart(
            alt.Chart(dstate)
            .mark_bar()
            .encode(
                y=alt.Y("customer_state:N", sort="-x", title=None),
                x=alt.X("late_pct:Q", title="Late deliveries (%)"),
                tooltip=["customer_state", "delivered_orders", "median_days", "p95_days", "late_pct"],
            )
            .properties(height=480),
            width="stretch",
        )
        st.caption(
            "Delivery time is skewed, so the median and 95th percentile are shown in the tooltip instead of the mean."
        )

    left, right = st.columns(2)
    with left:
        dmonth = data("delivery_by_month")
        if need(dmonth, "delivery_by_month"):
            dmonth["purchase_month"] = pd.to_datetime(dmonth["purchase_month"])
            st.subheader("Late rate over time")
            st.altair_chart(
                alt.Chart(dmonth)
                .mark_line(point=True)
                .encode(
                    x=alt.X("purchase_month:T", title="Month"),
                    y=alt.Y("late_pct:Q", title="Late deliveries (%)"),
                    tooltip=["purchase_month:T", "delivered_orders", "median_days", "late_pct"],
                )
                .properties(height=300),
                width="stretch",
            )
    with right:
        rs = data("review_score_by_lateness")
        if need(rs, "review_score_by_lateness"):
            st.subheader("Review score: late versus on time")
            st.dataframe(rs, hide_index=True, width="stretch")

# ------------------------------------------------------------------ sellers
with tab_sell:
    conc = data("seller_revenue_concentration")
    if need(conc, "seller_revenue_concentration"):
        st.subheader("Revenue concentration (decile 1 = top 10 percent of sellers)")
        st.altair_chart(
            alt.Chart(conc)
            .mark_bar()
            .encode(
                x=alt.X("decile:O", title="Seller revenue decile"),
                y=alt.Y("pct_of_revenue:Q", title="Share of revenue (%)"),
                tooltip=["decile", "sellers", "revenue", "pct_of_revenue"],
            )
            .properties(height=300),
            width="stretch",
        )

    sc = data("seller_scorecard")
    if need(sc, "seller_scorecard"):
        st.subheader("Seller scorecard (sellers with 30 or more orders)")
        min_orders = st.slider("Minimum orders", 30, int(max(sc["orders"].max(), 31)), 30)
        view = sc[sc["orders"] >= min_orders]
        st.dataframe(view, hide_index=True, width="stretch")
        st.altair_chart(
            alt.Chart(view)
            .mark_circle(opacity=0.6)
            .encode(
                x=alt.X("late_pct:Q", title="Late deliveries (%)"),
                y=alt.Y("avg_review_score:Q", title="Average review score", scale=alt.Scale(zero=False)),
                size=alt.Size("revenue:Q", title="Revenue"),
                tooltip=["seller_id", "seller_state", "orders", "revenue", "avg_review_score", "late_pct"],
            )
            .properties(height=380),
            width="stretch",
        )

# ------------------------------------------------------------------ ML
with tab_ml:
    st.subheader("Predicting late deliveries")
    metrics_path = ML_DIR / "metrics.json"
    if not metrics_path.exists():
        st.info("No model results yet. Run `python ml/train_late_delivery.py` first.")
    else:
        m = json.loads(metrics_path.read_text())
        st.write(
            f"**Setup.** Time-based split: trained on orders from {m['train_period'][0][:10]} to "
            f"{m['train_period'][1][:10]} ({m['train_rows']:,} orders), tested on {m['test_period'][0][:10]} to "
            f"{m['test_period'][1][:10]} ({m['test_rows']:,} orders). Late rate was {m['late_rate_train']:.1%} in "
            f"training and {m['late_rate_test']:.1%} in the test period."
        )
        comp = pd.read_csv(ML_DIR / "model_comparison.csv")
        st.write(f"**Selected model** (best cross-validated PR AUC in the training period): `{m['selected_model']}`")
        st.dataframe(comp, hide_index=True, width="stretch")
        st.caption(
            "cv_pr_auc columns come from time-series cross-validation inside the training period. The other metrics are on the "
            "later test period. PR AUC is the main metric because late orders are a minority, so a model with no skill scores "
            "about the late rate. top10 columns show what happens if only the 10 percent highest-risk orders are flagged. "
            "Compare the cross-validated and test columns: a model that wins in validation but not on later data is a sign "
            "that conditions changed between the periods."
        )

        left, right = st.columns(2)
        with left:
            if (ML_DIR / "pr_curves.png").exists():
                st.image(str(ML_DIR / "pr_curves.png"))
        with right:
            imp_path = ML_DIR / "permutation_importance.csv"
            if imp_path.exists():
                imp = pd.read_csv(imp_path).head(10)
                st.write("**Most important features** (drop in PR AUC when shuffled)")
                st.altair_chart(
                    alt.Chart(imp)
                    .mark_bar()
                    .encode(y=alt.Y("feature:N", sort="-x", title=None), x=alt.X("importance_mean:Q", title="Importance"))
                    .properties(height=300),
                    width="stretch",
                )

        dec_path = ML_DIR / "decile_table.csv"
        if dec_path.exists():
            st.write("**Do higher predicted risks really end up late more often?**")
            dec = pd.read_csv(dec_path)
            long = dec.melt(
                id_vars="risk_decile",
                value_vars=["predicted_late_rate", "actual_late_rate"],
                var_name="measure",
                value_name="rate",
            )
            st.altair_chart(
                alt.Chart(long)
                .mark_bar()
                .encode(
                    x=alt.X("risk_decile:O", title="Risk decile (1 = highest predicted risk)"),
                    y=alt.Y("rate:Q", title="Late rate"),
                    color="measure:N",
                    xOffset="measure:N",
                )
                .properties(height=300),
                width="stretch",
            )

        st_path = ML_DIR / "state_error_analysis.csv"
        if st_path.exists():
            st.write("**Error analysis by state** (negative gap = the model under-predicts late deliveries there)")
            st.dataframe(pd.read_csv(st_path), hide_index=True, width="stretch")
