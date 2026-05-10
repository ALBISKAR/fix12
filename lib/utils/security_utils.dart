import 'dart:convert';
import 'dart:io'; // ضروري لفحص نوع النظام (Android/iOS)
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';

class SecurityUtils {
  // 1. دالة تشفير المعرفات (SHA-256) كما هي لديك
  static String hashDeviceId(String rawId) {
    var bytes = utf8.encode(rawId);
    var digest = sha256.convert(bytes);
    return digest.toString();
  }

  // 2. 🛡️ دالة كشف المحاكيات (جديد)
  static Future<bool> isEmulator() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      // 1. فحص المسارات والملفات المشبوهة (نظام الملفات الوهمي) 📂
      bool hasEmulatorFiles =
          File('/system/lib/libc_malloc_debug_qemu.so').existsSync() ||
              File('/sys/qemu_trace').existsSync() ||
              File('/system/bin/qemu-props').existsSync() ||
              Directory('/dev/socket/qemud').existsSync() ||
              Directory('/dev/qemu_pipe').existsSync();

      // 2. فحص الهوية التقنية العميقة (حتى لو تم تغيير الاسم) 🆔
      bool isEmulatorIdentity = androidInfo.fingerprint.contains("generic") ||
          androidInfo.fingerprint.contains("vbox") ||
          androidInfo.fingerprint
              .contains("test-keys") || // الهواتف الرسمية تستخدم release-keys
          androidInfo.hardware.toLowerCase().contains("goldfish") ||
          androidInfo.hardware.toLowerCase().contains("ranchu") ||
          androidInfo.model.toLowerCase().contains("sdk_gphone") ||
          androidInfo.manufacturer.toLowerCase().contains("genymotion");

      // 3. فحص التناقض في "البصمة" (التي كشفت جهازك سابقاً) 🎯
      // لاحظنا أن جهازك ينتحل S23 ولكن بصمته "gracelte" (Note 7)
      bool isSpoofed = androidInfo.fingerprint.contains("gracelte") ||
          androidInfo.fingerprint.contains("google_sdk");

      // النتيجة النهائية
      bool result = hasEmulatorFiles || isEmulatorIdentity || isSpoofed;

      if (result) {
        await sendSecurityReport(
            "Advanced Emulator/VMS Detected via Filesystem");
      }

      return result;
    }
    return false;
  }

  

// 📱 دالة جلب معرف الجهاز الفريد (Device ID)
  static Future<String> getDeviceId() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String rawId = "unknown_id";

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      // نستخدم الـ id الخاص بنظام أندرويد
      rawId = androidInfo.id;
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      rawId = iosInfo.identifierForVendor ?? "unknown_ios";
    }

    // نقوم بتشفير المعرف قبل إرجاعه لزيادة الأمان
    return hashDeviceId(rawId);
  }

// دالة للتأكد من أن الجهاز غير مرتبط بحساب آخر
  static Future<bool> isDeviceAlreadyRegistered(String hashedId) async {
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('device_id', isEqualTo: hashedId)
        .get();

    // إذا وجدنا أي مستخدم يملك نفس المعرف، نرجع true
    return query.docs.isNotEmpty;
  }

  // 3. دالة إرسال التقارير الأمنية ونظام الحظر التلقائي (كما هي لديك)
  static Future<void> sendSecurityReport(String reason) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);

    // تسجيل المخالفة في Firestore
    await FirebaseFirestore.instance.collection('security_reports').add({
      'uid': user.uid,
      'reason': reason,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // زيادة عداد المخالفات
    await userRef.update({
      'violation_count': FieldValue.increment(1),
    });

    // فحص الحظر التلقائي عند الوصول لـ 3 مخالفات
    final userDoc = await userRef.get();
    int count = (userDoc.data()?['violation_count'] ?? 0).toInt();

    if (count >= 3) {
      await userRef.update({
        'isBanned': true,
        'banReason': "تم الحظر تلقائياً لتكرار محاولات الغش (3 مخالفات)",
      });
    }
  }
}
