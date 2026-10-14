-- Revenue trends
-- Reads analytics.orders_enriched (one row per order). Builds nothing.
--
-- Scope decision: only orders that have items and were not canceled or unavailable.
-- Those orders never became a sale, so counting them would overstate revenue.
-- Revenue here means item price only (no freight), taken from the per-order
-- summary table, so there is no join fan-out.
--
-- Queries marked "@export" are run by scripts/export_dashboard_data.py.
-- Comments inside an exported query must not contain semicolons.

-- @export: monthly_revenue
-- Only months with at least 500 orders are reported. In the real data, 2016 has tiny volumes
-- (2 orders in Sep, 290 in Oct, none in Nov, 1 in Dec) and Sep 2018 has 1 order, so growth rates
-- computed against those months are meaningless (thousands of percent). The IF() below also
-- blanks the growth value whenever the previous row is not the immediately preceding month.
WITH monthly AS (
  SELECT
    purchase_month,
    COUNT(*) AS orders,
    ROUND(SUM(items_revenue), 2) AS revenue,
    ROUND(AVG(items_revenue), 2) AS avg_order_value
  FROM `olist-analytics-510317.analytics.orders_enriched`
  WHERE has_items
    AND order_status NOT IN ('canceled', 'unavailable')
  GROUP BY purchase_month
  HAVING COUNT(*) >= 500
)
SELECT
  *,
  IF(
    DATE_DIFF(purchase_month, LAG(purchase_month) OVER (ORDER BY purchase_month), MONTH) = 1,
    ROUND(100 * SAFE_DIVIDE(
      revenue - LAG(revenue) OVER (ORDER BY purchase_month),
      LAG(revenue) OVER (ORDER BY purchase_month)
    ), 1),
    NULL
  ) AS mom_growth_pct
FROM monthly
ORDER BY purchase_month;

-- Note for interpretation: with the 500-order rule the result covers Jan 2017 to Aug 2018.
-- The first month has no growth value because there is no earlier month to compare with.


-- @export: revenue_by_category
-- Top product categories by item revenue. Joins at item level (price lives on the item row).
SELECT
  p.category_english AS category,
  COUNT(DISTINCT i.order_id) AS orders,
  ROUND(SUM(i.price), 2) AS revenue,
  ROUND(AVG(i.price), 2) AS avg_item_price
FROM `olist-analytics-510317.raw.order_items` AS i
JOIN `olist-analytics-510317.staging.orders` AS o
  ON i.order_id = o.order_id
LEFT JOIN `olist-analytics-510317.staging.products` AS p
  ON i.product_id = p.product_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY category
ORDER BY revenue DESC
LIMIT 20;


-- @export: revenue_by_state
-- Revenue and order volume by customer state.
SELECT
  customer_state,
  COUNT(*) AS orders,
  ROUND(SUM(items_revenue), 2) AS revenue,
  ROUND(AVG(items_revenue), 2) AS avg_order_value
FROM `olist-analytics-510317.analytics.orders_enriched`
WHERE has_items
  AND order_status NOT IN ('canceled', 'unavailable')
GROUP BY customer_state
ORDER BY revenue DESC;
