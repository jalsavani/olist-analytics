from pathlib import Path
from google.cloud import bigquery

PROJECT = "olist-analytics-510317"
DATA_DIR = Path(__file__).resolve().parent.parent / "data"

# CSV file name -> raw table name
FILES = {
    "olist_customers_dataset.csv": "customers",
    "olist_orders_dataset.csv": "orders",
    "olist_order_items_dataset.csv": "order_items",
    "olist_order_payments_dataset.csv": "order_payments",
    "olist_order_reviews_dataset.csv": "order_reviews",
    "olist_products_dataset.csv": "products",
    "olist_sellers_dataset.csv": "sellers",
    "olist_geolocation_dataset.csv": "geolocation",
    "product_category_name_translation.csv": "product_category_translation",
}


def main():
    client = bigquery.Client(project=PROJECT)
    config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        autodetect=True,
        allow_quoted_newlines=True,
        write_disposition=bigquery.WriteDisposition.WRITE_TRUNCATE,
    )

    for filename, table in FILES.items():
        path = DATA_DIR / filename
        if not path.exists():
            raise FileNotFoundError(f"Missing {path}. Download the dataset from Kaggle into data/.")
        print(f"Loading {filename} -> raw.{table} ...", end=" ", flush=True)
        with open(path, "rb") as f:
            job = client.load_table_from_file(f, f"{PROJECT}.raw.{table}", job_config=config)
        job.result()
        print(f"{job.output_rows:,} rows")


if __name__ == "__main__":
    main()