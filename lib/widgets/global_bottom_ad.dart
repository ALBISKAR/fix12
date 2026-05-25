import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';

class GlobalBottomAd extends StatefulWidget {
  const GlobalBottomAd({super.key});

  @override
  State<GlobalBottomAd> createState() => _GlobalBottomAdState();
}

class _GlobalBottomAdState extends State<GlobalBottomAd> {
  BannerAd? _adMobBanner;
  bool _isAdMobLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAdMobBanner();
  }

  void _loadAdMobBanner() {
    final String? currentUid = FirebaseAuth.instance.currentUser?.uid;
    // استثناء المسؤول لحماية الحساب الإعلاني من النقرات الذاتية
    if (currentUid == 'OeEwi4nMZrPjRLRiqWf1373btQT2') return;

    _adMobBanner = BannerAd(
      adUnitId: AdManager.adMobBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          debugPrint("✅ AdMob Banner Loaded Successfully");
          if (mounted) {
            setState(() => _isAdMobLoaded = true);
          }
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint("❌ AdMob Banner Failed: ${error.message}");
          ad.dispose();
          if (mounted) {
            setState(() => _isAdMobLoaded = false);
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _adMobBanner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String? currentUid = FirebaseAuth.instance.currentUser?.uid;
    // إذا كان المستخدم هو الأدمن لا يتم عرض أي شيء
    if (currentUid == 'OeEwi4nMZrPjRLRiqWf1373btQT2') {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black.withValues(alpha: 0.03), // خلفية خفيفة جداً لتمييز منطقة الإعلانات
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1️⃣ البانر الأول: إعلان AdMob (يظهر فقط إذا تم تحميله بنجاح)
          if (_isAdMobLoaded && _adMobBanner != null)
            SizedBox(
              height: 50,
              width: double.infinity,
              child: AdWidget(ad: _adMobBanner!),
            ),

          // 🛑 فاصل صغير جداً لحماية الحساب من مخالفات النقرات غير المقصودة وسياسات AdMob
          if (_isAdMobLoaded)
            const SizedBox(height: 4), 

          // 2️⃣ البانر الثاني: إعلان Start.io (يتم استدعاؤه وإجباره على الظهور أسفل AdMob)
          // قمنا بتمرير قوة الإجبار (forceAdMob: false) ليعود ويعرض بانر Start.io المجهز في الـ AdManager
          AdManager.smartBanner(_adMobBanner),
        ],
      ),
    );
  }
}