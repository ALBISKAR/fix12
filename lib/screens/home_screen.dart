import 'dart:async';
import 'package:provider/provider.dart';
import 'package:syria_earn_pro/providers/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:syria_earn_pro/screens/history_screen.dart';
import 'package:syria_earn_pro/screens/offers_tab_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:syria_earn_pro/screens/withdraw_screen.dart';
import 'package:syria_earn_pro/screens/leaderboard_screen.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:check_vpn_connection/check_vpn_connection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
// ✅ استيراد ملف خدمة Start.io (سيرفر 1) الجديد

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
  int unityRewardPoints = 10;
  int admobRewardPoints = 10;
  Timer? _unityTimer;
  Timer? _admobTimer;

  bool _canClaimDaily = false;

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

    // 1️⃣ أولاً: عمليات جلب البيانات الخفيفة والأساسية فوراً
    _startNetworkMonitoring();
    _startBanListener();
    _loadUserData();

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _checkDailyRewardStatus(user.uid);
      _setupPointsStream();

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

      // 🌐 السيرفر 1 (Start.io): تأجيل تهيئة وتحميل أول فيديو لمدة (ثانية واحدة)
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          AdManager.initialize(); // تهيئة المحركات الشاملة (أدموب + Start.io)
          AdManager.loadServer1Ad(); // بدء جلب كائن الفيديو لسيرفر 1
          debugPrint("⚡ [سيرفر 1]: تم بدء التهيئة والتحميل بنجاح بعد ثانية.");
        }
      });

      // 🔔 إعلان فتح التطبيق (App Open): تأجيل العرض حتى تستقر الشاشة تماماً بعد (ثانيتين)
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          AdManager.showAppOpenAdOnce();
          debugPrint(
              "⚡ [إعلان الفتح]: تم بدء طلب إعلان فتح التطبيق بعد ثانيتين.");
        }
      });
    }

    // 2️⃣ ثانياً: تهيئة الـ الانيميشن والـ Controllers الخاصة بالواجهة فوراً لمنع أي تجميد
    _controller = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();

    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging && mounted) {
        HapticFeedback.selectionClick();
        AdManager.showSmartAd();
      }
    });

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
            totalPoints = (snapshot.data())?['points'] ?? 0;
          });
        }
      }, onError: (error) {
        debugPrint("📡 Stream Error: $error");
      });
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!mounted) return;

        if (userDoc.exists) {
          setState(() {
            totalPoints =
                (userDoc.data() as Map<String, dynamic>?)?['points'] ?? 0;
          });
        }
      } else {
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
    if (!mounted) return;

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
    );
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
    DateTime endTime = DateTime.now().add(Duration(seconds: duration));

    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      '${server}_cooldown_until': Timestamp.fromDate(endTime),
      'login_lock_until':
          Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1))),
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
          DateTime now = DateTime.now(); // ستتم المقارنة وتحديث التايمر المستقل

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

// ✅ التعديل الحاسم: جعل الـ cooldown يستقبل القيمة السحابية القادمة من الـ StreamBuilder مباشرة دون قيم افتراضية ثابتة داخل الكود
  void _handleAdSelection({required String server, required int cooldown}) {
    if (_isAdProcessing) return;

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

    if (server == "unity") {
      // 🚀 تشغيل وعرض إعلان سيرفر 1 (Start.io) الجديد فوراً عند النقر
      AdManager.showServer1Ad(context);
    } else {
      setState(() {
        _isAdProcessing = true;
        _isWaiting = true;
      });
      _startWaitingTimer();

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
              // ✅ تمرير المتغير السحابي الديناميكي هنا أيضاً لـ AdMob
              _startCooldownWithFirebase(
                  "admob", FirebaseAuth.instance.currentUser!.uid, cooldown);
              _showSuccessSnackBar(tr('admob_request_success'));
            }
          } catch (e) {
            _showErrorSnackBar(tr('admob_connection_error'));
          } finally {
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
          _showErrorSnackBar(tr('admob_ad_not_ready'));
        },
      );
    }
  }

  void _initNotifications() {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    flutterLocalNotificationsPlugin.initialize(
        settings: const InitializationSettings(android: android));
  }

  Future<void> _sendTimeNotification(String messageKey) async {
    const android = AndroidNotificationDetails(
      'reward_timer_id',
      'تنبيهات الأرباح',
      importance: Importance.max,
      priority: Priority.high,
      color: Color(0xFF4527A0),
      icon: '@mipmap/ic_launcher',
    );

    int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    await flutterLocalNotificationsPlugin.show(
      id: notificationId,
      title: tr('notification_reward_title'),
      body: tr(messageKey),
      notificationDetails: const NotificationDetails(android: android),
    );
  }

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    return "${twoDigits(duration.inHours)}:${twoDigits(duration.inMinutes.remainder(60))}:${twoDigits(duration.inSeconds.remainder(60))}";
  }

  void _startWaitingTimer() {
    _secondsRemaining = 15;
    setState(() {
      _isWaiting = true;
    });

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
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

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
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

  Future<DateTime?> _getStrictNetworkTime() async {
    try {
      final response = await http
          .get(Uri.parse('https://worldtimeapi.org/api/timezone/Etc/UTC'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DateTime.parse(data['utc_datetime']);
      }
    } catch (_) {}

    try {
      final response = await http
          .get(Uri.parse(
              'https://timeapi.io/api/Time/current/zone?timeZone=UTC'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DateTime.parse(data['dateTime']);
      }
    } catch (_) {}

    return null;
  }

  void _claimDailyReward() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('verifying_network_time')),
          duration: const Duration(milliseconds: 800),
        ),
      );

      DateTime? networkTime = await _getStrictNetworkTime();

      if (networkTime == null) {
        _showErrorSnackBar(tr('network_time_error'));
        return;
      }

      final userDocRef =
          FirebaseFirestore.instance.collection('users').doc(user.uid);
      final doc = await userDocRef.get();

      if (doc.exists && doc.data() != null) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        int currentStreak = data['streak_count'] ?? 0;
        if (currentStreak >= 7) {
          currentStreak = 0;
        }

        if (data.containsKey('last_daily_claim')) {
          Timestamp lastClaimTimestamp = data['last_daily_claim'];
          DateTime lastClaimDate = lastClaimTimestamp.toDate();

          DateTime eligibleTime = lastClaimDate.add(const Duration(days: 1));

          if (networkTime.isBefore(eligibleTime)) {
            Duration realRemaining = eligibleTime.difference(networkTime);

            _showErrorSnackBar(
                "${tr('next_reward_waiting')} ${_formatDuration(realRemaining)}");
            return;
          }
        }

        await userDocRef.set({
          'last_security_timestamp': Timestamp.fromDate(networkTime),
        }, SetOptions(merge: true));

        _showRewardDialog(
            user.uid, currentStreak, true, Duration.zero, networkTime);
      }
    } catch (e) {
      _showErrorSnackBar(tr('error_occurred'));
    }
  }

  Future<void> _processDailyReward(String uid, int rewardAmount,
      int currentStreak, DateTime networkTime) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      String todayStr =
          "${networkTime.year}-${networkTime.month}-${networkTime.day}";

      int nextStreak = (currentStreak >= 6) ? 0 : currentStreak + 1;

      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'points': FieldValue.increment(rewardAmount),
        'streak_count': nextStreak,
        'last_claim_date_str': todayStr,
        'last_daily_claim': Timestamp.fromDate(networkTime),
        'last_security_timestamp': Timestamp.fromDate(networkTime),
        'points_history': FieldValue.arrayUnion([
          {
            'type': 'daily_reward_claim',
            'amount': rewardAmount,
            'timestamp': Timestamp.fromDate(networkTime),
          }
        ])
      });

      _checkDailyRewardStatus(uid);

      if (!mounted) return;
      HapticFeedback.mediumImpact();

      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text(tr('reward_processing_msg')),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackBar(tr('withdraw_error'));
    }
  }

  void _checkDailyRewardStatus(String uid) async {
    try {
      DateTime now = DateTime.now();
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

  void _showRewardDialog(String uid, int streak, bool canClaim,
      Duration remaining, DateTime networkTime) {
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
                  if (context.mounted) {
                    setDialogState(() {
                      liveRemaining =
                          liveRemaining - const Duration(seconds: 1);
                    });
                  }
                } else {
                  if (context.mounted) {
                    setDialogState(() {
                      canClaim = true;
                    });
                  }
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
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(canClaim ? Icons.card_giftcard : Icons.timer_outlined,
                        color: Colors.amber, size: 50),
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
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 15),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: List.generate(7, (index) {
                          bool isPast = index < streak;
                          bool isCurrent = index == streak;
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            padding: const EdgeInsets.all(8),
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
                            AdManager.showSmartAd();
                            timer?.cancel();
                            Navigator.pop(ctx);

                            if (!mounted) return;
                            int rewardAmount = 10 + (streak * 5);
                            await _processDailyReward(
                                uid, rewardAmount, streak, networkTime);
                          },
                          child: Text(tr('claim_reward_now')),
                        )
                      : TextButton(
                          onPressed: () {
                            AdManager.showSmartAd();
                            timer?.cancel();
                            Navigator.pop(ctx);
                          },
                          child: Text(tr('close'),
                              style: const TextStyle(color: Colors.white54)),
                        ),
                ),
              ],
            );
          },
        );
      },
    ).then((_) => timer?.cancel());
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 15),
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
    final PageController arcadePageController = PageController(initialPage: 0);
    int arcadeCurrentPage = 0;
    Timer? arcadeTimer;

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
                      fontSize: 60,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(color: Colors.black45, blurRadius: 10)]),
                ),
                Text(
                  "≈ \$${dollarValue.toStringAsFixed(2)}",
                  style: TextStyle(
                      color: Colors.greenAccent.withValues(alpha: 0.8),
                      fontSize: 18,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 15),

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

                const SizedBox(height: 15),

                // 2. 🔥 شريط سجل استلام النقاط الحركي المستقر
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('completed_tasks')
                      .orderBy('timestamp', descending: true)
                      .limit(10)
                      .snapshots(),
                  builder: (context, tasksSnap) {
                    if (!tasksSnap.hasData || tasksSnap.data!.docs.isEmpty) {
                      return Container(
                        height: 42,
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
                      if (uniqueTasks.length == 5) break;
                    }

                    return StatefulBuilder(
                      builder: (context, setLocalState) {
                        if (arcadeTimer == null || !arcadeTimer!.isActive) {
                          arcadeTimer =
                              Timer.periodic(const Duration(seconds: 2), (t) {
                            if (arcadePageController.hasClients) {
                              arcadeCurrentPage =
                                  (arcadeCurrentPage + 1) % uniqueTasks.length;
                              arcadePageController.animateToPage(
                                arcadeCurrentPage,
                                duration: const Duration(milliseconds: 400),
                                curve: Curves.easeInOut,
                              );
                              setLocalState(() {});
                            } else {
                              t.cancel();
                            }
                          });
                        }

                        return Container(
                          height: 42,
                          margin: const EdgeInsets.symmetric(horizontal: 25),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.02)),
                          ),
                          child: PageView.builder(
                            controller: arcadePageController,
                            itemCount: uniqueTasks.length,
                            scrollDirection: Axis.vertical,
                            physics: const NeverScrollableScrollPhysics(),
                            itemBuilder: (context, index) {
                              var taskData = uniqueTasks[index].data()
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

                              bool isAdMob = taskData['taskType'] == 'admob_ad';
// ✅ فحص دقيق لنوع المهمة وعرض الترجمة المناسبة حسب ما هو مخزن في الفايربيس
                              String serverName = "";
                              if (taskData['taskType'] == 'admob_ad') {
                                serverName = tr(
                                    'admob_payout'); // يعرض "سيرفر 2" أو الاسم المترجم لأدموب
                              } else if (taskData['taskType'] == 'server1_ad' ||
                                  taskData['taskType'] == 'unity_ad') {
                                serverName = tr(
                                    'unity_payout'); // يعرض "سيرفر 1" المترجم الخاص بـ Start.io
                              } else {
                                serverName = taskData['taskType'] ??
                                    ""; // أي نوع مهمة أخرى كالعروض
                              }

// 1. استخراج القيم من الفايربيس (تأكد من مطابقة أسماء الحقول في Firebase)
                              int liveUnityPoints =
                                  (config['unity_points'] ?? 10).toInt();
                              int liveAdMobPoints =
                                  (config['admob_points'] ?? 10).toInt();

// 3. التحديد الديناميكي للنقاط
                              int earnedPoints = (taskData['rewardAmount'] ??
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
                                            isAdMob
                                                ? FontAwesomeIcons.google
                                                : FontAwesomeIcons.gamepad,
                                            size: 13,
                                            color: isAdMob
                                                ? Colors.blueAccent
                                                : Colors.amber,
                                          ),
                                          const SizedBox(width: 8),
                                          RichText(
                                            text: TextSpan(
                                              style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  fontFamily: 'sans-serif'),
                                              children: [
                                                const TextSpan(
                                                    text: "Player ",
                                                    style: TextStyle(
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
                                        "Player";
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
                                              isAdMob
                                                  ? FontAwesomeIcons.google
                                                  : FontAwesomeIcons.gamepad,
                                              size: 13,
                                              color: isAdMob
                                                  ? Colors.blueAccent
                                                  : Colors.amber,
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

  Widget _buildVideoTab(int unityRemaining, int admobRemaining,
      int cooldownSeconds, int unityPoints, int admobPoints) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildVideoServerCard(
          title: tr('unity_payout'),
          // ✅ تم جعل الوصف قابلاً للترجمة ويمرر النقاط الديناميكية بشكل صحيح
          sub: _unitySecondsLeft > 0
              ? "${tr('wait')} ${_formatTime(_unitySecondsLeft)}"
              : tr('watch_video_earn', args: [unityPoints.toString()]),
          points: unityPoints,
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
          // ✅ تم تطبيق نفس الشيء لسيرفر أدموب
          sub: _admobSecondsLeft > 0
              ? "${tr('wait')} ${_formatTime(_admobSecondsLeft)}"
              : tr('watch_video_earn', args: [admobPoints.toString()]),
          points: admobPoints,
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
            const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        leading: ShaderMask(
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: isPremium
                ? [Colors.amber, Colors.orangeAccent]
                : [Colors.blueAccent, Colors.cyanAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: FaIcon(icon as FaIconData?, color: Colors.white, size: 42),
        ),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            Text(sub,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
                _finalizeRatingPoints(ctx);
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
    ).then((_) => timer?.cancel());
  }

  void _finalizeRatingPoints(BuildContext dialogContext) async {
    String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) return;

    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'has_rated_app': true,
        'points': FieldValue.increment(25),
        'points_history': FieldValue.arrayUnion([
          {
            'type': 'rate_app_bonus',
            'amount': 25,
            'timestamp': DateTime.now().toIso8601String(),
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
              Navigator.pop(context);
              _claimDailyReward();
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
      String title, String sub, int pts, IconData icon, VoidCallback action,
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
                letterSpacing: 0.5)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(sub,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 14, height: 1.3)),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  fontSize: 17)),
        ),
        onTap: action,
      ),
    );
  }

  @override
  void dispose() {
    _banListener?.cancel();
    _unityTimer?.cancel();
    _admobTimer?.cancel();
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
                                    unitypoints,
                                    admobpoints),
                              ),
                              _buildOffersTab(hasRated),
                            ],
                          ),
                        ),
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
}
