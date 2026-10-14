-- Cohort retention and repeat purchases
--
-- Key detail: in Olist, customer_id is created fresh for every order.
-- The real person is customer_unique_id, so all customer-level analysis uses that column.
-- Using customer_id would show a repeat rate of 0 percent for everyone.
--
-- Scope: orders with items that were not canceled or unavailable.
-- A cohort is the group of customers whose first purchase fell in the same month.
-- month_offset 0 is the cohort month itself, so retention at offset 0 is always 100 percent.
-- Comments inside an exported query must not contain semicolons.

-- @export: cohort_retention
-- The dataset ends partway through Sep 2018 (1 order that month). Without a cutoff, every cohort
-- would show a fake drop to roughly 0 percent at the offset that lands on Sep 2018 or later.
-- last_full_month is the latest month with at least 500 orders, and nothing after it is counted,
-- so cohort and offset combinations beyond the data simply have no row.
WITH last_full_month AS (
  SELECT MAX(purchase_month) AS month
  FROM (
    SELECT purchase_month
    FROM `olist-analytics-510317.analytics.orders_enriched`
    WHERE has_items
      AND order_status NOT IN ('canceled', 'unavailable')
    GROUP BY purchase_month
    HAVING COUNT(*) >= 500
  )
),
customer_orders AS (
  SELECT customer_unique_id, order_id, purchase_month
  FROM `olist-analytics-510317.analytics.orders_enriched`
  WHERE has_items
    AND order_status NOT IN ('canceled', 'unavailable')
    AND purchase_month <= (SELECT month FROM last_full_month)
),
first_purchase AS (
  SELECT customer_unique_id, MIN(purchase_month) AS cohort_month
  FROM customer_orders
  GROUP BY customer_unique_id
),
activity AS (
  SELECT DISTINCT
    f.cohort_month,
    c.customer_unique_id,
    DATE_DIFF(c.purchase_month, f.cohort_month, MONTH) AS month_offset
  FROM customer_orders AS c
  JOIN first_purchase AS f
    ON c.customer_unique_id = f.customer_unique_id
),
cohort_size AS (
  SELECT cohort_month, COUNT(*) AS cohort_customers
  FROM first_purchase
  GROUP BY cohort_month
)
SELECT
  a.cohort_month,
  s.cohort_customers,
  a.month_offset,
  COUNT(DISTINCT a.customer_unique_id) AS active_customers,
  ROUND(100 * SAFE_DIVIDE(COUNT(DISTINCT a.customer_unique_id), s.cohort_customers), 2) AS retention_pct
FROM activity AS a
JOIN cohort_size AS s
  ON a.cohort_month = s.cohort_month
WHERE a.month_offset BETWEEN 0 AND 12
GROUP BY a.cohort_month, s.cohort_customers, a.month_offset
ORDER BY a.cohort_month, a.month_offset;


-- @export: repeat_purchase_rate
-- Share of customers who ordered more than once.
SELECT
  COUNT(*) AS customers,
  COUNTIF(n_orders > 1) AS repeat_customers,
  ROUND(100 * SAFE_DIVIDE(COUNTIF(n_orders > 1), COUNT(*)), 2) AS repeat_rate_pct
FROM (
  SELECT customer_unique_id, COUNT(DISTINCT order_id) AS n_orders
  FROM `olist-analytics-510317.analytics.orders_enriched`
  WHERE has_items
    AND order_status NOT IN ('canceled', 'unavailable')
  GROUP BY customer_unique_id
);

-- Interpretation notes for the write-up:
-- 1. Late cohorts have had less time to come back, so compare cohorts at the same month_offset only.
-- 2. Small cohorts (the earliest months) are noisy. Check cohort_customers before reading a percentage.
