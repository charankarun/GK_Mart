/**
 * ==============================================================================
 * FILE: functions/src/index.ts
 * PURPOSE: Firebase Cloud Functions for backend business logic, validation, and analytics.
 * LAYER: Backend / Cloud Infrastructure
 * DEPENDENCIES: firebase-admin, firebase-functions
 * 
 * ARCHITECTURE NOTES:
 * 
 *   Customer (App)
 *       │
 *       ▼ [Direct Firestore Write]
 *   Creates "Pending" Order
 *       │
 *       ▼ [Firestore Document Trigger: onDocumentCreated]
 *   processPendingOrder (Cloud Function)
 *       ├── 1. Reads catalog products in a Firestore Transaction
 *       ├── 2. Performs SECURITY CHECK: Validates catalog prices against client prices
 *       ├── 3. Performs STOCK CHECK: Validates inventory availability
 *       ├── 4. Increments order counter & assigns official Order ID (e.g., GK00001)
 *       ├── 5. Updates catalog inventory (reduces stock, marks unavailable if 0)
 *       ├── 6. Transitions order status to "Placed"
 *       └── 7. Dispatches deterministic notifications (Customer & Admin logs)
 *       │
 *       ▼ [Client Listener]
 *   Customer App hears status change to "Placed" & completes checkout.
 * 
 * IDEMPOTENCY & FAULT TOLERANCE:
 * - Order processing uses a single consolidated Transaction. If stock check, price validation,
 *   or ID generation fails, the entire transaction reverts and the order transitions to "Failed".
 * - Cron jobs (cleanupStuckOrders) clean up lingering "Pending" orders that timed out.
 * ==============================================================================
 */

import * as functions from "firebase-functions/v2";
import { logger } from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as v1 from "firebase-functions/v1";
import * as admin from "firebase-admin";

admin.initializeApp();
const db = admin.firestore();

/**
 * @function processPendingOrder
 * @trigger Firestore - onDocumentCreated ("orders/{orderId}")
 * @purpose Handles validation, stock deduction, official ID generation, and transitions order from Pending to Placed.
 * @inputs event - Firestore Event containing the raw pending order data.
 * @outputs Promise<void> - Completes when transaction finishes and notifications are dispatched.
 * @transactionFlow
 *   - Fetches product details in read-phase.
 *   - Validates client prices/discount/subtotal against authoritative catalog values.
 *   - Verifies stock and locks quantities.
 *   - Atomically increments orders counter.
 *   - Updates product stock levels.
 *   - Updates order document with official order identifier and "Placed" status.
 * @failureHandling
 *   - Any error during validation/transaction reverts all changes and updates the order status to "Failed" with failureReason.
 * @securityConsiderations
 *   - Client prices are never trusted. All calculations are validated on the backend.
 *   - Prevents stock-tampering and race conditions by operating inside a transaction.
 * @sideEffects
 *   - Dispatches notification documents to /notifications for customer and admins.
 */
export const processPendingOrder = functions.firestore.onDocumentCreated(
  "orders/{orderId}",
  async (event) => {
    const orderDoc = event.data;
    if (!orderDoc) return;

    const order = orderDoc.data();
    if (order.status !== "Pending") return;

    logger.info("processPendingOrder: started", { functionName: "processPendingOrder", orderId: event.params.orderId, userId: order.userId, itemCount: (order.items || []).length });

    try {
      const generatedOrderId = await db.runTransaction(async (transaction) => {
        const orderRef = db.collection("orders").doc(event.params.orderId);

        // 1. Read products
        const items = order.items || [];
        const productRefs = items.map((item: any) => db.collection("products").doc(item.productId));
        const productDocs: admin.firestore.DocumentSnapshot[] = [];
        for (const ref of productRefs) {
          productDocs.push(await transaction.get(ref) as any);
        }

        // 2. Validate stock and prices
        let expectedOriginalAmount = 0;
        let expectedProductSavings = 0;

        for (let i = 0; i < items.length; i++) {
          const item = items[i];
          const productDoc = productDocs[i];
          if (!productDoc.exists) {
            throw new Error(`Product no longer available: ${item.name || item.productId}`);
          }
          const productData = productDoc.data();

          // A. Stock Validation
          const trackStock = productData?.trackStock ?? (productData?.stockQuantity != null);
          if (trackStock) {
            const currentStock = productData?.stockQuantity || 0;
            if (currentStock < item.quantity) {
              throw new Error(`Out of stock: ${item.name}`);
            }
          }

          // B. Price Validation against current catalog data (Never trust client values)
          const authoritativePrice = typeof productData?.price === "number" ? productData.price : 0;
          const authoritativeDiscountPrice = typeof productData?.discountPrice === "number" ? productData.discountPrice : 0;

          const basePrice = authoritativePrice;
          const baseDiscountPrice = authoritativeDiscountPrice;

          const effectivePrice = (baseDiscountPrice > 0 && baseDiscountPrice < basePrice)
            ? baseDiscountPrice
            : basePrice;

          const clientPrice = typeof item.price === "number" ? item.price : 0;
          const clientDiscountPrice = typeof item.discountPrice === "number" ? item.discountPrice : 0;
          const clientLineTotal = typeof item.lineTotal === "number" ? item.lineTotal : 0;

          const expectedLineTotal = Math.round(effectivePrice * item.quantity * 100) / 100;

          // Perform checks for item price and discount price and line total
          if (
            Math.abs(clientPrice - authoritativePrice) > 0.001 ||
            Math.abs(clientDiscountPrice - authoritativeDiscountPrice) > 0.001 ||
            Math.abs(clientLineTotal - expectedLineTotal) > 0.001
          ) {
            logger.error("SECURITY ALERT: Price tampering detected on item", {
              orderId: event.params.orderId,
              userId: order.userId,
              productId: item.productId,
              clientPrice,
              catalogPrice: authoritativePrice,
              clientDiscountPrice,
              catalogDiscountPrice: authoritativeDiscountPrice,
              clientLineTotal,
              expectedLineTotal
            });
            throw new Error("Product price has changed. Please place the order again.");
          }

          expectedOriginalAmount += effectivePrice * item.quantity;
          expectedProductSavings += (basePrice - effectivePrice) * item.quantity;
        }

        // Recalculate totals
        expectedOriginalAmount = Math.round(expectedOriginalAmount * 100) / 100;
        expectedProductSavings = Math.round(expectedProductSavings * 100) / 100;

        // Calculate expected cartDiscount
        // BUSINESS RULE: Cart Discount thresholds
        // OriginalAmount >= 4000: ₹150 off
        // OriginalAmount >= 3000: ₹100 off
        // OriginalAmount >= 2000: ₹50 off
        let expectedCartDiscount = 0;
        if (expectedOriginalAmount >= 4000) {
          expectedCartDiscount = 150;
        } else if (expectedOriginalAmount >= 3000) {
          expectedCartDiscount = 100;
        } else if (expectedOriginalAmount >= 2000) {
          expectedCartDiscount = 50;
        }

        // Calculate expected deliveryFee
        // BUSINESS RULE: Free delivery on orders >= ₹699. Otherwise flat ₹50.
        const expectedDeliveryFee = expectedOriginalAmount >= 699 ? 0 : 50;

        // Calculate expected final totals
        const expectedTotalAmount = Math.round((expectedOriginalAmount - expectedCartDiscount + expectedDeliveryFee) * 100) / 100;
        const expectedTotalSavings = Math.round((expectedProductSavings + expectedCartDiscount) * 100) / 100;

        // Compare against client values
        const clientOriginalAmount = typeof order.originalAmount === "number" ? order.originalAmount : 0;
        const clientSubtotal = typeof order.subtotal === "number" ? order.subtotal : 0;
        const clientTotalAmount = typeof order.totalAmount === "number" ? order.totalAmount : 0;
        const clientTotal = typeof order.total === "number" ? order.total : 0;
        const clientTotalSavings = typeof order.totalSavings === "number" ? order.totalSavings : 0;
        const clientCartDiscount = typeof order.cartDiscount === "number" ? order.cartDiscount : 0;
        const clientDeliveryFee = typeof order.deliveryFee === "number" ? order.deliveryFee : 0;

        let orderLevelMismatch = false;

        if (order.originalAmount !== undefined && Math.abs(clientOriginalAmount - expectedOriginalAmount) > 0.001) {
          orderLevelMismatch = true;
        }
        if (order.subtotal !== undefined && Math.abs(clientSubtotal - expectedOriginalAmount) > 0.001) {
          orderLevelMismatch = true;
        }
        if (order.totalAmount !== undefined && Math.abs(clientTotalAmount - expectedTotalAmount) > 0.001) {
          orderLevelMismatch = true;
        }
        if (order.total !== undefined && Math.abs(clientTotal - expectedTotalAmount) > 0.001) {
          orderLevelMismatch = true;
        }
        if (order.totalSavings !== undefined && Math.abs(clientTotalSavings - expectedTotalSavings) > 0.001) {
          orderLevelMismatch = true;
        }
        if (order.cartDiscount !== undefined && Math.abs(clientCartDiscount - expectedCartDiscount) > 0.001) {
          orderLevelMismatch = true;
        }
        if (order.deliveryFee !== undefined && Math.abs(clientDeliveryFee - expectedDeliveryFee) > 0.001) {
          orderLevelMismatch = true;
        }

        // Additional aggregated assertions as fallback checks
        const clientOriginalVal = Math.round((order.originalAmount || order.subtotal || 0) * 100) / 100;
        const clientTotalVal = Math.round((order.totalAmount || order.total || 0) * 100) / 100;
        const clientSavingsVal = Math.round((order.totalSavings || 0) * 100) / 100;
        const clientDiscountVal = Math.round((order.cartDiscount || 0) * 100) / 100;
        const clientDeliveryVal = Math.round((order.deliveryFee || 0) * 100) / 100;

        if (
          Math.abs(clientOriginalVal - expectedOriginalAmount) > 0.001 ||
          Math.abs(clientTotalVal - expectedTotalAmount) > 0.001 ||
          Math.abs(clientSavingsVal - expectedTotalSavings) > 0.001 ||
          Math.abs(clientDiscountVal - expectedCartDiscount) > 0.001 ||
          Math.abs(clientDeliveryVal - expectedDeliveryFee) > 0.001 ||
          orderLevelMismatch
        ) {
          logger.error("SECURITY ALERT: Order totals mismatch or tampering detected", {
            orderId: event.params.orderId,
            userId: order.userId,
            clientOriginalAmount, clientSubtotal, expectedOriginalAmount,
            clientTotalAmount, clientTotal, expectedTotalAmount,
            clientTotalSavings, expectedTotalSavings,
            clientCartDiscount, expectedCartDiscount,
            clientDeliveryFee, expectedDeliveryFee
          });
          throw new Error("Product price has changed. Please place the order again.");
        }

        // 3. Read counter and generate official ID
        // SECURITY & PERFORMANCE: Order counter sequencing handles collisions sequentially.
        const counterRef = db.collection("counters").doc("orders");
        const counterDoc = await transaction.get(counterRef);
        const nextNumber = counterDoc.exists ? (counterDoc.data()?.next || 2) : 2;
        const officialOrderId = `GK${nextNumber.toString().padStart(5, '0')}`;

        // 4. Update stock
        // BUSINESS RULE: Deduct product quantity from inventory and disable item if stock hits 0.
        for (let i = 0; i < items.length; i++) {
          const item = items[i];
          const productDoc = productDocs[i];
          if (productDoc.exists) {
            const productData = productDoc.data();
            const trackStock = productData?.trackStock ?? (productData?.stockQuantity != null);
            if (trackStock) {
              const currentStock = productData?.stockQuantity || 0;
              const nextQuantity = currentStock - item.quantity;

              const updateData: any = {
                stockQuantity: admin.firestore.FieldValue.increment(-item.quantity),
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              };
              if (nextQuantity <= 0) {
                updateData.isAvailable = false;
              }
              transaction.update(productRefs[i], updateData);
            }
          }
        }

        // 5. Update counter
        transaction.set(counterRef, {
          next: nextNumber + 1,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        // 6. Update order status and official ID
        // PERFORMANCE: Generate search tokens for admin order management search.
        const searchValues = [
          officialOrderId,
          order.userName || order.customerName || "",
          order.phone || "",
          ...(order.items || []).map((item: any) => item.name || "")
        ].filter((val): val is string => typeof val === "string" && val.trim().length > 0);
        const updatedTokens = generateOrderSearchTokens(searchValues);

        transaction.update(orderRef, {
          orderId: officialOrderId,
          status: "Placed",
          searchTokens: updatedTokens,
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        return officialOrderId;
      });

      logger.info("processPendingOrder: order placed successfully", { functionName: "processPendingOrder", orderId: event.params.orderId, officialOrderId: generatedOrderId, userId: order.userId, operation: "stock_deducted_order_placed" });

      // Secondary Block (Post-Commit) - Notifications
      try {
        const batch = db.batch();
        const dateStr = new Date().toISOString();

        // Use deterministic IDs
        const custNotifRef = db.collection("notifications").doc(`customer_order_placed_${event.params.orderId}`);
        const adminNotifRef = db.collection("notifications").doc(`admin_new_order_${event.params.orderId}`);

        const amount = order.totalAmount || 0;
        const amountStr = amount % 1 === 0 ? amount.toFixed(0) : amount.toFixed(2);
        const title = `Order Placed - ${generatedOrderId}`;
        const body = `Your order of ₹${amountStr} has been successfully placed.`;
        const adminBody = `New order ${generatedOrderId} placed by ${order.userName || order.customerName || 'Customer'} for ₹${amountStr}.`;

        batch.set(custNotifRef, {
          type: "customer_order_placed",
          eventType: "customer_order_placed",
          targetUserId: order.userId,
          targetRole: "",
          sourceUserId: "",
          sourceInstanceId: "backend",
          orderId: event.params.orderId,
          status: "placed",
          title: title,
          body: body,
          amount: amountStr,
          customerName: order.userName || order.customerName || "",
          phone: order.phone || "",
          date: dateStr,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false
        });

        batch.set(adminNotifRef, {
          type: "admin_new_order",
          eventType: "admin_new_order",
          targetUserId: "",
          targetRole: "admin",
          sourceUserId: "",
          sourceInstanceId: "backend",
          orderId: event.params.orderId,
          status: "placed",
          title: `New Order: ${generatedOrderId}`,
          body: adminBody,
          amount: amountStr,
          customerName: order.userName || order.customerName || "",
          phone: order.phone || "",
          date: dateStr,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          isRead: false
        });

        await batch.commit();
      } catch (error) {
        logger.warn("processPendingOrder: notification dispatch failed (non-critical)", { functionName: "processPendingOrder", orderId: event.params.orderId, officialOrderId: generatedOrderId, operation: "notification_dispatch", error: (error as any)?.message });
      }
    } catch (error: any) {
      logger.error("processPendingOrder: transaction failed", { functionName: "processPendingOrder", orderId: event.params.orderId, userId: order.userId, operation: "place_order_transaction", status: "Failed", error: error?.message });
      // Transaction failed
      await db.collection("orders").doc(event.params.orderId).update({
        status: "Failed",
        failureReason: error.message || "Unknown error",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
  }
);

/**
 * @function processOrderCancellation
 * @trigger Firestore - onDocumentUpdated ("orders/{orderId}")
 * @purpose Handles restocking products when an order transitions to Cancellation_Requested or Cancelled.
 * @inputs event - Firestore Event with before and after state documents.
 * @outputs Promise<void> - Completes when inventory restoration is completed.
 * @transactionFlow
 *   - Evaluates if the order had stock deducted (status transitions from valid validation states).
 *   - Restores item quantities back to database using increments.
 *   - Automatically flags products as 'available' if stock quantity rises above 0.
 * @securityConsiderations
 *   - Idempotency check: Rejects stock restoration if order was already cancelled.
 */
export const processOrderCancellation = functions.firestore.onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;

    logger.info("processOrderCancellation: started", { functionName: "processOrderCancellation", orderId: event.params.orderId, beforeStatus: before.status, afterStatus: after.status, eventType: "cancellation" });

    // Only process when status changes to Cancelled or Cancellation_Requested for the FIRST time
    // If it was already cancelled or requested, do not restore stock again (prevent duplicate restorations)
    if (before.status === "Cancelled" || before.status === "Cancellation_Requested") {
      return;
    }

    if (after.status !== "Cancellation_Requested" && after.status !== "Cancelled") {
      return;
    }

    try {
      const wasStockDeducted = [
        "Placed",
        "Order Confirmed",
        "Packed",
        "Shipped",
        "Out for Delivery"
      ].includes(before.status);

      await db.runTransaction(async (transaction) => {
        const orderRef = db.collection("orders").doc(event.params.orderId);

        if (wasStockDeducted) {
          // 1. Read products to restore stock
          const items = after.items || [];
          const productRefs = items.map((item: any) => db.collection("products").doc(item.productId));
          const productDocs: admin.firestore.DocumentSnapshot[] = [];
          for (const ref of productRefs) {
            productDocs.push(await transaction.get(ref) as any);
          }

          // 2. Restore stock
          for (let i = 0; i < items.length; i++) {
            const item = items[i];
            const productDoc = productDocs[i];
            if (productDoc.exists) {
              const productData = productDoc.data();
              const trackStock = productData?.trackStock ?? (productData?.stockQuantity != null);
              if (trackStock) {
                const currentStock = productData?.stockQuantity || 0;
                const nextQuantity = currentStock + item.quantity;

                const updateData: any = {
                  stockQuantity: admin.firestore.FieldValue.increment(item.quantity),
                  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                };
                if (nextQuantity > 0) {
                  updateData.isAvailable = true;
                }
                transaction.update(productRefs[i], updateData);
              }
            }
          }
        }

        // 3. Update order status to Cancelled
        transaction.update(orderRef, {
          status: "Cancelled",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      });

      const operationName = wasStockDeducted ? "stock_restore_cancel" : "status_only_cancel";
      logger.info(`processOrderCancellation: order cancelled successfully (${operationName})`, { functionName: "processOrderCancellation", orderId: event.params.orderId, itemCount: (after.items || []).length, operation: operationName });
    } catch (error: any) {
      logger.error("processOrderCancellation: transaction failed", { functionName: "processOrderCancellation", orderId: event.params.orderId, beforeStatus: before.status, afterStatus: after.status, operation: "cancellation_transaction", error: error?.message });
    }
  }
);

/**
 * @function processOrderStatusUpdate
 * @trigger Firestore - onDocumentUpdated ("orders/{orderId}")
 * @purpose Dispatches push notifications to customer subcollections on order progress changes.
 * @inputs event - Firestore Event with before and after state documents.
 */
export const processOrderStatusUpdate = functions.firestore.onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;

    if (before.status === after.status) return;

    // Ignore transitions handled explicitly elsewhere (like cancellation requests starting up)
    if (after.status === "Cancellation_Requested" || after.status === "Pending") return;

    const status = after.status;
    const orderId = event.params.orderId;
    const targetUserId = after.userId;

    const normalizedStatus = status.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
    const eventId = event.id || Date.now().toString();

    logger.info("processOrderStatusUpdate: dispatching notification", { functionName: "processOrderStatusUpdate", orderId, status, eventType: `status_${normalizedStatus}`, targetUserId });

    try {
      const notifRef = db.collection("notifications").doc(`customer_status_${orderId}_${normalizedStatus}_${eventId}`);
      await notifRef.set({
        type: "order_status",
        eventType: "order_status",
        targetUserId: targetUserId,
        targetRole: "",
        sourceUserId: "",
        sourceInstanceId: "backend",
        orderId: orderId,
        status: normalizedStatus,
        title: `Order ${status}`,
        body: `Your order is now ${status}.`,
        amount: "",
        customerName: after.userName || after.customerName || "",
        phone: after.phone || "",
        date: new Date().toISOString(),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        isRead: false
      });
      logger.info("processOrderStatusUpdate: status notification dispatched", { functionName: "processOrderStatusUpdate", orderId, status, eventType: `status_${normalizedStatus}`, targetUserId, operation: "notification_dispatch" });
    } catch (error) {
      logger.warn("processOrderStatusUpdate: notification dispatch failed (non-critical)", { functionName: "processOrderStatusUpdate", orderId, status, targetUserId, operation: "notification_dispatch", error: (error as any)?.message });
    }
  }
);

/**
 * @function cleanupStuckOrders
 * @trigger Cloud Scheduler Cron - "every 15 minutes"
 * @purpose Traverses and fails orders trapped in "Pending" for >15 minutes to unlock resources.
 */
export const cleanupStuckOrders = onSchedule("every 15 minutes", async (event) => {
  const fifteenMinsAgo = new Date(Date.now() - 15 * 60 * 1000);

  try {
    const snapshot = await db.collection("orders")
      .where("status", "==", "Pending")
      .where("timestamp", "<", admin.firestore.Timestamp.fromDate(fifteenMinsAgo))
      .get();

    if (snapshot.empty) {
      logger.info("cleanupStuckOrders: no stuck orders found", { functionName: "cleanupStuckOrders", operation: "scheduled_cleanup" });
      return;
    }

    let batch = db.batch();
    let count = 0;

    for (const doc of snapshot.docs) {
      batch.update(doc.ref, {
        status: "Failed",
        failureReason: "Transaction Timeout (Order stuck in Pending)",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      count++;

      // PERFORMANCE: Respect Firestore batch operation size limitations of 500 writes max.
      if (count === 500) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }

    logger.info("cleanupStuckOrders: cleanup completed", { functionName: "cleanupStuckOrders", operation: "scheduled_cleanup", ordersFailedCount: snapshot.size });
  } catch (error) {
    logger.error("cleanupStuckOrders: cleanup failed", { functionName: "cleanupStuckOrders", operation: "scheduled_cleanup", error: (error as any)?.message });
  }
});

/**
 * @function processUserDeletion
 * @trigger Auth - onDelete
 * @purpose Wipes user metadata folders and redacts sensitive customer references from historical orders.
 */
export const processUserDeletion = v1.auth.user().onDelete(async (user) => {
  const uid = user.uid;

  try {
    let batch = db.batch();
    let count = 0;

    // 1. Delete user documents
    batch.delete(db.collection("users").doc(uid));
    batch.delete(db.collection("carts").doc(uid));
    batch.delete(db.collection("wishlist").doc(uid));
    count += 3;

    // 2. Anonymize Orders
    const ordersSnapshot = await db.collection("orders").where("userId", "==", uid).get();

    for (const doc of ordersSnapshot.docs) {
      batch.update(doc.ref, {
        userName: "Deleted User",
        customerName: "Deleted User",
        phone: "Redacted",
        address: "Redacted",
        email: "Redacted",
        searchTokens: [],
        userDeleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      count++;

      // Handle Firestore 500 operation limit per batch
      if (count === 500) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }

    // Commit any remaining operations
    if (count > 0) {
      await batch.commit();
    }

    logger.info("processUserDeletion: completed", { functionName: "processUserDeletion", uid, operation: "user_data_deletion", ordersAnonymized: ordersSnapshot.size });
  } catch (error) {
    logger.error("processUserDeletion: failed", { functionName: "processUserDeletion", uid, operation: "user_data_deletion", error: (error as any)?.message });
  }
}
);

/**
 * @function processProductWrite
 * @trigger Firestore - onDocumentWritten ("products/{productId}")
 * @purpose Syncs counters in administrative dashboard_stats upon catalog product updates.
 */
export const processProductWrite = functions.firestore.onDocumentWritten(
  "products/{productId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    let totalDelta = 0;
    let availableDelta = 0;
    let lowStockDelta = 0;

    const evaluate = (data: any | undefined) => {
      if (!data) return { exists: false, available: false, lowStock: false };

      const isAvailable = data.isAvailable === true;
      const trackStock = data.trackStock === true;
      const stockQuantity = typeof data.stockQuantity === 'number' ? data.stockQuantity : null;
      const lowStockThreshold = typeof data.lowStockThreshold === 'number' ? data.lowStockThreshold : 5;

      const isStockEmpty = trackStock && stockQuantity !== null && stockQuantity <= 0;
      const isLowStock = trackStock && stockQuantity !== null && stockQuantity > 0 && stockQuantity <= lowStockThreshold;
      const available = isAvailable && !isStockEmpty;

      return { exists: true, available, lowStock: isLowStock };
    };

    const b = evaluate(before);
    const a = evaluate(after);

    if (!b.exists && a.exists) totalDelta += 1;
    if (b.exists && !a.exists) totalDelta -= 1;

    if (!b.available && a.available) availableDelta += 1;
    if (b.available && !a.available) availableDelta -= 1;

    if (!b.lowStock && a.lowStock) lowStockDelta += 1;
    if (b.lowStock && !a.lowStock) lowStockDelta -= 1;

    const outOfStockDelta = totalDelta - availableDelta;

    if (totalDelta === 0 && availableDelta === 0 && outOfStockDelta === 0 && lowStockDelta === 0) {
      return;
    }

    const updates: any = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    if (totalDelta !== 0) updates.totalProducts = admin.firestore.FieldValue.increment(totalDelta);
    if (availableDelta !== 0) updates.availableProducts = admin.firestore.FieldValue.increment(availableDelta);
    if (outOfStockDelta !== 0) updates.outOfStockProducts = admin.firestore.FieldValue.increment(outOfStockDelta);
    if (lowStockDelta !== 0) updates.lowStockProducts = admin.firestore.FieldValue.increment(lowStockDelta);

    try {
      await db.collection("system_stats").doc("dashboard_stats").set(updates, { merge: true });
    } catch (error) {
      logger.error("processProductWrite: failed to update product stats", { functionName: "processProductWrite", productId: event.params.productId, operation: "stats_update", totalDelta, availableDelta, error: (error as any)?.message });
    }
  }
);

/**
 * @function processCategoryWrite
 * @trigger Firestore - onDocumentWritten ("categories/{categoryId}")
 * @purpose Syncs total categories count in administrative dashboard_stats.
 */
export const processCategoryWrite = functions.firestore.onDocumentWritten(
  "categories/{categoryId}",
  async (event) => {
    const beforeExists = event.data?.before.exists ?? false;
    const afterExists = event.data?.after.exists ?? false;

    let delta = 0;
    if (!beforeExists && afterExists) delta = 1;
    if (beforeExists && !afterExists) delta = -1;

    if (delta === 0) return;

    try {
      await db.collection("system_stats").doc("dashboard_stats").set({
        totalCategories: admin.firestore.FieldValue.increment(delta),
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });
    } catch (error) {
      logger.error("processCategoryWrite: failed to update category stats", { functionName: "processCategoryWrite", categoryId: event.params.categoryId, operation: "stats_update", delta, error: (error as any)?.message });
    }
  }
);

/**
 * @function recalibrateInventoryStats
 * @trigger Callable onCall
 * @purpose Recalculates stats values from products collection to resolve counts mismatches.
 * @securityConsiderations
 *   - Restricts execution strictly to authenticated owners or administrative UIDs.
 */
export const recalibrateInventoryStats = onCall(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Must be authenticated."
      );
    }

    const userDoc = await db.collection("users").doc(request.auth.uid).get();
    const role = userDoc.data()?.role?.toString().trim().toLowerCase();
    if (!userDoc.exists || (role !== "admin" && role !== "owner")) {
      throw new HttpsError(
        "permission-denied",
        "Must be an admin or owner to recalibrate stats."
      );
    }

    try {
      const categoriesSnapshot = await db.collection("categories").count().get();
      const totalCategories = categoriesSnapshot.data().count;

      const productsSnapshot = await db.collection("products").get();

      let totalProducts = 0;
      let availableProducts = 0;
      // let outOfStockProducts = 0; // unused
      let lowStockProducts = 0;

      for (const doc of productsSnapshot.docs) {
        const data = doc.data();
        totalProducts += 1;

        const isAvailable = data.isAvailable === true;
        const trackStock = data.trackStock === true;
        const stockQuantity = typeof data.stockQuantity === 'number' ? data.stockQuantity : null;
        const lowStockThreshold = typeof data.lowStockThreshold === 'number' ? data.lowStockThreshold : 5;

        const isStockEmpty = trackStock && stockQuantity !== null && stockQuantity <= 0;
        const isLowStock = trackStock && stockQuantity !== null && stockQuantity > 0 && stockQuantity <= lowStockThreshold;
        const available = isAvailable && !isStockEmpty;

        if (available) availableProducts += 1;
        if (isLowStock) lowStockProducts += 1;
      }

      const outOfStockProductsCalc = totalProducts - availableProducts;

      await db.collection("system_stats").doc("dashboard_stats").set({
        totalCategories,
        totalProducts,
        availableProducts,
        outOfStockProducts: outOfStockProductsCalc,
        lowStockProducts,
        lastRecalibratedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastRecalibratedBy: request.auth.uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

      logger.info("recalibrateInventoryStats: completed", { functionName: "recalibrateInventoryStats", uid: request.auth.uid, operation: "inventory_recalibration", totalProducts, availableProducts, outOfStockProducts: outOfStockProductsCalc, lowStockProducts, totalCategories });
      return { success: true, message: "Inventory stats recalibrated successfully." };

    } catch (error) {
      logger.error("recalibrateInventoryStats: failed", { functionName: "recalibrateInventoryStats", uid: request.auth.uid, operation: "inventory_recalibration", error: (error as any)?.message });
      throw new functions.https.HttpsError("internal", "Failed to recalibrate inventory stats.");
    }
  }
);

/**
 * @function processOrderWrite
 * @trigger Firestore - onDocumentWritten ("orders/{orderId}")
 * @purpose Syncs total revenue, total orders, and pending orders indicators inside order_analytics document.
 */
export const processOrderWrite = functions.firestore.onDocumentWritten(
  "orders/{orderId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    let ordersDelta = 0;
    let pendingDelta = 0;
    let deliveredDelta = 0;
    let revenueDelta = 0.0;

    const normalizeStatus = (status: any) => {
      if (!status) return 'Placed';
      const trimmed = String(status).trim();
      if (!trimmed) return 'Placed';
      const lowerStatus = trimmed.toLowerCase();

      if (lowerStatus === 'pending') return 'Placed';
      if (lowerStatus === 'confirmed' || lowerStatus === 'order confirmed') return 'Order Confirmed';
      if (lowerStatus === 'processing') return 'Packed';
      if (lowerStatus === 'out for delivery' || lowerStatus === 'out_for_delivery' || lowerStatus === 'out-for-delivery') return 'Out for Delivery';
      if (lowerStatus === 'canceled') return 'Cancelled';

      const validStatuses = [
        'Pending', 'Cancellation_Requested', 'Placed', 'Order Confirmed',
        'Packed', 'Shipped', 'Out for Delivery', 'Delivered', 'Cancelled'
      ];

      for (const valid of validStatuses) {
        if (valid.toLowerCase() === lowerStatus) return valid;
      }
      return 'Placed';
    };

    const getRevenue = (data: any) => {
      const fields = ['totalAmount', 'total', 'paymentAmount'];
      for (const field of fields) {
        let val = data[field];
        if (val != null) {
          if (typeof val === 'string') val = parseFloat(val);
          if (typeof val === 'number' && !isNaN(val)) return val < 0 ? 0 : val;
        }
      }
      return 0.0;
    };

    const evaluate = (data: any | undefined) => {
      if (!data) return { exists: false, pending: false, delivered: false, revenue: 0.0 };
      const status = normalizeStatus(data.status);
      const isPending = status === 'Placed' || status === 'Packed' || status === 'Out for Delivery';
      const isDelivered = status === 'Delivered';
      const revenue = getRevenue(data);
      return { exists: true, pending: isPending, delivered: isDelivered, revenue };
    };

    const b = evaluate(before);
    const a = evaluate(after);

    if (!b.exists && a.exists) ordersDelta += 1;
    if (b.exists && !a.exists) ordersDelta -= 1;

    if (!b.pending && a.pending) pendingDelta += 1;
    if (b.pending && !a.pending) pendingDelta -= 1;

    if (!b.delivered && a.delivered) deliveredDelta += 1;
    if (b.delivered && !a.delivered) deliveredDelta -= 1;

    revenueDelta = a.revenue - b.revenue;

    if (ordersDelta === 0 && pendingDelta === 0 && deliveredDelta === 0 && revenueDelta === 0.0) {
      return;
    }

    const updates: any = { updatedAt: admin.firestore.FieldValue.serverTimestamp() };
    if (ordersDelta !== 0) updates.totalOrders = admin.firestore.FieldValue.increment(ordersDelta);
    if (pendingDelta !== 0) updates.pendingOrders = admin.firestore.FieldValue.increment(pendingDelta);
    if (deliveredDelta !== 0) updates.deliveredOrders = admin.firestore.FieldValue.increment(deliveredDelta);
    if (revenueDelta !== 0.0) updates.revenue = admin.firestore.FieldValue.increment(revenueDelta);

    try {
      await db.collection("system_stats").doc("order_analytics").set(updates, { merge: true });
    } catch (error) {
      logger.error("processOrderWrite: failed to update order analytics", { functionName: "processOrderWrite", orderId: event.params.orderId, operation: "stats_update", ordersDelta, pendingDelta, deliveredDelta, revenueDelta, error: (error as any)?.message });
    }
  }
);

/**
 * @function recalibrateOrderAnalytics
 * @trigger Callable onCall
 * @purpose Recalculates metrics (revenue, totals, statuses) from scratch based on orders logs to correct analytical offsets.
 * @securityConsiderations
 *   - Restricts execution strictly to authenticated owners or administrative accounts.
 */
export const recalibrateOrderAnalytics = onCall(
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Must be authenticated."
      );
    }

    const userDoc = await db.collection("users").doc(request.auth.uid).get();
    const role = userDoc.data()?.role?.toString().trim().toLowerCase();
    if (!userDoc.exists || (role !== "admin" && role !== "owner")) {
      throw new HttpsError(
        "permission-denied",
        "Must be an admin or owner to recalibrate stats."
      );
    }

    const normalizeStatus = (status: any) => {
      if (!status) return 'Placed';
      const trimmed = String(status).trim();
      if (!trimmed) return 'Placed';
      const lowerStatus = trimmed.toLowerCase();

      if (lowerStatus === 'pending') return 'Placed';
      if (lowerStatus === 'confirmed' || lowerStatus === 'order confirmed') return 'Order Confirmed';
      if (lowerStatus === 'processing') return 'Packed';
      if (lowerStatus === 'out for delivery' || lowerStatus === 'out_for_delivery' || lowerStatus === 'out-for-delivery') return 'Out for Delivery';
      if (lowerStatus === 'canceled') return 'Cancelled';

      const validStatuses = [
        'Pending', 'Cancellation_Requested', 'Placed', 'Order Confirmed',
        'Packed', 'Shipped', 'Out for Delivery', 'Delivered', 'Cancelled'
      ];

      for (const valid of validStatuses) {
        if (valid.toLowerCase() === lowerStatus) return valid;
      }
      return 'Placed';
    };

    const getRevenue = (data: any) => {
      const fields = ['totalAmount', 'total', 'paymentAmount'];
      for (const field of fields) {
        let val = data[field];
        if (val != null) {
          if (typeof val === 'string') val = parseFloat(val);
          if (typeof val === 'number' && !isNaN(val)) return val < 0 ? 0 : val;
        }
      }
      return 0.0;
    };

    try {
      let totalOrders = 0;
      let pendingOrders = 0;
      let deliveredOrders = 0;
      let revenue = 0.0;

      const ordersSnapshot = await db.collection("orders").get();

      for (const doc of ordersSnapshot.docs) {
        const data = doc.data();
        totalOrders += 1;
        const status = normalizeStatus(data.status);
        if (status === 'Placed' || status === 'Packed' || status === 'Out for Delivery') {
          pendingOrders += 1;
        } else if (status === 'Delivered') {
          deliveredOrders += 1;
        }
        revenue += getRevenue(data);
      }

      await db.collection("system_stats").doc("order_analytics").set({
        totalOrders,
        pendingOrders,
        deliveredOrders,
        revenue,
        lastRecalibratedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastRecalibratedBy: request.auth.uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      }, { merge: true });

      logger.info("recalibrateOrderAnalytics: completed", { functionName: "recalibrateOrderAnalytics", uid: request.auth.uid, operation: "order_recalibration", totalOrders, pendingOrders, deliveredOrders, revenue });
      return { success: true, message: "Order analytics recalibrated successfully." };

    } catch (error) {
      logger.error("recalibrateOrderAnalytics: failed", { functionName: "recalibrateOrderAnalytics", uid: request.auth.uid, operation: "order_recalibration", error: (error as any)?.message });
      throw new functions.https.HttpsError("internal", "Failed to recalibrate order analytics.");
    }
  }
);

/**
 * @function processAuthoritativeAnalytics
 * @trigger Firestore - onDocumentUpdated ("orders/{orderId}")
 * @purpose Captures transitions from Pending -> Placed and logs official revenues in a separate ledger.
 * @transactionFlow
 *   - Verifies if the order has been logged previously in analytics_ledger.
 *   - Writes receipt record to analytics_ledger for idempotency.
 *   - Increments authoritative revenue metrics inside system_stats.
 * @securityConsiderations
 *   - Uses an idempotency check record so that a duplicated order trigger does not register duplicate revenue.
 */
export const processAuthoritativeAnalytics = functions.firestore.onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();

    if (!before || !after) return;

    const beforeStatus = before.status;
    const afterStatus = after.status;

    // Trigger only on Pending -> Placed
    if (beforeStatus !== 'Pending' || afterStatus !== 'Placed') {
      return;
    }

    const orderId = event.params.orderId;
    const ledgerRef = db.collection('analytics_ledger').doc(`purchase_placed_${orderId}`);
    const analyticsRef = db.collection('system_stats').doc('authoritative_analytics');

    const getRevenue = (data: any) => {
      const fields = ['totalAmount', 'total', 'paymentAmount'];
      for (const field of fields) {
        let val = data[field];
        if (val != null) {
          if (typeof val === 'string') val = parseFloat(val);
          if (typeof val === 'number' && !isNaN(val)) return val < 0 ? 0 : val;
        }
      }
      return 0.0;
    };

    const revenue = getRevenue(after);
    try {
      await db.runTransaction(async (transaction) => {
        const ledgerDoc = await transaction.get(ledgerRef);
        if (ledgerDoc.exists) {
          logger.warn("processAuthoritativeAnalytics: duplicate event skipped (idempotency lock active)", { functionName: "processAuthoritativeAnalytics", orderId, eventType: "Pending->Placed", operation: "analytics_increment" });
          return;
        }

        transaction.set(ledgerRef, {
          orderId: orderId,
          processedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        transaction.set(analyticsRef, {
          successfulPurchases: admin.firestore.FieldValue.increment(1),
          successfulRevenue: admin.firestore.FieldValue.increment(revenue),
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
      });
      logger.info("processAuthoritativeAnalytics: purchase counted", { functionName: "processAuthoritativeAnalytics", orderId, eventType: "Pending->Placed", operation: "analytics_increment", revenue });
    } catch (error) {
      logger.error("processAuthoritativeAnalytics: transaction failed", { functionName: "processAuthoritativeAnalytics", orderId, eventType: "Pending->Placed", operation: "analytics_increment", error: (error as any)?.message });
    }
  }
);

/**
 * @function generateOrderSearchTokens
 * @purpose Utility function to build a searchable prefix/substring token list from order parameters.
 * @inputs values - Array of raw strings to tokenize (Order ID, client details, items).
 * @outputs string[] - List of unique alphanumeric tokens matching search bounds.
 */
function generateOrderSearchTokens(values: string[]): string[] {
  const tokens = new Set<string>();
  const maxTokens = 120;

  function addCoreTokens(value: string) {
    const normalized = value.trim().toLowerCase();
    if (normalized.length === 0) return;
    const compact = normalized.replace(/[^a-z0-9]/g, '');
    if (normalized.length >= 2) tokens.add(normalized);
    if (compact.length >= 2) tokens.add(compact);
    const parts = normalized.split(/[^a-z0-9]+/);
    for (const part of parts) {
      if (part.length >= 2) tokens.add(part);
    }
  }

  function addPrefixes(value: string) {
    const maxLength = value.length > 20 ? 20 : value.length;
    for (let length = 2; length <= maxLength; length++) {
      tokens.add(value.substring(0, length));
      if (tokens.size >= maxTokens) return;
    }
  }

  // BUSINESS RULE: Allow matching items via suffix checks (e.g. searching "0912" matches order id "GK00000912").
  function addSuffixes(value: string) {
    const maxLength = value.length > 20 ? 20 : value.length;
    for (let length = 2; length <= maxLength; length++) {
      tokens.add(value.substring(value.length - length));
      if (tokens.size >= maxTokens) return;
    }
  }

  function addSubstrings(value: string) {
    for (let start = 0; start < value.length; start++) {
      for (let length = 2; length <= 8; length++) {
        const end = start + length;
        if (end > value.length) break;
        tokens.add(value.substring(start, end));
        if (tokens.size >= maxTokens) return;
      }
    }
  }

  for (const rawValue of values) {
    addCoreTokens(rawValue);
    const compact = rawValue.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
    if (compact.length < 2) continue;
    addPrefixes(compact);
    addSuffixes(compact);
    addSubstrings(compact);
    if (tokens.size >= maxTokens) break;
  }

  return Array.from(tokens).slice(0, maxTokens);
}
