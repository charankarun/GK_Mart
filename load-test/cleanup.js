#!/usr/bin/env node
/**
 * cleanup.js
 * ─────────────────────────────────────────────────────────────────────────────
 * Removes all data written to the Firebase Local Emulator during the load test:
 *   - 30 Firebase Auth users
 *   - users/{uid} Firestore docs
 *   - All orders where isLoadTest === true
 *   - carts/{uid} and subcollection items/{productId}
 *   - otp_rate_limits docs for test phones and their IP variants
 *   - products and categories where isLoadTest === true
 *   - Disables the load-test bypass flag: system_config/load_test.enabled = false
 *
 * Project ID: demo-slv-super-market
 *
 * Usage:
 *   node load-test/cleanup.js
 * ─────────────────────────────────────────────────────────────────────────────
 */

"use strict";

// ── Set emulator env vars BEFORE any Firebase import ─────────────────────────
const PROJECT_ID = "slv-super-market-staging";
const admin = require("firebase-admin");
const fs = require("fs");
const path = require("path");

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    throw new Error("CRITICAL ABORT: GOOGLE_APPLICATION_CREDENTIALS is not set. A dedicated staging service account key is required.");
}

const credPath = path.resolve(process.env.GOOGLE_APPLICATION_CREDENTIALS);
const credJson = JSON.parse(fs.readFileSync(credPath, "utf8"));

if (credJson.project_id !== "slv-super-market-staging") {
    throw new Error(`CRITICAL ABORT: The provided service account key belongs to ${credJson.project_id}, but must strictly target slv-super-market-staging!`);
}

admin.initializeApp({ projectId: PROJECT_ID });

const auth = admin.auth();
const db = admin.firestore();

const ACCOUNTS_PATH = path.join(__dirname, "accounts.json");

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Delete all docs in a snapshot in batches of 499. */
async function batchDelete(snapshot) {
  if (snapshot.empty) return 0;
  let count = 0;
  let batch = db.batch();
  let batchCount = 0;

  for (const doc of snapshot.docs) {
    batch.delete(doc.ref);
    batchCount++;
    count++;
    if (batchCount === 499) {
      await batch.commit();
      batch = db.batch();
      batchCount = 0;
    }
  }
  if (batchCount > 0) await batch.commit();
  return count;
}

/** Delete all documents in a collection where isLoadTest === true. */
async function deleteLoadTestDocs(collectionName) {
  const snap = await db.collection(collectionName).where("isLoadTest", "==", true).get();
  const count = await batchDelete(snap);
  console.log(`   🗑️  ${collectionName}: deleted ${count} load-test docs`);
  return count;
}

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  console.log("🧹 GK Mart — Emulator Cleanup Script");
  console.log("   Environment: Live Staging");
  console.log("");

  // ── 1. Load accounts.json ────────────────────────────────────────────────
  if (!fs.existsSync(ACCOUNTS_PATH)) {
    console.warn("⚠️  accounts.json not found — skipping Auth user deletion.");
    console.warn("   (Emulator may have been restarted; users are already gone.)");
  } else {
    const accounts = JSON.parse(fs.readFileSync(ACCOUNTS_PATH, "utf8"));
    const uids = accounts.map((a) => a.uid);

    // ── 2. Delete Firebase Auth users ──────────────────────────────────────
    console.log(`👤 Deleting ${uids.length} Auth users...`);
    // deleteUsers supports up to 1000 UIDs per call
    const chunks = [];
    for (let i = 0; i < uids.length; i += 1000) {
      chunks.push(uids.slice(i, i + 1000));
    }
    let deletedAuth = 0;
    for (const chunk of chunks) {
      const result = await auth.deleteUsers(chunk);
      deletedAuth += result.successCount;
      if (result.failureCount > 0) {
        console.warn(`   ⚠️  ${result.failureCount} Auth deletions failed:`, result.errors);
      }
    }
    console.log(`   ✅ ${deletedAuth} Auth users deleted`);

    // ── 3. Delete users/{uid} Firestore docs ───────────────────────────────
    console.log("📄 Deleting users Firestore docs...");
    let batch = db.batch();
    let batchCount = 0;
    let userCount = 0;
    for (const uid of uids) {
      batch.delete(db.collection("users").doc(uid));
      batchCount++;
      userCount++;
      if (batchCount === 499) {
        await batch.commit();
        batch = db.batch();
        batchCount = 0;
      }
    }
    if (batchCount > 0) await batch.commit();
    console.log(`   ✅ ${userCount} user docs deleted`);

    // ── 4. Delete carts + items subcollections ─────────────────────────────
    console.log("🛒 Deleting cart documents...");
    let cartCount = 0;
    for (const uid of uids) {
      const cartRef = db.collection("carts").doc(uid);
      // Delete subcollection items first
      const itemsSnap = await cartRef.collection("items").get();
      if (!itemsSnap.empty) {
        const itemBatch = db.batch();
        itemsSnap.docs.forEach((d) => itemBatch.delete(d.ref));
        await itemBatch.commit();
      }
      // Delete cart doc itself
      const cartSnap = await cartRef.get();
      if (cartSnap.exists) {
        await cartRef.delete();
        cartCount++;
      }
    }
    console.log(`   ✅ ${cartCount} cart docs + subcollections deleted`);

    // ── 5. Delete otp_rate_limits docs ────────────────────────────────────
    console.log("🔒 Deleting otp_rate_limits docs...");
    const phones = accounts.map((a) => a.phone.replace("+91", "91")); // normalised form
    let rlBatch = db.batch();
    let rlCount = 0;
    let rlBatchCount = 0;
    for (const phone of phones) {
      // Phone-based doc
      rlBatch.delete(db.collection("otp_rate_limits").doc(phone));
      rlCount++;
      rlBatchCount++;
      if (rlBatchCount === 499) {
        await rlBatch.commit();
        rlBatch = db.batch();
        rlBatchCount = 0;
      }
    }
    if (rlBatchCount > 0) await rlBatch.commit();
    // Also delete any IP-prefixed docs for 127.0.0.1 (likely emulator IP)
    const ipVariants = [
      "ip_127_0_0_1",
      "validate_ip_127_0_0_1",
      "ip_unknown",
      "validate_ip_unknown",
    ];
    const ipBatch = db.batch();
    for (const ipKey of ipVariants) {
      ipBatch.delete(db.collection("otp_rate_limits").doc(ipKey));
    }
    await ipBatch.commit();
    console.log(`   ✅ ${rlCount} phone rate-limit docs deleted (+ IP variants)`);
  }

  // ── 6. Delete orders where isLoadTest === true ───────────────────────────
  console.log("📦 Deleting load-test orders...");
  await deleteLoadTestDocs("orders");

  // ── 7. Delete products and categories where isLoadTest === true ──────────
  console.log("🏷️  Deleting load-test products and categories...");
  await deleteLoadTestDocs("products");
  await deleteLoadTestDocs("categories");

  // ── 8. Disable load-test bypass flag ─────────────────────────────────────
  console.log("🚦 Disabling load-test bypass flag...");
  await db.collection("system_config").doc("load_test").set({
    enabled: false,
    disabledAt: admin.firestore.FieldValue.serverTimestamp(),
    note: "Load test completed and cleaned up.",
  });
  console.log("   ✅ system_config/load_test.enabled = false");

  // ── 9. Remove accounts.json and seeded-data.json ─────────────────────────
  const seededDataPath = path.join(__dirname, "seeded-data.json");
  for (const f of [ACCOUNTS_PATH, seededDataPath]) {
    if (fs.existsSync(f)) {
      fs.unlinkSync(f);
      console.log(`   🗑️  ${path.basename(f)} deleted`);
    }
  }

  console.log("");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("✅  Cleanup complete. Load test mode DISABLED.");
  console.log("    Verify at: http://localhost:4000 (Emulator UI)");
  console.log("    → Firestore → system_config/load_test → enabled: false");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

main().catch((err) => {
  console.error("❌ Cleanup failed:", err);
  process.exit(1);
});
