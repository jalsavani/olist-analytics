SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM `olist-analytics-510317.raw.customers`
UNION ALL SELECT 'orders', COUNT(*) FROM `olist-analytics-510317.raw.orders`
UNION ALL SELECT 'order_items', COUNT(*) FROM `olist-analytics-510317.raw.order_items`
UNION ALL SELECT 'order_payments', COUNT(*) FROM `olist-analytics-510317.raw.order_payments`
UNION ALL SELECT 'order_reviews', COUNT(*) FROM `olist-analytics-510317.raw.order_reviews`
UNION ALL SELECT 'products', COUNT(*) FROM `olist-analytics-510317.raw.products`
UNION ALL SELECT 'sellers', COUNT(*) FROM `olist-analytics-510317.raw.sellers`
UNION ALL SELECT 'geolocation', COUNT(*) FROM `olist-analytics-510317.raw.geolocation`
UNION ALL SELECT 'product_category_translation', COUNT(*) FROM `olist-analytics-510317.raw.product_category_translation`;