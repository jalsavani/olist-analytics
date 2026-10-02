-- Query 1: what states can an order be in?
SELECT order_status, COUNT(*) AS n_orders
FROM `olist-analytics-510317.raw.orders`
GROUP BY order_status
ORDER BY n_orders DESC;
/*
Row	    order_status	n_orders
1	    delivered	    96478
2	    shipped	        1107
3	    canceled	    625
4	    unavailable	    609
5	    invoiced	    314
6	    processing	    301
7	    created	        5
8	    approved	    2
*/

-- Inference: about 97% of orders are delivered (96,478 of 99,441).


-- Query 2: how many orders are missing a delivery date?
SELECT
  COUNT(*) AS total_orders,
  COUNTIF(order_delivered_customer_date IS NULL) AS missing_delivery_date,
  COUNTIF(order_approved_at IS NULL) AS missing_approval_date
FROM `olist-analytics-510317.raw.orders`;
/*
Row	    total_orders	missing_delivery_date	missing_approval_date
1	    99441	        2965	                160	
*/

/* Inference: 2,965 are missing. But 99,441 - 96,478 delivered is 2,963 orders that weren't delivered.
That's close but not equal, so a handful of delivered orders might be missing their date, or the missing dates might not line up with the statuses. 
We can check this with a query later. */


-- Query 3: are the review IDs actually unique?
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT review_id) AS unique_review_ids,
  COUNT(DISTINCT order_id) AS unique_orders
FROM `olist-analytics-510317.raw.order_reviews`;
/* 
Row	    total_rows	unique_review_ids	unique_orders
1	    99224	    98410	            98673
*/

/* Inference: order_reviews has 99,224 rows but only 98,410 unique review_ids and 98,673 unique order_ids. 
So some review IDs repeat, and some orders have more than one review. 
If we join reviews to orders without handling this, those orders get counted twice. 
We need to look at the duplicates to decide how to handle them. */


-- Query 4: do missing delivery dates line up with status?
SELECT
  order_status,
  COUNT(*) AS n_orders,
  COUNTIF(order_delivered_customer_date IS NULL) AS missing_delivery_date
FROM `olist-analytics-510317.raw.orders`
GROUP BY order_status
ORDER BY n_orders DESC;
/* 
Row	    order_status	n_orders	missing_delivery_date
1	    delivered	    96478	    8
2	    shipped	        1107	    1107
3	    canceled	    625	        619
4	    unavailable	    609	        609
5	    invoiced	    314	        314
6	    processing	    301	        301
7	    created	        5	        5
8	    approved	    2	        2
*/

/* Inference: 8 delivered orders have no delivery date, which is a true data gap, 
and 6 canceled orders do have one (619 of 625 are missing it), which is odd. 
The 8 plus the 6 explain the gap of 2 between 2,965 and 2,963. */


-- Query 5: which review IDs repeat?
SELECT
  review_id,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT order_id) AS n_orders
FROM `olist-analytics-510317.raw.order_reviews`
GROUP BY review_id
HAVING COUNT(*) > 1
ORDER BY n_rows DESC
LIMIT 10;
/*
Row	    review_id	                        n_rows	n_orders
1	    f4bb9d6dd4fb6dcc2298f0e7b17b8e1e	3	    3
2	    dbdf1ea31790c8ecfcc6750525661a9b	3	    3
3	    ddc52555ca27b0fe67d5255147682d2d	3	    3
4	    e44840754f12fad2b8646712121b349a	3	    3
5	    08528f70f579f0c830189efc523d2182	3	    3
6	    2d6ac45f859465b5c185274a1c929637	3	    3
7	    32415bbf6e341d5d517080a796f79b5c	3	    3
8	    4548534449b1f572e357211b90724f1b	3	    3
9	    abbfacb2964f74f6487c9c10ac46daa6	3	    3
10	    9e25d6e3025e9b9a0fc7f03588d33e2b	3	    3
*/

/* Inference: Each repeated review_id appears 3 times across 3 different orders.
So review_id is not a unique key. One review ID was reused on several orders.*/


-- Query 6: which orders have more than one review?
SELECT
  order_id,
  COUNT(*) AS n_reviews
FROM `olist-analytics-510317.raw.order_reviews`
GROUP BY order_id
HAVING COUNT(*) > 1
ORDER BY n_reviews DESC
LIMIT 10;
/*
Row	    order_id	                        n_reviews
1	    03c939fd7fd3b38f8485a0f95798f1f6	3
2	    df56136b8031ecd28e200bb18e6ddb2e	3
3	    c88b1d1b157a9999ce368f218a407141	3
4	    8e17072ec97ce29f0e1f111e598b0c85	3
5	    c761a8b74f1e876bc5efc4186f720e27	2
6	    7f13a20e25350f4a55fb2a7c9a2e8d88	2
7	    e1e8e3bca903de27e9a1c72b5a5795e0	2
8	    4420cbe16c262f724b648cd1294c88b6	2
9	    fa350da9efbba83c2957b629bf6c2c7c	2
10	    75d5d3d16567a27eefc5752aeb063072	2	
*/

-- Checking one of the orders with multiple reviews to see if the reviews are different or duplicates.
SELECT *
FROM `olist-analytics-510317.raw.order_reviews`
WHERE order_id = '03c939fd7fd3b38f8485a0f95798f1f6';
/* 
Row	    review_id	                        order_id	                        review_score	review_comment_title	review_comment_message	                                                review_creation_date	    review_answer_timestamp
1	    405eb2ea45e1dbe2662541ae5b47e2aa	03c939fd7fd3b38f8485a0f95798f1f6	3	            null	                Seria ótimo se tivesem entregue os 3 (três) pedidos de uma única vez.	2018-03-06 00:00:00 UTC	    2018-03-06 19:50:32 UTC
2	    b04ed893318da5b863e878cd3d0511df	03c939fd7fd3b38f8485a0f95798f1f6	3	            null	                Um ponto negativo que achei foi a cobrança de 3 taxas de entregas, sendo que comprei os 3 produtos iguais numa só compra.
E mesmo comprando os produtos juntos, chegaram separados.	                                                                                                                                    2018-03-20 00:00:00 UTC	    2018-03-21 02:28:23 UTC
3	    f4bb9d6dd4fb6dcc2298f0e7b17b8e1e	03c939fd7fd3b38f8485a0f95798f1f6	4	            null	                null	                                                                2018-03-29 00:00:00 UTC	    2018-03-30 00:29:09 UTC
*/

/* Inference: Order 03c939... has 3 rows with different review IDs, scores, comments, and timestamps.
These are distinct reviews, not copies.
The comments say the customer got three packages from one purchase, and each package apparently got its own review. */


-- Query 7: is the pair (review_id, order_id) unique?
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT CONCAT(review_id, '-', order_id)) AS unique_pairs
FROM `olist-analytics-510317.raw.order_reviews`;
/*
Row	total_rows	unique_pairs
1	99224	    99224
*/

/* Inference: (review_id, order_id) is unique, so there are no exact duplicates, but 551 rows are extra reviews on the same orders.
Staging needs to reduce reviews to one row per order before joining. */


-- Query 8: look at the 8 delivered orders with no delivery date.
SELECT
  order_id,
  order_status,
  order_purchase_timestamp,
  order_approved_at,
  order_delivered_carrier_date,
  order_delivered_customer_date,
  order_estimated_delivery_date
FROM `olist-analytics-510317.raw.orders`
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;
/*
Row	order_id	                        order_status	order_purchase_timestamp	order_approved_at	    order_delivered_carrier_date	order_delivered_customer_date	order_estimated_delivery_date
1	2d858f451373b04fb5c984a1cc2defaf	delivered	    2017-05-25 23:22:43 UTC	    2017-05-25 23:30:16 UTC	null	                        null	                        2017-06-23 00:00:00 UTC
2	2d1e2d5bf4dc7227b3bfebb81328c15f	delivered	    2017-11-28 17:44:07 UTC	    2017-11-28 17:56:40 UTC	2017-11-30 18:12:23 UTC	        null	                        2017-12-18 00:00:00 UTC
3	ab7c89dc1bf4a1ead9d6ec1ec8968a84	delivered	    2018-06-08 12:09:39 UTC	    2018-06-08 12:36:39 UTC	2018-06-12 14:10:00 UTC	        null	                        2018-06-26 00:00:00 UTC
4	f5dd62b788049ad9fc0526e3ad11a097	delivered	    2018-06-20 06:58:43 UTC	    2018-06-20 07:19:05 UTC	2018-06-25 08:05:00 UTC	        null	                        2018-07-16 00:00:00 UTC
5	20edc82cf5400ce95e1afacc25798b31	delivered	    2018-06-27 16:09:12 UTC	    2018-06-27 16:29:30 UTC	2018-07-03 19:26:00 UTC	        null	                        2018-07-19 00:00:00 UTC
6	0d3268bad9b086af767785e3f0fc0133	delivered	    2018-07-01 21:14:02 UTC	    2018-07-01 21:29:54 UTC	2018-07-03 09:28:00 UTC	        null	                        2018-07-24 00:00:00 UTC
7	2ebdfc4f15f23b91474edf87475f108e	delivered	    2018-07-01 17:05:11 UTC	    2018-07-01 17:15:12 UTC	2018-07-03 13:57:00 UTC	        null	                        2018-07-30 00:00:00 UTC
8	e69f75a717d64fc5ecdfae42b2e8e086	delivered	    2018-07-01 22:05:55 UTC	    2018-07-01 22:15:14 UTC	2018-07-03 13:57:00 UTC	        null	                        2018-07-30 00:00:00 UTC
*/

/* Inference: All 8 are marked delivered but have no customer delivery date.
I'd keep these orders in the data, since they're real orders with real revenue, but exclude them from delivery-time metrics.
*/


-- Before we join products to categories, let's check whether each product has a category translation.
SELECT
  p.product_category_name,
  COUNT(*) AS n_products
FROM `olist-analytics-510317.raw.products` AS p
LEFT JOIN `olist-analytics-510317.raw.product_category_translation` AS t
  ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY n_products DESC;
/*
Row	product_category_name	                        n_products
1	null	                                        610
2	portateis_cozinha_e_preparadores_de_alimentos	10
3	pc_gamer	                                    3
*/

/* Inference: 623 of 32,951 products (about 1.9%) have no English category from a plain join.
610 products have a NULL category, so they can't match any translation. Staging will label them 'unknown' instead of guessing.
2 real categories are missing from the translation table: portateis_cozinha_e_preparadores_de_alimentos (10 products) and pc_gamer (3 products).
Staging will map them by hand, and the SQL will have a comment saying the mapping was added manually and isn't part of the source data. */


-- Are the products with missing categories and missing photos the same products?
SELECT
  COUNTIF(category_english = 'unknown') AS no_category,
  COUNTIF(category_english = 'unknown' AND product_photos_qty IS NULL) AS no_category_and_no_photos,
  COUNTIF(product_weight_g IS NULL AND category_english = 'unknown') AS no_weight_and_no_category
FROM `olist-analytics-510317.staging.products`;
/*
Row	no_category	no_category_and_no_photos	no_weight_and_no_category
1	610	        610	                        1
*/

/* Inference: All 610 products with no category also have no photo count, so they're the same incomplete listings.
Only 1 of the 2 products missing weight is in that group, so the other has a category and is a separate gap.
Staging will flag these and leave them as NULL, not fill them in. */


-- order_items: what makes a row unique?
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT order_id) AS unique_orders,
  COUNT(DISTINCT CONCAT(order_id, '-', CAST(order_item_id AS STRING))) AS unique_order_item_pairs,
  COUNTIF(price <= 0) AS nonpositive_price,
  COUNTIF(freight_value < 0) AS negative_freight
FROM `olist-analytics-510317.raw.order_items`;
/*
Row	total_rows	unique_orders	unique_order_item_pairs	nonpositive_price	negative_freight
1	112650	    98666	        112650	                0	                0	
*/

/* Inference: (order_id, order_item_id) is unique across all 112,650 rows, so that pair is the table's key. 
No price is zero or negative and no freight is negative.
The table covers 98,666 orders, but orders has 99,441, so 775 orders have no items at all. */


-- order_payments: how many payment rows per order, and what types exist?
SELECT
  payment_type,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT order_id) AS n_orders,
  COUNTIF(payment_value <= 0) AS nonpositive_value
FROM `olist-analytics-510317.raw.order_payments`
GROUP BY payment_type
ORDER BY n_rows DESC;
/*
Row	payment_type	n_rows	n_orders	nonpositive_value
1	credit_card	    76795	76505	    0
2	boleto	        19784	19784	    0
3	voucher	        5775	3866	    6
4	debit_card	    1529	1528	    0
5	not_defined	    3	    3	        3
*/

/* Inference: The rows add up to 103,886, matching the load. 
Many orders have more than one payment row, such as 5,775 voucher rows across 3,866 orders, which probably means customers split a payment across several vouchers. 
There are 9 zero-value rows: 6 vouchers and all 3 of the not_defined rows. */

-- which orders have no items?
SELECT
  o.order_status,
  COUNT(*) AS n_orders
FROM `olist-analytics-510317.raw.orders` AS o
LEFT JOIN (
  SELECT DISTINCT order_id
  FROM `olist-analytics-510317.raw.order_items`
) AS i
  ON o.order_id = i.order_id
WHERE i.order_id IS NULL
GROUP BY o.order_status
ORDER BY n_orders DESC;
/*
Row	order_status	n_orders
1	unavailable	    603
2	canceled	    164
3	created	        5
4	invoiced	    2
5	shipped	        1
*/

/* Inference: (order_id, order_item_id) is unique. 
No non-positive prices or negative freight. 
775 orders have no items, mostly unavailable (603) or canceled (164). */


-- What are the zero-value payments?
SELECT
  p.order_id,
  p.payment_type,
  p.payment_value,
  o.order_status
FROM `olist-analytics-510317.raw.order_payments` AS p
JOIN `olist-analytics-510317.raw.orders` AS o
  ON p.order_id = o.order_id
WHERE p.payment_value <= 0;
/*
Row	order_id	                        payment_type	payment_value	order_status
1	8bcbe01d44d147f901cd3192671144db	voucher	        0.0	            delivered
2	fa65dad1b0e818e3ccc5cb0e39231352	voucher	        0.0	            shipped
3	6ccb433e00daae1283ccc956189c82ae	voucher	        0.0	            delivered
4	4637ca194b6387e2d538dc89b124b0ee	not_defined	    0.0	            canceled
5	00b1cb0320190ca0daa2c88b35206009	not_defined	    0.0	            canceled
6	45ed6e85398a87c253db47c2d9f48216	voucher	        0.0	            delivered
7	fa65dad1b0e818e3ccc5cb0e39231352	voucher	        0.0	            shipped
8	c8c528189310eaa44a745b8d9d26908b	not_defined	    0.0	            canceled
9	b23878b3e8eb4d25a158f57d96331b18	voucher	        0.0	            delivered
*/

/* Inference: Orders can have several payment rows (e.g. split vouchers). 9 rows have
zero value (6 voucher, 3 not_defined); the not_defined rows are all on canceled orders.
Kept, since they don't affect sums. */


-- Fan-out check:
SELECT
  (SELECT SUM(price) FROM `olist-analytics-510317.raw.order_items`) AS correct_item_revenue,
  SUM(i.price) AS revenue_after_joining_payments
FROM `olist-analytics-510317.raw.order_items` AS i
JOIN `olist-analytics-510317.raw.order_payments` AS p
  ON i.order_id = p.order_id;
/*
Row	correct_item_revenue	revenue_after_joining_payments
1	1.3591643700000547E7	1.4209115340004705E7
*/

/* Inference: Joining order_items to order_payments directly inflated item revenue from
13,591,643.70 to 14,209,115.34 (about +4.5%), because each item row repeats once per payment row.
Staging will summarize both tables to one row per order before any join. */

