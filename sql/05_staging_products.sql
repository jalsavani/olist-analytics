-- 
CREATE OR REPLACE TABLE `olist-analytics-510317.staging.products` AS
SELECT
  p.product_id,
  p.product_category_name AS category_portuguese,
  COALESCE(
    t.product_category_name_english,
    -- Manual mappings: these two categories are missing from the translation table
    CASE p.product_category_name
      WHEN 'pc_gamer' THEN 'pc_gamer'
      WHEN 'portateis_cozinha_e_preparadores_de_alimentos'
        THEN 'portable_kitchen_food_preparers'
    END,
    'unknown'
  ) AS category_english,
  p.product_photos_qty,
  p.product_weight_g,
  p.product_length_cm,
  p.product_height_cm,
  p.product_width_cm
FROM `olist-analytics-510317.raw.products` AS p
LEFT JOIN `olist-analytics-510317.raw.product_category_translation` AS t
  ON p.product_category_name = t.product_category_name;

-- Check the results of the staging table
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT product_id) AS unique_products,
  COUNTIF(category_english = 'unknown') AS unknown_category
FROM `olist-analytics-510317.staging.products`;
/*
Row	total_rows	unique_products	unknown_category
1	32951	    32951	        610
*/

SELECT
  COUNTIF(product_weight_g IS NULL) AS missing_weight,
  COUNTIF(product_length_cm IS NULL) AS missing_length,
  COUNTIF(product_photos_qty IS NULL) AS missing_photos
FROM `olist-analytics-510317.staging.products`;
/*
Row	missing_weight	missing_length	missing_photos
1	2	            2	            610
*/

/* Inference: 610 products are missing product_photos_qty, the same count as the NULL categories.
That suggests they're the same products, but equal counts don't prove it, so we'll check.
Only 2 products are missing weight and length. My guess that these gaps would line up with the 610 was half right: the photos count matches,
but weight and dimensions are almost complete */

