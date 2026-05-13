import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdManager {
  static const String unityGameId = '6070088';
  static const String adMobBannerId = 'ca-app-pub-3359289133347380/2505476154';
  static const String adMobRewardedId = 'ca-app-pub-3359289133347380/7487583368';
  static const String appOpenAdId = 'ca-app-pub-3359289133347380/3645365681';
  static const String adMobInterstitialId = 'ca-app-pub-3359289133347380/1879660708';

  static InterstitialAd? _interstitialAd;
  static AppOpenAd? _appOpenAd;
  static bool _isAppOpenAdLoading = false;
  static bool _isShowingAppOpenAd = false;
  static bool _isUnityReady = false;
  static int _clickCounter = 0;
  static const int _adThreshold = 5;
  static DateTime? _appOpenLoadTime;

  // التحقق من الأدمن (UID الحالي الخاص بك)
  static bool get _isAdmin =>
      FirebaseAuth.instance.currentUser?.uid == 'OeEwi4nMZrPjRLRiqWf1373btQT2';

  static void initialize() {
    if (_isAdmin) {
      debugPrint("🚀 Admin Detected: Ads Initialization Skipped.");
      return;
    }
    MobileAds.instance.initialize();
    loadAppOpenAd();
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
    // استثناء الأدمن من التحميل
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
        },
        onAdFailedToLoad: (error) {
          _isAppOpenAdLoading = false;
          _appOpenAd = null;
        },
      ),
    );
  }

  static bool get isAppOpenAdAvailable {
    if (_appOpenAd == null || _appOpenLoadTime == null) return false;
    return DateTime.now().difference(_appOpenLoadTime!).inHours < 4;
  }

  static void showAppOpenAd() {
    // استثناء الأدمن من العرض
    if (_isAdmin || _isShowingAppOpenAd) return;

    if (!isAppOpenAdAvailable) {
      loadAppOpenAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) => _isShowingAppOpenAd = true,
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
        loadAppOpenAd();
      },
    );
    _appOpenAd!.show();
  }

  // ==================== الإعلانات البينية (Smart Ad) ====================

  static void showSmartAd() {
    if (_isAdmin) return; // استثناء الأدمن

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
    if (_isAdmin) return; // لا تحمل الإعلان للأدمن
    InterstitialAd.load(
      adUnitId: adMobInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) => _interstitialAd = null,
      ),
    );
  }

  // ==================== إعلانات المكافأة ====================

  static void showUnityVideo({required VoidCallback onReward, VoidCallback? onFailed}) {
    if (_isAdmin) {
      debugPrint("🎯 Admin Reward: Instant Access Granted.");
      onReward(); // منح الجائزة للأدمن فوراً بدون إعلان
      return;
    }
    if (!_isUnityReady) {
      onFailed?.call();
      return;
    }
    markUserAsWatching();
    UnityAds.showVideoAd(
      placementId: 'Rewarded_Android',
      onComplete: (id) => onReward(),
      onFailed: (id, error, msg) => onFailed?.call(),
    );
  }

  static void showAdMobVideo({required Function onReward, required Function onFailed}) {
    if (_isAdmin) {
      onReward(); // منح الجائزة للأدمن فوراً
      return;
    }
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

  // ==================== البانر (Banner) ====================

  static Widget smartBanner(BannerAd? adMobBanner, {bool forceAdMob = false}) {
    if (_isAdmin) return const SizedBox.shrink(); // الأدمن لا يرى البانر أبداً
    
    if (adMobBanner != null) {
      return SizedBox(height: 50, child: AdWidget(ad: adMobBanner));
    }
    if (forceAdMob) return const SizedBox.shrink();
    if (_isUnityReady) return UnityBannerAd(placementId: 'Banner_Android');
    return const SizedBox.shrink();
  }

  static BannerAd createBannerAd() {
    // ملاحظة: بما أن هذه الدالة ترجع كائن BannerAd، يفضل استدعاؤها بشرط الأدمن في الواجهة (UI)
    return BannerAd(
      adUnitId: adMobBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => debugPrint("✅ Banner Ad Loaded"),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint("❌ Banner Ad Failed: ${error.message}");
        },
      ),
    )..load();
  }

  static Future<void> markUserAsWatching() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isAdmin) return;
    try {
      final lockUntil = DateTime.now().add(const Duration(hours: 1));
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({'login_lock_until': lockUntil});
    } catch (e) {
      debugPrint('❌ Lock Error: $e');
    }
  }
}