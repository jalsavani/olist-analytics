-- Seller performance
--
-- Seller metrics need item-level data because one order can contain items from several sellers.
-- The order-level review score and late flag are attached to each (seller, order) pair, so a seller
-- is judged on the orders they took part in. That is a simplification when an order has several sellers.
-- Scope: orders that were not canceled or unavailable.
-- Comments inside an exported query must not contain semicolons.

-- @export: seller_scorecard
-- Sellers with fewer than 30 orders are dropped because their rates are too noisy to rank.
WITH seller_orders AS (
  SELECT
    i.seller_id,
    i.order_id,
    SUM(i.price) AS seller_revenue
  FROM `olist-analytics-510317.raw.order_items` AS i
  JOIN `olist-analytics-510317.staging.orders` AS o
    ON i.order_id = o.order_id
  WHERE o.order_status NOT IN ('canceled', 'unavailable')
  GROUP BY i.seller_id, i.order_id
)
SELECT
  so.seller_id,
  s.seller_state,
  COUNT(*) AS orders,
  ROUND(SUM(so.seller_revenue), 2) AS revenue,
  ROUND(AVG(r.avg_review_score), 2) AS avg_review_score,
  ROUND(100 * AVG(CAST(o.is_late AS INT64)), 2) AS late_pct
FROM seller_orders AS so
JOIN `olist-analytics-510317.staging.orders` AS o
  ON so.order_id = o.order_id
LEFT JOIN `olist-analytics-510317.staging.order_reviews` AS r
  ON so.order_id = r.order_id
LEFT JOIN `olist-analytics-510317.raw.sellers` AS s
  ON so.seller_id = s.seller_id
GROUP BY so.seller_id, s.seller_state
HAVING COUNT(*) >= 30
ORDER BY revenue DESC;


-- @export: seller_revenue_concentration
-- How concentrated is revenue? Sellers are split into 10 equal groups by revenue (decile 1 = top sellers).
WITH seller_revenue AS (
  SELECT i.seller_id, SUM(i.price) AS revenue
  FROM `olist-analytics-510317.raw.order_items` AS i
  JOIN `olist-analytics-510317.staging.orders` AS o
    ON i.order_id = o.order_id
  WHERE o.order_status NOT IN ('canceled', 'unavailable')
  GROUP BY i.seller_id
),
ranked AS (
  SELECT *, NTILE(10) OVER (ORDER BY revenue DESC) AS decile
  FROM seller_revenue
)
SELECT
  decile,
  COUNT(*) AS sellers,
  ROUND(SUM(revenue), 2) AS revenue,
  ROUND(100 * SAFE_DIVIDE(SUM(revenue), SUM(SUM(revenue)) OVER ()), 1) AS pct_of_revenue
FROM ranked
GROUP BY decile
ORDER BY decile;
