-- Fix the order_reviews table to remove duplicates and keep only the average review scores for each order
CREATE OR REPLACE TABLE `olist-analytics-510317.staging.order_reviews` AS
SELECT
  order_id,
  ROUND(AVG(review_score), 2) AS avg_review_score,
  COUNT(*) AS n_reviews,
  MIN(review_creation_date) AS first_review_date,
  MAX(review_creation_date) AS last_review_date
FROM `olist-analytics-510317.raw.order_reviews`
GROUP BY order_id;

-- Check the results of the staging table
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS unique_orders,
  COUNTIF(n_reviews > 1) AS orders_with_multiple_reviews
FROM `olist-analytics-510317.staging.order_reviews`;
/*
Row	total_rows	unique_orders	orders_with_multiple_reviews
1	98673	    98673	        547	
*/

-- Inference: You have 98,673 rows and 98,673 unique orders, so the table is one row per order. The 547 orders with multiple reviews also agrees with previous findings. 

