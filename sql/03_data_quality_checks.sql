-- =====================================================================
-- 03_data_quality_checks.sql
-- Olist e-commerce project: data quality checks (PostgreSQL)
-- Run each block separately and note the result in docs/data_quality_log.md
-- =====================================================================


-- ---------------------------------------------------------------------
-- CHECK 1: Row counts per table
-- Question: did every file load completely?
-- ---------------------------------------------------------------------
SELECT 'customers' AS table_name, COUNT(*) AS n_rows FROM customers UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers UNION ALL
SELECT 'products', COUNT(*) FROM products UNION ALL
SELECT 'orders', COUNT(*) FROM orders UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items UNION ALL
SELECT 'order_payments', COUNT(*) FROM order_payments UNION ALL
SELECT 'order_reviews', COUNT(*) FROM order_reviews UNION ALL
SELECT 'geolocation', COUNT(*) FROM geolocation UNION ALL
SELECT 'product_category_translation', COUNT(*) FROM product_category_translation;


-- ---------------------------------------------------------------------
-- CHECK 2: Orders by status
-- Question: which orders should count as real sales?
-- ---------------------------------------------------------------------
SELECT order_status,
       COUNT(*) AS n_orders,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct
FROM orders
GROUP BY order_status
ORDER BY n_orders DESC;


-- ---------------------------------------------------------------------
-- CHECK 3: Inconsistencies between status and delivery date
-- Question: are there delivered orders without a delivery date (or the opposite)?
-- ---------------------------------------------------------------------
-- 3a. Status 'delivered' but no customer delivery date
SELECT COUNT(*) AS delivered_without_date
FROM orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;

-- 3b. Delivery date present but status is not 'delivered'
SELECT order_status, COUNT(*) AS n_orders
FROM orders
WHERE order_delivered_customer_date IS NOT NULL
  AND order_status <> 'delivered'
GROUP BY order_status;

-- 3c. Illogical timestamps (delivery before purchase / carrier before approval)
SELECT
    COUNT(*) FILTER (WHERE order_delivered_customer_date < order_purchase_timestamp) AS delivered_before_purchase,
    COUNT(*) FILTER (WHERE order_delivered_carrier_date  < order_approved_at)        AS carrier_before_approval,
    COUNT(*) FILTER (WHERE order_approved_at             < order_purchase_timestamp) AS approved_before_purchase
FROM orders;


-- ---------------------------------------------------------------------
-- CHECK 4: Duplicate reviews
-- Question: is there exactly one review per order?
-- ---------------------------------------------------------------------
-- 4a. Orders with more than one review
SELECT COUNT(*) AS orders_with_multiple_reviews
FROM (
    SELECT order_id
    FROM order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) t;

-- 4b. review_id values that appear more than once (so it is NOT a valid key)
SELECT COUNT(*) AS duplicated_review_ids
FROM (
    SELECT review_id
    FROM order_reviews
    GROUP BY review_id
    HAVING COUNT(*) > 1
) t;

-- 4c. Orders with no review at all
SELECT COUNT(*) AS orders_without_review
FROM orders o
LEFT JOIN order_reviews r USING (order_id)
WHERE r.order_id IS NULL;

-- ---------------------------------------------------------------------
-- CHECK 5: customer_id vs customer_unique_id
-- Question: which column identifies a real person?
-- ---------------------------------------------------------------------
SELECT COUNT(DISTINCT customer_id)        AS distinct_customer_id,
       COUNT(DISTINCT customer_unique_id) AS distinct_customer_unique_id,
       COUNT(*)                           AS n_row
FROM customers;

-- Customers (real people) with more than one order
SELECT COUNT(*) AS repeat_customers,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT customer_unique_id) FROM customers), 2) AS pct_of_customers
FROM (
    SELECT c.customer_unique_id,
        COUNT(*) AS costumer_repetition
    FROM orders o
    JOIN customers c USING (customer_id)
    GROUP BY c.customer_unique_id
    HAVING COUNT(*) > 1
) t;


-- ---------------------------------------------------------------------
-- CHECK 6: Orders per month
-- Question: what is the reliable time window for the analysis?
-- ---------------------------------------------------------------------

SELECT EXTRACT(YEAR FROM order_purchase_timestamp) AS year,
       EXTRACT(MONTH FROM order_purchase_timestamp) AS month,
       COUNT(*) AS n_orders
FROM orders
GROUP BY year, month;

-- ---------------------------------------------------------------------
-- CHECK 7: Products, categories and translations
-- Question: can every product be given an English category name?
-- ---------------------------------------------------------------------
-- Number of distinct product and categories
SELECT COUNT(DISTINCT(product_id)) AS n_product,
        COUNT(DISTINCT(product_category_name)) AS n_category
FROM products

-- 7a. Products with NULL category
SELECT COUNT(*) AS products_without_category
FROM products
WHERE product_category_name IS NULL;

-- 7b. Categories used by products but missing from the translation table
SELECT p.product_category_name, COUNT(*) AS n_products
FROM products p
LEFT JOIN product_category_translation t USING (product_category_name)
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name;

-- 7c. Products with missing physical attributes
SELECT COUNT(*) FILTER (WHERE product_weight_g IS NULL) AS null_weight,
       COUNT(*) FILTER (WHERE product_weight_g = 0)     AS zero_weight,
       COUNT(*) FILTER (WHERE product_length_cm IS NULL) AS null_dimensions
FROM products;

SELECT product_id, product_category_name, product_height_cm,
        product_length_cm, product_width_cm, product_weight_g
FROM products
WHERE product_height_cm IS NULL
    OR product_width_cm IS NULL
    OR product_length_cm IS NULL
    OR product_weight_g IS NULL
    OR product_weight_g = 0


-- ---------------------------------------------------------------------
-- CHECK 8: Payments vs. items + freight
-- Question: does the amount paid match the value of the items?
-- NOTE: aggregate items and payments separately BEFORE joining,
-- otherwise the join multiplies rows and inflates the totals.
-- ---------------------------------------------------------------------
-- items and payments are aggregate before joining because otherwise we would 
-- have duplicates inflating the number of rows

WITH items AS (
    SELECT order_id, SUM(price + freight_value) AS items_total
    FROM order_items
    GROUP BY order_id
),
pays AS (
    SELECT order_id, SUM(payment_value) AS paid_total
    FROM order_payments
    GROUP BY order_id
)
SELECT COUNT(*) AS orders_compared,
       COUNT(*) FILTER (WHERE ABS(i.items_total - p.paid_total) > 0.01) AS mismatching_orders,
       ROUND(100.0 * COUNT(*) FILTER (WHERE ABS(i.items_total - p.paid_total) > 0.01) / COUNT(*), 2) AS pct_mismatch,
       ROUND(AVG(p.paid_total - i.items_total), 2) AS avg_difference
FROM items i
JOIN pays p USING (order_id);

-- 8b. Orders without items / without payments
SELECT
    (SELECT COUNT(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id))    AS orders_without_items,
    (SELECT COUNT(*) FROM orders o WHERE NOT EXISTS (SELECT 1 FROM order_payments p WHERE p.order_id = o.order_id)) AS orders_without_payments;

-- 8c. Orders without items, by status
SELECT o.order_status, COUNT(*) AS n_orders
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id)
GROUP BY o.order_status
ORDER BY n_orders DESC;


-- ---------------------------------------------------------------------
-- CHECK 9: Suspicious values
-- Question: are there zero/negative prices or odd payment values?
-- ---------------------------------------------------------------------
SELECT COUNT(*) FILTER (WHERE price <= 0)         AS non_positive_price,
       COUNT(*) FILTER (WHERE freight_value < 0)  AS negative_freight,
       COUNT(*) FILTER (WHERE freight_value = 0)  AS free_shipping_items,
       MAX(price)                                 AS max_price
FROM order_items;

SELECT payment_type, COUNT(*) AS n_payments,
       COUNT(*) FILTER (WHERE payment_value = 0) AS zero_value_payments
FROM order_payments
GROUP BY payment_type
ORDER BY n_payments DESC;

-- Review scores must be between 1 and 5
SELECT review_score, COUNT(*) AS n_reviews
FROM order_reviews
GROUP BY review_score
ORDER BY review_score;


-- ---------------------------------------------------------------------
-- CHECK 10: Geolocation table
-- Question: is there one row per zip prefix?
-- ---------------------------------------------------------------------
SELECT COUNT(*)                                   AS n_rows,
       COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zip_prefixes,
       ROUND(COUNT(*)::numeric / COUNT(DISTINCT geolocation_zip_code_prefix), 1) AS avg_rows_per_zip
FROM geolocation;
-- Decision to document: aggregate (e.g. AVG of lat/lng) per zip prefix before any join.

SELECT geolocation_lat, geolocation_lng, geolocation_zip_code_prefix, COUNT(*)
FROM geolocation
GROUP BY geolocation_lat, geolocation_lng, geolocation_zip_code_prefix
HAVING COUNT(*)>1
-- for the same latitude and longitude we have more than 1 row in some cases


-- ---------------------------------------------------------------------
-- CHECK 11: Encoding sanity check (from the load problem)
-- Question: are accented characters stored correctly?
-- ---------------------------------------------------------------------
SELECT geolocation_city, COUNT(*) AS n_rows
FROM geolocation
WHERE geolocation_city ILIKE 's%o paulo'
GROUP BY geolocation_city;
-- we still have 1 value encodided as sa£o paulo.
-- Expect 'são paulo' / 'sao paulo'; seeing 'sÃ£o paulo' means the load used the wrong encoding.
