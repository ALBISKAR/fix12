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
    if (currentUid == 'OeEwi4nMZrPjRLRiqWf1373btQT2') return;

    _adMobBanner = BannerAd(
      adUnitId: AdManager.adMobBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() => _isAdMobLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _isAdMobLoaded = false);
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
    // إذا كنت أنت المطور، لا تعرض شيئاً
    if (currentUid == 'OeEwi4nMZrPjRLRiqWf1373btQT2') {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min, // ليأخذ مساحة الإعلانات فقط
      children: [
        // 1. مساحة إعلان AdMob (تظهر فقط إذا توفر الإعلان)
        if (_isAdMobLoaded && _adMobBanner != null)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: AdWidget(ad: _adMobBanner!),
          ),

        // 2. مساحة إعلان Unity (تظهر فقط إذا توفر الإعلان)
        // ويدجيت Unity يعالج نفسه داخلياً، سيعرض مساحة فارغة إذا لم يتوفر
        SizedBox(
          width: double.infinity,
          height: 50,
          child: UnityBannerAd(
            placementId: 'Banner_Android',
            onLoad: (id) => debugPrint('✅ Unity Banner Loaded'),
            onFailed: (id, error, message) => 
                debugPrint('❌ Unity Banner Not Available'),
          ),
        ),
      ],
    );
  }
}