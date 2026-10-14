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
)
SELECT
  *,
  ROUND(100 * SAFE_DIVIDE(
    revenue - LAG(revenue) OVER (ORDER BY purchase_month),
    LAG(revenue) OVER (ORDER BY purchase_month)
  ), 1) AS mom_growth_pct
FROM monthly
ORDER BY purchase_month;

-- Note for interpretation: the first and last months of the dataset can be partial,
-- so check them before quoting growth rates. Look at the earliest and latest rows
-- of the result and compare their order counts with the months around them.


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
