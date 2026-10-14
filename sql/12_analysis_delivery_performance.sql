-- Delivery performance
--
-- All metrics use has_valid_delivery = TRUE (delivered orders that have a delivery date).
-- The 8 delivered orders without a date are excluded, not filled in.
-- Delivery time is skewed, so the median and 95th percentile are reported, not the mean.
-- Comments inside an exported query must not contain semicolons.

-- @export: delivery_by_state
-- States with fewer than 100 valid deliveries are dropped because their percentages are too noisy.
SELECT
  customer_state,
  COUNT(*) AS delivered_orders,
  APPROX_QUANTILES(delivery_days, 100)[OFFSET(50)] AS median_days,
  APPROX_QUANTILES(delivery_days, 100)[OFFSET(95)] AS p95_days,
  ROUND(100 * AVG(CAST(is_late AS INT64)), 2) AS late_pct
FROM `olist-analytics-510317.analytics.orders_enriched`
WHERE has_valid_delivery
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY late_pct DESC;


-- @export: delivery_by_month
-- Late rate over time. Months with very few orders are noisy.
SELECT
  purchase_month,
  COUNT(*) AS delivered_orders,
  APPROX_QUANTILES(delivery_days, 100)[OFFSET(50)] AS median_days,
  ROUND(100 * AVG(CAST(is_late AS INT64)), 2) AS late_pct
FROM `olist-analytics-510317.analytics.orders_enriched`
WHERE has_valid_delivery
GROUP BY purchase_month
ORDER BY purchase_month;


-- @export: review_score_by_lateness
-- Does a late delivery hurt the review score? Only orders that have a review are included.
-- avg_review_score is already averaged per order in staging.order_reviews.
SELECT
  IF(is_late, 'late', 'on time') AS delivery_outcome,
  COUNT(*) AS orders,
  ROUND(AVG(avg_review_score), 2) AS avg_review_score,
  ROUND(100 * AVG(CAST(avg_review_score <= 2 AS INT64)), 2) AS pct_low_score
FROM `olist-analytics-510317.analytics.orders_enriched`
WHERE has_valid_delivery
  AND avg_review_score IS NOT NULL
GROUP BY delivery_outcome
ORDER BY delivery_outcome;
