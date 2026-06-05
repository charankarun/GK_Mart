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
      await db.runTransaction(async (transaction) => {
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
      });
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
