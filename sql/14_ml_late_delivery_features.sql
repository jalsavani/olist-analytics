-- ML feature table: predict whether an order will be delivered late.
--
-- Unit of prediction: one delivered order (has_valid_delivery = TRUE and has items).
-- Label:  is_late = 1 when the order arrived after the estimated delivery date.
-- Prediction time: the moment the order is placed.
--
-- NO-LEAKAGE RULE: every feature must be known at purchase time. That is why this table
-- does NOT use delivery_days, the carrier or approval dates, review scores, or the
-- actual delivery date. The estimated delivery date IS allowed because Olist shows it to
-- the customer at checkout, so it exists before the outcome does.
--
-- Distance: the average latitude and longitude of each zip-code prefix in raw.geolocation
-- is used as that prefix's centre point. Distance is seller to customer, in km.
-- If an order has items from several sellers, the longest distance is used.
-- Zip prefixes with no geolocation row (or invalid coordinates) give a NULL distance and are handled in Python.
--
-- Timestamps are used as stored (UTC). Hour of day is therefore approximate, which is fine
-- for a model feature but should not be quoted as local time.

CREATE OR REPLACE TABLE `olist-analytics-510317.analytics.late_delivery_features` AS
WITH zip_centroids AS (
  SELECT
    geolocation_zip_code_prefix AS zip_prefix,
    AVG(geolocation_lat) AS lat,
    AVG(geolocation_lng) AS lng
  FROM `olist-analytics-510317.raw.geolocation`
  GROUP BY geolocation_zip_code_prefix
),
item_level AS (
  SELECT
    i.order_id,
    p.product_weight_g,
    p.product_length_cm * p.product_height_cm * p.product_width_cm AS volume_cm3,
    s.seller_state,
    c.customer_state,
    ST_DISTANCE(
      SAFE.ST_GEOGPOINT(sg.lng, sg.lat),
      SAFE.ST_GEOGPOINT(cg.lng, cg.lat)
    ) / 1000 AS distance_km
  FROM `olist-analytics-510317.raw.order_items` AS i
  JOIN `olist-analytics-510317.staging.orders` AS o
    ON i.order_id = o.order_id
  JOIN `olist-analytics-510317.raw.customers` AS c
    ON o.customer_id = c.customer_id
  LEFT JOIN `olist-analytics-510317.raw.sellers` AS s
    ON i.seller_id = s.seller_id
  LEFT JOIN `olist-analytics-510317.staging.products` AS p
    ON i.product_id = p.product_id
  LEFT JOIN zip_centroids AS sg
    ON s.seller_zip_code_prefix = sg.zip_prefix
  LEFT JOIN zip_centroids AS cg
    ON c.customer_zip_code_prefix = cg.zip_prefix
),
order_item_features AS (
  SELECT
    order_id,
    SUM(product_weight_g) AS total_weight_g,
    MAX(volume_cm3) AS max_item_volume_cm3,
    MAX(distance_km) AS max_distance_km,
    LOGICAL_AND(seller_state = customer_state) AS all_sellers_same_state
  FROM item_level
  GROUP BY order_id
)
SELECT
  e.order_id,
  e.order_purchase_timestamp,
  CAST(e.is_late AS INT64) AS is_late,

  -- timing
  EXTRACT(HOUR FROM e.order_purchase_timestamp) AS purchase_hour,
  EXTRACT(DAYOFWEEK FROM e.order_purchase_timestamp) AS purchase_dow,
  EXTRACT(MONTH FROM e.order_purchase_timestamp) AS purchase_month_num,
  DATE_DIFF(DATE(o.order_estimated_delivery_date), DATE(o.order_purchase_timestamp), DAY) AS estimated_days,

  -- where
  e.customer_state,
  f.max_distance_km,
  f.all_sellers_same_state,

  -- what
  e.n_items,
  e.n_sellers,
  e.n_distinct_products,
  f.total_weight_g,
  f.max_item_volume_cm3,

  -- how much and how paid
  e.items_revenue,
  e.freight_total,
  SAFE_DIVIDE(e.freight_total, e.items_revenue) AS freight_ratio,
  e.max_installments,
  e.paid_with_credit_card
FROM `olist-analytics-510317.analytics.orders_enriched` AS e
JOIN `olist-analytics-510317.staging.orders` AS o
  ON e.order_id = o.order_id
LEFT JOIN order_item_features AS f
  ON e.order_id = f.order_id
WHERE e.has_valid_delivery
  AND e.has_items;


-- Sanity checks to run after building (expected: row count close to the 96,470 valid deliveries
-- minus any with no items, no duplicate order_id, and a late rate near the 6.8 percent seen in staging).
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS unique_orders,
  ROUND(100 * AVG(is_late), 2) AS late_pct,
  COUNTIF(max_distance_km IS NULL) AS missing_distance,
  COUNTIF(total_weight_g IS NULL) AS missing_weight
FROM `olist-analytics-510317.analytics.late_delivery_features`;
