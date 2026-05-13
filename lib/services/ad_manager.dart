import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // من أجل kDebugMode

class AdManager {
  static const String unityGameId = '6070088';
  static const String adMobBannerId = 'ca-app-pub-3359289133347380/2505476154';
  static const String adMobRewardedId = 'ca-app-pub-3359289133347380/7487583368';
  static const String appOpenAdId = 'ca-app-pub-3359289133347380/3645365681';
  static const String adMobInterstitialId = 'ca-app-pub-3359289133347380/1879660708';

  static InterstitialAd? _interstitialAd;
  static AppOpenAd? _appOpenAd;
  static bool _isAppOpenAdLoading = false;
  static bool _isShowingAppOpenAd = false; // لمنع تداخل العرض
  static bool _isUnityReady = false;
  static int _clickCounter = 0;
  static const int _adThreshold = 5;
  static DateTime? _appOpenLoadTime;

  static bool get _isAdmin =>
      FirebaseAuth.instance.currentUser?.uid == 'OeEwi4nMZrPjRLRiqWf1373btQT2';

  // 🛡️ قفل الحساب (وظيفة الأمان الخاصة بك)
  static Future<void> markUserAsWatching() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isAdmin) return;
    try {
      final lockUntil = DateTime.now().add(const Duration(hours: 1));
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'login_lock_until': lockUntil});
      debugPrint('🛡️ Login locked until $lockUntil');
    } catch (e) {
      debugPrint('❌ Lock Error: $e');
    }
  }

  static void initialize() {
    if (_isAdmin) return;
    MobileAds.instance.initialize();
    
    loadAppOpenAd(); // تحميل إعلان الفتح عند البداية
    loadAdMobInterstitial();

    UnityAds.init(
      gameId: unityGameId,
      testMode: false,
      onComplete: () {
        _isUnityReady = true;
        loadUnityAd('Rewarded_Android');
      },
    );
  }

  // ==================== إعلان فتح التطبيق (App Open) ====================

  static void loadAppOpenAd() {
    if (_isAdmin || _isAppOpenAdLoading || isAppOpenAdAvailable) return;

    _isAppOpenAdLoading = true;
    AppOpenAd.load(
      adUnitId: appOpenAdId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _appOpenLoadTime = DateTime.now();
          _isAppOpenAdLoading = false;
          if (kDebugMode) print('✅ AppOpenAd Loaded Successfully');
        },
        onAdFailedToLoad: (error) {
          _isAppOpenAdLoading = false;
          _appOpenAd = null;
          if (kDebugMode) print('❌ AppOpenAd Failed to Load: $error');
        },
      ),
    );
  }

  static bool get isAppOpenAdAvailable {
    if (_appOpenAd == null || _appOpenLoadTime == null) return false;
    // صلاحية الإعلان 4 ساعات
    return DateTime.now().difference(_appOpenLoadTime!).inHours < 4;
  }

  static void showAppOpenAd() {
    if (_isAdmin || _isShowingAppOpenAd) return;

    if (!isAppOpenAdAvailable) {
      loadAppOpenAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAppOpenAd = true;
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        _isShowingAppOpenAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadAppOpenAd();
      },
      onAdDismissedFullScreenContent: (ad) {
        _isShowingAppOpenAd = false;
        ad.dispose();
        _appOpenAd = null;
        loadAppOpenAd(); // تحميل الإعلان التالي
      },
    );

    _appOpenAd!.show();
  }

  // ======================================================================

  static void showSmartAd() {
    _clickCounter++;
    if (_clickCounter >= _adThreshold) {
      if (_interstitialAd != null) {
        _interstitialAd!.show();
        _interstitialAd = null;
        _clickCounter = 0;
        loadAdMobInterstitial();
      } else {
        _clickCounter = 0;
        loadAdMobInterstitial();
      }
    }
  }

  static void loadAdMobInterstitial() {
    if (_isAdmin) return;
    InterstitialAd.load(
      adUnitId: adMobInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) => _interstitialAd = null,
      ),
    );
  }

  static void showUnityVideo({required VoidCallback onReward, VoidCallback? onFailed}) {
    if (_isAdmin) { onReward(); return; }
    if (!_isUnityReady) { onFailed?.call(); return; }
    markUserAsWatching();
    UnityAds.showVideoAd(
      placementId: 'Rewarded_Android',
      onComplete: (id) => onReward(),
      onFailed: (id, error, msg) => onFailed?.call(),
    );
  }

  static void showAdMobVideo({required Function onReward, required Function onFailed}) {
    if (_isAdmin) { onReward(); return; }
    RewardedAd.load(
      adUnitId: adMobRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          markUserAsWatching();
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) => ad.dispose(),
            onAdFailedToShowFullScreenContent: (ad, error) => ad.dispose(),
          );
          ad.show(onUserEarnedReward: (ad, reward) => onReward());
        },
        onAdFailedToLoad: (err) => onFailed(),
      ),
    );
  }

  static void loadUnityAd(String placementId) {
    if (_isAdmin) return;
    UnityAds.load(
      placementId: placementId,
      onComplete: (id) => debugPrint("✅ Unity Ad Loaded: $id"),
      onFailed: (id, error, msg) => debugPrint("❌ Unity Ad Failed: $msg"),
    );
  }

  static Widget smartBanner(BannerAd? adMobBanner, {bool forceAdMob = false}) {
    if (_isAdmin) return const SizedBox.shrink();
    if (adMobBanner != null) {
      return SizedBox(height: 50, child: AdWidget(ad: adMobBanner));
    }
    if (forceAdMob) return const SizedBox.shrink();
    if (_isUnityReady) return UnityBannerAd(placementId: 'Banner_Android');
    return const SizedBox.shrink();
  }
}