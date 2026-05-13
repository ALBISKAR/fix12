import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
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
    // استثناء المسؤول
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
          // لا تقم بتغيير الحالة لـ false هنا فوراً لإعطاء فرصة لإعادة المحاولة لاحقاً
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
    if (currentUid == 'OeEwi4nMZrPjRLRiqWf1373btQT2') {
      return const SizedBox.shrink();
    }

    return Container(
      color: Colors.black
          .withValues(alpha: 0.05), // خلفية خفيفة جداً لتمييز منطقة الإعلانات
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. مساحة AdMob
          if (_isAdMobLoaded && _adMobBanner != null)
            SizedBox(
              height: 50,
              width: double.infinity,
              child: AdWidget(ad: _adMobBanner!),
            ),

          // 2. مساحة Unity (المعدلة لضمان الظهور)
          SizedBox(
            height: 50,
            width: double.infinity,
            child: UnityBannerAd(
              placementId: 'Banner_Android',
              onLoad: (id) => debugPrint('✅ Unity Banner Loaded: $id'),
              onFailed: (id, error, message) =>
                  debugPrint('❌ Unity Banner Failed: $message'),
              onClick: (id) => debugPrint('Unity Banner Clicked: $id'),
            ),
          ),
        ],
      ),
    );
  }
}
