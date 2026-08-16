#!/usr/bin/env node
/**
 * seed-accounts.js
 * ─────────────────────────────────────────────────────────────────────────────
 * Seeds the Firebase Local Emulator Suite with:
 *   - 30 Firebase Auth test users (phone numbers +919000000001..+919000000030)
 *   - 30 Firestore users/{uid} documents
 *   - 3 product categories + 15 products (with realistic searchTokens)
 *   - system_config/load_test flag { enabled: true } (Gate 2 of dual-gate bypass)
 *
 * Produces two output files (both gitignored):
 *   load-test/accounts.json    — VU credentials for k6
 *   load-test/seeded-data.json — category IDs + product searchTokens for k6 queries
 *
 * Project ID: demo-slv-super-market
 * The demo- prefix forces the Admin SDK into hard-offline mode — it cannot
 * contact the real Firebase project even if emulator env vars are misconfigured.
 *
 * Usage:
 *   node load-test/seed-accounts.js
 *
 * Prerequisites:
 *   firebase emulators:start --only auth,firestore,functions --project demo-slv-super-market
 *   firebase emulators:start --only auth,firestore,functions --project slv-super-market-staging
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

// Initialize using GOOGLE_APPLICATION_CREDENTIALS for the live staging DB
admin.initializeApp({ projectId: PROJECT_ID });

const https = require("https"); // not used for HTTP — using node fetch compat
const { get: httpGet, request: httpReq } = require("http");

const auth = admin.auth();
const db = admin.firestore();

// ── Constants ─────────────────────────────────────────────────────────────────
const ACCOUNT_COUNT = 30;
const AUTH_EMULATOR = "http://127.0.0.1:9099";
const FAKE_API_KEY = "fake-api-key"; // emulator accepts any non-empty key
const OUT_DIR = path.join(__dirname);

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Simple HTTP POST helper (avoids fetch/axios dependency). */
function httpPost(url, body) {
  return new Promise((resolve, reject) => {
    const bodyStr = JSON.stringify(body);
    const urlObj = new URL(url);
    const opts = {
      hostname: urlObj.hostname,
      port: urlObj.port,
      path: urlObj.pathname + urlObj.search,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(bodyStr),
      },
    };
    const req = (urlObj.protocol === "https:" ? require("https").request : require("http").request)(opts, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          reject(new Error(`JSON parse error: ${data}`));
        }
      });
    });
    req.on("error", reject);
    req.write(bodyStr);
    req.end();
  });
}

/**
 * Generates searchTokens for a product name using the same prefix/substring
 * logic as generateOrderSearchTokens in index.ts (simplified for seeding).
 */
function generateSearchTokens(name) {
  const tokens = new Set();
  const norm = name.trim().toLowerCase();
  const compact = norm.replace(/[^a-z0-9]/g, "");

  // Full normalized name
  if (norm.length >= 2) tokens.add(norm);
  if (compact.length >= 2) tokens.add(compact);

  // Word parts
  for (const part of norm.split(/[^a-z0-9]+/)) {
    if (part.length >= 2) tokens.add(part);
  }

  // Prefixes (up to 20 chars)
  const maxLen = Math.min(compact.length, 20);
  for (let l = 2; l <= maxLen; l++) {
    tokens.add(compact.substring(0, l));
  }

  // Substrings of length 2–6
  for (let s = 0; s < compact.length; s++) {
    for (let l = 2; l <= 6; l++) {
      if (s + l > compact.length) break;
      tokens.add(compact.substring(s, s + l));
    }
  }

  return Array.from(tokens).slice(0, 60);
}

// ── Catalogue data ────────────────────────────────────────────────────────────
const CATEGORIES = [
  { id: "cat001", name: "Dairy", icon: "🥛", isLoadTest: true },
  { id: "cat002", name: "Vegetables", icon: "🥦", isLoadTest: true },
  { id: "cat003", name: "Beverages", icon: "🥤", isLoadTest: true },
];

const PRODUCTS_RAW = [];
for (let i = 1; i <= 300; i++) {
  PRODUCTS_RAW.push({
    id: `prod${i.toString().padStart(3, '0')}`,
    name: `Load Test Product ${i}`,
    categoryId: `cat00${(i % 3) + 1}`, // Loops through cat001, cat002, cat003
    price: Math.floor(Math.random() * 200) + 20,
    stockQuantity: 2000 // Very high stock to prevent exhaustion during pilot runs
  });
}

const PRODUCTS = PRODUCTS_RAW.map((p) => ({
  ...p,
  isAvailable: true,
  trackStock: true,
  isLoadTest: true,
  searchTokens: generateSearchTokens(p.name),
  searchName: p.name.toLowerCase(),
  discountPrice: 0,
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  updatedAt: admin.firestore.FieldValue.serverTimestamp(),
}));

// ── Main ──────────────────────────────────────────────────────────────────────
async function main() {
  console.log("🌱 GK Mart — Emulator Seed Script");
  console.log("   Project       : " + PROJECT_ID);
  console.log("   Environment   : Live Staging\n");
  console.log("");

  // ── 1. Seed categories ───────────────────────────────────────────────────
  console.log("📂 Seeding categories...");
  const catBatch = db.batch();
  for (const cat of CATEGORIES) {
    catBatch.set(db.collection("categories").doc(cat.id), {
      name: cat.name,
      icon: cat.icon,
      isLoadTest: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await catBatch.commit();
  console.log(`   ✅ ${CATEGORIES.length} categories seeded`);

  // ── 2. Seed products ─────────────────────────────────────────────────────
  console.log("📦 Seeding products...");
  const prodBatch = db.batch();
  for (const prod of PRODUCTS) {
    prodBatch.set(db.collection("products").doc(prod.id), prod);
  }
  await prodBatch.commit();
  console.log(`   ✅ ${PRODUCTS.length} products seeded`);

  // ── 3. Create Auth users + Firestore user docs ───────────────────────────
  console.log("👤 Creating 30 test Auth users...");
  const accounts = [];

  for (let n = 1; n <= ACCOUNT_COUNT; n++) {
    const phone = `+91900000${String(n).padStart(4, "0")}`;
    const displayName = `LoadTest User ${n}`;

    // Create (or re-use) Firebase Auth user in emulator
    let uid;
    try {
      const existing = await auth.getUserByPhoneNumber(phone);
      uid = existing.uid;
      console.log(`   ♻️  Reusing existing user ${n}: ${uid}`);
    } catch (err) {
      if (err.code === "auth/user-not-found") {
        const created = await auth.createUser({ phoneNumber: phone, displayName });
        uid = created.uid;
        console.log(`   ➕ Created user ${n}: ${uid}`);
      } else {
        throw err;
      }
    }

    // Firestore user document
    await db.collection("users").doc(uid).set({
      uid,
      phone,
      name: displayName,
      role: "customer",
      isLoadTest: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Mint custom token → exchange for ID token via emulator REST
    const customToken = await auth.createCustomToken(uid);
    const WEB_API_KEY = process.env.WEB_API_KEY;
    if (!WEB_API_KEY) throw new Error("Missing WEB_API_KEY env var");
    
    const signInResp = await httpPost(
      `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${WEB_API_KEY}`,
      { token: customToken, returnSecureToken: true }
    );

    if (!signInResp.idToken) {
      throw new Error(`signInWithCustomToken failed for user ${n}: ${JSON.stringify(signInResp)}`);
    }

    const expiresAt = Date.now() + parseInt(signInResp.expiresIn, 10) * 1000;

    accounts.push({
      n,
      uid,
      phone,
      idToken: signInResp.idToken,
      refreshToken: signInResp.refreshToken,
      expiresAt,
    });

    // Small delay to avoid emulator rate limiting
    await new Promise((r) => setTimeout(r, 50));
  }

  console.log(`   ✅ ${accounts.length} accounts ready`);

  // ── 4. Write accounts.json ───────────────────────────────────────────────
  const accountsPath = path.join(OUT_DIR, "accounts.json");
  fs.writeFileSync(accountsPath, JSON.stringify(accounts, null, 2));
  console.log(`📄 accounts.json written → ${accountsPath}`);

  // ── 5. Write seeded-data.json (real tokens for k6 search queries) ────────
  const seededData = {
    categoryIds: CATEGORIES.map((c) => c.id),
    // Collect a flat unique list of all searchTokens from all products
    allSearchTokens: [
      ...new Set(PRODUCTS.flatMap((p) => p.searchTokens)),
    ],
    // Per-product summary for k6 cart scenario.
    // unit and imageUrl are required by validCartItemWrite() in firestore.rules.
    products: PRODUCTS.map((p) => ({
      id: p.id,
      categoryId: p.categoryId,
      price: p.price,
      discountPrice: p.discountPrice,
      name: p.name,
      unit: p.unit || "",
      imageUrl: p.imageUrl || "",
      searchTokens: p.searchTokens,
    })),
  };
  const seededDataPath = path.join(OUT_DIR, "seeded-data.json");
  fs.writeFileSync(seededDataPath, JSON.stringify(seededData, null, 2));
  console.log(`📄 seeded-data.json written → ${seededDataPath}`);

  // ── 6. Enable load-test Firestore flag (Gate 2) ──────────────────────────
  console.log("🚦 Enabling load-test bypass flag (system_config/load_test)...");
  await db.collection("system_config").doc("load_test").set({
    enabled: true,
    testOtp: "000000",
    note: "LOAD TEST ACTIVE — run cleanup.js when done",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  console.log("   ✅ Flag enabled");

  console.log("");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
  console.log("⚠️   LOAD TEST MODE IS NOW ACTIVE on live staging.");
  console.log("    Run  node load-test/cleanup.js  when done.");
  console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
}

main().catch((err) => {
  console.error("❌ Seed failed:", err);
  process.exit(1);
});
