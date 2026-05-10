import 'dart:async';
import 'package:provider/provider.dart';
import 'package:syria_earn_pro/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:syria_earn_pro/screens/history_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:syria_earn_pro/screens/withdraw_screen.dart';
import 'package:syria_earn_pro/screens/leaderboard_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:check_vpn_connection/check_vpn_connection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart'; // 👈 أضف هذا السطر في الأعلى
import 'package:package_info_plus/package_info_plus.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _secondsRemaining = 0;
  bool _isWaiting = false;
  int totalPoints = 0;
  bool _isAdProcessing = false;
  late TabController _tabController;
  late AnimationController _controller;
  late Animation<double> _animation;
  int _unitySecondsLeft = 0;
  int _admobSecondsLeft = 0;
  int unityRewardPoints = 10; // قيمة افتراضية
  int admobRewardPoints = 15; // قيمة افتراضية
  Timer? _unityTimer;
  Timer? _admobTimer;
  BannerAd? _adMobBanner;

  // 🔐 أضف هذه الدالة تحت المتغيرات في بداية الكلاس
  bool get isAdmin =>
      FirebaseAuth.instance.currentUser?.uid == 'OeEwi4nMZrPjRLRiqWf1373btQT2';

  StreamSubscription<DocumentSnapshot>? _banListener;

  void _navigateToHistory() {
    // عرض إعلان ذكي قبل الانتقال لزيادة الأرباح
    AdManager.showSmartAd();

    // الانتقال إلى شاشة السجل التي سننشئها
    Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => const HistoryScreen()),
    );
  }

  void _startBanListener() {
    String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) return;

    _banListener = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists) {
        var data = snapshot.data() as Map<String, dynamic>;
        bool isBanned = data['isBanned'] ?? false;

        if (isBanned) {
          // 1. إيقاف المراقب
          _banListener?.cancel();

          // 2. تسجيل الخروج من Firebase
          await FirebaseAuth.instance.signOut();

          if (!mounted) return;

          // 3. التوجيه لصفحة تسجيل الدخول مع رسالة توضيحية
          Navigator.pushNamedAndRemoveUntil(
              context, '/login', (route) => false);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('banned_msg')),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 10),
            ),
          );
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _startNetworkMonitoring();
    _startBanListener();
    _loadUserData();
    //WidgetsBinding.instance.addPostFrameCallback((_) {
    // AdManager.connectTapjoy();
    // });
    // 🔄 مزامنة العدادات من السيرفر فور الدخول
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _syncCooldownFromFirebase(user.uid);
    }
    _setupPointsStream();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });
    // 3. ✨ تهيئة الأنميشن
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    // 4. 📑 تهيئة التاب Controller
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        HapticFeedback.selectionClick();
        AdManager.showSmartAd();
      }
    });

    // 5. 🚀 تنفيذ العمليات بعد رسم الشاشة وتجهيز إعلان AdMob الثابت
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // تهيئة محرك الإعلانات العام
        AdManager.initialize();
        AdManager.showAppOpenAd();

// استبدل الجزء الخاص بـ BannerAd بهذا الكود المطور
        _adMobBanner = BannerAd(
          adUnitId: AdManager.adMobBannerId,
          size: AdSize.banner,
          request: const AdRequest(),
          listener: BannerAdListener(
            onAdLoaded: (ad) {
              if (mounted) setState(() {}); // تحديث الواجهة فور التحميل
            },
            onAdFailedToLoad: (ad, error) {
              ad.dispose();
              debugPrint('❌ AdMob Error: ${error.message}');
            },
          ),
        )..load(); // البدء بالتحميل فوراً

        _initNotifications();
      }
    });
  }

  void _checkForUpdate() async {
    try {
      // 1. جلب بيانات الإصدار الحالي من التطبيق نفسه
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String localVersion = packageInfo.version;

      // 2. جلب الإعدادات من Firestore
      var config = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      if (config.exists) {
        String serverVersion = config.data()?['current_version'] ?? "1.0.0";
        String updateUrl = config.data()?['update_url'] ?? "";
        bool isForceUpdate = config.data()?['force_update'] ?? false;

        // 3. مقارنة الإصدارات (إذا كان إصدار السيرفر أحدث)
        if (serverVersion != localVersion && isForceUpdate) {
          _showUpdateDialog(updateUrl);
        }
      }
    } catch (e) {
      debugPrint("Update Check Error: $e");
    }
  }

  void _showUpdateDialog(String url) {
    showDialog(
      context: context,
      barrierDismissible: false, // منع إغلاق النافذة بالضغط خارجها
      builder: (context) => PopScope(
        canPop: false, // 🚫 منع التراجع تماماً (بديل onWillPop)
        onPopInvokedWithResult: (didPop, result) {
          // يمكنك إضافة منطق إضافي هنا إذا لزم الأمر
        },
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(tr('update_required_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.amber, fontWeight: FontWeight.bold)),
          content: Text(tr('update_required_msg'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  // استخدام url_launcher لفتح الرابط
                  final Uri uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(tr('update_now'),
                    style: const TextStyle(
                        color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _setupPointsStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists && mounted) {
          setState(() {
            // تأكد من تحويل القيمة لـ int لتجنب تعارض الأنواع
            totalPoints = (snapshot.data())?['points'] ?? 0;
          });
        }
      }, onError: (error) {
        debugPrint("📡 Stream Error: $error");
        // اختياري: محاولة إعادة الاتصال بعد 5 ثوانٍ
      });
    }
  }

  // تأكد من وجود هذه الدالة خارج initState كما ناقشنا سابقاً
  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        // فحص mounted قبل تحديث الواجهة (setState)
        if (!mounted) return;

        if (userDoc.exists) {
          setState(() {
            // الطريقة الآمنة لقراءة الحقل حتى لو كان غير موجود في Firestore
            totalPoints =
                (userDoc.data() as Map<String, dynamic>?)?['points'] ?? 0;
          });
        }
      } else {
        // فحص mounted قبل الانتقال لشاشة تسجيل الدخول (حل التحذير 158)
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      debugPrint("خطأ في جلب البيانات: $e");
    }
  }

  StreamSubscription? _networkSubscription;

  void _startNetworkMonitoring() {
    _networkSubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) async {
      // جلب المستند من Firestore بدلاً من RemoteConfig
      var configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      bool isProtectionEnabled =
          configDoc.data()?['is_vpn_protection_enabled'] ?? true;

      if (isProtectionEnabled) {
        if (await CheckVpnConnection.isVpnActive()) {
          _showVpnBlocker();
        }
      }
    });
  }

  void _showVpnBlocker() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false, // يمنع إغلاق النافذة
      builder: (context) => PopScope(
        canPop: false, // يمنع زر الرجوع في الأندرويد
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title:
              const Icon(Icons.security_rounded, color: Colors.red, size: 50),
          // ✅ التعديل الصحيح:
          content: Text(
            tr('close_vpn'), // سيجلب النص من tr.json أو ar.json تلقائياً
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                bool isVpnStillActive = await CheckVpnConnection.isVpnActive();
                if (!context.mounted) return;
                if (!isVpnStillActive) {
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(tr('vpn_still_active'))) // ✅ تم تعديله
                      );
                }
              },
              child: Text(tr('vpn_check_now')), // ✅ تم تعديله
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _banListener?.cancel();
    _unityTimer?.cancel(); // إيقاف مؤقت سيرفر 1
    _admobTimer?.cancel(); // إيقاف مؤقت سيرفر 2
    _controller.dispose();
    _tabController.dispose();
    _adMobBanner?.dispose();
    _networkSubscription?.cancel();
    super.dispose();
  }

  void _runTimer(String server, int remaining) {
    if (server == "unity") {
      _unitySecondsLeft = remaining;
      _unityTimer?.cancel();
      _unityTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_unitySecondsLeft > 0) {
          setState(() => _unitySecondsLeft--);
        } else {
          timer.cancel();
          _sendTimeNotification(tr('reward_ready_server_1')); // ✅ سيرفر 1
        }
      });
    } else {
      _admobSecondsLeft = remaining;
      _admobTimer?.cancel();
      _admobTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_admobSecondsLeft > 0) {
          setState(() => _admobSecondsLeft--);
        } else {
          timer.cancel();
          _sendTimeNotification(tr('reward_ready_admob')); // ✅ أد موب
        }
      });
    }
  }

// تعديل الدالة لتستقبل المدة (duration) كمعامل
  void _startCooldownWithFirebase(
      String server, String uid, int duration) async {
    DateTime endTime = DateTime.now().add(Duration(seconds: duration));

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      '${server}_cooldown_until': Timestamp.fromDate(endTime),
      'login_lock_until':
          Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
    }, SetOptions(merge: true));

    _runTimer(server, duration);
  }

  void _syncCooldownFromFirebase(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;
      for (String server in ["unity", "admob"]) {
        if (data.containsKey('${server}_cooldown_until')) {
          Timestamp timestamp = data['${server}_cooldown_until'];
          DateTime endTime = timestamp.toDate();
          DateTime now = DateTime.now();

          if (endTime.isAfter(now)) {
            int remaining = endTime.difference(now).inSeconds;
            _runTimer(server, remaining);
          }
        }
      }
    }
  }
  // ✨ دالة مساعدة لتحويل الثواني (300) إلى شكل (05:00) لتضعها في الواجهة

  void _showSuccessSnackBar(String message) {
    if (!mounted) return; // حماية في حال أغلق المستخدم الصفحة فوراً

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message, style: const TextStyle(fontSize: 16))),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating, // لجعل الرسالة تطفو فوق الأزرار
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showLimitReachedDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              // تم تغيير Icon إلى FaIcon لحل مشكلة التوافق
              const FaIcon(FontAwesomeIcons.circleExclamation,
                  color: Colors.orange),
              const SizedBox(width: 10),
              Text(tr('limit_reached_title')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('limit_reached_desc'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tr('limit_reached_reset'),
                  style: TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.orange),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('got_it'),
                  style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        );
      },
    );
  }

  // --- 4. واجهات التبويبات (Tab Content) ---
  void _handleAdSelection({required String server, int cooldown = 300}) {
    // 🚫 1. فحص القفل: إذا كانت هناك عملية جارية، اخرج فوراً لمنع التكرار
    if (_isAdProcessing) return;

    // 2. التحقق من وقت الانتظار الحالي
    if (server == "unity") {
      if (_unitySecondsLeft > 0) {
        _showErrorSnackBar("${tr('wait')} ${_formatTime(_unitySecondsLeft)}");
        return;
      }
    } else {
      if (_admobSecondsLeft > 0) {
        _showErrorSnackBar("${tr('wait')} ${_formatTime(_admobSecondsLeft)}");
        return;
      }
    }

    // 🔒 3. تفعيل القفل ومؤشر الانتظار
    setState(() {
      _isAdProcessing = true;
      _isWaiting = true;
    });

    _startWaitingTimer();

    if (server == "unity") {
      AdManager.showUnityVideo(
        onReward: () async {
          try {
            // 🛡️ إرسال الطلب للسيرفر
            await FirebaseFirestore.instance.collection('completed_tasks').add({
              'userId': FirebaseAuth.instance.currentUser!.uid,
              'taskType': 'unity_ad',
              'timestamp': FieldValue.serverTimestamp(),
              'status': 'pending',
            });

            if (mounted) {
              _startCooldownWithFirebase(
                  "unity", FirebaseAuth.instance.currentUser!.uid, cooldown);
              _showSuccessSnackBar("✅ تم إرسال الطلب، ستضاف النقاط قريباً");
            }
          } catch (e) {
            _showErrorSnackBar("❌ خطأ في الاتصال، حاول مجدداً");
          } finally {
            // 🔓 4. فك القفل دائماً عند انتهاء العملية (سواء نجحت أو فشلت)
            if (mounted) {
              setState(() {
                _isWaiting = false;
                _isAdProcessing = false;
              });
            }
          }
        },
        onFailed: () {
          // 🔓 فك القفل في حالة فشل تحميل الإعلان
          if (mounted) {
            setState(() {
              _isWaiting = false;
              _isAdProcessing = false;
            });
          }
          _showErrorSnackBar("⏳ الإعلان غير جاهز، حاول مجدداً");
        },
      );
    } else {
      AdManager.showAdMobVideo(
        onReward: () async {
          try {
            await FirebaseFirestore.instance.collection('completed_tasks').add({
              'userId': FirebaseAuth.instance.currentUser!.uid,
              'taskType': 'admob_ad',
              'timestamp': FieldValue.serverTimestamp(),
              'status': 'pending',
            });

            if (mounted) {
              _startCooldownWithFirebase(
                  "admob", FirebaseAuth.instance.currentUser!.uid, cooldown);
              _showSuccessSnackBar("💰 تم إرسال الطلب، ستضاف النقاط قريباً");
            }
          } catch (e) {
            _showErrorSnackBar("❌ فشل إرسال الطلب، تأكد من الإنترنت");
          } finally {
            // 🔓 فك القفل عند انتهاء عملية AdMob
            if (mounted) {
              setState(() {
                _isWaiting = false;
                _isAdProcessing = false;
              });
            }
          }
        },
        onFailed: () {
          if (mounted) {
            setState(() {
              _isWaiting = false;
              _isAdProcessing = false;
            });
          }
          _showErrorSnackBar("⏳ تعذر تحميل إعلان جوجل، حاول لاحقاً");
        },
      );
    }
  }

// أضف المعاملات لكي تستقبل القيم المحسوبة من السيرفر
  Widget _buildVideoTab(
      int unityRemaining,
      int admobRemaining,
      int cooldownSeconds,
      int unityPoints, // أضف هذا المتغير
      int admobPoints // أضف هذا المتغير
      ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- سيرفر Unity ---
        _buildVideoServerCard(
          title: tr('unity_ad'),
          sub: _unitySecondsLeft > 0
              ? "${tr('wait')} ${_formatTime(_unitySecondsLeft)}"
              : tr('video_ad_sub'),
          points: unityPoints, // استخدام القيمة القادمة من فايربيس
          icon: FontAwesomeIcons.unity,
          remaining: unityRemaining,
          isPremium: true,
          onTap: () {
            if (_unitySecondsLeft > 0 || _isWaiting || unityRemaining <= 0) {
              if (unityRemaining <= 0) _showLimitReachedDialog();
              return;
            }
            setState(() => _isWaiting = true);
            _handleAdSelection(server: "unity", cooldown: cooldownSeconds);
          },
        ),

        const SizedBox(height: 20),

        // --- سيرفر AdMob ---
        _buildVideoServerCard(
          title: tr('admob_ad'),
          sub: _admobSecondsLeft > 0
              ? "${tr('wait')} ${_formatTime(_admobSecondsLeft)}"
              : tr('video_ad_sub'),
          points: admobPoints, // استخدام القيمة القادمة من فايربيس
          icon: FontAwesomeIcons.google,
          remaining: admobRemaining,
          isPremium: false,
          onTap: () {
            if (_admobSecondsLeft > 0 || _isWaiting || admobRemaining <= 0) {
              if (admobRemaining <= 0) _showLimitReachedDialog();
              return;
            }
            setState(() => _isWaiting = true);
            _handleAdSelection(server: "admob", cooldown: cooldownSeconds);
          },
        ),

        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildVideoServerCard({
    required String title,
    required String sub,
    required int points,
    required dynamic icon,
    required VoidCallback onTap,
    required int remaining,
    bool isPremium = false,
  }) {
    return Card(
      color: const Color(0xFF1E1E2E), // اللون الداكن الفائق
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isPremium
              ? Colors.amber.withValues(alpha: 0.3)
              : Colors.cyanAccent.withValues(alpha: 0.3),
        ),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        leading: ShaderMask(
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: isPremium
                ? [Colors.amber, Colors.orangeAccent]
                : [Colors.blueAccent, Colors.cyanAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: FaIcon(icon as FaIconData?,
              color: Colors.white, size: 42), // أيقونة ضخمة
        ),
        title: Text(
          title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            Text(sub,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 16)), // نص واضح
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: remaining > 0
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                // ✅ الترجمة تعمل هنا الآن
                "${tr('remaining')}: $remaining",
                style: TextStyle(
                  color: remaining > 0 ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        trailing: Text(
          "+$points",
          style: const TextStyle(
              color: Colors.greenAccent,
              fontWeight: FontWeight.w900,
              fontSize: 18),
        ),
        onTap: remaining > 0 ? onTap : null,
      ),
    );
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  Widget _buildTaskCard(
      String title, String sub, int pts, IconData icon, VoidCallback action,
      {bool isPremium = false}) {
    return Card(
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          // ✅ تم استبدال withOpacity بـ withValues(alpha: ...)
          color:
              isPremium ? Colors.amber.withValues(alpha: 0.5) : Colors.white10,
        ),
      ),
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        leading: ShaderMask(
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: isPremium
                ? [Colors.amber, Colors.orangeAccent, Colors.yellowAccent]
                : [Colors.blueAccent, Colors.cyanAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: Icon(icon, color: Colors.white, size: 38),
        ),
        title: Text(title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
              letterSpacing: 0.5,
            )),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(sub,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.3,
              )),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            // ✅ تحديث الشفافية هنا أيضاً للطريقة الجديدة
            color: Colors.greenAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
          ),
          child: Text("+$pts",
              style: const TextStyle(
                color: Colors.greenAccent,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              )),
        ),
        onTap: action,
      ),
    );
  }

  void _startWaitingTimer() {
    // 1. تصفير العداد قبل البدء لضمان الدقة
    _secondsRemaining = 15;

    setState(() {
      _isWaiting = true;
    });

    // 2. استخدام متغير مؤقت محلي لتجنب الـ Memory Leak في تركيا
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        // 👈 حماية: إذا أغلق المستخدم الصفحة، نوقف المؤقت فوراً
        timer.cancel();
        return;
      }

      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        timer.cancel();
        setState(() {
          _isWaiting = false;
        });
      }
    });
  }

  // 2. دالة رسالة الخطأ (باللون الأحمر)
  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // --- 7. دوال المكافأة اليومية والحساب ---
  void _claimDailyReward() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      int currentStreak = 0;
      bool canClaim = true;
      Duration remainingTime = Duration.zero;

      if (doc.exists && doc.data() != null) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        currentStreak = data['streak_count'] ?? 0;

        if (data.containsKey('last_daily_claim') &&
            data['last_daily_claim'] != null) {
          dynamic rawDate = data['last_daily_claim'];
          DateTime lastClaimDate;

          if (rawDate is Timestamp) {
            lastClaimDate = rawDate.toDate();
          } else if (rawDate is String) {
            lastClaimDate = DateTime.parse(rawDate);
          } else {
            lastClaimDate = DateTime.now().subtract(const Duration(days: 2));
          }

          DateTime nextClaimDate = lastClaimDate.add(const Duration(hours: 24));
          DateTime now = DateTime.now();

          if (now.isBefore(nextClaimDate)) {
            canClaim = false;
            remainingTime = nextClaimDate.difference(now);
          }
        }
      }

      if (mounted) {
        // نمرر المعاملات لـ Dialog الذي سيستدعي _processDailyReward لاحقاً
        _showRewardDialog(user.uid, currentStreak, canClaim, remainingTime);
      }
    } catch (e) {
      debugPrint("❌ Error in Daily Reward: $e");
      _showErrorSnackBar("فشل جلب البيانات، حاول مجدداً");
    }
  }

  Future<void> _processDailyReward(String uid, int rewardAmount) async {
    try {
      // استخدام الوقت المحلي للسجل لتجنب تعارض serverTimestamp داخل المصفوفات
      final now = DateTime.now();

      // إنشاء Batch لضمان تنفيذ العمليات معاً
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 1. مرجع طلب المكافأة
      DocumentReference requestRef =
          FirebaseFirestore.instance.collection('reward_requests').doc();
      batch.set(requestRef, {
        'userId': uid,
        'timestamp': FieldValue.serverTimestamp(),
        'amount': rewardAmount,
      });

      // 2. مرجع المستخدم وتحديث البيانات
      DocumentReference userRef =
          FirebaseFirestore.instance.collection('users').doc(uid);
      batch.update(userRef, {
        'points': FieldValue.increment(rewardAmount),
        'last_daily_claim': FieldValue.serverTimestamp(),
        'points_history': FieldValue.arrayUnion([
          {
            'type': 'daily_reward_claim',
            'amount': rewardAmount,
            'timestamp': now.toIso8601String(), // استخدام صيغة وقت ثابتة
          }
        ])
      });

      // تنفيذ كل العمليات دفعة واحدة
      await batch.commit();

      if (!mounted) return;

      // إظهار رسالة نجاح واضحة
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('reward_processing_msg')),
          backgroundColor: Colors.green, // اللون الأخضر يطمن المستخدم
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint("❌ Daily Reward Error: $e");
      if (!mounted) return;
      _showErrorSnackBar(tr('withdraw_error'));
    }
  }

  // --- 8. بناء الواجهة الرئيسية (Build) ---
// --- 8. بناء الواجهة الرئيسية (Build) ---
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    Color unselectedTabColor =
        themeProvider.isDarkMode ? Colors.white54 : Colors.black45;
    Color indicatorColor = Colors.amber;

    return StreamBuilder<DocumentSnapshot>(
      // 1. مراقبة مستند الإعدادات العامة (Config)
      stream: FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .snapshots(),
      builder: (context, configSnapshot) {
        return StreamBuilder<DocumentSnapshot>(
          // 2. مراقبة مستند المستخدم الحالي
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            // حالة التحميل: إظهار مؤشر التحميل حتى تتوفر البيانات
            if (!configSnapshot.hasData || !userSnapshot.hasData) {
              return Scaffold(
                backgroundColor: themeProvider.isDarkMode
                    ? Colors.black
                    : const Color(0xFFF5F7FA),
                body: const Center(
                    child: CircularProgressIndicator(color: Colors.amber)),
              );
            }

            // --- استخراج بيانات المستخدم أولاً لحل مشكلة hasRated ---
            final userData =
                userSnapshot.data?.data() as Map<String, dynamic>? ?? {};

            // ✅ تعريف hasRated داخل النطاق الصحيح (Scope)
            final bool hasRated = userData['has_rated_app'] ?? false;

            // --- استخراج بيانات الإعدادات (Config) ---
            final config =
                configSnapshot.data?.data() as Map<String, dynamic>? ?? {};
            final int unitypoints = config['unity_points'] ?? 10;
            final int admobpoints = config['admob_points'] ?? 5;
            // ✅ استخراج الحدود اليومية المنفصلة من Firestore
            final int cooldownSeconds = config['video_cooldown_seconds'] ?? 300;
            final int unityDailyLimit = config['unity_daily_limit'] ?? 20;
            final int admobDailyLimit = config['admob_daily_limit'] ?? 20;

            final int currentExchangeRate = config['exchange_rate'] ?? 1000;
            final bool isUnderMaintenance =
                config['under_maintenance'] ?? false;
            final String maintenanceMsg =
                config['maintenance_message'] ?? tr('maintenance_msg_default');

            // حساب الفيديوهات المتبقية لكل سيرفر[cite: 2]
            final List<dynamic> history = userData['points_history'] ?? [];

// 1. تعريف الوقت الحالي أولاً
            final DateTime now = DateTime.now();

// 2. حساب إعلانات Unity اليوم
            int unityWatched = history.where((item) {
              final rawTimestamp = item['timestamp'];
              if (rawTimestamp == null || item['type'] != 'unity_ad') {
                return false;
              }

              final DateTime timestamp = (rawTimestamp as Timestamp).toDate();

              return timestamp.year == now.year &&
                  timestamp.month == now.month &&
                  timestamp.day == now.day;
            }).length;

// 3. حساب إعلانات AdMob اليوم
            int admobWatched = history.where((item) {
              final rawTimestamp = item['timestamp'];
              if (rawTimestamp == null || item['type'] != 'admob_ad') {
                return false;
              }

              final DateTime timestamp = (rawTimestamp as Timestamp).toDate();

              return timestamp.year == now.year &&
                  timestamp.month == now.month &&
                  timestamp.day == now.day;
            }).length;

            int unityRemaining =
                (unityDailyLimit - unityWatched).clamp(0, unityDailyLimit);
            int admobRemaining =
                (admobDailyLimit - admobWatched).clamp(0, admobDailyLimit);

            // التحقق من حالة الصيانة
            if (isUnderMaintenance) {
              return _buildMaintenanceScreen(maintenanceMsg);
            }

            return FadeTransition(
              opacity: _animation,
              child: Scaffold(
                body: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: themeProvider.isDarkMode
                          ? [const Color(0xFF4527A0), Colors.black]
                          : [const Color(0xFFFFFFFF), const Color(0xFFDDE1E7)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                  child: SafeArea(
                    child: Column(
                      children: [
                        _buildHeader(uid, currentExchangeRate),
                        _buildPointsDisplay(uid, currentExchangeRate),
                        TabBar(
                          controller: _tabController,
                          indicatorColor: indicatorColor,
                          labelColor: indicatorColor,
                          unselectedLabelColor: unselectedTabColor,
                          tabs: [
                            Tab(
                                icon: const Icon(Icons.play_circle_fill),
                                text: tr('video_server')),
                            // تم حذف تبويب الألعاب هنا
                            Tab(
                                icon: const Icon(Icons.grid_view_rounded),
                                text: tr('offers')),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 20, horizontal: 15),
                                child: _buildVideoTab(
                                    unityRemaining,
                                    admobRemaining,
                                    cooldownSeconds,
                                    unitypoints, // المتغير الذي يجلب القيمة من فايربيس (تأكد من اسمه لديك)
                                    admobpoints // المتغير الذي يجلب القيمة من فايربيس
                                    ),
                              ),

                              _buildOffersTab(
                                  hasRated), // تمرير الحالة لتبويب العروض
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white10),
                        _buildAdsSection(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildOffersTab(bool hasRated) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          // زر Tapjoy
          /*ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigoAccent,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15))),
            onPressed: () => AdManager.showTapjoyOfferwall(),
            icon: const Icon(Icons.workspace_premium_rounded,
                color: Colors.white),
            label: Text(tr('tapjoy_wall'),
                style: const TextStyle(color: Colors.white, fontSize: 18)),
          ),
          const SizedBox(height: 15),
            */
          // ✅ زر التقييم بـ 25 نقطة مترجم وبدون أخطاء
          _buildTaskCard(
            hasRated ? tr('rated_thanks') : tr('rate_app_title'),
            hasRated ? "" : tr('rate_app_sub'),
            25,
            Icons.stars_rounded,
            hasRated
                ? () {} // تعطيل النقر تماماً بعد الحصول على النقاط
                : () async {
                    const String url =
                        "https://play.google.com/store/apps/details?id=com.mohamad.syria_earn";
                    final Uri uri = Uri.parse(url);

                    try {
                      if (await canLaunchUrl(uri)) {
                        // 1. فتح المتجر للمستخدم
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);

                        // 2. إظهار نافذة "التحقق الوهمي" مع العداد التنازلي
                        if (mounted) {
                          _showFakeVerificationDialog();
                        }
                      }
                    } catch (e) {
                      debugPrint("Error: $e");
                      if (mounted) _showErrorSnackBar(tr('error_occurred'));
                    }
                  },
            isPremium: !hasRated, // سيتوقف التصميم الملون (الذهبي) بعد التقييم
          ),
        ],
      ),
    );
  }

  void _showFakeVerificationDialog() {
    int countdown = 60;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false, // يمنع الإغلاق عند النقر خارج النافذة
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              if (countdown > 0) {
                if (mounted) setDialogState(() => countdown--);
              } else {
                t.cancel();
                _finalizeRatingPoints(ctx);
              }
            });

            // ✅ استخدام PopScope لمنع إغلاق النافذة عند الضغط على زر الرجوع في الأندرويد
            return PopScope(
              canPop: false, // يمنع الرجوع تماماً حتى ينتهي الوقت
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                // اختيارياً: يمكنك إظهار رسالة صغيرة تخبره بضرورة الانتظار
              },
              child: AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Colors.amber, width: 1),
                ),
                title: Row(
                  children: [
                    // ✅ استبدال الأيقونة التي سببت الخطأ بأيقونة ShieldVerified
                    const Icon(Icons.verified_user_rounded,
                        color: Colors.amber),
                    const SizedBox(width: 10),
                    Text(
                      tr('verifying'),
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
// داخل العمود (Column) الخاص بمحتوى النافذة (Content)
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.amber),
                    const SizedBox(height: 25),
                    Text(
                      tr('verifying_desc'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 15),

                    // ✅ إضافة رابط التطبيق هنا
// ✅ أضف هذا الجزء داخل العمود (Column) بدلاً من الرابط الطويل
                    InkWell(
                      onTap: () async {
                        const String url =
                            "https://play.google.com/store/apps/details?id=com.mohamad.syria_earn";
                        final Uri uri = Uri.parse(url);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri,
                              mode: LaunchMode.externalApplication);
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          tr('click_here_to_rate'), // ✅ استخدم مفتاح الترجمة هنا
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration
                                .underline, // إضافة خط تحت النص لإظهار أنه رابط
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Text(
                      "00:${countdown.toString().padLeft(2, '0')}",
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      tr('verifying_points_hint'),
                      style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) => timer?.cancel());
  }

  void _finalizeRatingPoints(BuildContext dialogContext) async {
    String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) return;

    try {
      // تحديث قاعدة البيانات
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'has_rated_app': true,
        'points': FieldValue.increment(25),
        'points_history': FieldValue.arrayUnion([
          {
            'type': 'rate_app_bonus',
            'amount': 25,
            // ✅ الحل: استخدم DateTime.now() بدلاً من serverTimestamp داخل المصفوفة
            'timestamp': DateTime.now(),
          }
        ])
      });

      if (!mounted) return;

      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }

      _showSuccessSnackBar("${tr('success_rate')} 25 ${tr('points')}");
    } catch (e) {
      debugPrint("Error finalizing points: $e");

      if (mounted && dialogContext.mounted) {
        Navigator.pop(dialogContext);
        _showErrorSnackBar(tr('error_occurred'));
      }
    }
  }

  // دالة تصميم شاشة الصيانة (بنفس ثيم التطبيق)
  Widget _buildMaintenanceScreen(String message) {
    // 👈 نستخدم message الممررة هنا
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4527A0), Colors.black],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.build_circle_rounded,
                size: 80, color: Colors.amber),
            const SizedBox(height: 20),
            Text(
              tr('maintenance_title'),
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white),
            ),
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                message, // ✅ تم استبدال _maintenanceMsg بـ message
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16, color: Colors.white70, height: 1.5),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              // بما أننا نستخدم Stream، لا نحتاج لاستدعاء دالة يدويًا
              // الزر يمكنه فقط عرض رسالة "سيتم التحديث تلقائيًا" أو تركه فارغاً
              onPressed: () {},
              child: Text(tr('waiting_update'), // "بانتظار التحديث..."
                  style: const TextStyle(color: Colors.black)),
            )
          ],
        ),
      ),
    );
  }

// home_screen.dart

  Widget _buildHeader(String? uid, int exchangeRate) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    // حساب القيمة الدولارية
    double rate = exchangeRate > 0 ? exchangeRate.toDouble() : 1000.0;
    double dollarValue = totalPoints / rate;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // --- القسم الأيمن: زر القائمة + اسم التطبيق ---
          Row(
            children: [
              // زر الـ 3 شخطات (المسؤول عن فتح الـ Drawer)
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_rounded, size: 28),
                  color:
                      themeProvider.isDarkMode ? Colors.amber : Colors.black87,
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Syria Earn",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: themeProvider.isDarkMode
                          ? Colors.white
                          : Colors.black87,
                    ),
                  ),
                  Container(
                    height: 3,
                    width: 30,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ],
          ),

          // --- القسم الأيسر: بطاقة النقاط ---
          InkWell(
            onTap: () => _navigateToWithdraw(uid),
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stars_rounded,
                      color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "$totalPoints",
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.amber,
                        ),
                      ),
                      Text(
                        "\$${dollarValue.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontSize: 10,
                          color: themeProvider.isDarkMode
                              ? Colors.greenAccent
                              : Colors.green,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // دالة مساعدة لإنشاء الأزرار بحجم أصغر لتجنب الـ Overflow

  Widget _buildPointsDisplay(String? uid, int exchangeRate) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const CircularProgressIndicator(color: Colors.amber);
        }

        var data = snap.data?.data() as Map<String, dynamic>?;
        int points = (data?['points'] ?? 0).toInt();

        // 🟢 إضافة مراقبة الإعدادات السحابية (Exchange Rate)
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('app_settings')
              .doc('config')
              .snapshots(),
          builder: (context, configSnap) {
            final config =
                configSnap.data?.data() as Map<String, dynamic>? ?? {};
            int exchangeRate = config['exchange_rate'] ?? 1000;
            double dollarValue = points / exchangeRate;

            return Column(
              children: [
                // عرض النقاط بشكل كبير
                Text(
                  "$points",
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 60,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 10)]),
                ),

                // ✨ إضافة: عرض ما يعادلها بالدولار تحت النقاط مباشرة
                Text(
                  "≈ \$${dollarValue.toStringAsFixed(2)}",
                  style: TextStyle(
                      color: Colors.greenAccent.withValues(alpha: 0.8),
                      fontSize: 18,
                      fontWeight: FontWeight.w500),
                ),

                const SizedBox(height: 15),

                // 📢 إشعار السحوبات (الخبر العاجل)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('global_notifications')
                      .orderBy('timestamp', descending: true)
                      .limit(1)
                      .snapshots(),
                  builder: (context, notifSnap) {
                    if (!notifSnap.hasData || notifSnap.data!.docs.isEmpty) {
                      return const SizedBox(height: 40);
                    }

                    var notifData = notifSnap.data!.docs.first.data()
                        as Map<String, dynamic>;
                    String lang = context.locale.languageCode;
                    String message = notifData['message_$lang'] ??
                        notifData['message_en'] ??
                        "";

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 15, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.greenAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified,
                              color: Colors.greenAccent, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              message,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAdsSection() {
    final String? currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == 'OeEwi4nMZrPjRLRiqWf1373btQT2') {
      return const SizedBox.shrink();
    }

    return Container(
      height: 60,
      width: double.infinity,
      color: Colors
          .transparent, // جعل الخلفية شفافة لتتناسب مع الـ Gradient الخاص بك
      alignment: Alignment.center,
      // تأكد من أن _adMobBanner ليس null قبل العرض لتجنب الـ Red Screen
      child: _adMobBanner != null
          ? AdManager.smartBanner(_adMobBanner, forceAdMob: true)
          : const SizedBox.shrink(),
    );
  }

  void _navigateToWithdraw(String? uid) {
    // 1. إظهار الإعلان فوراً (تجربة مستخدم أسرع)
    AdManager.showSmartAd();

    // 2. الانتقال فوراً دون انتظار Firebase
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (c) => const WithdrawScreen()),
      );
    }
  }

  void _navigateToLeaderboard() {
    AdManager.showSmartAd();
    Navigator.push(
        context, MaterialPageRoute(builder: (c) => const LeaderboardScreen()));
  }

  void _initNotifications() {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    flutterLocalNotificationsPlugin.initialize(
        settings: const InitializationSettings(android: android));
  }

// أضف String message هنا 👇
  Future<void> _sendTimeNotification(String messageKey) async {
    const android = AndroidNotificationDetails(
      'reward_timer_id',
      'تنبيهات الأرباح',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF4527A0),
      icon: '@mipmap/ic_launcher',
    );

    // توليد معرف فريد لتجنب تداخل الإشعارات
    int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await flutterLocalNotificationsPlugin.show(
      id: notificationId,
      title: tr('notification_reward_title'),
      body: tr(messageKey),
      notificationDetails: NotificationDetails(android: android),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  // --- 10. الحوارات (Dialogs) ---
  void _showRewardDialog(
      String uid, int streak, bool canClaim, Duration remaining) {
    Duration liveRemaining = remaining;
    Timer? timer;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            if (!canClaim && timer == null) {
              timer = Timer.periodic(const Duration(seconds: 1), (t) {
                if (liveRemaining.inSeconds > 0) {
                  setDialogState(() {
                    liveRemaining = liveRemaining - const Duration(seconds: 1);
                  });
                } else {
                  setDialogState(() {
                    canClaim = true;
                  });
                  t.cancel();
                }
              });
            }

            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
              ),
              title: Text(tr('daily_streak'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),

              // 🛠️ الإصلاح هنا: استخدام SingleChildScrollView ومنع تمدد العمود
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min, // يمنع العمود من أخذ مساحة الشاشة كاملة
                  children: [
                    Icon(canClaim ? Icons.card_giftcard : Icons.timer_outlined,
                        color: Colors.amber,
                        size: 50), // تقليل الحجم قليلاً (من 60 لـ 50)
                    const SizedBox(height: 10),
                    Text(
                        canClaim
                            ? tr('daily_reward_ready')
                            : tr('next_reward_in'),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 8),
                    Text(
                      canClaim
                          ? "${10 + (streak * 5)} ${tr('points')}"
                          : _formatDuration(liveRemaining),
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 24, // تقليل الخط قليلاً لتوفير مساحة
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 15),

                    // شريط الأيام
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(7, (index) {
                          bool isPast = index < streak;
                          bool isCurrent = index == streak;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(8), // تقليل البادينج
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? Colors.amber
                                  : (isPast
                                      ? Colors.green.withValues(alpha: 0.4)
                                      : Colors.white10),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              children: [
                                Text("${tr('day')} ${index + 1}",
                                    style: TextStyle(
                                        color: isCurrent
                                            ? Colors.black
                                            : Colors.white60,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold)),
                                Text("${10 + (index * 5)}",
                                    style: TextStyle(
                                        color: isCurrent
                                            ? Colors.black
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Center(
                  child: canClaim
                      ? ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber,
                              foregroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12))),
                          onPressed: () async {
                            // 1. إيقاف المؤقت فوراً لتوفير موارد الهاتف
                            timer?.cancel();

                            // 2. إغلاق النافذة المنبثقة
                            Navigator.pop(ctx);

                            // 3. 🛡️ التحقق من أن الصفحة لا تزال نشطة قبل المعالجة
                            if (!mounted) return;

                            // 4. ✅ حساب قيمة الجائزة (10 نقاط أساسية + 5 عن كل يوم في السلسلة)
                            int rewardAmount = 10 + (streak * 5);

                            // 5. 🚀 استدعاء الدالة مع المعاملين (المعرف والمبلغ) لتعمل مع سجل النقاط
                            await _processDailyReward(uid, rewardAmount);
                          },
                          child: Text(tr('claim_reward_now')),
                        )
                      : TextButton(
                          onPressed: () {
                            // إيقاف المؤقت وإغلاق النافذة في حالة عدم توفر الجائزة
                            timer?.cancel();
                            Navigator.pop(ctx);
                          },
                          child: Text(tr('close'),
                              style: TextStyle(color: Colors.white54)),
                        ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => timer?.cancel());
  }

  Widget _buildAppDrawer(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    return Drawer(
      backgroundColor:
          themeProvider.isDarkMode ? const Color(0xFF1A1A2E) : Colors.white,
      child: Column(
        children: [
          // رأس القائمة
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Color(0xFF1A1A2E)),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.amber,
              child: Icon(Icons.person, size: 40, color: Colors.black),
            ),
            accountName: const Text("Syria Earn Pro",
                style: TextStyle(fontWeight: FontWeight.bold)),
            accountEmail: Text(tr('welcome_msg')),
          ),

          // 1. زر تبديل الوضع (Dark/Light)
          ListTile(
            leading: Icon(
                themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: Colors.orange),
            title: Text(
                themeProvider.isDarkMode ? "الوضع النهاري" : "الوضع الليلي"),
            subtitle: const Text("تغيير مظهر التطبيق لراحة العين"),
            onTap: () {
              themeProvider.toggleTheme();
              Navigator.pop(context);
            },
          ),

          // 2. سجل النقاط
          ListTile(
            leading: const Icon(Icons.history, color: Colors.cyan),
            title: Text(tr('points_history_title')),
            subtitle: const Text("شاهد جميع العمليات التي قمت بها"),
            onTap: () {
              Navigator.pop(context);
              _navigateToHistory();
            },
          ),

          // 3. المتصدرين
          ListTile(
            leading: const Icon(Icons.leaderboard, color: Colors.amber),
            title: const Text("لوحة المتصدرين"),
            subtitle: const Text("اكتشف ترتيبك بين المستخدمين"),
            onTap: () {
              Navigator.pop(context);
              _navigateToLeaderboard();
            },
          ),

          // 4. المكافأة اليومية
          ListTile(
            leading: const Icon(Icons.card_giftcard, color: Colors.pink),
            title: const Text("المكافأة اليومية"),
            subtitle: const Text("احصل على نقاط مجانية كل 24 ساعة"),
            onTap: () {
              Navigator.pop(context);
              _claimDailyReward();
            },
          ),

          const Divider(),

          // 5. الإعدادات
          ListTile(
            leading: const Icon(Icons.settings, color: Colors.grey),
            title: Text(tr('settings_title')),
            subtitle: const Text("إعدادات الحساب والتطبيق"),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
        ],
      ),
    );
  }
}
