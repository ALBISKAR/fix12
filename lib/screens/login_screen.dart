import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:check_vpn_connection/check_vpn_connection.dart';
import 'package:syria_earn_pro/utils/security_utils.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  bool _isAccepted = false;
  BannerAd? _loginBanner;
  final TextEditingController _referralController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn.standard(
    scopes: <String>[
      'email',
    ],
  );
  final String _adminUid = 'OeEwi4nMZrPjRLRiqWf1373btQT2';

  @override
  void initState() {
    super.initState();
    _requestNotificationPermissions();
    _checkUpdate();
    AdManager.initialize();

    // 📥 تحميل إعلان البانر لصفحة تسجيل الدخول
    _loginBanner = BannerAd(
      adUnitId: AdManager.adMobBannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) => setState(() {}),
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          debugPrint('Login Banner Error: ${error.message}');
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _loginBanner?.dispose(); // 👈 تنظيف ذاكرة الإعلان عند الخروج
    _referralController.dispose();
    super.dispose();
  }

  // 🔔 دالة إرسال الإشعار للمسؤول (تمت إضافتها هنا ليعمل الكود)
  Future<void> sendNotificationToAdmin(String title, String body) async {
    const String serverKey = 'AIzaSyDw2o4boLXWVKQ4WTW7fSfKkXsAJE5DR8I';
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
      if (kDebugMode) print("Notification Error: $e");
    }
  }

  void _showUpdateDialog({required bool isMandatory}) {
    showDialog(
      context: context,
      barrierDismissible: !isMandatory,
      builder: (context) => PopScope(
        canPop: !isMandatory,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Icon(Icons.system_update, color: Colors.amber, size: 50),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('update_available_title'),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 15),
              Text(
                isMandatory
                    ? tr('mandatory_update_msg')
                    : tr('optional_update_msg'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
            ],
          ),
          actions: [
            Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _launchStoreUrl(),
                    child: Text(tr('update_now'),
                        style: const TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
                if (!isMandatory)
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('later'),
                        style: const TextStyle(color: Colors.white54)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchStoreUrl() async {
    try {
      // 1. جلب رابط التحديث من مستند config في Firestore
      final configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      // 2. استخراج الرابط (مع وضع رابط احتياطي في حال كان الحقل فارغاً)
      final String updateUrl = configDoc.data()?['update_url'] ??
          'https://play.google.com/store/apps';

      // 3. فتح الرابط في المتصفح الخارجي أو المتجر
      if (await canLaunchUrl(Uri.parse(updateUrl))) {
        await launchUrl(Uri.parse(updateUrl),
            mode: LaunchMode.externalApplication);
      } else {
        debugPrint("Could not launch $updateUrl");
      }
    } catch (e) {
      debugPrint("Error fetching update_url: $e");
    }
  }

  Future<void> _requestNotificationPermissions() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(
          alert: true, badge: true, sound: true);

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        User? currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null && currentUser.uid == _adminUid) {
          await FirebaseMessaging.instance
              .subscribeToTopic('admin_notifications');
        }
      }
    } catch (e) {
      debugPrint("Notification Error: $e");
    }
  }

  Future<void> _checkUpdate() async {
    try {
      // 1. جلب نسخة التطبيق الحالية
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version.split('+')[0].trim();

      // 2. جلب البيانات من Firestore بدلاً من Remote Config
      var configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      if (configDoc.exists) {
        String firebaseVersion =
            configDoc.data()?['current_version']?.toString().trim() ?? '';
        bool isForceUpdate = configDoc.data()?['force_update'] ?? false;

        debugPrint("----------------------------");
        debugPrint("FIRESTORE CHECK:");
        debugPrint("APP: '$currentVersion'");
        debugPrint("FIRESTORE: '$firebaseVersion'");
        debugPrint("FORCE UPDATE: $isForceUpdate");
        debugPrint("----------------------------");

        // 3. المقارنة: إذا كان الإصدار في Firestore أحدث والتحديث إجباري
        if (firebaseVersion.isNotEmpty &&
            currentVersion != firebaseVersion &&
            isForceUpdate) {
          if (!mounted) return;
          _showUpdateDialog(isMandatory: true);
        }
      }
    } catch (e) {
      debugPrint("Update Check Error: $e");
    }
  }

  Future<void> _signInWithGoogle() async {
    // 1. جلب الإعدادات من Firestore لفحص الـ VPN
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      bool isVpnProtectionEnabled =
          configDoc.data()?['is_vpn_protection_enabled'] ?? true;

      if (isVpnProtectionEnabled) {
        final bool isVpnActive = await CheckVpnConnection.isVpnActive();
        if (!mounted) return;
        if (isVpnActive) {
          _showSnack(tr('close_vpn'));
          return;
        }
      }
    } catch (e) {
      debugPrint("خطأ في جلب إعدادات VPN: $e");
    }

    if (!_isAccepted) {
      _showSnack(tr('accept_terms_error'));
      return;
    }

    setState(() => _isLoading = true);

    try {
      String secureId = await SecurityUtils.getDeviceId();

      // 2. تسجيل الدخول بـ Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        setState(() => _isLoading = false);
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final User? user = userCredential.user;

      if (user != null) {
        final userDocRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);
        final docSnapshot = await userDocRef.get();

        // 🛡️ فحص قفل "مشاهدة الفيديو" (منع مسح البيانات)
        if (docSnapshot.exists &&
            docSnapshot.data()!.containsKey('login_lock_until')) {
          Timestamp lockTimestamp = docSnapshot.data()?['login_lock_until'];
          DateTime lockDate = lockTimestamp.toDate();

          if (DateTime.now().difference(lockDate).inSeconds < 3600) {
            int remaining =
                60 - (DateTime.now().difference(lockDate).inMinutes);
            _showSnack(tr('restricted_access_msg',
                namedArgs: {'minutes': remaining.toString()}));
            await FirebaseAuth.instance.signOut();
            await _googleSignIn.signOut();
            setState(() => _isLoading = false);
            return;
          }
        }

        // 3. 🛡️ فحص الحظر الدائم
        if (docSnapshot.exists && (docSnapshot.data()?['isBanned'] ?? false)) {
          _showSnack(tr('account_banned_msg'));
          await _googleSignIn.signOut();
          await FirebaseAuth.instance.signOut();
          if (mounted) setState(() => _isLoading = false);
          return;
        }

        // 4. 🛡️ نظام حماية الجهاز (التحقق من UID و Device ID)
        if (user.uid != _adminUid) {
          if (userCredential.additionalUserInfo!.isNewUser &&
              !docSnapshot.exists) {
            final deviceQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('device_id', isEqualTo: secureId)
                .limit(1)
                .get();

            if (deviceQuery.docs.isNotEmpty &&
                deviceQuery.docs.first.id != user.uid) {
              _showSnack(tr('device_already_registered'));
              await _googleSignIn.signOut();
              await FirebaseAuth.instance.signOut();
              if (mounted) setState(() => _isLoading = false);
              return;
            }
          } else if (docSnapshot.exists) {
            String? savedDeviceId = docSnapshot.data()?['device_id'];
            if (savedDeviceId != null &&
                savedDeviceId != "" &&
                savedDeviceId != secureId) {
              if (mounted) setState(() => _isLoading = false);
              _showDeviceLockedDialog();
              return;
            }
          }
        }

        // 5. نظام الإحالة وإنشاء الحساب
// 5. نظام الإحالة وإنشاء الحساب (نسخة مصلحة)
        String myCode = user.uid.substring(0, 6).toUpperCase();
        String enteredCode = _referralController.text.trim().toUpperCase();

        if (userCredential.additionalUserInfo!.isNewUser ||
            !docSnapshot.exists) {
          String referredByCode = "";

          if (enteredCode.isNotEmpty && enteredCode != myCode) {
            final friendQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('my_referral_code', isEqualTo: enteredCode)
                .limit(1)
                .get();

            if (friendQuery.docs.isNotEmpty) {
              referredByCode = enteredCode;
            }
          }

          // إنشاء ملف المستخدم - السيرفر سيتولى زيادة العدادات تلقائياً
          await userDocRef.set({
            'name': user.displayName,
            'email': user.email,
            'my_referral_code': myCode,
            'referred_by': referredByCode,
            'device_id': secureId,
            'isBanned': false,
            'points': 0,
            'createdAt': FieldValue.serverTimestamp(),
            'last_login': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } else {
          // تحديث وقت الدخول للمستخدم القديم
          await userDocRef.update({
            'last_login': FieldValue.serverTimestamp(),
          });
        }

// 6. الدخول للشاشة الرئيسية (تأكد من إغلاق حالة التحميل أولاً)
        if (mounted) {
          setState(
              () => _isLoading = false); // 👈 ضروري لمنع ظهور خطأ في الخلفية
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e) {
      debugPrint("Login Error: $e");
      _showSnack(tr('withdraw_error'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.language, color: Colors.amber, size: 28),
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
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 20.0, vertical: 20.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.account_balance_wallet,
                        size: 100, color: Colors.amber),
                    const SizedBox(height: 20),
                    const Text("Syria Earn Pro",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 40),
                    TextField(
                      controller: _referralController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: tr('referral_hint'),
                        hintStyle: const TextStyle(color: Colors.white24),
                        prefixIcon: const Icon(Icons.card_giftcard,
                            color: Colors.amber),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.05),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(15),
                            borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Checkbox(
                            value: _isAccepted,
                            activeColor: Colors.amber,
                            onChanged: (value) =>
                                setState(() => _isAccepted = value!)),
                        Text(tr('i_agree_to'),
                            style: const TextStyle(color: Colors.white70)),
                        GestureDetector(
                          onTap: () => Navigator.pushNamed(context, '/privacy'),
                          child: Text(" ${tr('privacy_policy')}",
                              style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                  decoration: TextDecoration.underline)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _isLoading
                        ? const CircularProgressIndicator(color: Colors.amber)
                        : ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  _isAccepted ? Colors.white : Colors.white24,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(double.infinity, 55),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(15)),
                            ),
                            icon: const Icon(Icons.login),
                            onPressed: _isLoading || !_isAccepted
                                ? null
                                : _signInWithGoogle,
                            label: Text(tr('google_login'),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold)),
                          ),
                  ],
                ),
              ),
            ),
          ),
          if (FirebaseAuth.instance.currentUser?.uid != _adminUid)
            Container(
                width: double.infinity,
                height: 50,
                alignment: Alignment.center,
                child: AdManager.smartBanner(_loginBanner)),
        ],
      ),
    );
  }

  // 🔒 نافذة تنبيه عند محاولة الدخول من جهاز غير مسجل
  void _showDeviceLockedDialog() {
    // 💡 نستخدم متغير محلي داخل الدالة للتحكم في حالة التحميل
    bool isRequestSending = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Icon(Icons.phonelink_lock,
                  color: Colors.redAccent, size: 50),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('device_mismatch_title'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  Text(
                    tr('device_mismatch_body'),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
              actions: [
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        // استخدام المتغير لتغيير الأيقونة
                        icon: isRequestSending
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.send),
                        label: Text(tr('send_reset_request')),
                        // تعطيل الزر أثناء الإرسال
                        onPressed: isRequestSending
                            ? null
                            : () async {
                                setDialogState(() => isRequestSending = true);

                                try {
                                  final user =
                                      FirebaseAuth.instance.currentUser;
                                  String secureId =
                                      await SecurityUtils.getDeviceId();

                                  await FirebaseFirestore.instance
                                      .collection('reset_requests')
                                      .add({
                                    'email': user?.email ?? "unknown",
                                    'userId': user?.uid,
                                    'device_id': secureId,
                                    'status': 'pending',
                                    'timestamp': FieldValue.serverTimestamp(),
                                  });

                                  await FirebaseAuth.instance.signOut();
                                  await _googleSignIn.signOut();

                                  if (!context.mounted) return;
                                  Navigator.pop(ctx);
                                  _showSnack(tr('request_sent_success'));
                                } catch (e) {
                                  if (mounted) {
                                    setDialogState(
                                        () => isRequestSending = false);
                                    _showSnack(tr('withdraw_error'));
                                  }
                                }
                              },
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        await _googleSignIn.signOut();
                        if (!context.mounted) return;
                        Navigator.pop(ctx);
                      },
                      child: Text(tr('close'),
                          style: const TextStyle(color: Colors.white54)),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }
}
