-- Proof that fan-out is gone
SELECT FORMAT('%.2f', SUM(i.items_revenue)) AS revenue_after_summary_joins
FROM `olist-analytics-510317.staging.orders` AS o
JOIN `olist-analytics-510317.staging.order_items_summary` AS i
  ON o.order_id = i.order_id
LEFT JOIN `olist-analytics-510317.staging.order_payments_summary` AS p
  ON o.order_id = p.order_id;
/*
Row	revenue_after_summary_joins
1	13591643.70
*/

/* Inference: After summarizing items and payments to one row per order, joining all three
tables returns 13,591,643.70, identical to the direct sum of item prices. 
The ~4.5% inflation from the raw join is gone. */


-- Find the order with no payment row
SELECT o.order_id, o.order_status, o.order_purchase_timestamp
FROM `olist-analytics-510317.staging.orders` AS o
LEFT JOIN `olist-analytics-510317.staging.order_payments_summary` AS p
  ON o.order_id = p.order_id
WHERE p.order_id IS NULL;
/*
Row	order_id	                        order_status	order_purchase_timestamp
1	bfbd0f9bdef84302105ad712db648a6c	delivered	    2016-09-15 12:16:38 UTC
*/

/* Inference: One delivered order (15 Sept, 2016) has no payment row. 
It's kept in the data and flagged with has_payment_record = FALSE instead of being deleted or given an invented payment. */