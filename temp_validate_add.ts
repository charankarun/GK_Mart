
export const validateMsg91Session = onCall(
  { secrets: [msg91AuthKey] },
  async (request) => {
    const { accessToken } = request.data;
    
    const ip = request.rawRequest.ip || "unknown";
    const now = admin.firestore.Timestamp.now();
    const ipLimitRef = db.collection("otp_rate_limits").doc(`validate_ip_${ip.replace(/\./g, '_')}`);
    await db.runTransaction(async (transaction) => {
      const ipDoc = await transaction.get(ipLimitRef);
      const hourAgo = new Date(now.toDate().getTime() - 60 * 60 * 1000);

      let ipRequests = ipDoc.exists ? (ipDoc.data()?.requests || []) : [];
      ipRequests = ipRequests.filter((ts: any) => ts.toDate() > hourAgo);
      if (ipRequests.length >= 20) {
        throw new HttpsError("resource-exhausted", "Too many validation requests from this IP. Please try again later.");
      }
      
      ipRequests.push(now);
      transaction.set(ipLimitRef, { requests: ipRequests }, { merge: true });
    });

    try {
      const authKey = msg91AuthKey.value();
      const url = "https://control.msg91.com/api/v5/widget/verifyAccessToken";
      
      const res = await fetch(url, { 
        method: 'POST', 
        headers: { 
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ 
          "authkey": authKey,
          "access-token": accessToken 
        })
      });
      
      const data = await res.json();

      if (data.type === "error" || !data.mobile) {
        logger.warn("MSG91 token validation failed", { response: data });
        throw new HttpsError("permission-denied", "Invalid or expired access token.");
      }

      let verifiedPhone = data.mobile;
      if (!verifiedPhone.startsWith("+")) {
        verifiedPhone = `+${verifiedPhone}`;
      }

      let uid: string;
      try {
        const userRecord = await admin.auth().getUserByPhoneNumber(verifiedPhone);
        uid = userRecord.uid;
      } catch (error: any) {
        if (error.code === 'auth/user-not-found') {
          const newUser = await admin.auth().createUser({ phoneNumber: verifiedPhone });
          uid = newUser.uid;
        } else {
          throw error;
        }
      }

      const customToken = await admin.auth().createCustomToken(uid);
      logger.info("MSG91 validate session success", { phone: verifiedPhone, uid });
      
      return { token: customToken };
    } catch (e: any) {
      logger.error("validateMsg91Session exception", { error: e.message });
      if (e instanceof HttpsError) throw e;
      throw new HttpsError("internal", "Token validation failed.");
    }
  }
);
