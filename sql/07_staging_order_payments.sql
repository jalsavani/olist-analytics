-- Build the two per-order summary tables (2)
-- [check 06_staging_order_items.sql for the first summary table]
CREATE OR REPLACE TABLE `olist-analytics-510317.staging.order_payments_summary` AS
SELECT
  order_id,
  COUNT(*) AS n_payment_rows,
  COUNT(DISTINCT payment_type) AS n_payment_types,
  SUM(payment_value) AS total_payment_value,
  MAX(payment_installments) AS max_installments,
  LOGICAL_OR(payment_type = 'credit_card') AS paid_with_credit_card,
  LOGICAL_OR(payment_type = 'voucher') AS paid_with_voucher
FROM `olist-analytics-510317.raw.order_payments`
GROUP BY order_id;

-- Check the results of the staging table
SELECT
  (SELECT COUNT(*) FROM `olist-analytics-510317.staging.order_items_summary`) AS item_orders,
  (SELECT COUNT(*) FROM `olist-analytics-510317.staging.order_payments_summary`) AS payment_orders,
  (SELECT ROUND(SUM(items_revenue), 2) FROM `olist-analytics-510317.staging.order_items_summary`) AS summed_item_revenue;
/*
Row	item_orders	payment_orders	summed_item_revenue
1	98666	    99440	        1.35916437E7	
*/

/* Inference: All 3 numbers check out, just that payment_orders is 99,440 and matches what I expected.
But it's one fewer than the 99,441 orders in the table, so exactly one order has no payment row at all. */

