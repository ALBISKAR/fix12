import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'; // المكتبة الجديدة
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class OffersWallScreen extends StatefulWidget {
  const OffersWallScreen({super.key});

  @override
  State<OffersWallScreen> createState() => _OffersWallScreenState();
}

class _OffersWallScreenState extends State<OffersWallScreen> {
  InAppWebViewController? webViewController;
  bool _isLoading = true;
  String get currentLocale => context.locale.languageCode;

// إعدادات احترافية متوافقة مع الإصدار الجديد لتقليل استهلاك الذاكرة
  final InAppWebViewSettings settings = InAppWebViewSettings(
    // تحسينات عامة للأداء
    javaScriptEnabled: true,
    useShouldOverrideUrlLoading: true, 
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: true,
    
    // إعدادات لتقليل الضغط على الرام (RAM)
    transparentBackground: true,
    supportZoom: false, // إيقاف الزووم يوفر الذاكرة
    
    // إعدادات أندرويد خاصة لزيادة الاستقرار
    useHybridComposition: true, // يقلل من مشاكل الـ Render في المحاكيات
    cacheMode: CacheMode.LOAD_DEFAULT, // إدارة ذكية للكاش
  );

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    final String offerwallUrl = "https://qckclk.com/list/NOUA?subid=$uid&lang=$currentLocale";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Syria Earn - Offers", style: TextStyle(color: Colors.amber)),
        backgroundColor: const Color(0xFF1A1A2E),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(offerwallUrl)),
            initialSettings: settings,
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
            onLoadStart: (controller, url) {
              setState(() => _isLoading = true);
            },
            onLoadStop: (controller, url) async {
              setState(() => _isLoading = false);
              // تنظيف الذاكرة المخبأة فور الانتهاء
              await InAppWebViewController.clearAllCache();
            },
            // الحل النهائي لفتح متجر بلاي والروابط الخارجية دون انهيار
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              var uri = navigationAction.request.url!;
              if (!["http", "https", "file", "chrome", "data", "javascript"].contains(uri.scheme)) {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  return NavigationActionPolicy.CANCEL;
                }
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: Colors.amber)),
        ],
      ),
    );
  }
}