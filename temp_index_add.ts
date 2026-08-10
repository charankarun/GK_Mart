  }

  return Array.from(tokens).slice(0, maxTokens);
}

import { defineSecret } from "firebase-functions/params";

const msg91AuthKey = defineSecret("MSG91_AUTH_KEY");
const MSG91_TEMPLATE_ID = "YOUR_MSG91_TEMPLATE_ID"; // To be replaced in Firebase config

export const sendOtp = onCall(
  { secrets: [msg91AuthKey] },
  async (request) => {
    const { phoneNumber } = request.data;
    if (!phoneNumber || typeof phoneNumber !== "string" || !/^\+91[0-9]{10}$/.test(phoneNumber)) {
      throw new HttpsError("invalid-argument", "Invalid Indian phone number format. Must be +91 followed by 10 digits.");
    }

    const normalizedPhone = phoneNumber.replace("+91", "91");
    const ip = request.rawRequest.ip || "unknown";

    const now = admin.firestore.Timestamp.now();
    const rateLimitRef = db.collection("otp_rate_limits").doc(normalizedPhone);
    const ipLimitRef = db.collection("otp_rate_limits").doc(`ip_${ip.replace(/\./g, '_')}`);

    await db.runTransaction(async (transaction) => {
      const rlDoc = await transaction.get(rateLimitRef);
      const ipDoc = await transaction.get(ipLimitRef);

      const hourAgo = new Date(now.toDate().getTime() - 60 * 60 * 1000);

      // Check IP limits
      let ipRequests = ipDoc.exists ? (ipDoc.data()?.requests || []) : [];
      ipRequests = ipRequests.filter((ts: any) => ts.toDate() > hourAgo);
      if (ipRequests.length >= 10) {
        throw new HttpsError("resource-exhausted", "Too many requests from this IP. Please try again later.");
      }

      let phoneRequests = rlDoc.exists ? (rlDoc.data()?.requests || []) : [];
      phoneRequests = phoneRequests.filter((ts: any) => ts.toDate() > hourAgo);
      
      const blockedUntil = rlDoc.exists ? rlDoc.data()?.blockedUntil : null;
      if (blockedUntil && blockedUntil.toDate() > now.toDate()) {
        throw new HttpsError("resource-exhausted", "Too many failed attempts. Try again later.");
      }

      if (phoneRequests.length >= 5) {
        throw new HttpsError("resource-exhausted", "Too many requests for this phone number. Try again later.");
      }

      if (phoneRequests.length > 0) {
        const lastReq = phoneRequests[phoneRequests.length - 1].toDate();
        if (now.toDate().getTime() - lastReq.getTime() < 60000) {
          throw new HttpsError("resource-exhausted", "Please wait 60 seconds before requesting a new OTP.");
        }
      }

      ipRequests.push(now);
      phoneRequests.push(now);

      transaction.set(rateLimitRef, { requests: phoneRequests, failedAttempts: 0, blockedUntil: null }, { merge: true });
      transaction.set(ipLimitRef, { requests: ipRequests }, { merge: true });
    });

    try {
      const authKey = msg91AuthKey.value();
      const url = `https://control.msg91.com/api/v5/otp?template_id=${MSG91_TEMPLATE_ID}&mobile=${normalizedPhone}&authkey=${authKey}`;
      
      const res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' } });
      const data = await res.json();

      if (data.type === "error") {
        logger.error("MSG91 sendOtp error", { phone: normalizedPhone, msg91Response: data });
        throw new HttpsError("internal", "Failed to send OTP.");
      }
      
      logger.info("MSG91 sendOtp success", { phone: normalizedPhone });
      return { success: true };
    } catch (e: any) {
      logger.error("sendOtp exception", { error: e.message });
      throw new HttpsError("internal", "Failed to send OTP.");
    }
  }
);

export const verifyOtp = onCall(
  { secrets: [msg91AuthKey] },
  async (request) => {
    const { phoneNumber, otp } = request.data;
    if (!phoneNumber || typeof phoneNumber !== "string" || !/^\+91[0-9]{10}$/.test(phoneNumber)) {
      throw new HttpsError("invalid-argument", "Invalid phone number format.");
    }
    if (!otp || typeof otp !== "string" || otp.length < 4) {
      throw new HttpsError("invalid-argument", "Invalid OTP format.");
    }

    const normalizedPhone = phoneNumber.replace("+91", "91");
    const rateLimitRef = db.collection("otp_rate_limits").doc(normalizedPhone);
    const now = admin.firestore.Timestamp.now();

    await db.runTransaction(async (transaction) => {
      const rlDoc = await transaction.get(rateLimitRef);
      if (!rlDoc.exists) return; // Allow verify even if no limit doc, though rare

      const blockedUntil = rlDoc.data()?.blockedUntil;
      if (blockedUntil && blockedUntil.toDate() > now.toDate()) {
        throw new HttpsError("resource-exhausted", "Too many failed attempts. Try again later.");
      }
    });

    try {
      const authKey = msg91AuthKey.value();
      const url = `https://control.msg91.com/api/v5/otp/verify?otp=${otp}&mobile=${normalizedPhone}`;
      
      const res = await fetch(url, { method: 'GET', headers: { 'authkey': authKey } });
      const data = await res.json();

      if (data.type === "error") {
        await db.runTransaction(async (transaction) => {
          const rlDoc = await transaction.get(rateLimitRef);
          let failedAttempts = rlDoc.exists ? (rlDoc.data()?.failedAttempts || 0) : 0;
          failedAttempts++;
          
          let blockedUntil = null;
          if (failedAttempts >= 3) {
            blockedUntil = admin.firestore.Timestamp.fromDate(new Date(now.toDate().getTime() + 15 * 60 * 1000));
          }
          transaction.set(rateLimitRef, { failedAttempts, blockedUntil }, { merge: true });
        });
        
        throw new HttpsError("invalid-argument", "Incorrect OTP or OTP expired.");
      }

      // OTP Verified Successfully
      // Clear failed attempts
      await rateLimitRef.set({ failedAttempts: 0, blockedUntil: null }, { merge: true });

      // Handle Firebase Auth User
      let uid: string;
      try {
        const userRecord = await admin.auth().getUserByPhoneNumber(phoneNumber);
        uid = userRecord.uid;
      } catch (error: any) {
        if (error.code === 'auth/user-not-found') {
          const newUser = await admin.auth().createUser({ phoneNumber });
          uid = newUser.uid;
        } else {
          throw error;
        }
      }

      // Generate custom token
      const customToken = await admin.auth().createCustomToken(uid);
      logger.info("MSG91 verifyOtp success", { phone: normalizedPhone, uid });
      return { token: customToken };
    } catch (e: any) {
      logger.error("verifyOtp exception", { error: e.message });
      if (e instanceof HttpsError) throw e;
      throw new HttpsError("internal", "Verification failed.");
    }
  }
);
