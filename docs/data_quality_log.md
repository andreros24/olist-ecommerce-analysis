# Data Quality Log


| # | Check | Issue found | Evidence (numbers) | Decision / treatment |
|---|-------|-------------|--------------------|----------------------|
| 1 | Load | CSV read with WIN1252 instead of UTF-8, `order_reviews` failed to load | Error at row 340 | Added `\encoding UTF8` to `02_load_data.sql`, truncated and reloaded all tables |
| 2 | Order status | Not every order is a real sale | `96478` delivered, `1107` shipped, `625` canceled, `609` unavailable, `314` invoiced, `301` processing, `5` created, `2` approved | Analyze revenue on `delivered` orders only (state this in README) |
| 3 | Delivery dates | Delivered orders with no delivery date or delivery date but status not delivered | `8` orders with no delivery date, `6` delivery dates with status canceled  | Exclude from delivery-time metrics |
| 4 | Orders Timestamps | Illogical orders timestamps | `1359` carrier before approval | This doesn’t affect revenue or delivery-vs-estimate metrics, and I don’t use approval-to-carrier times |
| 5 | Reviews | Orders with multiple reviews | `547` orders, `789` review_id that appears more that once (NOT valid key), `768` orders with no reviews | Keep the latest review per order (`vw_reviews_dedup`), orders with no reviews will not be considered when performing computiation on reviews (AVG ignores NULL values) |
| 6 | Customers | `customer_id` is per order, not per person | `99441` customer_id vs `96096` customer_unique_id, `2997` costumers have more than 1 order | Use `customer_unique_id` for all customer-level analysis |
| 7 | Time window | Sparse months at the start and end of the data | In 2016 and after September 2018 the number of orders is too low for comparison with other months | Restrict to Jan 2017 - Aug 2018 |
| 8 | Products | Products with no category / missing translation | `32951` products, `73` categories, `610` products with no category, for 2 categories: `portateis cozinha e preparadores de alimentos` and `pc_gamer` we don't have an english translation, for 2 products data about dimensions and weight are missing | Instead of using Portuguese names we can use `pc_gamer` and `portable_kitchen_food_preparers` for the 2 missing translation |
| 9 | Payments | Amount paid differs from items + freight | `0.31`% of orders, `303` orders in total, `775` orders without items (`603` unavailable, `164` canceled, `5` created, `2` invoiced, `1` shipped), `1` order without payment | Use item price + freight for product revenue; use payments for cash flow |
| 10 | Geolocation | Many rows per zip prefix and for the same latitude and longitude couple | `1000163` rows for `19015` prefixes | Aggregate per zip prefix before joining |
| 11 | Encoding | Source issue in the encoding of Brazilian city | `1` value was store as sa£o paulo in the original csv file| Use zip code latitude and longitude to identify cities instead of name city |

## Notes
- Add any extra issue you discover while exploring the data.
- Link each decision to the SQL view where it is implemented.
