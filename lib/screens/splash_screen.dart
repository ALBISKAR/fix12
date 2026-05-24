import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syria_earn_pro/utils/security_utils.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:syria_earn_pro/screens/home_screen.dart';
import 'package:syria_earn_pro/screens/login_screen.dart';
import 'package:syria_earn_pro/screens/intro_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _progress = 0.0;
  Timer? _timer;
  final String _adminUid = "OeEwi4nMZrPjRLRiqWf1373btQT2";

  @override
  void initState() {
    super.initState();
    // تأجيل تنفيذ العمليات حتى يتم رسم الواجهة أولاً لمنع تجمد التطبيق (ANR)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startAppInitialization();
    });
  }

  Future<void> _startAppInitialization() async {
    debugPrint("🚀 بدء عملية التهيئة...");

    final currentUser = FirebaseAuth.instance.currentUser;

    // 1. الفحص الأمني (ضروري جداً الانتظار هنا)
    bool isEnvironmentSafe = await SecurityUtils.runComprehensiveSecurityCheck(
        context: context, user: currentUser, adminUid: _adminUid);

    if (!isEnvironmentSafe || !mounted) return;

    // 2. تحميل الإعلانات والعمليات في الخلفية (بدون انتظار - Async)
    _runBackgroundTasks(currentUser);

    // 3. بدء المؤقت للتحميل البصري (10 ثوانٍ)
    _startLoadingTimer(currentUser);
  }

  void _runBackgroundTasks(User? user) async {
    // إصلاح بيانات المستخدم إذا كان مسجلاً
    if (user != null && user.uid != _adminUid) {
      await _repairUserData(user);
    }

    // تحميل الإعلانات (للمستخدم العادي فقط)
    if (user == null || user.uid != _adminUid) {
      debugPrint("📢 جاري تحميل الإعلانات...");
      AdManager.loadAppOpenAd();
      AdManager.loadAdMobInterstitial();
    }
  }

  void _startLoadingTimer(User? user) {
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        if (_progress < 1.0) {
          _progress += 0.01; // 100 خطوة * 100ms = 10 ثواني
        } else {
          timer.cancel();
          _proceedToNextScreen(user);
        }
      });
    });
  }

  Future<void> _proceedToNextScreen(User? user) async {
    final prefs = await SharedPreferences.getInstance();
    AdManager.showAppOpenAdOnce();

    if (!mounted) return;

    final bool isIntroSeen = prefs.getBool('is_intro_seen') ?? false;
    Widget target = (user == null)
        ? (isIntroSeen ? const LoginScreen() : const IntroScreen())
        : const HomeScreen();

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => target),
      (route) => false,
    );
  }

  Future<void> _repairUserData(User user) async {
    try {
      final docRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snapshot = await docRef.get();
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null &&
            (!data.containsKey('points') ||
                !data.containsKey('streak_count'))) {
          await docRef.set({
            'points': data['points'] ?? 100,
            'streak_count': data['streak_count'] ?? 0,
          }, SetOptions(merge: true));
        }
      }
    } catch (e) {
      debugPrint("❌ Repair error: $e");
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int percentage = (_progress * 100).toInt();

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // الدائرة والنسبة المئوية
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 8,
                    backgroundColor: Colors.white10,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(Colors.amber),
                  ),
                ),
                Text(
                  "$percentage%",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    shadows: [Shadow(color: Colors.amber, blurRadius: 15)],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),
            // اسم التطبيق
            const Text(
              "Syria Earn Pro",
              style: TextStyle(
                color: Colors.white,
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 20),
            // الرسالة الجديدة بخط جميل
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                'loading_ads_msg'.tr(), // استخدام دالة الترجمة
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
