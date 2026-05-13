const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// ======================================================================
// 1. 💰 دالة CPALead Postback (النسخة الآمنة والمطورة)
// ======================================================================
exports.cpaleadPostback = onRequest(async (req, res) => {
    const userId = req.query.subid;
    const payout = parseFloat(req.query.payout);
    const leadId = req.query.lead_id; // معرف العملية الفريد لمنع التكرار
    const password = req.query.password; // كلمة المرور للتأمين

    // 🔒 تأمين بكلمة مرور (يجب مطابقتها في إعدادات CPALead)
    const MY_POSTBACK_PASSWORD = "Mhmed@0011";
    if (password !== MY_POSTBACK_PASSWORD) {
        return res.status(401).send("Unauthorized");
    }

    if (!userId || !leadId || isNaN(payout)) {
        return res.status(400).send("Invalid Data");
    }

    try {
        const userRef = db.collection('users').doc(userId);
        const leadRef = db.collection('processed_leads').doc(leadId); // سجل العمليات

        await db.runTransaction(async (t) => {
            // التحقق هل العملية تمت معالجتها مسبقاً؟
            const leadDoc = await t.get(leadRef);
            if (leadDoc.exists) {
                console.log(`⚠️ Lead ${leadId} already processed.`);
                return;
            }

            const userDoc = await t.get(userRef);
            if (!userDoc.exists) throw new Error("User Not Found");

            const userPercentage = 0.7; // نسبة المستخدم (70%)
            const conversionRate = 1000; // كل 1 دولار يقابله 1000 نقطة إجمالية

            const rewardPoints = Math.round((payout * conversionRate) * userPercentage); // تحويل الدولار لنقاط

            t.update(userRef, {
                points: admin.firestore.FieldValue.increment(rewardPoints),
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: `cpalead_${leadId}`,
                    amount: rewardPoints,
                    type: 'offerwall_reward',
                    timestamp: new Date()
                })
            });

            // تسجيل الـ lead_id لمنع التكرار مستقبلاً
            t.set(leadRef, {
                userId: userId,
                amount: rewardPoints,
                processedAt: admin.firestore.FieldValue.serverTimestamp()
            });
        });

        return res.status(200).send("OK");
    } catch (error) {
        console.error("❌ CPALead Error:", error);
        return res.status(500).send("Error");
    }
});

// ======================================================================
// 2. 🎁 المكافأة اليومية
// ======================================================================
exports.processDailyReward = onDocumentCreated("reward_requests/{requestId}", async (event) => {
    const snap = event.data;
    if (!snap) return null;
    const { userId } = snap.data();
    const userRef = db.collection('users').doc(userId);

    try {
        await db.runTransaction(async (t) => {
            const userDoc = await t.get(userRef);
            if (!userDoc.exists) return;

            const userData = userDoc.data();
            const lastClaim = userData.last_daily_claim?.toDate() || new Date(0);
            const now = new Date();

            if (now.getTime() - lastClaim.getTime() < 23 * 60 * 60 * 1000) {
                t.update(snap.ref, { status: 'error', reason: 'too_early' });
                return;
            }

            const streak = parseInt(userData.streak_count || 0);
            const reward = 10 + (streak * 5);

            t.update(userRef, {
                points: admin.firestore.FieldValue.increment(reward),
                last_daily_claim: admin.firestore.FieldValue.serverTimestamp(),
                streak_count: (streak >= 6) ? 0 : streak + 1,
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: `daily_${now.toISOString().split('T')[0]}`,
                    amount: reward, type: 'daily_reward', timestamp: now
                })
            });

            t.update(snap.ref, { status: 'success', processedAt: admin.firestore.FieldValue.serverTimestamp() });
        });
    } catch (error) { console.error("❌ Daily Reward Error:", error); }
});

// ======================================================================
// 3. 📺 مكافأة الإعلانات (AdMob & Unity)
// ======================================================================
exports.verifytaskandaddpoints = onDocumentCreated("completed_tasks/{taskId}", async (event) => {
    const snap = event.data;
    if (!snap) return null;
    const { userId, taskType } = snap.data();
    const userRef = db.collection('users').doc(userId);
    const configRef = db.collection('app_settings').doc('config');

    try {
        await db.runTransaction(async (t) => {
            const configDoc = await t.get(configRef);
            const configData = configDoc.exists ? configDoc.data() : {};

            let adLimit = (taskType === 'unity_ad') ? (configData.unity_daily_limit || 20) : (configData.admob_daily_limit || 20);
            let adPoints = (taskType === 'unity_ad') ? (configData.unity_points || 10) : (configData.admob_points || 10);

            const userDoc = await t.get(userRef);
            if (!userDoc.exists) return;

            const today = new Date().toISOString().split('T')[0];
            const history = userDoc.data().points_history || [];
            const count = history.filter(i => i.type === taskType && i.timestamp?.toDate().toISOString().split('T')[0] === today).length;

            if (count >= adLimit) {
                t.update(snap.ref, { status: 'rejected', reason: 'limit_reached' });
                return;
            }

            t.update(userRef, {
                points: admin.firestore.FieldValue.increment(adPoints),
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: event.params.taskId, amount: adPoints, type: taskType, timestamp: new Date()
                })
            });
            t.update(snap.ref, { status: 'verified', processedAt: admin.firestore.FieldValue.serverTimestamp() });
        });
    } catch (error) { console.error("❌ Ads Error:", error); }
});

// ======================================================================
// 4. 🤝 نظام الإحالة (إصلاح منطق الإضافة)
// ======================================================================
exports.onUserReferralReward = onDocumentCreated("users/{userId}", async (event) => {
    const configRef = db.collection('app_settings').doc('config');
    try {
        const configDoc = await configRef.get();
        const configData = configDoc.exists ? configDoc.data() : {};

        const inviterPoints = configData.referral_reward_inviter || 50;
        const newPoints = configData.referral_reward_new_user || 25;

        await configRef.update({ total_users: admin.firestore.FieldValue.increment(1) });

        const newUser = event.data.data();
        const referredByCode = (newUser.referred_by || "").toString().trim().toUpperCase();
        if (!referredByCode) return null;

        const referrerQuery = await db.collection('users').where('my_referral_code', '==', referredByCode).limit(1).get();
        if (referrerQuery.empty) return null;

        const referrerRef = referrerQuery.docs[0].ref;

        await db.runTransaction(async (t) => {
            t.update(referrerRef, {
                points: admin.firestore.FieldValue.increment(inviterPoints),
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: `ref_bonus_${event.params.userId}`, amount: inviterPoints, type: 'referral_reward', timestamp: new Date()
                })
            });
            t.update(event.data.ref, {
                points: admin.firestore.FieldValue.increment(newPoints),
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: `welcome_bonus`, amount: newPoints, type: 'welcome_reward', timestamp: new Date()
                })
            });
        });
    } catch (e) { console.error("❌ Referral Error:", e); }
});

// ======================================================================
// 5. 🕒 العمليات التلقائية
// ======================================================================
exports.syncGlobalStats = onDocumentUpdated("users/{userId}", async (event) => {
    const newData = event.data.after.data();
    const prevData = event.data.before.data();
    if (newData.points !== prevData.points) {
        const diff = (newData.points || 0) - (prevData.points || 0);
        return db.collection('app_settings').doc('config').set({
            total_points_distributed: admin.firestore.FieldValue.increment(diff),
            daily_points: admin.firestore.FieldValue.increment(diff)
        }, { merge: true });
    }
});

exports.resetDailyStats = onSchedule("0 0 * * *", async (event) => {
    try {
        await db.collection('app_settings').doc('config').update({ daily_points: 0 });
    } catch (err) { console.error(err); }
});