import 'package:syria_earn_pro/utils/security_utils.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 👈 إضافة مكتبة SharedPreferences
import 'package:syria_earn_pro/screens/home_screen.dart';
import 'package:syria_earn_pro/screens/login_screen.dart';
import 'package:syria_earn_pro/screens/intro_screen.dart'; // 👈 تأكد من إنشاء هذا الملف
import 'dart:io';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    await Future.delayed(const Duration(seconds: 3));

    try {
      // 1. جلب حالة "تمكين فحص المحاكي" من السيرفر أولاً
      var config = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      bool isEmulatorCheckEnabled = true; // القيمة الافتراضية
      if (config.exists) {
        isEmulatorCheckEnabled =
            config.data()?['emulator_check_enabled'] ?? true;
      }

      // 2. إذا كان الفحص مفعلاً في السيرفر، نفحص الجهاز
// 2. إذا كان الفحص مفعلاً في السيرفر، نفحص الجهاز
      if (isEmulatorCheckEnabled) {
        bool isEmulator = await SecurityUtils.isEmulator();
        
        if (isEmulator) {
          // 🚫 حظر فوري للجميع (بما في ذلك المطور أثناء الاختبار)
          if (mounted) {
            _showEmulatorBlockDialog();
            return; // إيقاف الدخول للتطبيق
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Error during splash security check: $e");
    }

    // 3. المتابعة الطبيعية إذا لم يتم الحظر أو كان الفحص معطلاً
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) await _repairUserData(user);
    if (mounted) _proceedToNextScreen(user);
  }

// نافذة الحظر التي لا يمكن إغلاقها
  void _showEmulatorBlockDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false, // منع زر الرجوع نهائياً
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              const Icon(Icons.phonelink_erase, color: Colors.red, size: 60),
              const SizedBox(height: 15),
              Text(
                tr('emulator_not_allowed'), // تم التعديل للمفتاح الذي اتفقنا عليه
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ],
          ),
          content: Text(
            tr('use_physical_device_msg'), // الرسالة التفصيلية المترجمة
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => exit(0), // إغلاق التطبيق فوراً
                child: Text(
                  tr('exit_app'), // "إغلاق التطبيق"
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // دالة لإصلاح بيانات المستخدمين القدامى لضمان التوافق مع القواعد
  Future<void> _repairUserData(User user) async {
    try {
      final userDoc =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snapshot = await userDoc.get();

      if (snapshot.exists) {
        final data = snapshot.data();
        final Map<String, dynamic> updates = {};

        // إضافة حقول السلسلة اليومية إذا كانت مفقودة
        if (data != null) {
          if (!data.containsKey('streak_count')) updates['streak_count'] = 0;
          if (!data.containsKey('last_daily_claim')) {
            updates['last_daily_claim'] = DateTime.now()
                .subtract(const Duration(days: 2))
                .toIso8601String();
          }
          if (!data.containsKey('points')) updates['points'] = 100;

          if (updates.isNotEmpty) {
            await userDoc.update(updates);
            debugPrint("✅ تم إصلاح بيانات المستخدم: ${updates.keys.toList()}");
          }
        }
      }
    } catch (e) {
      debugPrint("❌ خطأ أثناء إصلاح البيانات في الـ Splash: $e");
    }
  }

  // 🚩🚩🚩🚩🚩 دالة الانتقال المعدلة 🚩🚩🚩🚩🚩
  void _proceedToNextScreen(User? user) async {
    // 1. تنفيذ العمليات غير المتزامنة أولاً
    final prefs = await SharedPreferences.getInstance();

    // 🛡️ 2. الحارس الأمني: فحص هل الشاشة لا تزال نشطة؟
    if (!mounted) return; // 👈 هذا السطر سيحذف الخطأ فوراً

    final bool isIntroSeen = prefs.getBool('is_intro_seen') ?? false;

    Widget targetScreen;
    if (user == null) {
      targetScreen = isIntroSeen ? const LoginScreen() : const IntroScreen();
    } else {
      targetScreen = const HomeScreen();
    }

    // الآن يمكنك استخدام context بأمان
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => targetScreen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E), // لون خلفية موحد
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // شعار التطبيق
            const Icon(Icons.stars, size: 120, color: Colors.amber),
            const SizedBox(height: 30),
            // اسم التطبيق
            const Text(
              "Syria Earn Pro",
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 50),
            // مؤشر التحميل
            const CircularProgressIndicator(
              color: Colors.amber,
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }
}
