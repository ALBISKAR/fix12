import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class OffersWallScreen extends StatefulWidget {
  const OffersWallScreen({super.key});

  @override
  // تأكد أن الاسم هنا يطابق اسم الكلاس في الأسفل
  State<OffersWallScreen> createState() => _OffersWallScreenState();
}

// تم تصحيح الاسم هنا من _MyAppState إلى _OffersWallScreenState
class _OffersWallScreenState extends State<OffersWallScreen> {
  InAppWebViewController? webViewController;
  bool _isLoading = true;

  String get currentLocale => context.locale.languageCode;

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    final String offerwallUrl =
        "https://qckclk.com/list/NOUA?subid=$uid&lang=$currentLocale";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Syria Earn - Offers",
            style: TextStyle(color: Colors.amber)),
        backgroundColor: const Color(0xFF1A1A2E),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(offerwallUrl)),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              useShouldOverrideUrlLoading: true,
              useOnDownloadStart: true,
              allowFileAccessFromFileURLs: true,
              allowUniversalAccessFromFileURLs: true,
              cacheMode: CacheMode.LOAD_DEFAULT,
              mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              useHybridComposition: true,
              transparentBackground: true,
            ),
            onWebViewCreated: (controller) {
              webViewController = controller;
            },
            onLoadStart: (controller, url) {
              setState(() {
                _isLoading = true;
              });
            },
            onLoadStop: (controller, url) async {
              setState(() {
                _isLoading = false;
              });
              // تنظيف الذاكرة
              await InAppWebViewController.clearAllCache();
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              var uri = navigationAction.request.url!;

              if (!["http", "https", "file", "chrome", "data", "javascript"]
                  .contains(uri.scheme)) {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  return NavigationActionPolicy.CANCEL;
                }
              }

              if (uri.toString().contains("play.google.com") ||
                  uri.toString().contains("market://")) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW;
            },
            onReceivedError: (controller, request, error) {
              // الإسم الجديد للدالة ومعاملاتها
              setState(() {
                _isLoading = false;
              });
              debugPrint("WebView Error: ${error.description}");
            },
          ),
          if (_isLoading)
            Container(
              color: const Color(0xFF1A1A2E),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              ),
            ),
        ],
      ),
    );
  }
}
