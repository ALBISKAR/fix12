import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:syria_earn_pro/utils/security_utils.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:audioplayers/audioplayers.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  bool _isAccepted = false;
  final TextEditingController _referralController = TextEditingController();
  final GoogleSignIn _googleSignIn = GoogleSignIn.standard(
    scopes: <String>[
      'email',
    ],
  );
  final String _adminUid = 'OeEwi4nMZrPjRLRiqWf1373btQT2';
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _requestNotificationPermissions();
    _checkUpdate();

  }

  @override
  void dispose() {
    _referralController.dispose();
    _audioPlayer.dispose();
    super.dispose();
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
            // ✅ تم إصلاح الانهيار الهيكلي: إزالة الـ Spacer الخاطئ وضبط أبعاد الأزرار
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                              color: Colors.black,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  if (!isMandatory) ...[
                    const SizedBox(height: 5),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('later'),
                          style: const TextStyle(color: Colors.white54)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _launchStoreUrl() async {
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      final String updateUrl = configDoc.data()?['update_url'] ??
          'https://play.google.com/store/apps';

      if (await canLaunchUrl(Uri.parse(updateUrl))) {
        await launchUrl(Uri.parse(updateUrl),
            mode: LaunchMode.externalApplication);
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
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      String currentVersion = packageInfo.version.split('+')[0].trim();

      var configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      if (configDoc.exists) {
        String firebaseVersion =
            configDoc.data()?['current_version']?.toString().trim() ?? '';
        bool isForceUpdate = configDoc.data()?['force_update'] ?? false;

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

// --- دوال التسجيل والأمان ---
  Future<void> _signInWithGoogle() async {
    if (!_isAccepted) {
      _showSnack(tr('accept_terms_error'));
      return;
    }

    setState(() => _isLoading = true);

    try {
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
        if (!mounted) return;

        // 🛡️ الفحص الأمني
        bool isEnvironmentSafe =
            await SecurityUtils.runComprehensiveSecurityCheck(
                context: context, user: user, adminUid: _adminUid);

        if (!isEnvironmentSafe || !mounted) {
          setState(() => _isLoading = false);
          return;
        }

        // ✅ معالجة بيانات المستخدم في Firestore
        String secureId = await SecurityUtils.getDeviceId();
        final userDocRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);
        final docSnapshot = await userDocRef.get();

        String myCode = user.uid.length >= 6
            ? user.uid.substring(0, 6).toUpperCase()
            : user.uid.toUpperCase();
        String enteredCode = _referralController.text.trim().toUpperCase();

        if (!docSnapshot.exists) {
          String referredByCode = "";
          if (enteredCode.isNotEmpty && enteredCode != myCode) {
            final friendQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('my_referral_code', isEqualTo: enteredCode)
                .limit(1)
                .get();
            if (friendQuery.docs.isNotEmpty) referredByCode = enteredCode;
          }

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
          await userDocRef.update({
            'last_login': FieldValue.serverTimestamp(),
          });
        }

        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e) {
      debugPrint("Login Error: $e");
      if (mounted) _showSnack(tr('login_error'));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    _audioPlayer.play(AssetSource('sounds/error.mp3')).catchError((_) {});
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
        // ✅ إضافة أيقونة الدعم الفني في الجهة اليسرى لسهولة الوصول
        leading: IconButton(
          icon: const Icon(Icons.support_agent_rounded,
              color: Colors.amber, size: 30),
          onPressed: _showSupportDialog, // تشغيل نافذة المراسلة المحمية
        ),
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
        ],
      ),
    );
  }

  void _showSupportDialog() async {
    final TextEditingController messageController = TextEditingController();
    bool isSending = false;
    String? supportUid = FirebaseAuth.instance.currentUser?.uid;

    // صمام أمان: إذا كان هناك مستخدم مسجل مسبقاً، نربط الرسالة بـ ID حسابه، وإلا نعتبرها رسالة لزائر مجهول
    String deviceSecureId = await SecurityUtils.getDeviceId();
    String docId = supportUid ?? "guest_$deviceSecureId";

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.support_agent_rounded,
                      color: Colors.amber, size: 28),
                  const SizedBox(width: 10),
                  Text(tr('support_title'),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr('support_desc'),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: messageController,
                    maxLines: 4,
                    maxLength: 250,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: tr('type_your_message'),
                      hintStyle:
                          const TextStyle(color: Colors.white24, fontSize: 13),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: isSending
                          ? null
                          : () {
                              if (ctx.mounted) Navigator.pop(ctx);
                            },
                      child: Text(tr('cancel'),
                          style: const TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: isSending
                          ? null
                          : () async {
                              String msg = messageController.text.trim();
                              if (msg.isEmpty) {
                                _showSnack(tr('message_empty_error'));
                                return;
                              }

                              setDialogState(() => isSending = true);

                              try {
                                // 1. جلب سجل آخر رسالة دعم لهذا الجهاز من الفايرستور لفحص التوقيت
                                final lastMsgDoc = await FirebaseFirestore
                                    .instance
                                    .collection('support_messages_cooldown')
                                    .doc(docId)
                                    .get();

                                if (lastMsgDoc.exists &&
                                    lastMsgDoc.data() != null) {
                                  Timestamp? lastTime = lastMsgDoc
                                      .data()!['last_sent_at'] as Timestamp?;
                                  if (lastTime != null) {
                                    DateTime eligibleTime = lastTime
                                        .toDate()
                                        .add(const Duration(hours: 1));

                                    // 2. الحماية الصارمة: إذا لم تمر ساعة كاملة، نمنع الإرسال فوراً
                                    if (DateTime.now().isBefore(eligibleTime)) {
                                      int remainingMinutes = eligibleTime
                                          .difference(DateTime.now())
                                          .inMinutes;
                                      _showSnack(
                                          tr('support_cooldown_msg', args: [
                                        remainingMinutes.clamp(1, 60).toString()
                                      ]));

                                      if (ctx.mounted) Navigator.pop(ctx);
                                      return;
                                    }
                                  }
                                }

                                // 3. رفع الرسالة إلى مجموعة الدعم الفني للأدمن
                                await FirebaseFirestore.instance
                                    .collection('support_messages')
                                    .add({
                                  'senderId': supportUid ?? "GUEST",
                                  'deviceId': deviceSecureId,
                                  'message': msg,
                                  'timestamp': FieldValue.serverTimestamp(),
                                  'status': 'unread',
                                });

                                // 4. تحديث ميقات الحظر (Cooldown) لهذا المستند سحابياً ليقفل لمدة ساعة
                                await FirebaseFirestore.instance
                                    .collection('support_messages_cooldown')
                                    .doc(docId)
                                    .set({
                                  'last_sent_at': FieldValue.serverTimestamp(),
                                });

                                if (!mounted) return;
                                if (ctx.mounted) Navigator.pop(ctx);
                                _showSnack(tr('message_sent_success'));
                              } catch (e) {
                                _showSnack(tr('error_occurred'));
                              } finally {
                                setDialogState(() => isSending = false);
                              }
                            },
                      child: isSending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.black, strokeWidth: 2),
                            )
                          : Text(tr('send'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
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
