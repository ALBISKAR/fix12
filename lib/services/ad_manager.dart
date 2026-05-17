import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:startapp_sdk/startapp.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdManager {
  // معرفات إعلانات أدموب (AdMob)
  static const String adMobBannerId = 'ca-app-pub-3359289133347380/2505476154';
  static const String adMobRewardedId = 'ca-app-pub-3359289133347380/7487583368';
  static const String appOpenAdId = 'ca-app-pub-3359289133347380/3645365681';
  static const String adMobInterstitialId = 'ca-app-pub-3359289133347380/1879660708';

  // كائنات التحكم (Admob)
  static InterstitialAd? _interstitialAd;
  static AppOpenAd? _appOpenAd;
  static bool _isAppOpenAdLoading = false;
  static bool _isShowingAppOpenAd = false;
  static int _clickCounter = 0;
  static const int _adThreshold = 5;
  static DateTime? _appOpenLoadTime;

  // كائنات التحكم الخاصة بـ Start.io (سيرفر 1 والبانر والبيني)
  static final StartAppSdk _startAppSdk = StartAppSdk();
  static StartAppRewardedVideoAd? _startAppRewardedVideoAd;
  static StartAppInterstitialAd? _startAppInterstitialAd;
  static StartAppBannerAd? _startAppBannerAd;
  static bool _isStartAppVideoLoading = false;
  static bool _isStartAppInterstitialLoading = false;
  static bool _isStartAppBannerLoading = false;

  // كولباك الإغلاق المباشر لتحديث واجهة العداد التنازلي في الـ HomeScreen
  static VoidCallback? onAdClosedCallback;

  // مفاتيح الأمن لقطع تداخل الإعلانات وحماية الحسابات
  static bool isShowingInterstitial = false;
  static bool _hasAppOpenAdShownToday = false; 

  // التحقق من الأدمن (UID الحالي الخاص بك)
  static bool get _isAdmin =>
      FirebaseAuth.instance.currentUser?.uid == 'OeEwi4nMZrPjRLRiqWf1373btQT2';

  /// ⚙️ تهيئة المحركات الشاملة لشبكات الإعلانات (بدون يونيتي)
  static void initialize() {
    if (_isAdmin) {
      debugPrint("🚀 Admin Detected: Ads Initialization Skipped.");
      return;
    }
    MobileAds.instance.initialize();
    loadAppOpenAd();
    loadAdMobInterstitial();
    
    // تهيئة وتجهيز إعلانات Start.io (سيرفر 1)
    _startAppSdk.setTestAdsEnabled(false); // اجعلها false للإعلانات الحقيقية
    loadServer1Ad();
    loadStartAppInterstitial();
    loadStartAppBanner();
  }

  // ==================== 📺 إعلانات المكافأة لـ سيرفر 1 (Start.io) ====================

  static void loadServer1Ad() {
    if (_isAdmin || _isStartAppVideoLoading || _startAppRewardedVideoAd != null) return;
    _isStartAppVideoLoading = true;

    _startAppSdk.loadRewardedVideoAd(
      onAdNotDisplayed: () {
        debugPrint("⚠️ لم يتم عرض إعلان سيرفر 1 بنجاح");
        _clearAndReloadServer1();
      },
      onAdHidden: () {
        debugPrint("🔔 قام المستخدم بإغلاق إعلان سيرفر 1");
        if (onAdClosedCallback != null) {
          onAdClosedCallback!();
        }
        _clearAndReloadServer1();
      },
      onVideoCompleted: () async {
        debugPrint("👑 اكتمل الفيديو! جاري جلب الإعدادات السحابية...");
        final config = await FirebaseFirestore.instance.collection('app_settings').doc('config').get();
        int serverCooldown = config.data()?['video_cooldown_seconds'] ?? 300;
        int serverPoints = config.data()?['unity_points'] ?? 10;
        
        _assignPointsToFirestore(serverCooldown, serverPoints);
      },
    ).then((ad) {
      _startAppRewardedVideoAd = ad;
      _isStartAppVideoLoading = false;
      debugPrint("✅ سيرفر 1 (Start.io) جاهز تماماً لبث الفيديو");
    }).catchError((error) {
      _isStartAppVideoLoading = false;
      _startAppRewardedVideoAd = null;
      debugPrint("❌ فشل تحميل إعلان سيرفر 1: $error");
    });
  }

  static void showServer1Ad(BuildContext context) {
    if (_startAppRewardedVideoAd != null) {
      _startAppRewardedVideoAd!.show();
    } else {
      loadServer1Ad();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🔄 جاري الاتصال بسيرفر 1.. اضغط مجدداً بعد ثانيتين ⏳"),
          backgroundColor: Colors.blueGrey,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  static void _clearAndReloadServer1() {
    _startAppRewardedVideoAd?.dispose();
    _startAppRewardedVideoAd = null;
    _isStartAppVideoLoading = false;
    loadServer1Ad();
  }

  static Future<void> _assignPointsToFirestore(int cooldownSeconds, int unityPoints) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || _isAdmin) return;

    final userDocRef = FirebaseFirestore.instance.collection('users').doc(currentUser.uid);
    final taskDocRef = FirebaseFirestore.instance.collection('completed_tasks').doc();

    WriteBatch batch = FirebaseFirestore.instance.batch();
    DateTime cooldownEndTime = DateTime.now().add(Duration(seconds: cooldownSeconds));

    batch.update(userDocRef, {
      'points': FieldValue.increment(unityPoints), 
      'unity_cooldown_until': Timestamp.fromDate(cooldownEndTime), 
    });

    batch.set(taskDocRef, {
      'userId': currentUser.uid,
      'taskType': 'server1_ad',
      'rewardAmount': unityPoints, 
      'timestamp': FieldValue.serverTimestamp(),
    });

    await batch.commit();
    _clearAndReloadServer1();
  }

  // ✅ دالة تحميل بانر Start.io في الخلفية
  static void loadStartAppBanner() {
    if (_isAdmin || _isStartAppBannerLoading || _startAppBannerAd != null) return;
    _isStartAppBannerLoading = true;

    _startAppSdk.loadBannerAd(StartAppBannerType.BANNER).then((ad) {
      _startAppBannerAd = ad;
      _isStartAppBannerLoading = false;
      debugPrint("✅ Start.io Banner Ad Loaded Successfully");
    }).catchError((error) {
      _isStartAppBannerLoading = false;
      _startAppBannerAd = null;
      debugPrint("❌ Start.io Banner Load Failed: $error");
    });
  }

  // ==================== 📐 البانر الذكي الهجين (Smart Banner) ====================

  static Widget smartBanner(BannerAd? adMobBanner, {bool forceAdMob = false}) {
    if (_isAdmin) return const SizedBox.shrink(); 
    
    if (adMobBanner != null) {
      return SizedBox(height: 50, child: AdWidget(ad: adMobBanner));
    }
    if (forceAdMob) return const SizedBox.shrink();
    
    if (_startAppBannerAd != null) {
      return Container(
        width: double.infinity,
        height: 50,
        alignment: Alignment.center,
        child: StartAppBanner(_startAppBannerAd!),
      );
    }
    
    loadStartAppBanner();
    return const SizedBox.shrink();
  }

  // ==================== 🔔 إعلان فتح التطبيق (App Open AdMob) ====================

  static void loadAppOpenAd() {
    if (_isAdmin || _isAppOpenAdLoading || isAppOpenAdAvailable || _hasAppOpenAdShownToday) return;

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

  static void showAppOpenAdOnce() {
    if (_isAdmin || _isShowingAppOpenAd || isShowingInterstitial || _hasAppOpenAdShownToday) return;

    if (!isAppOpenAdAvailable) {
      loadAppOpenAd();
      return;
    }

    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        _isShowingAppOpenAd = true;
        _hasAppOpenAdShownToday = true; 
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
      },
    );
    _appOpenAd!.show();
  }

  // ==================== 💎 الإعلانات البينية الذكية (Smart Ad) ====================

  static void showSmartAd() {
    if (_isAdmin) return; 

    _clickCounter++;
    if (_clickCounter >= _adThreshold) {
      if (_interstitialAd != null) {
        _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
          onAdShowedFullScreenContent: (ad) => isShowingInterstitial = true,
          onAdDismissedFullScreenContent: (ad) {
            ad.dispose();
            isShowingInterstitial = false; 
            loadAdMobInterstitial();
          },
          onAdFailedToShowFullScreenContent: (ad, error) {
            ad.dispose();
            isShowingInterstitial = false;
            loadAdMobInterstitial();
          },
        );
        _interstitialAd!.show();
        _interstitialAd = null;
        _clickCounter = 0;
      } else if (_startAppInterstitialAd != null) {
        _startAppInterstitialAd!.show().then((_) {
          isShowingInterstitial = true;
          _startAppInterstitialAd = null;
          _clickCounter = 0;
          isShowingInterstitial = false;
          loadStartAppInterstitial();
        });
      } else {
        _clickCounter = 0;
        loadAdMobInterstitial();
        loadStartAppInterstitial();
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

  static void loadStartAppInterstitial() {
    if (_isAdmin || _isStartAppInterstitialLoading || _startAppInterstitialAd != null) return;
    _isStartAppInterstitialLoading = true;

    _startAppSdk.loadInterstitialAd().then((ad) {
      _startAppInterstitialAd = ad;
      _isStartAppInterstitialLoading = false;
    }).catchError((error) {
      _isStartAppInterstitialLoading = false;
      _startAppInterstitialAd = null;
    });
  }

  // ==================== 📺 إعلانات المكافأة لـ سيرفر 2 (AdMob) ====================

  static void showAdMobVideo({required Function onReward, required Function onFailed}) {
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

  static BannerAd createBannerAd() {
    return BannerAd(
      adUnitId: adMobBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => debugPrint("✅ Banner Ad Loaded"),
        onAdFailedToLoad: (ad, error) => ad.dispose(),
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