-- One row per order (99,441): status, delivery metrics, customer location, item/payment/review summaries; missing pieces kept as NULL and flagged.
CREATE OR REPLACE TABLE `olist-analytics-510317.analytics.orders_enriched` AS
SELECT
  o.order_id,
  o.customer_id,
  c.customer_unique_id,
  c.customer_city,
  c.customer_state,
  o.order_status,
  o.order_purchase_timestamp,
  DATE_TRUNC(DATE(o.order_purchase_timestamp), MONTH) AS purchase_month,
  o.has_valid_delivery,
  o.delivery_days,
  o.is_late,
  i.n_items,
  i.n_distinct_products,
  i.n_sellers,
  i.items_revenue,
  i.freight_total,
  p.total_payment_value,
  p.max_installments,
  p.paid_with_credit_card,
  p.paid_with_voucher,
  r.avg_review_score,
  r.n_reviews,
  (i.order_id IS NOT NULL) AS has_items,
  (p.order_id IS NOT NULL) AS has_payment_record
FROM `olist-analytics-510317.staging.orders` AS o
LEFT JOIN `olist-analytics-510317.raw.customers` AS c
  ON o.customer_id = c.customer_id
LEFT JOIN `olist-analytics-510317.staging.order_items_summary` AS i
  ON o.order_id = i.order_id
LEFT JOIN `olist-analytics-510317.staging.order_payments_summary` AS p
  ON o.order_id = p.order_id
LEFT JOIN `olist-analytics-510317.staging.order_reviews` AS r
  ON o.order_id = r.order_id;


-- Check the results of the analytics table
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS unique_orders,
  COUNTIF(NOT has_items) AS orders_without_items,
  COUNTIF(NOT has_payment_record) AS orders_without_payment,
  FORMAT('%.2f', SUM(items_revenue)) AS total_item_revenue
FROM `olist-analytics-510317.analytics.orders_enriched`;
/*
Row	total_rows	unique_orders	orders_without_items	orders_without_payment	total_item_revenue
1	99441	    99441	        775	                    1	                    13591643.70
*/