# Product Catalog Integration Plan

## Goal

Use the raw `data/food.parquet` catalog as an offline source of truth while keeping the Flutter app fast, stable, and independent of the 7GB file.

## Architecture

```text
Raw Catalog
  -> Catalog Processing Job
  -> optimized_product_catalog.parquet
  -> Firestore product_catalog collection
  -> ProductCatalogService
  -> Admin barcode product form
```

## Optimized Catalog Shape

Target document path:

```text
product_catalog/{barcode}
```

Fields:

- `barcode`: string
- `productName`: string
- `category`: string
- `imageUrl`: string
- `mrp`: number or null
- `source`: string
- `updatedAt`: timestamp
- `searchTokens`: array<string>

Indexes:

- `barcode` lookup is served by document ID.
- `searchTokens array-contains + productName ascending` for admin catalog search.
- Optional `category + productName` for category browsing.

## ProductCatalogService API

```dart
abstract class ProductCatalogService {
  Future<CatalogProduct?> getProductByBarcode(String barcode);

  Future<List<CatalogProduct>> searchProducts({
    required String query,
    int limit = 20,
  });

  Future<double?> getProductMRP(String barcode);
}
```

Behavior:

- `getProductByBarcode()` reads `product_catalog/{normalizedBarcode}`.
- `searchProducts()` uses indexed search tokens and a small limit.
- `getProductMRP()` returns null when no MRP exists.
- Lookup failure never blocks product creation; the admin form keeps manual entry enabled.

## Processing Job

Input formats:

- Parquet
- CSV
- XLSX

Processing rules:

- Stream data by row group or chunk.
- Select only `code`, `product_name`, `categories_tags/categories`, `images`, and future MRP fields.
- Preserve barcode leading zeros.
- Prefer `product_name.lang == "main"`, then English, then first available text.
- Remove rows without barcode.
- Deduplicate by barcode.
- Prefer rows with product name, valid category, and usable image metadata.
- Output `optimized_product_catalog.parquet`.
- Batch import to Firestore in chunks of 400 to 450 writes.

## Scale Targets

- 10k products: Firestore direct lookup and indexed search are sufficient.
- 50k products: keep search token arrays compact and import in batches.
- 100k products: consider prefix fields or Algolia/Meilisearch for richer admin search, but barcode lookup remains a direct document read.

## Rollout

1. Generate and inspect `optimized_product_catalog.parquet`.
2. Import a small staging subset into `product_catalog`.
3. Add Firestore rules for read-only signed-in/admin catalog access.
4. Wire `ProductCatalogService` into the existing barcode lookup flow.
5. Keep OpenFoodFacts/network lookup as optional fallback only if needed.
6. Monitor lookup miss rate and import errors before full rollout.
