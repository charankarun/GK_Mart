/**
 * One-off diagnostic script created during load testing to analyze
 * Firestore cross-transaction contention ("10 ABORTED") and stock exhaustion 
 * errors by parsing the failureReason field from failed order documents.
 */
const admin = require("firebase-admin");
const serviceAccount = require("../staging-service-account.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();

async function analyzeFailures() {
  const snapshot = await db.collection("orders")
    .where("status", "==", "Failed")
    .limit(10)
    .get();
  
  console.log("Sample of Failed Orders:");
  snapshot.forEach(doc => {
    const data = doc.data();
    const reason = data.failureReason || "Unknown";
    if (reason.includes("ABORTED")) {
      const productIds = (data.items || []).map(i => i.productId).join(", ");
      console.log(`Order ${doc.id} | Reason: ${reason.substring(0, 50)}... | Products Involved: ${productIds}`);
    }
  });
}

analyzeFailures().catch(console.error);
