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

// ✅ دالة الحماية العبقرية: تكشف المحاكيات المتخفية بأسماء هواتف حقيقية (بدون استثناء المطور)
  static Future<bool> isEmulator() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

      // 🛡️ صمام أمان لهواتف سامسونغ الحقيقية القديمة (مثل J7)
      // إذا كان الجهاز يمتلك لوحة أم معمارية تخص معالجات سامسونغ الحقيقية (مثل universal أو exynos)
      // فإنه يهرب تماماً من فحص المحاكي لأنه جهاز حقيقي 100% مهما كان قديماً
      String board = androidInfo.board.toLowerCase();
      String hardware = androidInfo.hardware.toLowerCase();
      String manufacturer = androidInfo.manufacturer.toLowerCase();
      String brand = androidInfo.brand.toLowerCase();

      bool isRealSamsungExynos = brand.contains("samsung") &&
          (board.contains("universal") ||
              board.contains("exynos") ||
              hardware.contains("s5e"));

      if (isRealSamsungExynos) {
        return false; // عُبور آمن فوراً لجهاز J7 وأشباهه الحقيقية
      }

      // 1️⃣ فحص معمارية المعالج العميقة 🧠
      // المحاكيات تعمل على الكمبيوتر بمعالجات Intel أو AMD (معمارية x86) بينما الهواتف تعمل بمعالجات ARM.
      List<String> supportedAbis = androidInfo.supportedAbis;
      bool isX86Architecture = supportedAbis.any((abi) =>
          abi.toLowerCase().contains("x86") ||
          abi.toLowerCase().contains("amd64"));

      // 2️⃣ فحص ملفات النظام والمحركات الوهمية العميقة 📂
      bool hasEmulatorFiles =
          File('/system/lib/libc_malloc_debug_qemu.so').existsSync() ||
              File('/sys/qemu_trace').existsSync() ||
              File('/system/bin/qemu-props').existsSync() ||
              Directory('/dev/socket/qemud').existsSync() ||
              Directory('/dev/qemu_pipe').existsSync() ||
              File('/system/bin/nox-prop').existsSync() ||
              Directory('/dev/vboxguest').existsSync() ||
              Directory('/dev/vboxuser').existsSync();

      // 3️⃣ فحص الحقول الجازمة التي ينسى المحاكي تزييفها (Identity) 🆔
      bool isEmulatorIdentity = hardware.contains("goldfish") ||
          hardware.contains("ranchu") ||
          hardware.contains("vbox86") ||
          androidInfo.model.toLowerCase().contains("sdk_gphone") ||
          manufacturer.contains("genymotion") ||
          manufacturer.contains("bluestacks") ||
          brand.contains("generic") ||
          androidInfo.bootloader.toLowerCase().contains("unknown") ||
          androidInfo.device.toLowerCase().contains("generic");

      // 4️⃣ فحص التناقض في "البصمة" وتزييف الهوية (Spoofing) 🎯
      bool isSpoofed = androidInfo.fingerprint.startsWith("generic") ||
          androidInfo.fingerprint.contains("test-keys") ||
          androidInfo.fingerprint.contains("google_sdk");

      // 🔥 النتيجة النهائية
      bool result = isX86Architecture ||
          hasEmulatorFiles ||
          isEmulatorIdentity ||
          isSpoofed;

      if (result) {
        await sendSecurityReport(
            "Advanced Emulator/VMS Detected via Hardware Architecture");
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
