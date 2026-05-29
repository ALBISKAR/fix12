import 'dart:async';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:syria_earn_pro/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:syria_earn_pro/screens/history_screen.dart';
import 'package:syria_earn_pro/screens/lucky_wheel_dialog.dart';
import 'package:syria_earn_pro/screens/offers_tab_screen.dart';
import 'package:syria_earn_pro/screens/social_media_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:syria_earn_pro/screens/withdraw_screen.dart';
import 'package:syria_earn_pro/screens/leaderboard_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:check_vpn_connection/check_vpn_connection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';
import 'package:ntp/ntp.dart'; // إضافة حزمة وقت الإنترنت
import 'package:firebase_messaging/firebase_messaging.dart';
// ✅ استيراد ملف خدمة Start.io (سيرفر 1) الجديد

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  bool _isWaiting = false;
  bool _isAdProcessing = false;
  late TabController _tabController;
  late AnimationController _controller;
  late Animation<double> _animation;
  int _unitySecondsLeft = 0;
  int _admobSecondsLeft = 0;
  bool _isVpnDialogShowing = false;
  Timer? _unityTimer;
  Timer? _admobTimer;
  bool _canClaimDaily = false;

  late PageController _arcadePageController;
  Timer? _arcadeTimer;
  int _arcadeCurrentPage = 0;
  int _uniqueTasksLength = 0;
  
  final AudioPlayer _audioPlayer = AudioPlayer();
  late ConfettiController _confettiController;

  bool get isAdmin =>
      FirebaseAuth.instance.currentUser?.uid == 'OeEwi4nMZrPjRLRiqWf1373btQT2';

  StreamSubscription<DocumentSnapshot>? _banListener;

  void _navigateToHistory() {
    AdManager.showSmartAd();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (c) => const HistoryScreen()),
    );
  }

  void _navigateToWithdraw(String? uid) {
    AdManager.showSmartAd();
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (c) => const WithdrawScreen()),
      );
    }
  }

  void _navigateToLeaderboard() {
    AdManager.showSmartAd();
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (c) => const LeaderboardScreen()),
      );
    }
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
          _banListener?.cancel();
          await FirebaseAuth.instance.signOut();

          if (!mounted) return;
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
    WidgetsBinding.instance.addObserver(this); // تفعيل مراقب حالة التطبيق
    
    _tabController = TabController(length: 3, vsync: this); // تهيئة متحكم التبويبات

    // تهيئة متحكم الأنيميشن
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _arcadePageController = PageController(initialPage: 0);
    _arcadeTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_arcadePageController.hasClients && _uniqueTasksLength > 0) {
        _arcadeCurrentPage++;
        _arcadePageController.animateToPage(
          _arcadeCurrentPage,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
        );
      }
    });

    // 1️⃣ أولاً: عمليات جلب البيانات الخفيفة والأساسية فوراً
    _startNetworkMonitoring();
    _startBanListener();
    _loadUserData();

    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _checkDailyRewardStatus(user.uid);

      // 🔄 الربط الحاسم لكولباك إغلاق الإعلانات
      AdManager.onAdClosedCallback = () {
        if (mounted) {
          setState(() {
            _unitySecondsLeft = 0;
          });
          Future.delayed(const Duration(milliseconds: 500), () {
            _syncCooldownFromFirebase(user.uid);
          });
        }
      };

      // ⏱️ فحص العدادات التنازلية القادمة من فايربيس بعد نصف ثانية فقط من الإقلاع
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _syncCooldownFromFirebase(user.uid);
      });
    }
    // 3️⃣ ثالثاً: ترحيل الخدمات البعيدة والإشعارات لتعمل بعد رسم الشاشة كلياً (PostFrameCallback)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkForUpdate(); // فحص تحديثات التطبيق السحابية بأمان

        // 💬 تأجيل خدمات الإشعارات المحلية الثقيلة لمدة (3 ثوانٍ) لتعمل بصمت في الخلفية
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) _initNotifications();
        });
      }
    });
  }

  void _checkForUpdate() async {
    try {
      // 1. جلب بيانات النسخة الحالية المثبتة على هاتف المستخدم
      PackageInfo packageInfo = await PackageInfo.fromPlatform();

      // ✅ الإصلاح الأول: نأخذ رقم الإصدار فقط ونحذف أي زيادة بعد علامة الـ + لضمان دقة المطابقة
      String localVersion = packageInfo.version.split('+')[0].trim();

      // 2. جلب إعدادات التحديث من الفايرستور
      var config = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      if (config.exists && config.data() != null) {
        var data = config.data()!;

        // ✅ الإصلاح الثاني: تحويل القيمة جلبها كـ String بشكل صارم لمنع تضارب الأنواع (Cast Error)
        String serverVersion =
            data['current_version']?.toString().trim() ?? "1.0.0";
        String updateUrl = data['update_url']?.toString() ?? "";
        bool isForceUpdate = data['force_update'] ?? false;

        debugPrint(
            "📱 Local Version: '$localVersion' | 🌐 Server Version: '$serverVersion' | 🔥 Force: $isForceUpdate");

        // 3. التحقق والمقارنة الشرطية المستقرة
        if (serverVersion != localVersion &&
            isForceUpdate &&
            updateUrl.isNotEmpty) {
          if (mounted) {
            _showUpdateDialog(updateUrl);
          }
        }
      }
    } catch (e) {
      // طباعة الخطأ في الـ Console إذا حدث أي خلل أثناء الفحص للتتبع
      debugPrint("❌ Crucial Update Check Error: $e");
    }
  }

  void _showUpdateDialog(String url) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
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
                  AdManager.showSmartAd();
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

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      debugPrint("خطأ في جلب البيانات: $e");
    }
  }

  void _startNetworkMonitoring() {
    Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) async {
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
    if (!mounted || _isVpnDialogShowing) return;
    _isVpnDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title:
              const Icon(Icons.security_rounded, color: Colors.red, size: 50),
          content: Text(
            tr('close_vpn'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                AdManager.showSmartAd();
                bool isVpnStillActive = await CheckVpnConnection.isVpnActive();
                if (!context.mounted) return;
                if (!isVpnStillActive) {
                  Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(tr('vpn_still_active'))));
                }
              },
              child: Text(tr('vpn_check_now')),
            ),
          ],
        ),
      ),
    ).then((_) {
      _isVpnDialogShowing = false;
    });
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
          setState(() => _unitySecondsLeft--); // إنقاص ثانية بثانية آلياً
        } else {
          timer.cancel();
          _sendTimeNotification(tr('reward_ready_server_1'));
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
          _sendTimeNotification(tr('reward_ready_admob'));
        }
      });
    }
  }

  // ✅ إصلاح دالة الـ Cooldown المركزية: أصبحت تُستدعى فقط عند التحقق الفعلي والناجح للمكافآت
  void _startCooldownWithFirebase(
      String server, String uid, int duration) async {
    DateTime networkTime = await NTP.now(); // جلب الوقت الحقيقي من الإنترنت
    DateTime endTime = networkTime.add(Duration(seconds: duration));

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      '${server}_cooldown_until': Timestamp.fromDate(endTime),
    }, SetOptions(merge: true));

    // تشغيل التايمر المحلي فوراً لتحديث الواجهة بصرياً أمام المستخدم
    _runTimer(server, duration);
  }

// ✅ مزامنة العداد التنازلي لسيرفر 1 وسيرفر 2 من الفايربيس بالكامل
  void _syncCooldownFromFirebase(String uid) async {
    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      final data = doc.data()!;

      for (String server in ["unity", "admob"]) {
        String key = '${server}_cooldown_until';

        if (data.containsKey(key) && data[key] != null) {
          Timestamp timestamp = data[key];
          DateTime endTime = timestamp.toDate();
          DateTime now = await NTP.now(); // جلب الوقت الحقيقي من الإنترنت للمقارنة

          if (endTime.isAfter(now)) {
            int remaining = endTime.difference(now).inSeconds;
            _runTimer(server, remaining); // تشغيل العداد التنازلي التناقصي
          } else {
            setState(() {
              if (server == "unity") {
                _unitySecondsLeft = 0;
              } else {
                _admobSecondsLeft = 0;
              }
            });
          }
        }
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: UniqueKey(),
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
                child: Text(message, style: const TextStyle(fontSize: 16))),
          ],
        ),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
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
              const FaIcon(FontAwesomeIcons.circleExclamation,
                  color: Colors.orange),
              const SizedBox(width: 10),
              Text(tr('limit_reached_title')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('limit_reached_desc'), textAlign: TextAlign.center),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  tr('limit_reached_reset'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.orange),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                AdManager.showSmartAd();
                Navigator.of(context).pop();
              },
              child: Text(tr('got_it'),
                  style: const TextStyle(color: Colors.blueAccent)),
            ),
          ],
        );
      },
    );
  }

  void _handleAdSelection({required String server, required int cooldown}) {
    if (_isAdProcessing) return;

    // ✅ التعديل: فحص الوقت يتم فقط إذا لم تكن أنت الأدمن
    if (!isAdmin) {
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
    }

    // إذا كنت أدمن، أو كان الوقت قد انتهى، سيستمر الكود إلى هنا:

    bool isRewarding = false;
    Future<void> onLuckyWheelReward(int points) async {
      if (isRewarding) return;
      isRewarding = true;
      final uid = FirebaseAuth.instance.currentUser!.uid;
      int safePoints = points.clamp(1, 10); // سد ثغرة تعديل الحزم لإرسال نقاط وهمية (يسمح فقط بـ 1 إلى 10)
      DateTime networkTime = await NTP.now();
      try {
        WriteBatch batch = FirebaseFirestore.instance.batch();

        DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(uid);
        batch.update(userRef, {
          'points': FieldValue.increment(safePoints),
          'points_history': FieldValue.arrayUnion([
            {
              'taskId': 'lucky_wheel_${networkTime.millisecondsSinceEpoch}',
              'amount': safePoints,
              'type': 'lucky_wheel_reward',
              'timestamp': networkTime.toIso8601String(),
            }
          ]),
        });

        DocumentReference taskRef = FirebaseFirestore.instance.collection('completed_tasks').doc();
        batch.set(taskRef, {
          'userId': uid,
          'taskType': 'lucky_wheel_reward',
          'rewardAmount': safePoints,
          'status': 'verified',
          'timestamp': FieldValue.serverTimestamp(),
        });

        await batch.commit();

        if (mounted) {
          _confettiController.play();
          _startCooldownWithFirebase(server, uid, cooldown);
          _audioPlayer.play(AssetSource('sounds/success.mp3')).catchError((_) {});
          _showSuccessSnackBar(tr('you_won_points', args: [safePoints.toString()]));
        }
      } catch (e) {
        if (mounted) {
          _showErrorSnackBar(tr('admob_connection_error'));
          setState(() {
            _isWaiting = false;
            _isAdProcessing = false;
          });
        }
      }
    }

    if (server == "unity") {
      AdManager.onVideoCompletedCallback = () {
        if (mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => LuckyWheelDialog(
              onRewardEarned: onLuckyWheelReward,
            ),
          );
        }
      };
      AdManager.showServer1Ad(context);
    } else {
      setState(() {
        _isAdProcessing = true;
        _isWaiting = true;
      });

      bool rewarded = false;
      Timer? adSafetyTimer;

      adSafetyTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) {
          setState(() {
            _isWaiting = false;
            _isAdProcessing = false;
          });
        }
      });

      AdManager.showAdMobVideo(
        onReward: () {
          rewarded = true;
        },
        onAdClosed: () {
          adSafetyTimer?.cancel();
          if (mounted) {
            setState(() {
              _isWaiting = false;
              _isAdProcessing = false;
            });
          }
          if (rewarded && mounted) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => LuckyWheelDialog(
                onRewardEarned: (points) {
                  onLuckyWheelReward(points);
                },
              ),
            );
          }
        },
        onFailed: () {
          adSafetyTimer?.cancel();
          if (mounted) {
            setState(() {
              _isWaiting = false;
              _isAdProcessing = false;
            });
          }
          _showErrorSnackBar(tr('admob_ad_not_ready'));
        },
      );
    }
  }

  Future<void> _initNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await flutterLocalNotificationsPlugin.initialize(
        settings: const InitializationSettings(android: android));

    // 1. إعدادات Firebase Messaging للإشعارات الفورية
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 2. طلب الصلاحيات (مهم جداً لنظام أندرويد 13+ و iOS)
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // 3. الاشتراك في مجموعة (Topic) ليتمكن الأدمن من إرسال إشعار للجميع
    await messaging.subscribeToTopic('all_users');

    // 4. استقبال الإشعارات والتطبيق مفتوح (Foreground)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          id: notification.hashCode,
          title: notification.title,
          body: notification.body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              'push_notifications_channel',
              tr('new_offers_notifications'),
              importance: Importance.max,
              priority: Priority.high,
              color: Color(0xFF4527A0),
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });
  }

  Future<void> _sendTimeNotification(String messageKey) async {
    final android = AndroidNotificationDetails(
      'reward_timer_id',
      tr('profits_alerts'),
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF4527A0),
      icon: '@mipmap/ic_launcher',
    );

    int notificationId = (await NTP.now()).millisecondsSinceEpoch ~/ 1000;

    await flutterLocalNotificationsPlugin.show(
      id: notificationId,
      title: tr('notification_reward_title'),
      body: tr(messageKey),
      notificationDetails: NotificationDetails(android: android),
    );
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    _audioPlayer.play(AssetSource('sounds/error.mp3')).catchError((_) {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        key: UniqueKey(),
        content: Text(message,
            style: const TextStyle(color: Colors.white, fontSize: 14)),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

// ✅ 1. فحص هل المستخدم يحق له المطالبة (يعتمد على حقل السلسلة النصية للتاريخ المحفوظ مسبقاً)
  Future<void> _checkDailyRewardStatus(String uid) async {
    try {
      // 🚀 استخدام توقيت UTC ليتطابق تماماً مع سيرفر فايربيس ويمنع أخطاء المنطقة الزمنية
      DateTime now = (await NTP.now()).toUtc(); // استخدام وقت الشبكة المشفر
      String todayStr = "${now.year}-${now.month}-${now.day}";

      final userDocRef =
          FirebaseFirestore.instance.collection('users').doc(uid);
      final doc = await userDocRef.get();

      if (doc.exists && doc.data() != null) {
        var data = doc.data()!;
        if (data.containsKey('last_claim_date_str') &&
            data['last_claim_date_str'] != null) {
          String lastClaimStr = data['last_claim_date_str'];
          if (mounted) {
            setState(() {
              // يحق له المطالبة إذا كان تاريخ اليوم مختلفاً عن تاريخ آخر مطالبة
              _canClaimDaily = lastClaimStr != todayStr;
            });
          }
          return;
        }
      }

      if (mounted) {
        setState(() {
          _canClaimDaily = true;
        });
      }
    } catch (_) {}
  }

  // ✅ 2. المطالبة بالمكافأة مباشرة من Cloud Function لتجنب PERMISSION_DENIED
  bool _isClaimingDaily = false;
  Future<void> _claimDailyReward() async {
    if (_isClaimingDaily) return;
    _isClaimingDaily = true;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _isClaimingDaily = false;
      return;
    }

    if (!_canClaimDaily) {
      _isClaimingDaily = false;
      DateTime now = (await NTP.now()).toUtc();
      DateTime nextMidnight = DateTime.utc(now.year, now.month, now.day + 1);
      Duration remaining = nextMidnight.difference(now);
      String formattedTime = "${remaining.inHours.toString().padLeft(2, '0')}:${(remaining.inMinutes % 60).toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}";
      _showErrorSnackBar("${tr('next_reward_waiting')} $formattedTime");
      return;
    }

    setState(() => _canClaimDaily = false);

    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator(color: Colors.amber)),
      ),
    );

    try {
      final token = await user.getIdToken(true);
      // 👇 استبدل هذا الرابط بالرابط الصحيح الذي ظهر لك بعد رفع الدالة بنجاح
      final uri = Uri.parse('https://claimdailyreward-aa24flr7jq-uc.a.run.app');

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({'uid': user.uid}),
          )
          .timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (response.statusCode == 200) {
        _isClaimingDaily = false;
        final Map<String, dynamic> data =
            jsonDecode(response.body) as Map<String, dynamic>;
        final int reward = (data['rewardAmount'] ?? 10).toInt();
          _confettiController.play();
          _audioPlayer.play(AssetSource('sounds/success.mp3')).catchError((_) {});
        await _checkDailyRewardStatus(user.uid);
        _showDailyRewardSuccessDialog(reward);
        return;
      }

      if (response.statusCode == 409) {
        _isClaimingDaily = false;
        await _checkDailyRewardStatus(user.uid);
        DateTime now = (await NTP.now()).toUtc();
        DateTime nextMidnight = DateTime.utc(now.year, now.month, now.day + 1);
        Duration remaining = nextMidnight.difference(now);
        String formattedTime = "${remaining.inHours.toString().padLeft(2, '0')}:${(remaining.inMinutes % 60).toString().padLeft(2, '0')}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')}";
        _showErrorSnackBar("${tr('next_reward_waiting')} $formattedTime");
        return;
      }

      if (response.statusCode == 401) {
        _isClaimingDaily = false;
        debugPrint("❌ مكافأة يومية - غير مصرح: ${response.body}");
        _showErrorSnackBar(tr('error_occurred'));
        return;
      }

      debugPrint(
          "❌ فشل استلام المكافأة! الكود: ${response.statusCode} | التفاصيل: ${response.body}");
      _isClaimingDaily = false;
      _showErrorSnackBar(
          "${tr('error_occurred')} (Code: ${response.statusCode})");
      if (mounted) setState(() => _canClaimDaily = true);
    } catch (e) {
      _isClaimingDaily = false;
      debugPrint("❌ استثناء في المكافأة اليومية: $e");
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) setState(() => _canClaimDaily = true);
      _showErrorSnackBar(tr('error_occurred'));
    }
  }

  void _showDailyRewardSuccessDialog(int points) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Icon(Icons.card_giftcard_rounded,
            color: Colors.amber, size: 60),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              tr('daily_reward'),
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 15),
            Text(
              "+$points",
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              tr('points'),
              style: const TextStyle(color: Colors.greenAccent, fontSize: 18),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () => Navigator.pop(ctx),
            child:
                Text(tr('got_it'), style: const TextStyle(color: Colors.black)),
          )
        ],
      ),
    );
  }

  Widget _buildMaintenanceScreen(String message) {
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
                message,
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
              onPressed: () {
                AdManager.showSmartAd();
              },
              child: Text(tr('waiting_update'),
                  style: const TextStyle(color: Colors.black)),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(String? uid, int exchangeRate) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu_rounded, size: 34),
                  color:
                      themeProvider.isDarkMode ? Colors.amber : Colors.black87,
                  onPressed: () {
                    AdManager.showSmartAd();
                    Scaffold.of(context).openDrawer();
                  },
                ),
              ),
              const SizedBox(width: 2),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        "Syria Earn",
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w900,
                          color: themeProvider.isDarkMode
                              ? Colors.white
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildSmallActionIcon(
                        icon: Icons.language,
                        color: themeProvider.isDarkMode
                            ? Colors.amber.withValues(alpha: 0.9)
                            : Colors.black54,
                        onPressed: () {
                          AdManager.showSmartAd();
                        },
                        isPopup: true,
                      ),
                      const SizedBox(width: 10),
                    ],
                  ),
                  Container(
                    height: 4,
                    width: 60,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ],
          ),
          InkWell(
            onTap: () => _navigateToWithdraw(uid),
            borderRadius: BorderRadius.circular(15),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3), width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.account_balance_wallet_rounded,
                    color: Colors.amber,
                    size: 30,
                  ),
                  const SizedBox(width: 0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

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
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$points",
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 45,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 10)]),
                ),
                Text(
                  "≈ \$${dollarValue.toStringAsFixed(2)}",
                  style: TextStyle(
                      color: Colors.greenAccent.withValues(alpha: 0.8),
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),

                // 1. الرسالة العالمية (Global Notification)
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('global_notifications')
                      .orderBy('timestamp', descending: true)
                      .limit(1)
                      .snapshots(),
                  builder: (context, notifSnap) {
                    if (!notifSnap.hasData || notifSnap.data!.docs.isEmpty) {
                      return const SizedBox(height: 10);
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

                const SizedBox(height: 8),

                // 2. 🔥 شريط سجل استلام النقاط الشخصي
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('completed_tasks')
                      .orderBy('timestamp', descending: true)
                      .limit(10)
                      .snapshots(),
                  builder: (context, tasksSnap) {
                    if (!tasksSnap.hasData || tasksSnap.data!.docs.isEmpty) {
                      return Container(
                        height: 38,
                        margin: const EdgeInsets.symmetric(horizontal: 25),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.02)),
                        ),
                        child: Center(
                          child: Text(
                            tr('welcome_back'),
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                        ),
                      );
                    }

                    List<DocumentSnapshot> uniqueTasks = [];
                    Set<String> seenDocIds = {};

                    for (var doc in tasksSnap.data!.docs) {
                      if (!seenDocIds.contains(doc.id)) {
                        seenDocIds.add(doc.id);
                        uniqueTasks.add(doc);
                      }
                      if (uniqueTasks.length == 10) break; // زيادة عدد الأخبار المعروضة
                    }

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _uniqueTasksLength = uniqueTasks.length;
                      }
                    });

                    return Container(
                      height: 38,
                      margin: const EdgeInsets.symmetric(horizontal: 25),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.02)),
                      ),
                      child: PageView.builder(
                        controller: _arcadePageController,
                        scrollDirection: Axis.vertical,
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (context, index) {
                          var taskData = uniqueTasks[index % uniqueTasks.length].data()
                              as Map<String, dynamic>;

                              String taskUid =
                                  taskData['userId'] ?? taskData['uid'] ?? '';

                              String timeAgo = tr('just_now');
                              if (taskData['timestamp'] != null) {
                                Timestamp timestamp = taskData['timestamp'];
                                DateTime taskTime = timestamp.toDate();
                                Duration diff =
                                    DateTime.now().difference(taskTime);

                                if (diff.inMinutes < 1) {
                                  timeAgo = tr('just_now');
                                } else if (diff.inMinutes < 60) {
                                  timeAgo =
                                      "${diff.inMinutes} ${tr('minutes_ago')}";
                                } else if (diff.inHours < 24) {
                                  timeAgo =
                                      "${diff.inHours} ${tr('hours_ago')}";
                                } else {
                                  timeAgo = "${diff.inDays} ${tr('days_ago')}";
                                }
                              }

                            String taskType = taskData['taskType'] ?? '';
                            String serverName = "";
                            FaIconData taskIcon = FontAwesomeIcons.star;
                            Color taskIconColor = Colors.amber;

                            if (taskType == 'admob_ad') {
                              serverName = tr('admob_payout');
                              taskIcon = FontAwesomeIcons.google;
                              taskIconColor = Colors.blueAccent;
                            } else if (taskType == 'server1_ad' || taskType == 'unity_ad') {
                              serverName = tr('unity_payout');
                              taskIcon = FontAwesomeIcons.gamepad;
                              taskIconColor = Colors.amber;
                            } else if (taskType == 'lucky_wheel_reward') {
                              serverName = tr('spin_wheel');
                              taskIcon = FontAwesomeIcons.dharmachakra;
                              taskIconColor = Colors.purpleAccent;
                            } else if (taskType == 'daily_reward') {
                              serverName = tr('daily_reward');
                              taskIcon = FontAwesomeIcons.gift;
                              taskIconColor = Colors.greenAccent;
                            } else if (taskType == 'offerwall_reward') {
                              serverName = tr('offerwall_reward');
                              taskIcon = FontAwesomeIcons.fire;
                              taskIconColor = Colors.orangeAccent;
                            } else if (taskType == 'referral_reward') {
                              serverName = tr('referral_reward');
                              taskIcon = FontAwesomeIcons.users;
                              taskIconColor = Colors.cyanAccent;
                            } else {
                              serverName = taskType;
                            }

                              int liveUnityPoints =
                                  (config['unity_points'] ?? 10).toInt();
                              int liveAdMobPoints =
                                  (config['admob_points'] ?? 10).toInt();
                            bool isAdMob = taskType == 'admob_ad';

                              int earnedPoints = (taskData['rewardAmount'] ??
                                    taskData['amount'] ??
                                      taskData['points'] ??
                                      (isAdMob
                                          ? liveAdMobPoints
                                          : liveUnityPoints))
                                  .toInt();

                              if (taskUid.trim().isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          FaIcon(
                                          taskIcon,
                                            size: 13,
                                          color: taskIconColor,
                                          ),
                                          const SizedBox(width: 8),
                                          RichText(
                                            text: TextSpan(
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'sans-serif'),
                                              children: [
                                                TextSpan(
                                                    text: "${tr('unknown_player')} ",
                                                    style: const TextStyle(
                                                        color: Colors.white70)),
                                                TextSpan(
                                                    text: "(+$earnedPoints) ",
                                                    style: const TextStyle(
                                                        color:
                                                            Colors.greenAccent,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                                TextSpan(
                                                    text: "($serverName)",
                                                    style: TextStyle(
                                                        color: Colors.white
                                                            .withValues(
                                                                alpha: 0.5))),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          Text(timeAgo,
                                              style: const TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 10)),
                                          const SizedBox(width: 6),
                                          const Icon(Icons.check_circle_outline,
                                              color: Colors.greenAccent,
                                              size: 12),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('users')
                                    .doc(taskUid)
                                    .get(),
                                builder: (context, userSnap) {
                                  String finalName = "...";

                                  if (userSnap.hasData &&
                                      userSnap.data!.exists) {
                                    var userData = userSnap.data!.data()
                                        as Map<String, dynamic>?;
                                    finalName = userData?['username'] ??
                                        userData?['name'] ??
                                        userData?['email']?.split('@')[0] ??
                                            tr('unknown_player');
                                  }

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            FaIcon(
                                            taskIcon,
                                              size: 13,
                                            color: taskIconColor,
                                            ),
                                            const SizedBox(width: 8),
                                            RichText(
                                              text: TextSpan(
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    fontFamily: 'sans-serif'),
                                                children: [
                                                  TextSpan(
                                                      text: "$finalName ",
                                                      style: const TextStyle(
                                                          color:
                                                              Colors.white70)),
                                                  TextSpan(
                                                      text: "(+$earnedPoints) ",
                                                      style: const TextStyle(
                                                          color: Colors
                                                              .greenAccent,
                                                          fontWeight:
                                                              FontWeight.bold)),
                                                  TextSpan(
                                                      text: "($serverName)",
                                                      style: TextStyle(
                                                          color: Colors.white
                                                              .withValues(
                                                                  alpha: 0.5))),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              timeAgo,
                                              style: const TextStyle(
                                                  color: Colors.white38,
                                                  fontSize: 10),
                                            ),
                                            const SizedBox(width: 6),
                                            const Icon(
                                                Icons.check_circle_outline,
                                                color: Colors.greenAccent,
                                                size: 12),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                    );
                  },
                ),

                const SizedBox(height: 5),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildVideoTab(int unityRemaining, int admobRemaining,
      int cooldownSeconds, int unityPoints, int admobPoints) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildVideoServerCard(
          title: tr('unity_payout'),
          sub: _unitySecondsLeft > 0
              ? "${tr('wait')} ${_formatTime(_unitySecondsLeft)}"
              : tr('lucky_wheel_prompt'), // "أدر العجلة واربح نقاطاً عشوائية!"
          icon: FontAwesomeIcons.gamepad,
          remaining: unityRemaining,
          isPremium: true,
          onTap: () {
            if (_unitySecondsLeft > 0 || _isWaiting || unityRemaining <= 0) {
              if (unityRemaining <= 0) _showLimitReachedDialog();
              return;
            }
            // 🌟 مررنا الـ cooldown الديناميكي هنا كما أصلحناه سابقاً
            _handleAdSelection(server: "unity", cooldown: cooldownSeconds);
          },
        ),
        const SizedBox(height: 20),
        _buildVideoServerCard(
          title: tr('admob_payout'),
          sub: _admobSecondsLeft > 0
              ? "${tr('wait')} ${_formatTime(_admobSecondsLeft)}"
              : tr('lucky_wheel_prompt'),
          icon: FontAwesomeIcons.google,
          remaining: admobRemaining,
          isPremium: false,
          onTap: () {
            if (_admobSecondsLeft > 0 || _isWaiting || admobRemaining <= 0) {
              if (admobRemaining <= 0) _showLimitReachedDialog();
              return;
            }
            _handleAdSelection(server: "admob", cooldown: cooldownSeconds);
          },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildVideoServerCard({
    required String title,
    required String sub,
    required dynamic icon,
    required VoidCallback onTap,
    required int remaining,
    bool isPremium = false,
  }) {
    return Card(
      color: const Color(0xFF1E1E2E),
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
            const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
        leading: ShaderMask(
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: isPremium
                ? [Colors.amber, Colors.orangeAccent]
                : [Colors.blueAccent, Colors.cyanAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: FaIcon(icon, color: Colors.white, size: 50),
        ),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 22)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Text(sub,
                style: const TextStyle(color: Colors.white70, fontSize: 15)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: remaining > 0
                    ? Colors.green.withValues(alpha: 0.2)
                    : Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                "${tr('remaining')}: $remaining",
                style: TextStyle(
                  color: remaining > 0 ? Colors.greenAccent : Colors.redAccent,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SpinningWheelIcon(),
            const SizedBox(height: 5),
            const Text(
              "1 ~ 10",
              style: TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 14),
            ),
          ],
        ),
        onTap: remaining > 0 ? onTap : null,
      ),
    );
  }

  Widget _buildOffersTab(bool hasRated) {
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
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const OffersWallWidget()),
              );
            },
            isPremium: true,
          ),
          const SizedBox(height: 12),
          _buildTaskCard(
            hasRated ? tr('rated_thanks') : tr('rate_app_title'),
            hasRated ? "" : tr('rate_app_sub'),
            25,
            Icons.stars_rounded,
            hasRated
                ? () {}
                : () async {
                    const String url =
                        "https://play.google.com/store/apps/details?id=com.mohamad.syria_earn";
                    final Uri uri = Uri.parse(url);
                    try {
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                        if (mounted) {
                          _showFakeVerificationDialog();
                        }
                      }
                    } catch (e) {
                      debugPrint("Error: $e");
                      if (mounted) _showErrorSnackBar(tr('error_occurred'));
                    }
                  },
            isPremium: !hasRated,
          ),
        ],
      ),
    );
  }

  Widget _buildSocialMediaTab(Map<String, dynamic> userData) {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(20),
      mainAxisSpacing: 20,
      crossAxisSpacing: 20,
      children: [
        _buildSocialIconCard(tr('youtube'), FontAwesomeIcons.youtube, Colors.red, () => _goToSocialMediaScreen(0)),
        _buildSocialIconCard(tr('instagram'), FontAwesomeIcons.instagram, Colors.purpleAccent, () => _goToSocialMediaScreen(1)),
        _buildSocialIconCard(tr('facebook'), FontAwesomeIcons.facebook, Colors.blue, () => _goToSocialMediaScreen(2)),
        _buildSocialIconCard(tr('other_platforms'), Icons.more_horiz, Colors.orange, () => _goToSocialMediaScreen(3)),
      ],
    );
  }

  void _goToSocialMediaScreen(int index) {
    AdManager.showSmartAd();
    Navigator.push(context, MaterialPageRoute(builder: (_) => SocialMediaScreen(initialTabIndex: index)));
  }

  Widget _buildSocialIconCard(String title, dynamic icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 1),
          ]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon.fontPackage == 'font_awesome_flutter'
                ? FaIcon(icon, size: 50, color: color)
                : Icon(icon, size: 50, color: color),
            const SizedBox(height: 15),
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  void _showFakeVerificationDialog() {
    int countdown = 60;
    Timer? timer;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            // ✅ تم تغيير الاسم هنا ليكون دقيقاً لبيئة الدايلوج

            // تهيئة المؤقت بشكل آمن يضمن الإغلاق التلقائي دون تضارب الذاكرة
            timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
              // 🛡️ فحص حرج: التأكد أن نافذة الدايلوج ما زالت مفتوحة ونشطة في الشاشة الآن
              if (!dialogContext.mounted) {
                t.cancel();
                return;
              }

              if (countdown > 0) {
                setDialogState(() => countdown--);
              } else {
                t.cancel();
                // المتابعة بأمان وإغلاق النافذة من سياقها الخاص
                _finalizeRatingPoints(dialogContext);
              }
            });

            return PopScope(
              canPop: false,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
              },
              child: AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Colors.amber, width: 1),
                ),
                title: Row(
                  children: [
                    const Icon(Icons.verified_user_rounded,
                        color: Colors.amber),
                    const SizedBox(width: 10),
                    Text(
                      tr('verifying'),
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
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
                          tr('click_here_to_rate'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.blueAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
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
    ).then((_) {
      // 🛡️ إيقاف مؤكد للمؤقت عند خروج الشاشة بأي شكل لمنع تسريب الذاكرة (Memory Leak)
      timer?.cancel();
    });
  }

  void _finalizeRatingPoints(BuildContext dialogContext) async {
    String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) return;

    try {
      // 1. نقوم بإغلاق نافذة الـ Dialog أولاً بشكل آمن لفك الارتباط بالواجهة
      if (dialogContext.mounted) {
        Navigator.pop(dialogContext);
      }

      // تحقق حاسم من السيرفر: منع استغلال الدالة لأكثر من مرة عبر الهندسة العكسية
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>? ?? {};
      if (userData['has_rated_app'] == true) return;

      // 2. نقوم بتحديث البيانات سحابياً في الخلفية بأمان
      DateTime networkTime = await NTP.now();
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'has_rated_app': true,
        'points': FieldValue.increment(25),
        'points_history': FieldValue.arrayUnion([
          {
            'type': 'rate_app_bonus',
            'amount': 25,
            'timestamp': networkTime.toIso8601String(),
          }
        ])
      });

      // 3. نتحقق من الشاشة الرئيسية الخلفية قبل إظهار رسالة النجاح للمستخدم
      if (!mounted) return;
      _confettiController.play();
      _audioPlayer.play(AssetSource('sounds/success.mp3')).catchError((_) {});
      _showSuccessSnackBar("${tr('success_rate')} 25 ${tr('points')}");
    } catch (e) {
      debugPrint("Error finalizing points: $e");
      // في حالة حدوث خطأ شبكة غير متوقع، نكتفي بالتنبيه دون انهيار الواجهة
      if (mounted) {
        _showErrorSnackBar(tr('error_occurred'));
      }
    }
  }

  Widget _buildAppDrawer(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Drawer(
      backgroundColor: const Color(0xFF1A1A2E),
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(color: Colors.amber),
            currentAccountPicture: CircleAvatar(
              backgroundColor: const Color(0xFF1A1A2E),
              backgroundImage:
                  user?.photoURL != null ? NetworkImage(user!.photoURL!) : null,
              child: user?.photoURL == null
                  ? const Icon(Icons.person, size: 45, color: Colors.amber)
                  : null,
            ),
            accountName: Text(
              user?.displayName ?? tr('user_name_placeholder'),
              style: const TextStyle(
                  color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(user?.email ?? "",
                style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 12)),
          ),
          _drawerItem(
            icon: Icons.card_giftcard_rounded,
            title: tr('daily_reward'),
            subtitle:
                _canClaimDaily ? tr('reward_available') : tr('reward_claimed'),
            onTap: () {
              Navigator.of(context).pop();
              Future.microtask(() {
                if (mounted) _claimDailyReward();
              });
            },
            showBadge: _canClaimDaily,
          ),
          const Divider(color: Colors.white10, indent: 20, endIndent: 20),
          _drawerItem(
            icon: Icons.history_rounded,
            title: tr('points_history'),
            subtitle: tr('points_history_desc'),
            onTap: () {
              Navigator.pop(context);
              _navigateToHistory();
            },
          ),
          _drawerItem(
            icon: Icons.emoji_events_outlined,
            title: tr('leaderboard_title'),
            subtitle: tr('leaderboard_desc'),
            onTap: () {
              Navigator.pop(context);
              _navigateToLeaderboard();
            },
          ),
          _drawerItem(
            icon: Icons.settings_suggest_outlined,
            title: tr('settings_title'),
            subtitle: tr('settings_desc'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/settings');
            },
          ),
          const Spacer(),
          _drawerItem(
            icon: Icons.logout_rounded,
            title: tr('logout_title'),
            subtitle: tr('logout_desc'),
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildSmallActionIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
    bool isPopup = false,
  }) {
    return isPopup
        ? PopupMenuButton<String>(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(icon, size: 24, color: color),
            onSelected: (String langCode) async {
              await EasyLocalization.of(context)?.setLocale(Locale(langCode));
              if (mounted) setState(() {});
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'ar', child: Text("العربية")),
              const PopupMenuItem(value: 'en', child: Text("English")),
              const PopupMenuItem(value: 'es', child: Text("Español")),
              const PopupMenuItem(value: 'tr', child: Text("Türkçe")),
              const PopupMenuItem(value: 'hi', child: Text("हिन्दी")),
            ],
          )
        : IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(icon, size: 24, color: color),
            onPressed: () {
              AdManager.showSmartAd();
              onPressed();
            },
          );
  }

  Widget _drawerItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool showBadge = false,
  }) {
    return ListTile(
      leading: Stack(
        children: [
          Icon(icon, color: Colors.amber, size: 28),
          if (showBadge)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: const Color(0xFF1A1A2E), width: 1.5),
                ),
              ),
            ),
        ],
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 11)),
      onTap: onTap,
    );
  }

  Widget _buildTaskCard(
      String title, String sub, int pts, dynamic icon, VoidCallback action,
      {bool isPremium = false}) {
    return Card(
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color:
              isPremium ? Colors.amber.withValues(alpha: 0.5) : Colors.white10,
        ),
      ),
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        leading: ShaderMask(
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: isPremium
                ? [Colors.amber, Colors.orangeAccent, Colors.yellowAccent]
                : [Colors.blueAccent, Colors.cyanAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: icon.fontPackage != 'font_awesome_flutter'
              ? Icon(icon, color: Colors.white, size: 46)
              : FaIcon(icon, color: Colors.white, size: 46),
        ),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
                letterSpacing: 0.5)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(sub,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 15, height: 1.4)),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border:
                Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
          ),
          child: Text("+$pts",
              style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 20)),
        ),
        onTap: action,
      ),
    );
  }

  Widget _buildUpcomingRewardItem({
    required dynamic icon,
    required String title,
    required bool isReady,
    required String readyText,
    required String waitingText,
    required VoidCallback onTap,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    // Use FaIcon for FontAwesome icons and Icon for Material icons.
    final Widget iconWidget = (icon.fontPackage == 'font_awesome_flutter')
        ? FaIcon(icon, color: isReady ? Colors.amber : Colors.grey, size: 20)
        : Icon(icon, color: isReady ? Colors.amber : Colors.grey, size: 24);
    return GestureDetector(
      onTap: isReady ? onTap : null,
      child: Container(
        width: 130,
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: themeProvider.isDarkMode
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isReady
                ? Colors.amber.withValues(alpha: 0.4)
                : Colors.transparent,
            width: 1,
          ),
          boxShadow: themeProvider.isDarkMode
              ? []
              : [
                  const BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2))
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconWidget,
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: themeProvider.isDarkMode
                    ? Colors.white
                    : Colors.black87,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              isReady ? readyText : waitingText,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isReady
                    ? Colors.greenAccent
                    : (themeProvider.isDarkMode
                        ? Colors.white54
                        : Colors.black54),
                fontSize: 10,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpcomingRewards() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 2.0),
          child: Text(
            tr('upcoming_opportunities'),
            style: TextStyle(
              color: themeProvider.isDarkMode ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 15),
            children: [
              _buildUpcomingRewardItem(
                icon: Icons.card_giftcard_rounded,
                title: tr('daily_reward'),
                isReady: _canClaimDaily,
                readyText: tr('reward_available'),
                waitingText: tr('claimed_today'),
                onTap: _claimDailyReward,
              ),
              _buildUpcomingRewardItem(
                icon: FontAwesomeIcons.gamepad,
                title: tr('unity_payout'), // Server 1
                isReady: _unitySecondsLeft <= 0,
                readyText: tr('ready_to_watch'),
                waitingText: "${tr('wait')} ${_formatTime(_unitySecondsLeft)}",
                onTap: () => _tabController.animateTo(0),
              ),
              _buildUpcomingRewardItem(
                icon: FontAwesomeIcons.google,
                title: tr('admob_payout'), // Server 2
                isReady: _admobSecondsLeft <= 0,
                readyText: tr('ready_to_watch'),
                waitingText: "${tr('wait')} ${_formatTime(_admobSecondsLeft)}",
                onTap: () => _tabController.animateTo(0),
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
      ],
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _confettiController.dispose();
    WidgetsBinding.instance.removeObserver(this); // إزالة المراقب
    _banListener?.cancel();
    _unityTimer?.cancel();
    _admobTimer?.cancel();
    _arcadeTimer?.cancel();
    _arcadePageController.dispose();
    _controller.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    Color unselectedTabColor =
        themeProvider.isDarkMode ? Colors.white54 : Colors.black45;
    Color indicatorColor = Colors.amber;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .snapshots(),
      builder: (context, configSnapshot) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (!configSnapshot.hasData || !userSnapshot.hasData) {
              return Scaffold(
                backgroundColor: themeProvider.isDarkMode
                    ? Colors.black
                    : const Color(0xFFF5F7FA),
                body: const Center(
                    child: CircularProgressIndicator(color: Colors.amber)),
              );
            }

            final userData =
                userSnapshot.data?.data() as Map<String, dynamic>? ?? {};
            final bool hasRated = userData['has_rated_app'] ?? false;

            final config =
                configSnapshot.data?.data() as Map<String, dynamic>? ?? {};
            final int unitypoints = config['unity_points'] ?? 10;
            final int admobpoints = config['admob_points'] ??
                10; // مزامنة أرباح أدموب لتصبح 10 نقاط كاملة
            final int cooldownSeconds = config['video_cooldown_seconds'] ?? 300;
            final int unityDailyLimit = config['unity_daily_limit'] ?? 20;
            final int admobDailyLimit = config['admob_daily_limit'] ?? 20;

            final int currentExchangeRate = config['exchange_rate'] ?? 1000;
            final bool isUnderMaintenance =
                config['under_maintenance'] ?? false;
            final String maintenanceMsg =
                config['maintenance_message'] ?? tr('maintenance_msg_default');

            final List<dynamic> history = userData['points_history'] ?? [];
            final DateTime now = DateTime.now();

            int unityWatched = history.where((item) {
              final rawTimestamp = item['timestamp'];
              if (rawTimestamp == null || item['type'] != 'unity_ad') {
                return false;
              }
              final DateTime timestamp = (rawTimestamp is Timestamp)
                  ? rawTimestamp.toDate()
                  : DateTime.parse(rawTimestamp);
              return timestamp.year == now.year &&
                  timestamp.month == now.month &&
                  timestamp.day == now.day;
            }).length;

            int admobWatched = history.where((item) {
              final rawTimestamp = item['timestamp'];
              if (rawTimestamp == null || item['type'] != 'admob_ad') {
                return false;
              }
              final DateTime timestamp = (rawTimestamp is Timestamp)
                  ? rawTimestamp.toDate()
                  : DateTime.parse(rawTimestamp);
              return timestamp.year == now.year &&
                  timestamp.month == now.month &&
                  timestamp.day == now.day;
            }).length;

            int unityRemaining =
                (unityDailyLimit - unityWatched).clamp(0, unityDailyLimit);
            int admobRemaining =
                (admobDailyLimit - admobWatched).clamp(0, admobDailyLimit);

            if (isUnderMaintenance) {
              return _buildMaintenanceScreen(maintenanceMsg);
            }

            return FadeTransition(
              opacity: _animation,
              child: Scaffold(
                drawer: _buildAppDrawer(context),
                  body: Stack(
                    children: [
                      Container(
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
                        _buildUpcomingRewards(),
                        TabBar(
                          controller: _tabController,
                          indicatorColor: indicatorColor,
                          labelColor: indicatorColor,
                          unselectedLabelColor: unselectedTabColor,
                          tabs: [
                            Tab(
                                icon: const Icon(Icons.play_circle_fill),
                                text: tr('video_server')),
                            Tab(
                                icon: const Icon(Icons.grid_view_rounded),
                                text: tr('offers')),
                            Tab(
                                icon: const Icon(Icons.connect_without_contact_rounded),
                                text: tr('social_media')),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              SingleChildScrollView(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 15),
                                child: _buildVideoTab(
                                    unityRemaining,
                                    admobRemaining,
                                    cooldownSeconds,
                                    unitypoints,
                                    admobpoints),
                              ),
                              _buildOffersTab(hasRated),
                              _buildSocialMediaTab(userData),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                      ),
                      Align(
                        alignment: Alignment.topCenter,
                        child: ConfettiWidget(
                          confettiController: _confettiController,
                          blastDirectionality: BlastDirectionality.explosive,
                          emissionFrequency: 0.05,
                          numberOfParticles: 40,
                          gravity: 0.2,
                          colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
                        ),
                      ),
                    ],
                  ),
              ),
            );
          },
        );
      },
    );
  }
}

// ✅ ودجت منفصلة وخفيفة لتدوير الأيقونة بشكل لا نهائي
class SpinningWheelIcon extends StatefulWidget {
  const SpinningWheelIcon({super.key});

  @override
  State<SpinningWheelIcon> createState() => _SpinningWheelIconState();
}

class _SpinningWheelIconState extends State<SpinningWheelIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4), // 👈 يمكنك تغيير الرقم لتسريع أو إبطاء الدوران
    )..repeat(); // 👈 أمر بالدوران المستمر
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: const FaIcon(
        FontAwesomeIcons.dharmachakra,
        color: Colors.purpleAccent,
        size: 26,
      ),
    );
  }
}
