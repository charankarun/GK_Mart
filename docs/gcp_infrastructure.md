# GCP Infrastructure & Operations Runbook

## Section 1: Firestore Point-in-Time Recovery (PITR)

**What PITR is**  
Point-in-Time Recovery (PITR) is a Firestore feature that allows you to read documents from any point in time within the past 7 days at a 1-minute granularity.

**Why it matters**  
It provides immediate protection against accidental deletions, bad data migrations, or developer errors that corrupt operational data (e.g., unintentionally clearing the `orders` collection or resetting `inventoryStats`). Unlike traditional backups, it does not require an export/import cycle to recover specific documents.

**Recovery window**  
Up to **7 days** with 1-minute granularity.

**Exact Google Cloud Console navigation**
1. Go to the [Google Cloud Console](https://console.cloud.google.com).
2. Navigate to **Firestore**.
3. Select your database (usually `(default)`).
4. Click on the **Edit** button (or navigate to the Database details page).
5. Toggle **Point-in-time recovery (PITR)** to Enabled.
6. Click **Save**.

**Verification procedure**  
Run the following `gcloud` command to verify PITR is active:
```bash
gcloud alpha firestore databases describe --database="(default)"
```
Ensure `pointInTimeRecoveryEnablement` is set to `POINT_IN_TIME_RECOVERY_ENABLED`.

---

## Section 2: Firestore Backup Strategy

**Daily export strategy**  
While PITR covers the 7-day window, long-term disaster recovery requires daily scheduled exports. Use Cloud Scheduler to trigger a Cloud Function (or Cloud Run job) that calls the `v1.firestore.exportDocuments` API every night during off-peak hours.

**Recommended Cloud Storage bucket setup**
- Bucket Name: `gs://[PROJECT_ID]-firestore-backups`
- Location: Same multi-region or region as your Firestore instance.
- Storage Class: **Standard** or **Nearline** (for the first 30 days).

**Retention policy**
Configure an Object Lifecycle rule on the GCS bucket:
1. Transition to **Coldline** storage after 30 days.
2. Transition to **Archive** storage after 90 days.
3. Delete objects older than 365 days.

**Restore procedure**  
To restore a backup, use the `gcloud` CLI. Note that imports do not delete existing data, they only overwrite documents that exist in both the backup and the database, or add missing ones.
```bash
gcloud firestore import gs://[BUCKET_ID]/[EXPORT_PREFIX] --async
```

**Cost considerations**
- Storage costs in GCS (especially Coldline/Archive) are extremely low.
- However, exporting data from Firestore incurs **document read operations** (1 read per exported document). Exporting a very large database daily can result in significant read costs.

---

## Section 3: Cloud Monitoring Alerts

Based on the structured logging implementation in Phase 5.3, configure the following Log-Based Alerts in Google Cloud Monitoring.

### 1. Pending Order Processing Failure
* **Alert name**: `CRITICAL: processPendingOrder Failure`
* **Log filter**: 
  ```text
  resource.type="cloud_function" 
  AND jsonPayload.functionName="processPendingOrder" 
  AND severity>=ERROR
  ```
* **Severity**: CRITICAL
* **Suggested notification channels**: PagerDuty / SMS / High Priority Incident channel

### 2. Authoritative Analytics Processing Failure
* **Alert name**: `HIGH: processAuthoritativeAnalytics Failure`
* **Log filter**: 
  ```text
  resource.type="cloud_function" 
  AND jsonPayload.functionName="processAuthoritativeAnalytics" 
  AND severity>=ERROR
  ```
* **Severity**: HIGH
* **Suggested notification channels**: Technical Team Email / Engineering Slack

### 3. Stuck Orders Cleanup Failure
* **Alert name**: `HIGH: cleanupStuckOrders Failure`
* **Log filter**: 
  ```text
  resource.type="cloud_function" 
  AND jsonPayload.functionName="cleanupStuckOrders" 
  AND severity>=ERROR
  ```
* **Severity**: HIGH
* **Suggested notification channels**: Technical Team Email / Engineering Slack

### 4. Order Cancellation Failure
* **Alert name**: `CRITICAL: processOrderCancellation Failure`
* **Log filter**: 
  ```text
  resource.type="cloud_function" 
  AND jsonPayload.functionName="processOrderCancellation" 
  AND severity>=ERROR
  ```
* **Severity**: CRITICAL
* **Suggested notification channels**: PagerDuty / SMS / Support Team Email

---

## Section 4: Production Deployment Checklist

Before considering the environment fully ready for production traffic, verify the following are enabled and configured:

- [ ] **Firebase Crashlytics enabled** (Client-side crash reporting active)
- [ ] **Firebase Analytics enabled** (E-commerce events wired correctly)
- [ ] **Cloud Functions Monitoring enabled** (Structured `logger` methods verified)
- [ ] **Firestore PITR enabled** (Via GCP Console)
- [ ] **Firestore backups configured** (Scheduled exports to GCS enabled)
- [ ] **Alert policies configured** (Cloud Monitoring log-based alerts active)
- [ ] **Analytics ledger verification** (`system_stats/analytics_ledger` behaving idempotently)
- [ ] **Order analytics recalibration verification** (Manual trigger works securely)
- [ ] **Inventory stats recalibration verification** (Manual trigger works securely)

---

## Section 5: Disaster Recovery Runbook

In the event of catastrophic data corruption or loss that exceeds the PITR 7-day window, execute the following steps:

1. **Restore Firestore backup**
   - Identify the most recent clean GCS backup.
   - Run `gcloud firestore import gs://[BUCKET_ID]/[EXPORT_PREFIX]` into an empty/restored environment.
2. **Verify Cloud Functions**
   - Ensure all Cloud Functions are deployed and active. Monitor the Logs Explorer to ensure normal operations resume without cascading errors.
3. **Verify dashboard counters**
   - Check the admin dashboard to ensure `totalProducts`, `totalOrders`, etc., appear. They may be slightly stale depending on the backup time.
4. **Run inventory recalibration**
   - Trigger the `recalibrateInventoryStats` endpoint to sync `system_stats/inventory` with the actual restored `products` collection.
5. **Run order analytics recalibration**
   - Trigger the `recalibrateOrderAnalytics` endpoint to sync `system_stats/orders` with the actual restored `orders` collection.
6. **Verify analytics ledger integrity**
   - Ensure `system_stats/authoritative_analytics` matches the restored state. Because the authoritative analytics are driven by idempotency keys in `system_stats/analytics_ledger`, verify that the latest processed `orderId`s exist in the ledger so that historical orders do not trigger duplicate revenue additions if they are re-evaluated.
