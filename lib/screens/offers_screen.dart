import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

class OffersWallScreen extends StatefulWidget {
  const OffersWallScreen({super.key});

  @override
  State<OffersWallScreen> createState() => _OffersWallScreenState();
}

class _OffersWallScreenState extends State<OffersWallScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    
    // 1. جلب معرف المستخدم لربطه بالعروض (subid)
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    
    // 2. تجهيز الرابط الخاص بك مع تمرير الـ UID
    final String offerwallUrl = "https://qckclk.com/list/NOUA?subid=$uid";

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1A1A2E)) // لون متناسق مع تطبيقك
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(offerwallUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('offers_wall_title')), // تأكد من إضافة المفتاح في ملف اللغة
        backgroundColor: const Color(0xFF1A1A2E),
        elevation: 0,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(color: Colors.amber),
            ),
        ],
      ),
    );
  }
}