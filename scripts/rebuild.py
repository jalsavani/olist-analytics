from pathlib import Path
from google.cloud import bigquery

PROJECT = "olist-analytics-510317"
SQL_DIR = Path(__file__).resolve().parent.parent / "sql"

# Scripts that build derived tables, in dependency order.
# 00-02 (setup, raw checks, profiling) are run by hand; 08 holds diagnostic checks.
BUILD_ORDER = [
    "03_staging_orders.sql",
    "04_staging_order_reviews.sql",
    "05_staging_products.sql",
    "06_staging_order_items.sql",
    "07_staging_order_payments.sql",
    "09_analytics_orders_enriched.sql",
]


def main():
    client = bigquery.Client(project=PROJECT)

    for name in BUILD_ORDER:
        print(f"Running {name} ...", end=" ", flush=True)
        client.query((SQL_DIR / name).read_text()).result()
        print("done")

    row = list(client.query(f"""
        SELECT COUNT(*) AS n_rows,
               COUNT(DISTINCT order_id) AS n_orders,
               ROUND(SUM(items_revenue), 2) AS revenue
        FROM `{PROJECT}.analytics.orders_enriched`
    """).result())[0]

    assert row.n_rows == 99441 and row.n_orders == 99441, "Row count mismatch"
    assert abs(row.revenue - 13591643.70) < 0.01, "Revenue mismatch"
    print(f"Checks passed: {row.n_rows:,} orders, revenue {row.revenue:,.2f}")


if __name__ == "__main__":
    main()