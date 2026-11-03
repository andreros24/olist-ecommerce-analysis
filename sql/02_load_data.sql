-- Load in this order because of the foreign keys

\copy customers FROM 'data/olist_customers_dataset.csv' CSV HEADER
\copy sellers FROM 'data/olist_sellers_dataset.csv' CSV HEADER
\copy product_category_translation FROM 'data/product_category_name_translation.csv' CSV HEADER
\copy products FROM 'data/olist_products_dataset.csv' CSV HEADER
\copy orders FROM 'data/olist_orders_dataset.csv' CSV HEADER
\copy order_items FROM 'data/olist_order_items_dataset.csv' CSV HEADER
\copy order_payments FROM 'data/olist_order_payments_dataset.csv' CSV HEADER
\copy order_reviews FROM 'data/olist_order_reviews_dataset.csv' CSV HEADER
\copy geolocation FROM 'data/olist_geolocation_dataset.csv' CSV HEADER