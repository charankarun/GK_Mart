import * as functions from "firebase-functions/v2";
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
          if (productDoc.exists) {
            const productData = productDoc.data();
            const trackStock = productData?.trackStock ?? (productData?.stockQuantity != null);
            if (trackStock) {
              const currentStock = productData?.stockQuantity || 0;
              if (currentStock < item.quantity) {
                throw new Error(`Out of stock: ${item.name}`);
              }
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
    
    // Only process when status changes TO Cancellation_Requested
    if (before.status === "Cancellation_Requested" || after.status !== "Cancellation_Requested") {
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

    try {
      const notifRef = db.collection("notifications").doc(`customer_status_${orderId}_${normalizedStatus}`);
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
