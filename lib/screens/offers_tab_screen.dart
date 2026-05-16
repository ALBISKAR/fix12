import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

// ======================================================================
// 1. التبويب الرئيسي للعروض (الذي يتم استدعاؤه في الـ HomeScreen)
// ======================================================================
class OffersTabScreen extends StatefulWidget {
  final bool hasRated;
  const OffersTabScreen({super.key, required this.hasRated});

  @override
  State<OffersTabScreen> createState() => _OffersTabScreenState();
}

class _OffersTabScreenState extends State<OffersTabScreen> {
  void _showFakeVerificationDialog() {
    int countdown = 60;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (countdown > 0) {
                if (mounted) setDialogState(() => countdown--);
              } else {
                t.cancel();
                // 🛠️ التعديل الأول: نمرر الـ Navigator الخاص بـ ctx مباشرة بدلاً من الـ BuildContext نفسه
                final navigator = Navigator.of(ctx);
                _finalizeRatingPoints(navigator);
              }
            });

            return PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Colors.amber, width: 1),
                ),
                title: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded, color: Colors.amber),
                    const SizedBox(width: 10),
                    Text(tr('verifying'), style: const TextStyle(color: Colors.white, fontSize: 18)),
                  ],
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.amber),
                    const SizedBox(height: 25),
                    Text(tr('verifying_desc'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
                    const SizedBox(height: 15),
                    InkWell(
                      onTap: () async {
                        const String url = "https://play.google.com/store/apps/details?id=com.mohamad.syria_earn";
                        final Uri uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          tr('click_here_to_rate'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text("00:${countdown.toString().padLeft(2, '0')}", style: const TextStyle(color: Colors.amber, fontSize: 40, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                    const SizedBox(height: 15),
                    Text(tr('verifying_points_hint'), style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) => timer?.cancel());
  }

  // 🛠️ التعديل الثاني: نستقبل NavigatorState كـ Object مستقل، والـ Messenger يتم حفظه مسبقاً لحل مشكلة الـ Async Gap نهائياً
  void _finalizeRatingPoints(NavigatorState dialogNavigator) async {
    String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) return;

    // نقوم بحفظ الـ Messenger مسبقاً قبل عملية الـ await المتزامنة لكي لا نستخدم الـ BuildContext بعدها
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'has_rated_app': true,
        'points': FieldValue.increment(25),
        'points_history': FieldValue.arrayUnion([
          {
            'type': 'rate_app_bonus',
            'amount': 25,
            'timestamp': DateTime.now(),
          }
        ])
      });

      // 🛡️ فحص الـ mounted للـ State الأصلي لحماية المعالجة البرمجية
      if (!mounted) return;
      
      // إغلاق الدايلوج باستخدام كائن الـ Navigator المحفوظ مسبقاً وبأمان تام
      dialogNavigator.pop();

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text("${tr('success_rate')} 25 ${tr('points')}"),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      dialogNavigator.pop();
      
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(tr('error_occurred')), 
          backgroundColor: Colors.red.shade700, 
          behavior: SnackBarBehavior.floating
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          _buildTaskCard(
            tr('earn_points_offers'),
            tr('offers_wall_sub'),
            999,
            Icons.local_fire_department_rounded,
            () {
              // 🛡️ حماية الـ BuildContext قبل الانتقال المباشر للـ WebView
              if (!mounted) return;
              
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const OffersWallWidget()),
              );
            },
            isPremium: true,
          ),
          const SizedBox(height: 12),
          _buildTaskCard(
            widget.hasRated ? tr('rated_thanks') : tr('rate_app_title'),
            widget.hasRated ? "" : tr('rate_app_sub'),
            25,
            Icons.stars_rounded,
            widget.hasRated
                ? () {}
                : () async {
                    const String url = "https://play.google.com/store/apps/details?id=com.mohamad.syria_earn";
                    final Uri uri = Uri.parse(url);
                    
                    // حفظ الـ ScaffoldMessenger مسبقاً لحماية الـ catch block
                    final scaffoldMessenger = ScaffoldMessenger.of(context);
                    
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                        
                        // 🛡️ فحص كائن الـ State الحالي للتأكد من بقاء الشاشة حية
                        if (!mounted) return;
                        _showFakeVerificationDialog();
                      }
                    } catch (e) {
                      if (!mounted) return;
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(tr('error_occurred')), 
                          backgroundColor: Colors.red.shade700, 
                          behavior: SnackBarBehavior.floating
                        )
                      );
                    }
                  },
            isPremium: !widget.hasRated,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(String title, String sub, int pts, IconData icon, VoidCallback action, {bool isPremium = false}) {
    return Card(
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: isPremium ? Colors.amber.withValues(alpha: 0.5) : Colors.white10),
      ),
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: ShaderMask(
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: isPremium ? [Colors.amber, Colors.orangeAccent, Colors.yellowAccent] : [Colors.blueAccent, Colors.cyanAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Icon(icon, color: Colors.white, size: 38),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 0.5)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.3)),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
          ),
          child: Text("+$pts", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 17)),
        ),
        onTap: action,
      ),
    );
  }
}

// ======================================================================
// 2. شاشة واجهة الـ WebView المدمجة (CPALead Webview)
// ======================================================================
class OffersWallWidget extends StatefulWidget {
  const OffersWallWidget({super.key});

  @override
  State<OffersWallWidget> createState() => _OffersWallWidgetState();
}

class _OffersWallWidgetState extends State<OffersWallWidget> {
  InAppWebViewController? webViewController;
  bool _isLoading = true;

  String get currentLocale => context.locale.languageCode;

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "guest";
    final String offerwallUrl = "https://qckclk.com/list/NOUA?subid=$uid&lang=$currentLocale";

    return Scaffold(
      appBar: AppBar(
        title: const Text("Syria Earn - Offers", style: TextStyle(color: Colors.amber)),
        backgroundColor: const Color(0xFF1A1A2E),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.amber),
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
              await InAppWebViewController.clearAllCache();
            },
            shouldOverrideUrlLoading: (controller, navigationAction) async {
              var uri = navigationAction.request.url!;

              if (!["http", "https", "file", "chrome", "data", "javascript"].contains(uri.scheme)) {
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  return NavigationActionPolicy.CANCEL;
                }
              }

              if (uri.toString().contains("play.google.com") || uri.toString().contains("market://")) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
                return NavigationActionPolicy.CANCEL;
              }

              return NavigationActionPolicy.ALLOW;
            },
            onReceivedError: (controller, request, error) {
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