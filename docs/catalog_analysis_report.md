# Product Catalog Analysis Report

Source file: `data/food.parquet`

## Safety Notes

- The full parquet file was not loaded into memory.
- Inspection used parquet footer metadata plus one five-row projected batch.
- `pyarrow` was installed into `.dart_tool/parquet_tools` only for local inspection; it is not an app dependency.
- No Firestore import was performed.

## File Metadata

- Size: 7,511,036,020 bytes
- Parquet format version: 2.6
- Created by: `parquet-cpp-arrow version 18.0.0-SNAPSHOT`
- Rows: 4,506,615
- Row groups: 4,410
- Top-level fields: 111
- Leaf columns: 145
- Serialized metadata size: 97,235,064 bytes
- First sampled row groups: 1,021 to 1,024 rows each

## Relevant Column Candidates

- Barcode: `code`
- Product name: `product_name` (`list<struct<lang, text>>`)
- Category: `categories`, `categories_tags`
- Image metadata: `images`, `last_image_t`, `max_imgid`
- Brand: `brands`, `brands_tags`
- MRP: not present in the inspected schema
- Pack size/unit: `quantity`, `product_quantity`, `product_quantity_unit`

## Sample Records

| Barcode | Product Name | Category | Brand | Quantity | Image Metadata |
| --- | --- | --- | --- | --- | --- |
| `0000101209159` | `Veritable pate a tartiner noisettes chocolat noir` | Cocoa/hazelnut spreads | `Bovetti` | `350 g` | Present in `images` |
| `0000105000011` | `Chamomile Herbal Tea` | `en:null` | `Lagg's` | `1 g` | Empty `images` |
| `0000105000042` | `Lagg's, herbal tea, peppermint` | Tea bags | `Lagg's` | null | Empty `images` |
| `0000105000059` | `Linden Flowers Tea` | Tea leaves / tea bags | `Lagg's` | `1.5 g` | Empty `images` |
| `0000105000073` | `Herbal Tea, Hibiscus` | null | `Lagg's` | null | Empty `images` |

## Mapping Recommendation

Use these source-to-app mappings for the optimized catalog:

| App Field | Source Field | Notes |
| --- | --- | --- |
| `barcode` | `code` | Keep as a string and preserve leading zeros. |
| `productName` | `product_name` | Prefer `lang == "main"`, then English, then first non-empty text. |
| `category` | `categories_tags` or `categories` | Prefer cleaned tags; ignore `null` and `en:null`. |
| `imageUrl` | derived from `images` + `code` | Requires deterministic image URL derivation or later CDN hydration. |
| `mrp` | unavailable | Admin must enter MRP unless a future source includes pricing. |

## Processing Recommendation

Create `optimized_product_catalog.parquet` from streaming row groups with only:

- `barcode`
- `productName`
- `category`
- `imageUrl`
- `mrp`

Deduplicate by barcode, prefer rows with product name, category, and usable image metadata, and do not ship the raw 7GB catalog to mobile clients.
