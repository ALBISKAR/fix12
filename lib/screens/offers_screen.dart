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
  // 1. استخدام late مع تعريف الـ Controller
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeController();
  }

  void _initializeController() {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    final String offerwallUrl = "https://qckclk.com/list/NOUA?subid=$uid";

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF1A1A2E))
      // --- إضافة إعدادات تحسين الذاكرة ---
      ..enableZoom(false) // تعطيل الزووم يوفر في معالجة الرسوميات
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
            // تنظيف الذاكرة المخبأة (Cache) بشكل دوري لتقليل استهلاك RAM
            _controller.clearCache();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint("WebView Error: ${error.description}");
          },
          // منع فتح النوافذ المنبثقة (Popups) التي تستهلك ذاكرة إضافية
          onNavigationRequest: (NavigationRequest request) {
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(
        Uri.parse(offerwallUrl),
        // إضافة Headers لإخبار الموقع بأننا في بيئة تطبيق لتقليل استهلاك الموارد
        headers: const {'Cache-Control': 'no-cache'},
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // جعل الـ AppBar متناسق مع ثيم تطبيقك المظلم
      appBar: AppBar(
        title: Text(
          tr('offers_wall_title'),
          style:
              const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1A1A2E),
        iconTheme: const IconThemeData(color: Colors.amber), // لون زر الرجوع
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        color: const Color(0xFF1A1A2E), // لضمان عدم ظهور بياض أثناء التحميل
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.amber),
                    SizedBox(height: 10),
                    // نص اختياري أثناء التحميل
                    Text("Loading Offers...",
                        style: TextStyle(color: Colors.amber, fontSize: 12)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 1. توجيه الويب فيو لصفحة فارغة قبل الإغلاق لتفريغ الذاكرة
    _controller.loadRequest(Uri.parse('about:blank'));

    // 2. استدعاء السوبر ديبوز
    super.dispose();
  }
}
