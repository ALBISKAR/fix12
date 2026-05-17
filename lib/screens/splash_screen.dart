import 'dart:async';
import 'package:syria_earn_pro/utils/security_utils.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syria_earn_pro/screens/home_screen.dart';
import 'package:syria_earn_pro/screens/login_screen.dart';
import 'package:syria_earn_pro/screens/intro_screen.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'dart:io';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAppInitialization();
  }

// 🟢 نقطة الانطلاق الموحدة (محدثة لتخطي الانتظار للأدمن)
  void _startAppInitialization() {
    final currentUser = FirebaseAuth.instance.currentUser;
    const String adminUid = "OeEwi4nMZrPjRLRiqWf1373btQT2";

    // 🛡️ خط دفاع الأدمن السريع: إذا كنت أنت الأدمن، تجاوز الانتظار والتحميل فوراً
    if (currentUser != null && currentUser.uid == adminUid) {
      debugPrint("🚀 Admin Detected: Skipping Splash screen timer delay.");
      if (mounted) {
        setState(() {
          _progress = 1.0; // اكتمال الخط وهمياً فوراً
        });
      }
      _proceedToNextScreen(currentUser);
      _performBackgroundTasks(); // معالجة المهام الخلفية الضرورية دون تأخير
      return;
    }

    // 1. تشغيل عداد خط التحميل الطبيعي للمستخدمين (10 ثوانٍ) كما هو
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (mounted) {
        setState(() {
          if (_progress < 1.0) {
            _progress += 0.01;
          } else {
            _timer?.cancel();
            _proceedToNextScreen(FirebaseAuth.instance.currentUser);
          }
        });
      }
    });

    // 2. تشغيل العمليات الخلفية للمستخدمين بشكل متوازي
    _performBackgroundTasks();
  }

  Future<void> _performBackgroundTasks() async {
    // 📢 طلب الإعلانات فوراً (أهم خطوة لضمان جاهزيتها قبل الـ 100%)
    AdManager.loadAppOpenAd();
    AdManager.loadAdMobInterstitial();

    try {
      // جلب الإعدادات من السيرفر
      var config = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get()
          .timeout(const Duration(seconds: 4));

      // فحص المحاكي
      if (config.exists && (config.data()?['emulator_check_enabled'] ?? true)) {
        bool isEmulator = await SecurityUtils.isEmulator();
        if (isEmulator && mounted) {
          _timer?.cancel();
          _showEmulatorBlockDialog();
          return;
        }
      }

      // إصلاح بيانات المستخدم إن وجد
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _repairUserData(user);
      }
    } catch (e) {
      debugPrint("⚠️ Background tasks info: $e");
      // لا نعطل التطبيق في حال فشل المهام الخلفية، نترك الخط يكمل مساره
    }
  }

  void _proceedToNextScreen(User? user) async {
    final prefs = await SharedPreferences.getInstance();

    // محاولة عرض إعلان الفتح
    AdManager.showAppOpenAdOnce();

    // تأخير بسيط لضمان استقرار الواجهة بعد الإعلان
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final bool isIntroSeen = prefs.getBool('is_intro_seen') ?? false;
    Widget targetScreen;

    if (user == null) {
      targetScreen = isIntroSeen ? const LoginScreen() : const IntroScreen();
    } else {
      targetScreen = const HomeScreen();
    }

    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => targetScreen),
        (route) => false,
      );
    }
  }

  void _showEmulatorBlockDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: [
              const Icon(Icons.phonelink_erase, color: Colors.red, size: 60),
              const SizedBox(height: 15),
              Text(
                tr('emulator_not_allowed'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ],
          ),
          content: Text(
            tr('use_physical_device_msg'),
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
                onPressed: () => exit(0),
                child: Text(tr('exit_app'),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _repairUserData(User user) async {
    try {
      final userDoc =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snapshot = await userDoc.get();
      if (snapshot.exists) {
        final data = snapshot.data();
        final Map<String, dynamic> updates = {};
        if (data != null) {
          if (!data.containsKey('streak_count')) updates['streak_count'] = 0;
          if (!data.containsKey('last_daily_claim')) {
            updates['last_daily_claim'] = DateTime.now()
                .subtract(const Duration(days: 2))
                .toIso8601String();
          }
          if (!data.containsKey('points')) updates['points'] = 100;
          if (updates.isNotEmpty) await userDoc.update(updates);
        }
      }
    } catch (e) {
      debugPrint("❌ Data repair error: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.stars, size: 120, color: Colors.amber),
            const SizedBox(height: 30),
            const Text(
              "Syria Earn Pro",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5),
            ),
            const SizedBox(height: 60),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 50),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 8,
                      backgroundColor: Colors.white10,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.amber),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    "${(_progress * 100).toInt()}%",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    tr('loading_ads_msg'),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
