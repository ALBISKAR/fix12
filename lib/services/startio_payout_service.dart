import 'package:flutter/material.dart';
import 'package:startapp_sdk/startapp.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StartIoPayoutService {
  static final StartIoPayoutService instance = StartIoPayoutService._init();
  StartIoPayoutService._init();

  final StartAppSdk _startAppSdk = StartAppSdk();
  StartAppRewardedVideoAd? _rewardedVideoAd;
  bool _isAdLoading = false;

// ✅ أضف متغير لتخزين دالة التحديث في أعلى الكلاس
  VoidCallback? onAdClosedCallback;

  void loadServer1Ad() {
    if (_isAdLoading || _rewardedVideoAd != null) return;
    _isAdLoading = true;

    _startAppSdk.setTestAdsEnabled(true);

    _startAppSdk.loadRewardedVideoAd(
      onAdNotDisplayed: () {
        debugPrint("⚠️ لم يتم عرض الإعلان بنجاح");
        _clearAndReload();
      },
      onAdHidden: () {
        debugPrint("🔔 قام المستخدم بإغلاق الإعلان");
        // 🔥 تشغيل دالة التحديث فوراً عند الإغلاق لتشغيل التايمر في الواجهة
        if (onAdClosedCallback != null) {
          onAdClosedCallback!();
        }
        _clearAndReload();
      },
      onVideoCompleted: () {
        debugPrint("👑 اكتمل الفيديو! جاري منح النقاط سحابياً...");
        _assignPointsToFirestore();
      },
    ).then((ad) {
      _rewardedVideoAd = ad;
      _isAdLoading = false;
      debugPrint("✅ سيرفر 1 جاهز بنسبة 100% لبث الفيديو");
    }).catchError((error) {
      _isAdLoading = false;
      debugPrint("❌ فشل تحميل إعلان سيرفر 1: $error");
    });
  }

  /// 🖥️ دالة العرض الآمنة مع التحقق من وجود الكائن
  void showServer1Ad(BuildContext context) {
    if (_rewardedVideoAd != null) {
      _rewardedVideoAd!.show();
    } else {
      loadServer1Ad(); // إعادة المحاولة في الخلفية
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🔄 جاري الاتصال بسيرفر 1.. اضغط مجدداً بعد ثانيتين ⏳"),
          backgroundColor: Colors.blueGrey,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// تنظيف الذاكرة وإعادة التحميل لمنع تسريب البيانات (Memory Leak)
  void _clearAndReload() {
    _rewardedVideoAd?.dispose();
    _rewardedVideoAd = null;
    _isAdLoading = false;
    loadServer1Ad(); // تجهيز الفيديو القادم
  }

  /// 💰 الشحن السحابي المتوافق مع شريط السجل الحركي في الشاشة الرئيسية
  Future<void> _assignPointsToFirestore() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final userDocRef =
        FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
    final taskDocRef =
        FirebaseFirestore.instance.collection('completed_tasks').doc();

    WriteBatch batch = FirebaseFirestore.instance.batch();

    // 1. إضافة 10 نقاط كاملة وصحيحة للحساب الإجمالي للمستخدم
    batch.update(userDocRef, {
      'points': FieldValue.increment(10),
    });

    // 2. تدوين السجل بالحقل الصحيح (userId) ليعمل الشريط الحركي المتكرر دون انهيار
    batch.set(taskDocRef, {
      'userId': currentUser.uid,
      'taskType': 'server1_ad', // المسمى البرمجي المعتمد لـ سيرفر 1
      'rewardAmount': 10,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    _clearAndReload(); // تنظيف وتجهيز إعلان جديد
  }
}
