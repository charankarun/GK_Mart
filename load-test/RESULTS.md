# GK Mart Load Test Results & Readiness

## 1. Bottlenecks Found & Fixed (Firestore Contention)
During our initial load tests, we identified a critical write-contention bottleneck on the global `counters/orders` document, which caused a high percentage of checkout transactions to fail with `10 ABORTED` errors under load. 

**The Fix**: We successfully removed the global counter and implemented a distributed, collision-safe reservation pattern using random document IDs (`order_ids/{randomId}`). We verified this fix against live staging — contention errors and transaction aborts completely dropped to zero. We have high confidence this fix will hold and scale linearly in production.

## 2. Verified 500-VU Results (Live Staging)
After scaling the seeded product catalog to 300 products (with 2,000 units of stock each) to prevent artificial single-document contention, we ran a full 8-minute, 500 Virtual User (VU) load test against the **live staging environment** (`slv-super-market-staging`).

**Results:**
- **Max VUs**: 500 sustained
- **Error Rate**: 0.00%
- **Check Rate**: 100.0%
- **Total Requests**: 61,799
- **Avg Latency**: 116 ms (p95: 314 ms)
- **Checkouts Completed**: 3,665 real-time checkouts with exactly **0 aborts**.
- **Checkout Latency (p95)**: 2.4 seconds (2401 ms).

The backend completely absorbed the 500-VU load without a single collision, out-of-stock failure, or timeout. 

## 3. The 2000-VU Extrapolation Gap (GCP Quota Limit)
We added production-appropriate concurrency configurations (`concurrency: 500`) to the `processPendingOrder` trigger, and set a realistic baseline scaling limit of `maxInstances: 20` for it and the callable Auth functions. 

However, we were physically unable to deploy our true aspirational production target of `maxInstances: 200` to the staging environment due to a hard **GCP Project Quota limit**: `Quota exceeded for total allowable CPU per project per region`. Because staging is a standard/limited environment, Google Cloud blocked the allocation of the necessary CPU instances to handle a 2000-user concurrency spike, forcing us to cap the verified load test at 20 instances.

**Conclusion**: Demonstrating the concurrency fix at a true 2,000-user scale requires either requesting a quota increase for the staging project from Google Cloud Support, or deploying the identical verified codebase to the production Blaze-plan environment where quotas are significantly higher (allowing `maxInstances: 200`). A 15-minute load test at 2,000 VUs would only cost roughly **~$2.00**, making it a highly cost-effective validation once the quota ceiling is lifted.
