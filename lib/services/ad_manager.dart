import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:startapp_sdk/startapp.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdManager {
  // معرفات الإعلانات
  static const String adMobBannerId = 'ca-app-pub-3359289133347380/2505476154';
  static const String adMobRewardedId =
      'ca-app-pub-3359289133347380/7487583368';
  static const String appOpenAdId = 'ca-app-pub-3359289133347380/3645365681';
  static const String adMobInterstitialId =
      'ca-app-pub-3359289133347380/1879660708';

  // كائنات التحكم
  static InterstitialAd? _interstitialAd;
  static RewardedAd? _rewardedAd;
  static AppOpenAd? _appOpenAd;
  static BannerAd? _adMobBannerAd; // ✅ تم إضافة كاش للبانر لحل مشكلة التكرار

  static bool _isAppOpenAdLoading = false;
  static bool _isShowingAppOpenAd = false;
  static bool _isRewardedAdLoading = false;
  static int _clickCounter = 0;
  static const int _adThreshold = 5;

  // Start.io
  static final StartAppSdk _startAppSdk = StartAppSdk();
  static StartAppRewardedVideoAd? _startAppRewardedVideoAd;
  static StartAppInterstitialAd? _startAppInterstitialAd;
  static StartAppBannerAd? _startAppBannerAd;

  static bool _isStartAppVideoLoading = false;
  static bool _isStartAppInterstitialLoading = false;
  static bool _isStartAppBannerLoading = false;
  static bool _isShowingAd = false;

  static VoidCallback? onAdClosedCallback;

  static bool get isAdmin =>
      FirebaseAuth.instance.currentUser?.uid == 'OeEwi4nMZrPjRLRiqWf1373btQT2';

  static void initialize() {
    if (isAdmin) return;
    MobileAds.instance.initialize();
    loadAppOpenAd();
    loadAdMobInterstitial();
    _startAppSdk.setTestAdsEnabled(false);
    loadServer1Ad();
    loadStartAppInterstitial();
    loadStartAppBanner();
  }

  // ==================== سيرفر 1 (Start.io) ====================

  static void loadServer1Ad() {
    // 1. حماية: إذا كان التحميل جارياً أو الإعلان موجوداً، لا تفعل شيئاً
    if (isAdmin ||
        _isStartAppVideoLoading ||
        _startAppRewardedVideoAd != null) {
      return;
    }
    _isStartAppVideoLoading = true;

    _startAppSdk
        .loadRewardedVideoAd(
      onAdNotDisplayed: () => _clearAndReloadServer1(),
      onAdHidden: () {
        debugPrint("🔔 إغلاق إعلان سيرفر 1: جاري تنفيذ الكولباك...");

        // 2. إطلاق الكولباك بأمان داخل try-catch
        try {
          if (onAdClosedCallback != null) {
            onAdClosedCallback!();
            // 3. هام جداً: تصفير الكولباك لمنع إعادة النداء بشكل خاطئ
            onAdClosedCallback = null;
          }
        } catch (e) {
          debugPrint("❌ خطأ في تنفيذ الكولباك: $e");
        }

        // 4. تأجيل عملية التنظيف لضمان أن الواجهة قد تعاملت مع الكولباك أولاً
        Future.delayed(const Duration(milliseconds: 500), () {
          _clearAndReloadServer1();
        });
      },
      onVideoCompleted: () async {
        debugPrint("👑 الفيديو اكتمل، جاري تحديث النقاط...");
        try {
          final config = await FirebaseFirestore.instance
              .collection('app_settings')
              .doc('config')
              .get();

          if (config.exists) {
            _assignPointsToFirestore(
                config.data()?['video_cooldown_seconds'] ?? 300,
                config.data()?['unity_points'] ?? 10);
          }
        } catch (e) {
          debugPrint("❌ Firebase Error: $e");
        }
      },
    )
        .then((ad) {
      _startAppRewardedVideoAd = ad;
      _isStartAppVideoLoading = false;
      debugPrint("✅ سيرفر 1 جاهز");
    }).catchError((error) {
      _isStartAppVideoLoading = false;
      _startAppRewardedVideoAd = null;
      debugPrint("❌ فشل تحميل الإعلان: $error");
    });
  }

  static void showServer1Ad(BuildContext context) {
    if (_startAppRewardedVideoAd != null) {
      try {
        _startAppRewardedVideoAd!.show();
      } catch (e) {
        _clearAndReloadServer1();
      }
    } else {
      loadServer1Ad();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('connecting_server_1')),
          behavior: SnackBarBehavior.floating));
    }
  }

  static void _clearAndReloadServer1() {
    try {
      _startAppRewardedVideoAd?.dispose();
    } catch (_) {}
    _startAppRewardedVideoAd = null;
    _isStartAppVideoLoading = false;
    Future.delayed(const Duration(seconds: 3), () => loadServer1Ad());
  }

  // ==================== AdMob Interstitial & Rewarded ====================

  static void loadAdMobInterstitial() {
    if (isAdmin) return;
    _interstitialAd?.dispose(); // ✅ تخلص من القديم قبل التحميل
    InterstitialAd.load(
      adUnitId: adMobInterstitialId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitialAd = ad,
        onAdFailedToLoad: (error) => _interstitialAd = null,
      ),
    );
  }

// في ملف AdManager.dart
  static void showAdMobVideo({
    required Function onReward,
    required Function onFailed,
    Function? onAdClosed, // أضفنا هذا المعامل
  }) {
    if (_isRewardedAdLoading || isAdmin) return;
    _rewardedAd?.dispose();
    _isRewardedAdLoading = true;

    RewardedAd.load(
      adUnitId: adMobRewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _isRewardedAdLoading = false;
          _rewardedAd = ad;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _rewardedAd = null;

              // تأخير التنفيذ قليلاً لضمان استقرار الواجهة
              Future.delayed(const Duration(milliseconds: 500), () {
                if (onAdClosed != null) {
                  onAdClosed();
                }
              });
            },
            onAdFailedToShowFullScreenContent: (ad, error) {
              ad.dispose();
              _rewardedAd = null;
              onFailed();
            },
          );

          try {
            ad.show(onUserEarnedReward: (ad, reward) => onReward());
          } catch (e) {
            _isRewardedAdLoading = false;
            onFailed();
          }
        },
        onAdFailedToLoad: (err) {
          _isRewardedAdLoading = false;
          onFailed();
        },
      ),
    );
  }
  // ==================== البانر الذكي الهجين ====================

  static Widget smartBanner(BannerAd? loginBanner) {
    if (isAdmin) return const SizedBox.shrink();

    // إذا كان بانر AdMob جاهزاً
    if (_adMobBannerAd != null) {
      return SizedBox(height: 50, child: AdWidget(ad: _adMobBannerAd!));
    }

    // إذا كان بانر StartApp جاهزاً
    if (_startAppBannerAd != null) {
      return SizedBox(height: 50, child: StartAppBanner(_startAppBannerAd!));
    }

    return const SizedBox.shrink();
  }

  // ✅ إصلاح جذري: تحميل البانر مرة واحدة فقط وتخزينه
  static void loadAdMobBanner() {
    if (_adMobBannerAd != null) return;
    _adMobBannerAd = BannerAd(
      adUnitId: adMobBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _adMobBannerAd = null;
        },
      ),
    )..load();
  }

  static void loadStartAppBanner() {
    if (isAdmin || _isStartAppBannerLoading || _startAppBannerAd != null) {
      return;
    }
    _isStartAppBannerLoading = true;
    _startAppSdk.loadBannerAd(StartAppBannerType.BANNER).then((ad) {
      _startAppBannerAd = ad;
      _isStartAppBannerLoading = false;
    }).catchError((_) {
      _isStartAppBannerLoading = false;
    });
  }

  // ==================== إعلانات بينية ذكية ====================

  static void showSmartAd() {
    if (isAdmin || _isShowingAd) return;
    _clickCounter++;
    if (_clickCounter >= _adThreshold) {
      if (_interstitialAd != null || _startAppInterstitialAd != null) {
        _clickCounter = 0;
        if (_interstitialAd != null) {
          _isShowingAd = true;
          _interstitialAd!.fullScreenContentCallback =
              FullScreenContentCallback(
            onAdDismissedFullScreenContent: (ad) {
              ad.dispose();
              _isShowingAd = false;
              loadAdMobInterstitial();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _isShowingAd = false;
              loadAdMobInterstitial();
            },
          );
          _interstitialAd!.show();
          _interstitialAd = null;
        } else if (_startAppInterstitialAd != null) {
          _isShowingAd = true;
          _startAppInterstitialAd!.show().then((_) {
            _isShowingAd = false;
            _startAppInterstitialAd = null;
            loadStartAppInterstitial();
          });
        }
      } else {
        loadAdMobInterstitial();
        loadStartAppInterstitial();
      }
    }
  }

  static void loadStartAppInterstitial() {
    if (isAdmin ||
        _isStartAppInterstitialLoading ||
        _startAppInterstitialAd != null) {
      return;
    }
    _isStartAppInterstitialLoading = true;
    _startAppSdk.loadInterstitialAd().then((ad) {
      _startAppInterstitialAd = ad;
      _isStartAppInterstitialLoading = false;
    }).catchError((_) {
      _isStartAppInterstitialLoading = false;
      _startAppInterstitialAd = null;
    });
  }

  // ==================== App Open Ad ====================

  static void loadAppOpenAd() {
    if (isAdmin || _isAppOpenAdLoading || _appOpenAd != null) return;
    _isAppOpenAdLoading = true;
    AppOpenAd.load(
      adUnitId: appOpenAdId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpenAd = ad;
          _isAppOpenAdLoading = false;
        },
        onAdFailedToLoad: (_) {
          _isAppOpenAdLoading = false;
          _appOpenAd = null;
        },
      ),
    );
  }

  static void showAppOpenAdOnce() {
    if (isAdmin || _isShowingAppOpenAd || _appOpenAd == null) return;
    _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => _isShowingAppOpenAd = true,
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _appOpenAd = null;
        _isShowingAppOpenAd = false;
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _appOpenAd = null;
        _isShowingAppOpenAd = false;
      },
    );
    _appOpenAd!.show();
  }

  // ==================== Firestore Points ====================

  static Future<void> _assignPointsToFirestore(
      int cooldownSeconds, int unityPoints) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || isAdmin) return;

    final batch = FirebaseFirestore.instance.batch();
    batch.update(
        FirebaseFirestore.instance.collection('users').doc(currentUser.uid), {
      'points': FieldValue.increment(unityPoints),
      'unity_cooldown_until': Timestamp.fromDate(
          DateTime.now().add(Duration(seconds: cooldownSeconds))),
    });
    batch.set(FirebaseFirestore.instance.collection('completed_tasks').doc(), {
      'userId': currentUser.uid,
      'taskType': 'server1_ad',
      'rewardAmount': unityPoints,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    _clearAndReloadServer1();
  }

  // ✅ دالة البوابة: هل يمكن للمستخدم الدخول لدولاب الحظ؟
  static bool canAccessLuckyWheel() {
    if (isAdmin) return true; // الأدمن دائماً مسموح له

    // هنا يمكنك إضافة شروط إضافية للمستخدمين العاديين
    // مثل: التحقق من الوقت أو النقاط أو وجود تذكرة
    return true;
  }
}
