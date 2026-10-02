-- Make a staging table for the orders data
CREATE OR REPLACE TABLE `olist-analytics-510317.staging.orders` AS
SELECT
  order_id,
  customer_id,
  order_status,
  order_purchase_timestamp,
  order_approved_at,
  order_delivered_carrier_date,
  order_delivered_customer_date,
  order_estimated_delivery_date,

  (order_status = 'delivered'
   AND order_delivered_customer_date IS NOT NULL) AS has_valid_delivery,

  CASE
    WHEN order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
    THEN DATE_DIFF(DATE(order_delivered_customer_date),
                   DATE(order_purchase_timestamp), DAY)
  END AS delivery_days,

  CASE
    WHEN order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL
    THEN DATE(order_delivered_customer_date) > DATE(order_estimated_delivery_date)
  END AS is_late
FROM `olist-analytics-510317.raw.orders`;


-- Check the results of the staging table
SELECT
  COUNT(*) AS total_orders,
  COUNTIF(has_valid_delivery) AS valid_deliveries,
  COUNTIF(is_late) AS late_orders,
  MIN(delivery_days) AS min_days,
  MAX(delivery_days) AS max_days
FROM `olist-analytics-510317.staging.orders`;
/* 
Row	total_orders	valid_deliveries	late_orders	min_days	max_days
1	99441	        96470	            6534	    0	        210
*/

-- Inference: Everything looks good, but let's check for outliers in the delivery_days column


-- Check the extremes
SELECT
  COUNTIF(delivery_days = 0) AS same_day,
  COUNTIF(delivery_days > 60) AS over_60_days,
  APPROX_QUANTILES(delivery_days, 100)[OFFSET(50)] AS median_days,
  APPROX_QUANTILES(delivery_days, 100)[OFFSET(95)] AS p95_days
FROM `olist-analytics-510317.staging.orders`;
/*
Row	same_day	over_60_days	median_days	p95_days
1	1	        298	            10	        29
*/

/* Inference: The median is 10 days and the 95th percentile is 29, so 298 orders over 60 days (about 0.3% of valid deliveries) are far out in the tail.
They don't look like errors. The dates are in a logical order and no delivery came before its purchase, so these are most likely real slow deliveries.
The single same-day order is plausible too. But a few extreme values can drag an average up, so when reporting delivery times in the analysis,
lead with the median and the 95th percentile instead of the mean. */