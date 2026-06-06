import * as functions from "firebase-functions/v2";
import { onSchedule } from "firebase-functions/v2/scheduler";
import * as v1 from "firebase-functions/v1";
import * as admin from "firebase-admin";
admin.initializeApp();
const db = admin.firestore();

export const processPendingOrder = functions.firestore.onDocumentCreated(
  "orders/{orderId}",
  async (event) => {
    const orderDoc = event.data;
    if (!orderDoc) return;
    
    const order = orderDoc.data();
    if (order.status !== "Pending") return;

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

        // 2. Validate stock
        for (let i = 0; i < items.length; i++) {
          const item = items[i];
          const productDoc = productDocs[i];
          if (!productDoc.exists) {
            throw new Error(`Product no longer available: ${item.name || item.productId}`);
          }
          const productData = productDoc.data();
          const trackStock = productData?.trackStock ?? (productData?.stockQuantity != null);
          if (trackStock) {
            const currentStock = productData?.stockQuantity || 0;
            if (currentStock < item.quantity) {
              throw new Error(`Out of stock: ${item.name}`);
            }
          }
        }

        // 3. Read counter and generate official ID
        const counterRef = db.collection("counters").doc("orders");
        const counterDoc = await transaction.get(counterRef);
        const nextNumber = counterDoc.exists ? (counterDoc.data()?.next || 2) : 2;
        const officialOrderId = `GK${nextNumber.toString().padStart(5, '0')}`;

        // 4. Update stock
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
        transaction.update(orderRef, {
          orderId: officialOrderId,
          status: "Placed",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
        
        return officialOrderId;
      });

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
        console.error("Non-critical failure: Could not create notifications.", error);
      }
    } catch (error: any) {
      // Transaction failed
      await db.collection("orders").doc(event.params.orderId).update({
        status: "Failed",
        failureReason: error.message || "Unknown error",
        updatedAt: admin.firestore.FieldValue.serverTimestamp()
      });
    }
  }
);

export const processOrderCancellation = functions.firestore.onDocumentUpdated(
  "orders/{orderId}",
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    
    if (!before || !after) return;
    
    // Only process when status changes to Cancelled or Cancellation_Requested for the FIRST time
    // If it was already cancelled or requested, do not restore stock again (prevent duplicate restorations)
    if (before.status === "Cancelled" || before.status === "Cancellation_Requested") {
      return;
    }

    if (after.status !== "Cancellation_Requested" && after.status !== "Cancelled") {
      return;
    }

    try {
      await db.runTransaction(async (transaction) => {
        const orderRef = db.collection("orders").doc(event.params.orderId);
        
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

        // 3. Update order status to Cancelled
        transaction.update(orderRef, {
          status: "Cancelled",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      });
    } catch (error: any) {
      console.error("Cancellation failed", error);
    }
  }
);

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
    } catch (error) {
      console.error("Non-critical failure: Could not create status notification.", error);
    }
  }
);

export const cleanupStuckOrders = onSchedule("every 15 minutes", async (event) => {
  const fifteenMinsAgo = new Date(Date.now() - 15 * 60 * 1000);
  
  try {
    const snapshot = await db.collection("orders")
      .where("status", "==", "Pending")
      .where("timestamp", "<", admin.firestore.Timestamp.fromDate(fifteenMinsAgo))
      .get();

    if (snapshot.empty) {
      console.log("No stuck pending orders found.");
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

      if (count === 500) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
    
    console.log(`Cleaned up ${snapshot.size} stuck pending orders.`);
  } catch (error) {
    console.error("Error cleaning up stuck pending orders:", error);
  }
});

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
    
    console.log(`Successfully processed deletion for user ${uid}. Anonymized ${ordersSnapshot.size} orders.`);
  } catch (error) {
      console.error(`Error processing deletion for user ${uid}:`, error);
    }
  }
);

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
        // 3. Update order status to Cancelled
        transaction.update(orderRef, {
          status: "Cancelled",
          updatedAt: admin.firestore.FieldValue.serverTimestamp()
        });
      });
    } catch (error: any) {
      console.error("Cancellation failed", error);
    }
  }
);

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
    } catch (error) {
      console.error("Non-critical failure: Could not create status notification.", error);
    }
  }
);

export const cleanupStuckOrders = onSchedule("every 15 minutes", async (event) => {
  const fifteenMinsAgo = new Date(Date.now() - 15 * 60 * 1000);
  
  try {
    const snapshot = await db.collection("orders")
      .where("status", "==", "Pending")
      .where("timestamp", "<", admin.firestore.Timestamp.fromDate(fifteenMinsAgo))
      .get();

    if (snapshot.empty) {
      console.log("No stuck pending orders found.");
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

      if (count === 500) {
        await batch.commit();
        batch = db.batch();
        count = 0;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
    
    console.log(`Cleaned up ${snapshot.size} stuck pending orders.`);
  } catch (error) {
    console.error("Error cleaning up stuck pending orders:", error);
  }
});

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
    
    console.log(`Successfully processed deletion for user ${uid}. Anonymized ${ordersSnapshot.size} orders.`);
  } catch (error) {
      console.error(`Error processing deletion for user ${uid}:`, error);
    }
});

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
      console.error("Failed to update product stats:", error);
    }
  }
);

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
      console.error("Failed to update category stats:", error);
    }
  }
);

export const recalibrateInventoryStats = functions.https.onCall(
  async (request) => {
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated."
      );
    }
    
    const userDoc = await db.collection("users").doc(request.auth.uid).get();
    const role = userDoc.data()?.role?.toString().trim().toLowerCase();
    if (!userDoc.exists || (role !== "admin" && role !== "owner")) {
       throw new functions.https.HttpsError(
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
      let outOfStockProducts = 0;
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

      return { success: true, message: "Inventory stats recalibrated successfully." };

    } catch (error) {
      console.error("Recalibration failed:", error);
      throw new functions.https.HttpsError("internal", "Failed to recalibrate inventory stats.");
    }
  }
);

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
      console.error("Failed to update order analytics:", error);
    }
  }
);

export const recalibrateOrderAnalytics = functions.https.onCall(
  async (request) => {
    if (!request.auth) {
      throw new functions.https.HttpsError(
        "unauthenticated",
        "Must be authenticated."
      );
    }
    
    const userDoc = await db.collection("users").doc(request.auth.uid).get();
    const role = userDoc.data()?.role?.toString().trim().toLowerCase();
    if (!userDoc.exists || (role !== "admin" && role !== "owner")) {
       throw new functions.https.HttpsError(
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

      return { success: true, message: "Order analytics recalibrated successfully." };

    } catch (error) {
      console.error("Recalibration failed:", error);
      throw new functions.https.HttpsError("internal", "Failed to recalibrate order analytics.");
    }
  }
);
