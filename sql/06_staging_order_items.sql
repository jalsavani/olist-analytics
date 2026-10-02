-- Build the two per-order summary tables (1) 
-- [check 07_staging_order_payments.sql for the second summary table]
CREATE OR REPLACE TABLE `olist-analytics-510317.staging.order_items_summary` AS
SELECT
  order_id,
  COUNT(*) AS n_items,
  COUNT(DISTINCT product_id) AS n_distinct_products,
  COUNT(DISTINCT seller_id) AS n_sellers,
  SUM(price) AS items_revenue,
  SUM(freight_value) AS freight_total
FROM `olist-analytics-510317.raw.order_items`
GROUP BY order_id;