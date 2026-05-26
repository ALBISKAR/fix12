import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:startapp_sdk/startapp.dart';

class GlobalBottomAd extends StatefulWidget {
  const GlobalBottomAd({super.key});

  @override
  State<GlobalBottomAd> createState() => _GlobalBottomAdState();
}

class _GlobalBottomAdState extends State<GlobalBottomAd> {
  BannerAd? _adMobBanner;
  bool _isAdMobLoaded = false;
  StartAppBannerAd? _startAppBanner;
  bool _isStartAppLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAdMobBanner();
    _loadStartAppBanner();
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

  void _loadStartAppBanner() {
    // ✅ التأكد من تفعيل الإعلانات التجريبية للبانر تحديداً قبل طلبه 
    StartAppSdk().setTestAdsEnabled(false); // تأكد من تعطيل الإعلانات التجريبية للبانر في الإنتاج

    StartAppSdk().loadBannerAd(StartAppBannerType.BANNER).then((ad) {
      if (mounted) {
        setState(() {
          _startAppBanner = ad;
          _isStartAppLoaded = true;
        });
      }
    }).catchError((error) {
      debugPrint("❌ StartApp Banner Failed: $error");
      // ✅ ميزة إعادة المحاولة التلقائية: إذا فشل التحميل أو حدث Timeout، ننتظر 30 ثانية ونحاول مجدداً
      Future.delayed(const Duration(seconds: 30), () {
        // نتأكد أن الشاشة لا تزال مفتوحة، وأن البانر لم يتم تحميله بعد
        if (mounted && !_isStartAppLoaded) {
          _loadStartAppBanner();
        }
      });
    });
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
          if (_isStartAppLoaded && _startAppBanner != null)
            SizedBox(
              height: 50,
              width: double.infinity,
              child: StartAppBanner(_startAppBanner!),
            ),

          // 🛑 فاصل بسيط لحماية الحساب من مخالفات النقرات غير المقصودة
          if (_isStartAppLoaded && _isAdMobLoaded)
            const SizedBox(height: 8), 

          if (_isAdMobLoaded && _adMobBanner != null)
            SizedBox(
              height: 50,
              width: double.infinity,
              child: AdWidget(ad: _adMobBanner!),
            ),
        ],
      ),
    );
  }
}