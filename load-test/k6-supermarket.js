/**
 * k6-supermarket.js
 * ─────────────────────────────────────────────────────────────────────────────
 * k6 load-test for GK Mart — Firebase Local Emulator Suite
 * Project ID: demo-slv-super-market
 *
 * PILOT MODE (default — safe to run any time):
 *   k6 run load-test/k6-supermarket.js --out json=load-test/results-pilot.json
 *   Ramp: 0→200 (1m) hold 3m, 200→500 (1m) hold 2m, 500→0 (1m)  ≈ 8 min total
 *
 * FULL LOAD (explicit opt-in required):
 *   k6 run --env FULL=true load-test/k6-supermarket.js --out json=load-test/results.json
 *   Ramp: 0→200 (2m), 200→2000 (6m), hold 2000 (5m), 2000→0 (2m)  ≈ 15 min total
 *
 * Weighted user journeys:
 *   40% browse_products  — GET categories + runQuery products by category
 *   25% search_products  — runQuery searchTokens array-contains
 *   20% add_to_cart      — GET product + PATCH cart item (upsert, no precondition)
 *   10% checkout         — PUT order (client-generated ID) + poll for status transition
 *    5% login            — call verifyOtp with test OTP "000000"
 *
 * Prerequisites:
 *   firebase emulators:start --only auth,firestore,functions --project demo-slv-super-market
 *   node load-test/seed-accounts.js
 * ─────────────────────────────────────────────────────────────────────────────
 */

import http from "k6/http";
import { check, sleep, fail } from "k6";
import { SharedArray } from "k6/data";
import { Counter, Rate, Trend } from "k6/metrics";

// ── Configuration ──────────────────────────────────────────────────────────────
const PROJECT_ID = "slv-super-market-staging";
const WEB_API_KEY = __ENV.WEB_API_KEY;

if (!WEB_API_KEY) {
  throw new Error("Missing WEB_API_KEY environment variable. Pass it via -e WEB_API_KEY=...");
}

const FIRESTORE_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;
const FIRESTORE_COMMIT = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents:commit`;
const AUTH_TOKEN_URL = `https://securetoken.googleapis.com/v1/token?key=${WEB_API_KEY}`;
const FUNCTIONS_BASE = `https://us-central1-${PROJECT_ID}.cloudfunctions.net`;

const IS_FULL = __ENV.FULL === "true";

// ── Shared data (loaded once, shared across all VUs) ──────────────────────────
const accounts = new SharedArray("accounts", function () {
  // accounts.json produced by seed-accounts.js
  return JSON.parse(open("./accounts.json"));
});

const seededData = new SharedArray("seededData", function () {
  // seeded-data.json produced by seed-accounts.js
  return [JSON.parse(open("./seeded-data.json"))];
})[0];

// ── Custom metrics ─────────────────────────────────────────────────────────────
const tokenRefreshes = new Counter("token_refreshes");
const checkoutAborts = new Counter("checkout_aborts");
const scenarioBrowse = new Counter("scenario_browse");
const scenarioSearch = new Counter("scenario_search");
const scenarioCart = new Counter("scenario_cart");
const scenarioCheckout = new Counter("scenario_checkout");
const scenarioLogin = new Counter("scenario_login");
const checkoutLatency = new Trend("checkout_latency_ms");

// ── Ramp profiles ──────────────────────────────────────────────────────────────
const PILOT_STAGES = [
  { duration: "1m", target: 200 },  // ramp up
  { duration: "3m", target: 200 },  // hold
  { duration: "1m", target: 500 },  // ramp up
  { duration: "2m", target: 500 },  // hold
  { duration: "1m", target: 0 },    // ramp down
];

const FULL_STAGES = [
  { duration: "2m", target: 200 },   // warm-up
  { duration: "6m", target: 2000 },  // ramp-up
  { duration: "5m", target: 2000 },  // sustained load
  { duration: "2m", target: 0 },     // ramp-down
];

// ── k6 options ─────────────────────────────────────────────────────────────────
export const options = {
  scenarios: {
    supermarket_load: {
      executor: "ramping-vus",
      stages: IS_FULL ? FULL_STAGES : PILOT_STAGES,
      // Enable connection reuse across requests in the same VU to reduce
      // ephemeral port consumption on Windows (avoids port-exhaustion errors
      // at high VU counts that would look like app errors but are OS-level).
      exec: "default",
    },
  },

  // HTTP connection reuse — reduces Windows ephemeral port pressure at 2000 VUs.
  // Each VU reuses keep-alive connections rather than opening a new socket per request.
  noConnectionReuse: false,  // false = ALLOW connection reuse (keep-alive ON)

  thresholds: {
    http_req_duration: ["p(95)<3000", "p(99)<8000"],
    http_req_failed:   ["rate<0.02"],
    checks:            ["rate>0.95"],
  },

  // Reduce noise in the summary for cleaner output
  summaryTrendStats: ["avg", "min", "med", "max", "p(90)", "p(95)", "p(99)"],
};

// ── Per-VU state ───────────────────────────────────────────────────────────────
// k6 VU state is local to each VU — these are not shared.
let vuAccount = null;

function getAccount() {
  if (!vuAccount) {
    // Each VU gets a stable slot: VU 1→account[0], VU 2→account[1], etc.
    // With 2000 VUs and 30 accounts, each account is shared by ~67 VUs.
    vuAccount = Object.assign({}, accounts[(__VU - 1) % accounts.length]);
  }
  return vuAccount;
}

/** Refresh the Bearer token if it expires within 60 seconds. */
function refreshIfNeeded(account) {
  if (Date.now() < account.expiresAt - 60_000) return;

  const res = http.post(
    AUTH_TOKEN_URL,
    JSON.stringify({ grant_type: "refresh_token", refresh_token: account.refreshToken }),
    { headers: { "Content-Type": "application/json" }, tags: { scenario: "token_refresh" } }
  );

  if (res.status === 200) {
    const body = JSON.parse(res.body);
    account.idToken = body.id_token;
    account.refreshToken = body.refresh_token;
    account.expiresAt = Date.now() + parseInt(body.expires_in, 10) * 1000;
    tokenRefreshes.add(1);
  } else {
    console.warn(`VU${__VU}: token refresh failed (status ${res.status})`);
  }
}

function authHeaders(account) {
  return {
    "Authorization": `Bearer ${account.idToken}`,
    "Content-Type": "application/json",
  };
}

/** Pick a random element from an array. */
function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

/**
 * Generate a 20-character alphanumeric ID (a-z A-Z 0-9) that satisfies
 * validOrderId()'s ^[a-zA-Z0-9]{20}$ pattern in firestore.rules.
 */
function generateOrderId() {
  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let id = '';
  for (let i = 0; i < 20; i++) {
    id += chars[Math.floor(Math.random() * chars.length)];
  }
  return id;
}

// ── Scenario implementations ───────────────────────────────────────────────────

/**
 * 40% — Browse products
 * 1. GET all categories
 * 2. runQuery products by a random seeded categoryId
 */
function browseProd(account) {
  scenarioBrowse.add(1);

  // Step 1: list categories
  const catRes = http.get(
    `${FIRESTORE_BASE}/categories`,
    { headers: authHeaders(account), tags: { scenario: "browse_categories" } }
  );
  check(catRes, { "list categories 200": (r) => r.status === 200 });

  sleep(Math.random() * 1.5 + 0.3);

  // Step 2: products by category — use real categoryId from seeded-data.json
  const categoryId = pick(seededData.categoryIds);
  const query = {
    structuredQuery: {
      from: [{ collectionId: "products" }],
      where: {
        fieldFilter: {
          field: { fieldPath: "categoryId" },
          op: "EQUAL",
          value: { stringValue: categoryId },
        },
      },
      limit: 20,
    },
  };

  const prodRes = http.post(
    `${FIRESTORE_BASE}:runQuery`,
    JSON.stringify(query),
    { headers: authHeaders(account), tags: { scenario: "browse_products" } }
  );
  check(prodRes, { "browse products 200": (r) => r.status === 200 });
}

/**
 * 25% — Search products
 * runQuery with searchTokens array-contains using a real token from seeded-data.json.
 * Guaranteed to return at least one result.
 */
function searchProd(account) {
  scenarioSearch.add(1);

  // Draw a real token from the seeded catalogue — guarantees non-empty results
  const token = pick(seededData.allSearchTokens);

  const query = {
    structuredQuery: {
      from: [{ collectionId: "products" }],
      where: {
        fieldFilter: {
          field: { fieldPath: "searchTokens" },
          op: "ARRAY_CONTAINS",
          value: { stringValue: token },
        },
      },
      limit: 20,
    },
  };

  const res = http.post(
    `${FIRESTORE_BASE}:runQuery`,
    JSON.stringify(query),
    { headers: authHeaders(account), tags: { scenario: "search_products" } }
  );
  check(res, { "search products 200": (r) => r.status === 200 });
}

/**
 * 20% — Add to cart
 * 1. GET a random product doc
 * 2. PATCH carts/{uid}/items/{productId} — upsert, no precondition
 *    Simulates "update quantity" (same account may re-add the same item).
 *    No ?currentDocument.exists=false — avoids HTTP 412 ALREADY_EXISTS on repeat.
 */
function addToCart(account) {
  scenarioCart.add(1);

  const product = pick(seededData.products);

  // Step 1: read product
  const prodRes = http.get(
    `${FIRESTORE_BASE}/products/${product.id}`,
    { headers: authHeaders(account), tags: { scenario: "get_product" } }
  );
  check(prodRes, { "get product 200": (r) => r.status === 200 });

  sleep(Math.random() * 1 + 0.2);

  // Step 2: write cart item — upsert, no currentDocument precondition.
  // Fields must exactly match validCartItemWrite() hasOnly/hasAll in firestore.rules:
  //   [name, price, discountPrice, unit, image, quantity]
  // productId is the document ID in the path, not a body field.
  // addedAt and isLoadTest are not in the allowed list and must be omitted.
  const cartBody = {
    fields: {
      name:          { stringValue: product.name },
      price:         { doubleValue: product.price },
      discountPrice: { doubleValue: product.discountPrice !== undefined ? product.discountPrice : 0 },
      unit:          { stringValue: product.unit || "" },
      image:         { stringValue: product.imageUrl || "" },
      quantity:      { integerValue: "1" },
    },
  };

  const cartRes = http.patch(
    `${FIRESTORE_BASE}/carts/${account.uid}/items/${product.id}`,
    JSON.stringify(cartBody),
    { headers: authHeaders(account), tags: { scenario: "add_to_cart" } }
  );
  check(cartRes, { "add to cart 200": (r) => r.status === 200 });
}

/**
 * 10% — Checkout
 * 1. Generate a client-side 20-char alphanumeric orderId
 * 2. Write the order via documents:commit with fieldTransforms for REQUEST_TIME,
 *    satisfying the rules: data.createdAt == request.time && data.timestamp == request.time
 * 3. Poll GET for status transition (up to 10s)
 *    Note: processPendingOrder Cloud Function (counters/orders hot doc) is
 *    the primary bottleneck under load — watch for transaction abort log lines.
 */
function checkout(account) {
  scenarioCheckout.add(1);

  const product = pick(seededData.products);
  const qty = 1;
  const lineTotal = product.price * qty;
  const deliveryFee = lineTotal >= 699 ? 0 : 50;
  const totalAmount = lineTotal + deliveryFee;

  // Generate a 20-char alphanumeric order ID client-side so we can:
  //   1. Write to a known document path (required for data.orderId == orderId rule check)
  //   2. Use fieldTransforms for REQUEST_TIME (only available via commit, not PUT/PATCH)
  // The ^[a-zA-Z0-9]{20}$ pattern is accepted by validOrderId() in firestore.rules.
  const orderId = generateOrderId();
  const docName = `projects/${PROJECT_ID}/databases/(default)/documents/orders/${orderId}`;
  const orderPath = `orders/${orderId}`;

  // Use documents:commit to atomically write all fields + set createdAt/timestamp
  // via REQUEST_TIME transforms. This is the only way to satisfy:
  //   data.createdAt == request.time  AND  data.timestamp == request.time
  // as required by validOrderCreate() in firestore.rules.
  //
  // Fields in hasOnly: orderId, userId, userName, customerName, phone, address, pincode,
  //   items, originalAmount, cartDiscount, deliveryFee, totalAmount, total,
  //   totalSavings, searchTokens, status, paymentMethod, createdAt, timestamp
  // Fields in hasAll: orderId, userId, items, totalAmount, total, status, createdAt, timestamp
  // isLoadTest and subtotal are NOT in hasOnly — must not be sent.
  // Single Write object per the current Firestore v1 REST API spec:
  // `update`, `updateTransforms`, and `currentDocument` are sibling keys
  // on one Write entry — not separate array entries.
  // Reference: https://firebase.google.com/docs/firestore/reference/rest/v1/Write
  const commitBody = {
    writes: [
      {
        update: {
          name: docName,
          fields: {
            orderId:        { stringValue: orderId },
            status:         { stringValue: "Pending" },
            userId:         { stringValue: account.uid },
            userName:       { stringValue: `LoadTest User ${account.n}` },
            phone:          { stringValue: account.phone },
            originalAmount: { doubleValue: lineTotal },
            totalAmount:    { doubleValue: totalAmount },
            total:          { doubleValue: totalAmount },
            totalSavings:   { doubleValue: 0 },
            cartDiscount:   { doubleValue: 0 },
            deliveryFee:    { doubleValue: deliveryFee },
            items: {
              arrayValue: {
                values: [
                  {
                    mapValue: {
                      fields: {
                        productId:     { stringValue: product.id },
                        name:          { stringValue: product.name },
                        quantity:      { integerValue: String(qty) },
                        price:         { doubleValue: product.price },
                        discountPrice: { doubleValue: 0 },
                        lineTotal:     { doubleValue: lineTotal },
                      },
                    },
                  },
                ],
              },
            },
          },
        },
        // currentDocument: { exists: false } ensures this is a create, not an update,
        // matching the firestore.rules `allow create` path.
        currentDocument: { exists: false },
        // updateTransforms runs atomically with the update above in the same Write object.
        // These set createdAt and timestamp to the Firestore server request time,
        // satisfying: data.createdAt == request.time && data.timestamp == request.time
        updateTransforms: [
          { fieldPath: "createdAt", setToServerValue: "REQUEST_TIME" },
          { fieldPath: "timestamp", setToServerValue: "REQUEST_TIME" },
        ],
      },
    ],
  };

  const t0 = Date.now();
  const postRes = http.post(
    FIRESTORE_COMMIT,
    JSON.stringify(commitBody),
    { headers: authHeaders(account), tags: { scenario: "checkout_post" } }
  );

  if (!check(postRes, { "post order 200": (r) => r.status === 200 })) {
    checkoutAborts.add(1);
    return;
  }

  // Poll for status change (Pending → Placed by processPendingOrder)
  let placed = false;
  for (let attempt = 0; attempt < 10; attempt++) {
    sleep(1);
    const pollRes = http.get(
      `${FIRESTORE_BASE}/${orderPath}`,
      { headers: authHeaders(account), tags: { scenario: "checkout_poll" } }
    );
    if (pollRes.status !== 200) continue;
    try {
      const doc = JSON.parse(pollRes.body);
      const status = doc.fields?.status?.stringValue;
      if (status === "Placed" || status === "Failed") {
        placed = true;
        break;
      }
    } catch { /* continue polling */ }
  }

  const elapsed = Date.now() - t0;
  checkoutLatency.add(elapsed);

  check({ placed }, { "order placed within 10s": (v) => v.placed === true });
  if (!placed) checkoutAborts.add(1);
}

/**
 * 5% — Login
 * Call the verifyOtp Cloud Function with the test OTP "000000".
 * Exercises the dual-gate bypass path in index.ts.
 */
function loginFlow(account) {
  scenarioLogin.add(1);

  const res = http.post(
    `${FUNCTIONS_BASE}/verifyOtp`,
    JSON.stringify({ data: { phoneNumber: account.phone, otp: "000000" } }),
    { headers: { "Content-Type": "application/json" }, tags: { scenario: "login" } }
  );

  check(res, {
    "verifyOtp 200":        (r) => r.status === 200,
    "verifyOtp has token":  (r) => {
      try { return !!JSON.parse(r.body).result?.token; } catch { return false; }
    },
  });
}

// ── Default function ───────────────────────────────────────────────────────────
export default function () {
  const account = getAccount();
  refreshIfNeeded(account);

  // Weighted scenario selection
  const r = Math.random();
  if (r < 0.40) {
    browseProd(account);
  } else if (r < 0.65) {
    searchProd(account);
  } else if (r < 0.85) {
    addToCart(account);
  } else if (r < 0.95) {
    checkout(account);
  } else {
    loginFlow(account);
  }

  // Think time: 1–5 seconds between actions
  sleep(Math.random() * 4 + 1);
}

// ── Summary hook ───────────────────────────────────────────────────────────────
export function handleSummary(data) {
  const mode = IS_FULL ? "FULL (2000 VU)" : "PILOT (max 500 VU)";
  console.log(`\n📊 GK Mart Load Test — ${mode}`);
  console.log("═══════════════════════════════════════════");

  const dur = data.metrics.http_req_duration;
  if (dur) {
    console.log(`   p(95) latency : ${Math.round(dur.values["p(95)"])} ms`);
    console.log(`   p(99) latency : ${Math.round(dur.values["p(99)"])} ms`);
    console.log(`   avg latency   : ${Math.round(dur.values["avg"])} ms`);
  }

  const fail = data.metrics.http_req_failed;
  if (fail) {
    const rate = (fail.values["rate"] * 100).toFixed(2);
    const status = parseFloat(rate) < 2 ? "✅" : "❌";
    console.log(`   error rate    : ${rate}% ${status}`);
  }

  const checks = data.metrics.checks;
  if (checks) {
    const rate = (checks.values["rate"] * 100).toFixed(1);
    const status = parseFloat(rate) >= 95 ? "✅" : "❌";
    console.log(`   check rate    : ${rate}% ${status}`);
  }

  const aborts = data.metrics.checkout_aborts;
  if (aborts) {
    console.log(`   checkout aborts: ${aborts.values["count"]}`);
  }

  const co = data.metrics.checkout_latency_ms;
  if (co) {
    console.log(`   checkout p(95): ${Math.round(co.values["p(95)"])} ms`);
  }

  const refreshes = data.metrics.token_refreshes;
  if (refreshes) {
    console.log(`   token refreshes: ${refreshes.values["count"]}`);
  }

  console.log("═══════════════════════════════════════════");
  console.log("   Run node load-test/cleanup.js when done.");
  console.log("");

  // Return the default JSON summary
  return { stdout: JSON.stringify(data) };
}
