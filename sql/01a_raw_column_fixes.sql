-- Columns were auto-named string_field_0/1 because auto-detect was off at upload.
ALTER TABLE `olist-analytics-510317.raw.product_category_translation`
  RENAME COLUMN string_field_0 TO product_category_name;

ALTER TABLE `olist-analytics-510317.raw.product_category_translation`
  RENAME COLUMN string_field_1 TO product_category_name_english;