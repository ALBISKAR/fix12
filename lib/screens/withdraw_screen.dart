import 'package:logger/logger.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:syria_earn_pro/utils/security_utils.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:check_vpn_connection/check_vpn_connection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class WithdrawScreen extends StatefulWidget {
  const WithdrawScreen({super.key});

  @override
  State<WithdrawScreen> createState() => _WithdrawScreenState();
}

class _WithdrawScreenState extends State<WithdrawScreen> {
  final _formKey = GlobalKey<FormState>();
  final _mainController = TextEditingController();
  final _extraController = TextEditingController();
  String _selectedMethod = "USDT (TRC-20)";
  bool _isSending = false;
  final logger = Logger();

  // الإبقاء على طرق السحب كما هي في طلبك
  final Map<String, Map<String, dynamic>> _methods = {
    "USDT (TRC-20)": {
      "icon": Icons.account_balance_wallet,
      "color": Colors.tealAccent,
      "label": tr('wallet_address'),
      "hint": tr('wallet_hint'),
      "extra": ""
    },
    "شام كاش": {
      "icon": Icons.vibration,
      "color": Colors.orangeAccent,
      "label": tr('sham_cash_number'),
      "hint": "كود الاستقبال",
      "extra": tr('recipient_full_name')
    },
    "مكتب تركيا": {
      "icon": Icons.location_on,
      "color": Colors.redAccent,
      "label": tr('tr_phone'),
      "hint": "+90 5xx xxx xxxx",
      "extra": tr('recipient_full_name')
    },
    "مكتب سوريا": {
      "icon": Icons.storefront,
      "color": Colors.greenAccent,
      "label": tr('city_and_phone'),
      "hint": tr('wallet_hint'),
      "extra": tr('recipient_triple_name')
    },
    "Google Play": {
      "icon": Icons.shop,
      "color": Colors.blueAccent,
      "label": tr('email'),
      "hint": tr('wallet_hint'),
      "extra": ""
    },
    "App Store": {
      "icon": Icons.apple,
      "color": Colors.white,
      "label": tr('email'),
      "hint": tr('wallet_hint'),
      "extra": ""
    },
  };

  void _showSuccessSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.green),
    );
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> sendNotificationToAdmin(String title, String body) async {
    const String serverKey = 'YOUR_SERVER_KEY';
    const String fcmUrl = 'https://fcm.googleapis.com/fcm/send';

    final Map<String, dynamic> notificationData = {
      'notification': {
        'title': title,
        'body': body,
        'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        'sound': 'default',
      },
      'priority': 'high',
      'to': '/topics/admin_notifications',
    };

    try {
      await http.post(
        Uri.parse(fcmUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=$serverKey',
        },
        body: jsonEncode(notificationData),
      );
    } catch (e) {
      debugPrint("Error sending notification: $e");
    }
  }

  Future<void> _submitRequest(int minWithdrawFromFirestore) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid;

    try {
      // 1. جلب البيانات (استخدام Future.wait لتسريع العملية وجلبهم معاً)
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(uid).get(),
        FirebaseFirestore.instance
            .collection('app_settings')
            .doc('config')
            .get(),
      ]);

      final userDoc = results[0];
      final settingsDoc = results[1];

      if (!userDoc.exists || !settingsDoc.exists) {
        throw Exception("بيانات المستخدم أو الإعدادات غير موجودة");
      }

      int currentPoints = (userDoc.data()?['points'] ?? 0).toInt();
      String fullName = userDoc.data()?['name'] ?? tr('user_name_placeholder');
      _maskName(fullName);

      // جلب سعر الصرف (إذا لم يوجد نستخدم 1000 كقيمة افتراضية)
      int exchangeRate = settingsDoc.data()?['exchange_rate'] ?? 1000;
      double withdrawAmount = minWithdrawFromFirestore / exchangeRate;

      // 2. التحقق من الرصيد
      if (currentPoints < minWithdrawFromFirestore) {
        _showErrorSnackBar(
            "${tr('insufficient_points')} ($minWithdrawFromFirestore)");
        return; // الـ finally ستقوم بإيقاف _isSending
      }

      // 3. بدء عملية الـ Batch
      WriteBatch batch = FirebaseFirestore.instance.batch();

      // أ. تسجيل طلب السحب
      DocumentReference withdrawRef =
          FirebaseFirestore.instance.collection('withdrawals').doc();
      batch.set(withdrawRef, {
        'uid': uid,
        'email': user?.email,
        'method': _selectedMethod,
        'main_info': _mainController.text,
        'extra_info': _extraController.text,
        'status': 'pending',
        'points_deducted': minWithdrawFromFirestore,
        'amount_usd': withdrawAmount,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // ج. خصم النقاط
      DocumentReference userRef =
          FirebaseFirestore.instance.collection('users').doc(uid);
      batch.update(userRef, {
        'points': FieldValue.increment(-minWithdrawFromFirestore),
      });

      // تنفيذ الـ Batch
      await batch.commit();

      // 4. ردود الفعل والنجاح
      await sendNotificationToAdmin("طلب سحب جديد! 💰",
          "قام ${user?.email} بطلب سحب $withdrawAmount\$ عبر $_selectedMethod");

      await _sendTimeNotification('withdraw_success_key');
      HapticFeedback.heavyImpact();

      if (!mounted) return;
      _showSuccessSnackBar(tr('withdraw_success'));
      Navigator.pop(context);
    } catch (e, stackTrace) {
      // تسجيل الخطأ باحترافية
      logger.e("فشل في عملية السحب", error: e, stackTrace: stackTrace);
      if (mounted) _showErrorSnackBar(tr('withdraw_error'));
    } finally {
      // إيقاف مؤشر التحميل دائماً سواء نجحت العملية أو فشلت
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    var config = _methods[_selectedMethod]!;

    return StreamBuilder<DocumentSnapshot>(
      // مراقبة الحد الأدنى للسحب من الفايربيس لحظياً
      stream: FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .snapshots(),
      builder: (context, configSnapshot) {
        int minWithdrawPoints = 10000; // قيمة افتراضية
        if (configSnapshot.hasData && configSnapshot.data!.exists) {
          minWithdrawPoints =
              configSnapshot.data!['min_withdraw_points'] ?? 10000;
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(tr('withdraw_center'),
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: Colors.white)),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios,
                  color: Colors.amber, size: 20),
              onPressed: () {
                // 1. استدعاء عداد الإعلانات أولاً
                AdManager.showSmartAd();

                // 2. إغلاق الشاشة أو العودة للخلف
                Navigator.pop(context);
              },
            ),
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('choose_method'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 110,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _methods.keys.map((m) {
                        bool isSelected = _selectedMethod == m;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedMethod = m;
                            _mainController.clear();
                            _extraController.clear();
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 130,
                            margin: const EdgeInsets.only(right: 15),
                            decoration: BoxDecoration(
                              gradient: isSelected
                                  ? LinearGradient(colors: [
                                      config['color'],
                                      config['color'].withOpacity(0.6)
                                    ])
                                  : null,
                              color: isSelected
                                  ? null
                                  : Colors.white.withAlpha(13),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white12,
                                  width: 2),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(_methods[m]!['icon'],
                                    color: isSelected
                                        ? Colors.black
                                        : Colors.white54,
                                    size: 35),
                                const SizedBox(height: 8),
                                Text(m,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: isSelected
                                            ? Colors.black
                                            : Colors.white54,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(config['label'],
                      style: const TextStyle(
                          fontSize: 18,
                          color: Colors.amberAccent,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _mainController,
                    style: const TextStyle(color: Colors.white, fontSize: 22),
                    decoration: InputDecoration(
                      hintText: config['hint'],
                      hintStyle:
                          const TextStyle(color: Colors.white24, fontSize: 16),
                      filled: true,
                      fillColor: Colors.white.withAlpha(13),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.all(20),
                    ),
                    validator: (v) => v!.isEmpty ? tr('field_required') : null,
                  ),
                  if (config['extra'] != "") ...[
                    const SizedBox(height: 25),
                    Text(config['extra'],
                        style: const TextStyle(
                            fontSize: 18,
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _extraController,
                      style: const TextStyle(color: Colors.white, fontSize: 22),
                      decoration: InputDecoration(
                        hintText: tr('recipient_full_name'),
                        hintStyle: const TextStyle(
                            color: Colors.white24, fontSize: 16),
                        filled: true,
                        fillColor: Colors.white.withAlpha(13),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.all(20),
                      ),
                      validator: (v) =>
                          v!.isEmpty ? tr('name_required_for_transfer') : null,
                    ),
                  ],
                  const SizedBox(height: 50),
                  SizedBox(
                    width: double.infinity,
                    height: 75,
                    child: ElevatedButton(
                        onPressed: _isSending
                            ? null
                            : () async {
                                AdManager.showSmartAd();
                                bool isVpnActive =
                                    await CheckVpnConnection.isVpnActive();
                                if (!context.mounted) return;
                                if (isVpnActive) {
                                  SecurityUtils.sendSecurityReport(
                                      tr('vpn_withdrawal_attempt'));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                          content:
                                              Text(tr('vpn_withdraw_error')),
                                          backgroundColor: Colors.redAccent));
                                  return;
                                }
                                _submitRequest(minWithdrawPoints);
                              },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            disabledBackgroundColor: Colors.grey.shade800,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            elevation: 10),
                        child: _isSending
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                      color: Colors.black, strokeWidth: 2),
                                  SizedBox(width: 15),
                                  Text("Processing...",
                                      style: TextStyle(
                                          color: Colors.black, fontSize: 16)),
                                ],
                              )
                            : Text(
                                tr('confirm_withdraw',
                                    args: [minWithdrawPoints.toString()]),
                                style: TextStyle(
                                  fontSize: 18, // 🟢 تكبير الخط ليكون واضحاً
                                  fontWeight: FontWeight
                                      .w900, // 🟢 جعل الخط عريضاً جداً (Extra Bold)
                                  color: Color(
                                      0xFF1A1A2E), // 🟢 استخدام اللون الكحلي الداكن (نفس لون خلفية التطبيق) ليبرز فوق الأصفر
                                  letterSpacing: 0.5,
                                ),
                                textAlign: TextAlign
                                    .center, // لضمان توسط النص إذا كان في مربع حوار
                              )),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _maskName(String? fullName) {
    if (fullName == null || fullName.isEmpty) return "***";
    List<String> parts = fullName.split(' ');
    String firstName = parts[0];
    return "$firstName ***";
  }

  Future<void> _sendTimeNotification(String messageKey) async {
    const android = AndroidNotificationDetails(
        'reward_timer_id', 'تنبيهات الأرباح',
        importance: Importance.max,
        priority: Priority.high,
        color: Color(0xFF4527A0),
        icon: '@mipmap/ic_launcher');
    int notificationId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      await flutterLocalNotificationsPlugin.show(
          id: notificationId,
          title: tr('notification_reward_title'),
          body: tr(messageKey),
          notificationDetails: const NotificationDetails(android: android));
    } catch (e) {
      debugPrint("Notification Error: $e");
    }
  }
}
