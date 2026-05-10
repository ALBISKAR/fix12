import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:unity_ads_plugin/unity_ads_plugin.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
//import 'package:flutter_tapjoy/flutter_tapjoy.dart';

class AdManager {
  static const String unityGameId = '6070088';
  static const String adMobBannerId = 'ca-app-pub-3359289133347380/2505476154';
  static const String adMobRewardedId =
      'ca-app-pub-3359289133347380/7487583368';
  static const String appOpenAdId = 'ca-app-pub-3359289133347380/3645365681';
  static const String adMobInterstitialId =
      'ca-app-pub-3359289133347380/1879660708';

  static InterstitialAd? _interstitialAd;
  static AppOpenAd? _appOpenAd;
  static bool _isAppOpenAdLoading = false;
  static bool _isUnityReady = false;
  static int _clickCounter = 0;
  static const int _adThreshold = 5;
  static DateTime? _appOpenLoadTime;

  static bool get _isAdmin =>
      FirebaseAuth.instance.currentUser?.uid == 'OeEwi4nMZrPjRLRiqWf1373btQT2';

  // 🛡️ قفل الحساب لمدة ساعة
  static Future<void> markUserAsWatching() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _isAdmin) return;
    try {
      final lockUntil = DateTime.now().add(const Duration(hours: 1));
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'login_lock_until': lockUntil,
      });
      debugPrint('🛡️ Login locked until $lockUntil');
    } catch (e) {
      debugPrint('❌ Lock Error: $e');
    }
  }

  static void initialize() {
    if (_isAdmin) return;
    MobileAds.instance.initialize();
    loadAppOpenAd();
    loadAdMobInterstitial();
    if (_isUnityReady) return;
    UnityAds.init(
      gameId: unityGameId,
      testMode: false,
      onComplete: () {
        _isUnityReady = true;
        loadUnityAd('Rewarded_Android');
      },
    );
  }

  static void showSmartAd() {
    _clickCounter++; // زيادة العداد مع كل استدعاء

    debugPrint(
        "Ad Click Counter: $_clickCounter"); // لمراقبة العداد في الـ Console

    if (_clickCounter >= _adThreshold) {
      if (_interstitialAd != null) {
        _interstitialAd!.show();
        _interstitialAd = null; // تفريغ الإعلان بعد العرض
        _clickCounter = 0; // إعادة تصفير العداد
        showAdMobInterstitial(); // تحميل إعلان جديد للمرة القادمة
      } else {
        // إذا وصل لـ 7 نقرات والإعلان ليس جاهزاً بعد
        _clickCounter = 0;
        showAdMobInterstitial();
      }
    }
  }

  static void showAdMobInterstitial() {
    if (_isAdmin || _interstitialAd == null) {
      loadAdMobInterstitial();
      return;
    }
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _interstitialAd = null;
        loadAdMobInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _interstitialAd = null;
        loadAdMobInterstitial();
      },
    );
    _interstitialAd!.show();
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

  static void showUnityVideo(
      {required VoidCallback onReward, VoidCallback? onFailed}) {
    if (_isAdmin) {
      onReward();
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

  static void showAdMobVideo(
      {required Function onReward, required Function onFailed}) {
    if (_isAdmin) {
      onReward();
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

// ✅ دالة الاتصال بـ Tapjoy باستخدام الكود المصدري الخاص بك
  static void connectTapjoy() {
    // اترك الدالة فارغة حالياً لإيقاف الاتصال بالسيرفرات تماماً
    // Tapjoy.connect(apiKey, ...);
    debugPrint("Tapjoy is temporarily disabled for this update.");
  }

  static Future<void> showTapjoyOfferwall() async {}

  static void loadAppOpenAd() {
    // منع التحميل إذا كان أدمن، أو قيد التحميل، أو الإعلان موجود وصالح
    if (_isAdmin || _isAppOpenAdLoading || isAppOpenAdAvailable) return;

    _isAppOpenAdLoading = true;
    AppOpenAd.load(
      adUnitId: appOpenAdId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _appOpenLoadTime = DateTime.now(); // تسجيل وقت التحميل
          _isAppOpenAdLoading = false;
          debugPrint('✅ AppOpenAd Loaded');
        },
        onAdFailedToLoad: (error) {
          _isAppOpenAdLoading = false;
          _appOpenAd = null;
          debugPrint('❌ AppOpenAd Failed to Load: $error');
        },
      ),
    );
  }

// دالة فحص صلاحية الإعلان (إعلانات الفتح صالحة لـ 4 ساعات فقط)
  static bool get isAppOpenAdAvailable {
    if (_appOpenAd == null || _appOpenLoadTime == null) return false;
    return DateTime.now().difference(_appOpenLoadTime!).inHours < 4;
  }

  static void showAppOpenAd() {
    // إذا لم يكن الإعلان متاحاً، ابدأ بالتحميل وخرج
    if (_isAdmin || !isAppOpenAdAvailable) {
      debugPrint('⚠️ AppOpenAd not available, loading...');
      loadAppOpenAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        debugPrint('📱 AppOpenAd showing');
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('❌ AppOpenAd failed to show: $error');
        ad.dispose();
        _appOpenAd = null;
        loadAppOpenAd();
      },
      onAdDismissedFullScreenContent: (ad) {
        debugPrint('✅ AppOpenAd dismissed');
        ad.dispose();
        _appOpenAd = null;
        loadAppOpenAd(); // تحميل الإعلان القادم فوراً
      },
    );

    _appOpenAd!.show();
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
