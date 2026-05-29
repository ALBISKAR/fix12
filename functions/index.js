const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onRequest, onCall } = require("firebase-functions/v2/https"); // ✅ تم إضافة onCall هنا
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// ======================================================================
// 0. 🎡 دالة عجلة الحظ (مؤمنة في السيرفر)
// ======================================================================
exports.spinLuckyWheel = onCall(async (request) => {
    // 1. التحقق من تسجيل الدخول
    if (!request.auth) {
        throw new Error("يجب تسجيل الدخول أولاً");
    }

    const userId = request.auth.uid;
    const userRef = db.collection('users').doc(userId);

    // 2. منطق الاحتمالات (95% من 1 لـ 4، 4% من 5 لـ 8، 1% من 9 لـ 10)
    const random = Math.random();
    let points = 0;
    
    if (random < 0.95) {
        points = Math.floor(Math.random() * 4) + 1; // 1-4 نقاط (95%)
    } else if (random < 0.99) {
        points = Math.floor(Math.random() * 4) + 5; // 5-8 نقاط (4%)
    } else {
        points = Math.floor(Math.random() * 2) + 9; // 9-10 نقاط (1%)
    }

    // 3. تحديث النقاط في Firestore عبر Transaction لضمان الأمان
    await db.runTransaction(async (t) => {
        const userDoc = await t.get(userRef);
        if (!userDoc.exists) throw new Error("User Not Found");
        const userData = userDoc.data();
        
        // حماية متقدمة: منع استدعاء عجلة الحظ أكثر من مرة كل دقيقتين لمنع ثغرات السبام
        const lastSpin = userData.last_spin_time ? (userData.last_spin_time.toDate ? userData.last_spin_time.toDate() : new Date(0)) : new Date(0);
        if (Date.now() - lastSpin.getTime() < 2 * 60 * 1000) {
            throw new Error("يرجى الانتظار قبل المحاولة مرة أخرى");
        }

        t.update(userRef, {
            points: admin.firestore.FieldValue.increment(points),
            last_spin_time: admin.firestore.FieldValue.serverTimestamp(),
            points_history: admin.firestore.FieldValue.arrayUnion({
                taskId: `lucky_wheel_${Date.now()}`,
                amount: points,
                type: 'lucky_wheel_reward',
                timestamp: new Date()
            })
            });

            const newTaskRef = db.collection('completed_tasks').doc();
            t.set(newTaskRef, {
                userId: userId,
                taskType: 'lucky_wheel_reward',
                rewardAmount: points,
                status: 'verified',
                timestamp: new Date()
        });
    });

    return { points: points };
});

// ======================================================================
// 1. 💰 دالة CPALead Postback 
// ======================================================================
exports.cpaleadPostback = onRequest(async (req, res) => {
    const userId = req.query.subid;
    const payout = parseFloat(req.query.payout);
    const leadId = req.query.lead_id;
    const password = req.query.password;

    const MY_POSTBACK_PASSWORD = "Mhmed@0011";
    if (password !== MY_POSTBACK_PASSWORD) {
        return res.status(401).send("Unauthorized");
    }

    if (!userId || !leadId || isNaN(payout)) {
        return res.status(400).send("Invalid Data");
    }

    try {
        const userRef = db.collection('users').doc(userId);
        const leadRef = db.collection('processed_leads').doc(leadId);

        await db.runTransaction(async (t) => {
            const leadDoc = await t.get(leadRef);
            if (leadDoc.exists) return;

            const userDoc = await t.get(userRef);
            if (!userDoc.exists) throw new Error("User Not Found");

            const userPercentage = 0.7; 
            const conversionRate = 1000; 

            const rewardPoints = Math.round((payout * conversionRate) * userPercentage); 

            t.update(userRef, {
                points: admin.firestore.FieldValue.increment(rewardPoints),
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: `cpalead_${leadId}`,
                    amount: rewardPoints,
                    type: 'offerwall_reward',
                    timestamp: new Date()
                })
            });

            t.set(leadRef, {
                userId: userId,
                amount: rewardPoints,
                processedAt: admin.firestore.FieldValue.serverTimestamp()
            });

            const newTaskRef = db.collection('completed_tasks').doc();
            t.set(newTaskRef, {
                userId: userId,
                taskType: 'offerwall_reward',
                rewardAmount: rewardPoints,
                status: 'verified',
                timestamp: new Date()
            });
        });

        return res.status(200).send("OK");
    } catch (error) {
        return res.status(500).send("Error");
    }
});

// ======================================================================
// 2. 🎁 المكافأة اليومية (مؤمنة 100% بتوقيت السيرفر)
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
            const now = new Date(); 
            const lastClaim = userData.last_daily_claim ? userData.last_daily_claim.toDate() : new Date(0);

            if (now.getTime() - lastClaim.getTime() < 23 * 60 * 60 * 1000) {
                t.update(snap.ref, { status: 'error', reason: 'too_early', processedAt: admin.firestore.FieldValue.serverTimestamp() });
                return;
            }

            const streak = parseInt(userData.streak_count || 0);
            const reward = 10 + (streak * 5);
            const nextStreak = (streak >= 6) ? 0 : streak + 1;
            
            const todayStr = `${now.getUTCFullYear()}-${now.getUTCMonth() + 1}-${now.getUTCDate()}`;

            t.update(userRef, {
                points: admin.firestore.FieldValue.increment(reward),
                last_daily_claim: admin.firestore.FieldValue.serverTimestamp(),
                last_claim_date_str: todayStr, 
                streak_count: nextStreak,
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: `daily_${todayStr}`,
                    amount: reward, 
                    type: 'daily_reward', 
                    timestamp: now
                })
            });

            t.update(snap.ref, { status: 'success', rewardAmount: reward, processedAt: admin.firestore.FieldValue.serverTimestamp() });
            
            const newTaskRef = db.collection('completed_tasks').doc();
            t.set(newTaskRef, {
                userId: userId,
                taskType: 'daily_reward',
                rewardAmount: reward,
                status: 'verified',
                timestamp: now
            });
        });
    } catch (error) { console.error("❌ Daily Reward Error:", error); }
});

// ======================================================================
// 2b. 🎁 المكافأة اليومية المباشرة عبر HTTP
// ======================================================================
exports.claimDailyReward = onRequest(async (req, res) => {
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Authorization');

    if (req.method === 'OPTIONS') {
        return res.status(204).send('');
    }

    if (req.method !== 'POST') {
        return res.status(405).json({ error: 'method_not_allowed' });
    }

    try {
        const authHeader = req.headers.authorization || '';
        const match = authHeader.match(/^Bearer (.+)$/);
        if (!match) {
            return res.status(401).json({ error: 'unauthorized' });
        }

        const decodedToken = await admin.auth().verifyIdToken(match[1]);
        const uid = decodedToken.uid;
        const userRef = db.collection('users').doc(uid);

        const result = await db.runTransaction(async (t) => {
            const userDoc = await t.get(userRef);
            if (!userDoc.exists) {
                throw new Error('user_not_found');
            }

            const userData = userDoc.data() || {};
            const now = new Date();
            
            let lastClaim = new Date(0);
            if (userData.last_daily_claim) {
                if (typeof userData.last_daily_claim.toDate === 'function') {
                    lastClaim = userData.last_daily_claim.toDate();
                } else {
                    lastClaim = new Date(userData.last_daily_claim); // معالجة احتياطية إذا كان التاريخ محفوظاً كنص
                }
            }

            if (now.getTime() - lastClaim.getTime() < 23 * 60 * 60 * 1000) {
                return { status: 'error', reason: 'too_early' };
            }

            const streak = parseInt(userData.streak_count || 0);
            const reward = 10 + (streak * 5);
            const nextStreak = streak >= 6 ? 0 : streak + 1;
            const todayStr = `${now.getUTCFullYear()}-${now.getUTCMonth() + 1}-${now.getUTCDate()}`;

            t.update(userRef, {
                points: admin.firestore.FieldValue.increment(reward),
                last_daily_claim: admin.firestore.FieldValue.serverTimestamp(),
                last_claim_date_str: todayStr,
                streak_count: nextStreak,
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: `daily_${todayStr}`,
                    amount: reward,
                    type: 'daily_reward',
                    timestamp: now
                })
            });

            const newTaskRef = db.collection('completed_tasks').doc();
            t.set(newTaskRef, {
                userId: uid,
                taskType: 'daily_reward',
                rewardAmount: reward,
                status: 'verified',
                timestamp: now
            });

            return { status: 'success', reward };
        });

        if (result.status === 'error') {
            return res.status(409).json({ error: 'too_early' });
        }

        return res.status(200).json({ status: 'success', rewardAmount: result.reward });
    } catch (error) {
        console.error('❌ claimDailyReward Error:', error);
        if (error.message === 'user_not_found') {
            return res.status(404).json({ error: 'user_not_found' });
        }
        return res.status(500).json({ error: 'internal_error', details: error.message });
    }
});

// ======================================================================
// 3. 📺 مكافأة الإعلانات 
// ======================================================================
exports.verifytaskandaddpoints = onDocumentCreated("completed_tasks/{taskId}", async (event) => {
    const snap = event.data;
    if (!snap) return null;
    const { userId, taskType } = snap.data();

    // 🛑 حماية: هذه الدالة مخصصة للتحقق من الإعلانات فقط، ولا يجب أن تتدخل في عجلة الحظ أو المكافآت الأخرى
    if (taskType !== 'server1_ad' && taskType !== 'unity_ad' && taskType !== 'admob_ad') {
        return null;
    }

    const userRef = db.collection('users').doc(userId);
    const configRef = db.collection('app_settings').doc('config');

    try {
        await db.runTransaction(async (t) => {
            const configDoc = await t.get(configRef);
            const userDoc = await t.get(userRef);
            
            if (!userDoc.exists) return;

            const configData = configDoc.exists ? configDoc.data() : {};

            const isServer1 = taskType === 'server1_ad' || taskType === 'unity_ad';
            
            let adLimit = isServer1 ? (configData.unity_daily_limit || 20) : (configData.admob_daily_limit || 20);
            let adPoints = isServer1 ? (configData.unity_points || 10) : (configData.admob_points || 10);

            const today = new Date().toISOString().split('T')[0];
            const history = userDoc.data().points_history || [];
            
            const count = history.filter(i => {
                if (!i.timestamp || (i.type !== taskType && i.type !== 'unity_ad')) return false;
                const itemDate = (i.timestamp.toDate ? i.timestamp.toDate() : new Date(i.timestamp));
                return itemDate.toISOString().split('T')[0] === today;
            }).length;

            if (count >= adLimit) {
                t.update(snap.ref, { status: 'rejected', reason: 'limit_reached' });
                return;
            }

            t.update(userRef, {
                points: admin.firestore.FieldValue.increment(adPoints),
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: event.params.taskId, 
                    amount: adPoints, 
                    type: taskType, 
                    timestamp: new Date()
                })
            });
            
            t.update(snap.ref, { status: 'verified', rewardAmount: adPoints, processedAt: admin.firestore.FieldValue.serverTimestamp() });
        });
    } catch (error) { console.error("❌ Ads Verification Error:", error); }
});

// ======================================================================
// 4. 🤝 نظام الإحالة 
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
                    taskId: `ref_bonus_${event.params.userId}`, 
                    amount: inviterPoints, 
                    type: 'referral_reward', 
                    timestamp: new Date()
                })
            });
            t.update(event.data.ref, {
                points: admin.firestore.FieldValue.increment(newPoints),
                points_history: admin.firestore.FieldValue.arrayUnion({
                    taskId: `welcome_bonus`, 
                    amount: newPoints, 
                    type: 'welcome_reward', 
                    timestamp: new Date()
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
    
    // 1. 🛡️ نظام الحظر التلقائي الذكي
    // إذا وصلت مخالفات المستخدم الأمنية إلى 3، يتم حظره نهائياً من السيرفر
    const newViolations = newData.violation_count || 0;
    const prevViolations = prevData.violation_count || 0;
    
    if (newViolations >= 3 && prevViolations < 3 && !newData.isBanned) {
        await event.data.after.ref.update({
            isBanned: true,
            ban_reason: 'Automated ban: Multiple security violations (3+).'
        });
    }
    
    // 2. 📊 مزامنة النقاط وجدار الحماية المضاد للاختراق (Anti-Cheat)
    const prevPoints = prevData.points || 0;
    const newPoints = newData.points || 0;
    const diff = newPoints - prevPoints;
        
    if (diff > 0) {
        const prevHistoryLen = (prevData.points_history || []).length;
        const newHistoryLen = (newData.points_history || []).length;
        
        // 🛡️ فحص حرج: إذا زادت النقاط ولم يزداد سجل المهام، فهذه محاولة اختراق لتخطي السجل!
        if (newHistoryLen <= prevHistoryLen) {
            // الحد الأقصى للنقاط المسموح للعميل بإرسالها في الطلب الواحد هو 100 نقطة حسب Rules
            if (diff <= 100) {
                console.warn(`[Anti-Cheat] تم اكتشاف تلاعب بالرصيد للمستخدم ${event.params.userId}. جاري التراجع.`);
                // التراجع عن النقاط المسروقة وتسجيل مخالفة
                await event.data.after.ref.update({
                    points: prevPoints,
                    violation_count: admin.firestore.FieldValue.increment(1)
                });
                
                // إنشاء تقرير أمني للأدمن
                await db.collection('security_reports').add({
                    uid: event.params.userId,
                    reason: 'Anti-Cheat: ArrayUnion bypass detected (Points increased without history log).',
                    timestamp: admin.firestore.FieldValue.serverTimestamp()
                });
                return; // إيقاف إكمال العملية
            } else {
                // إذا كانت الزيادة أكبر من 100 فهذا مستحيل من العميل (يتم صده من Rules).
                // هذا يعني أن الأدمن هو من أضاف النقاط يدوياً من لوحة التحكم، فندعه يمر بأمان.
                console.log(`[Admin Edit] إضافة رصيد إداري (${diff}) للمستخدم ${event.params.userId}.`);
            }
        }
        
        // تحديث إحصائيات السيرفر بشكل طبيعي
        const batch = db.batch();
        const configRef = db.collection('app_settings').doc('config');
        batch.set(configRef, {
            total_points_distributed: admin.firestore.FieldValue.increment(diff),
            daily_points: admin.firestore.FieldValue.increment(diff),
            weekly_points: admin.firestore.FieldValue.increment(diff)
        }, { merge: true });

        const userRef = db.collection('users').doc(event.params.userId);
        batch.update(userRef, {
            weekly_points: admin.firestore.FieldValue.increment(diff)
        });

        await batch.commit();
    }
});

exports.resetDailyStats = onSchedule("0 0 * * *", async () => {
    try {
        await db.collection('app_settings').doc('config').update({ daily_points: 0 });
    } catch (err) { console.error(err); }
});

exports.resetWeeklyLeaderboard = onSchedule("0 0 * * 0", async () => {
    try {
        await db.collection('app_settings').doc('config').update({ weekly_points: 0 });
        const usersRef = db.collection('users');
        const snapshot = await usersRef.where('weekly_points', '>', 0).get();

        if (snapshot.empty) return;

        let batch = db.batch();
        let count = 0;

        for (const doc of snapshot.docs) {
            batch.update(doc.ref, { weekly_points: 0 });
            count++;
            if (count === 499) {
                await batch.commit();
                batch = db.batch();
                count = 0;
            }
        }
        if (count > 0) await batch.commit();
        console.log("✅ تم تصفير اللوحة الأسبوعية.");
    } catch (error) { console.error("❌ خطأ:", error); }
});
