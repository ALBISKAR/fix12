import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:check_vpn_connection/check_vpn_connection.dart';
import 'package:google_sign_in/google_sign_in.dart';

class SecurityUtils {
  // ==========================================
  // 1. الوظائف الأساسية (المعرفات والإنترنت)
  // ==========================================

  static String hashDeviceId(String rawId) {
    return sha256.convert(utf8.encode(rawId)).toString();
  }

  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    }
  }

  static Future<String> getDeviceId() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    String rawId = "unknown";

    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      rawId =
          "${androidInfo.id}_${androidInfo.hardware}_${androidInfo.board}_${androidInfo.product}";
    } else if (Platform.isIOS) {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      rawId = iosInfo.identifierForVendor ?? "unknown_ios";
    }
    return hashDeviceId(rawId);
  }

  static Future<bool> runComprehensiveSecurityCheck({
    required BuildContext context,
    required User? user,
    required String adminUid,
  }) async {

    const String myDeveloperDeviceId = "3a8edfc782d3c430cd4b89f2f2400f5b95df273a8907932d5dac3b700270dd15"; 
    
    // فحص معرف الجهاز الحالي
    String currentDeviceId = await getDeviceId();
    
    // إذا كان هذا جهازي، تخطي جميع فحوصات المحاكي والـ VPN
    if (currentDeviceId == myDeveloperDeviceId) {
      debugPrint("🛠️ وضع المطور مفعل: تم استثناء هذا الجهاز من قيود الحماية.");
      return true; 
    }
    bool isAdmin = user != null && user.uid == adminUid;

    // 1. جلب إعدادات الحماية من الفايربيس (مع قيم افتراضية قوية)
    bool checkEmu = true, checkVpn = true, checkMulti = true;
    try {
      final configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get(const GetOptions(source: Source.server));
      if (configDoc.exists) {
        checkEmu = configDoc.data()?['is_emulator_protection_enabled'] ?? true;
        checkVpn = configDoc.data()?['is_vpn_protection_enabled'] ?? true;
        checkMulti =
            configDoc.data()?['is_multi_account_protection_enabled'] ?? true;
      }
    } catch (_) {
      // تجاهل الخطأ واعتمد على الحماية القصوى الافتراضية
    }

    // 2. فحوصات الجهاز (لغير الأدمن)
// 2. فحوصات الجهاز (لغير الأدمن)
    if (!isAdmin) {
      // 1. فحص النواسخ (App Cloners) أولاً
      if (_isAppCloned()) {
        if (context.mounted) {
          showSecurityBlockDialog(context, 'reason_cloned_app');
        }
        return false;
      }

      // 2. فحص المحاكي
      if (checkEmu && await _isEmulatorCore()) {
        if (context.mounted) {
          showSecurityBlockDialog(context, 'reason_emulator');
        }
        return false;
      }

      // 3. فحص VPN
      if (checkVpn && await CheckVpnConnection.isVpnActive()) {
        if (context.mounted) showSecurityBlockDialog(context, 'reason_vpn');
        return false;
      }
    }

    // 3. فحوصات الحساب وقاعدة البيانات (إذا كان مسجلاً الدخول وليس أدمن)
    if (user != null && !isAdmin) {
      try {
        final userDocRef =
            FirebaseFirestore.instance.collection('users').doc(user.uid);
        final docSnapshot =
            await userDocRef.get(const GetOptions(source: Source.server));
        String secureId = await getDeviceId();

        if (docSnapshot.exists) {
          final data = docSnapshot.data()!;

          // فحص الحظر
          if (data['isBanned'] == true) {
            await _forceSignOut();
            if (context.mounted) _showSnack(context, tr('account_banned_msg'));
            return false;
          }

          // فحص قفل الدخول المؤقت
          if (data.containsKey('login_lock_until') &&
              data['login_lock_until'] != null) {
            DateTime lockDate =
                (data['login_lock_until'] as Timestamp).toDate();
            if (DateTime.now().isBefore(lockDate)) {
              int remaining = lockDate.difference(DateTime.now()).inMinutes;
              await _forceSignOut();
              if (context.mounted) {
                _showSnack(
                    context,
                    tr('restricted_access_msg', namedArgs: {
                      'minutes': remaining.clamp(1, 60).toString()
                    }));
              }
              return false;
            }
          }

          // فحص الحسابات المتعددة (Multi-account)
          if (checkMulti) {
            String? savedDeviceId = data['device_id'];
            if (savedDeviceId != null &&
                savedDeviceId.isNotEmpty &&
                savedDeviceId != secureId) {
              if (context.mounted) _showDeviceLockedDialog(context);
              return false;
            }
          }
        } else {
          // حالة مستخدم جديد: التأكد أن جهازه لم يستخدم لحساب آخر مسبقاً
          if (checkMulti) {
            final deviceQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('device_id', isEqualTo: secureId)
                .where('isBanned', isEqualTo: false)
                .limit(1)
                .get();
            if (deviceQuery.docs.isNotEmpty) {
              if (context.mounted) _showDeviceLockedDialog(context);
              return false;
            }
          }
        }
      } catch (e) {
        debugPrint("❌ SecurityUtils Error (Possible App Check block): $e");
        if (context.mounted) {
          showSecurityBlockDialog(context, 'reason_untrusted_env');
        }
        return false; // فشل الطلب بسبب App Check أو مشكلة بالشبكة
      }
    }

    return true; // الجهاز والحساب اجتازا كل الفحوصات بنجاح ✅
  }

// 🛡️ دالة كشف التطبيقات المنسوخة (Parallel Space / Dual Space)
  static bool _isAppCloned() {
    if (!Platform.isAndroid) return false;
    try {
      final List<String> clonerKeywords = [
        'parallel',
        'dualspace',
        'clone',
        'virtual',
        'multiple',
        '2face',
        'multi_account'
      ];
      String currentDataDir = Directory.current.path.toLowerCase();
      for (String keyword in clonerKeywords) {
        if (currentDataDir.contains(keyword)) {
          debugPrint("🚨 [Security] تم كشف بيئة منسوخة: $currentDataDir");
          return true;
        }
      }
    } catch (_) {}
    return false;
  }
  // ==========================================
  // 3. الدوال الداخلية (النوافذ والتحققات الدقيقة)
  // ==========================================

  static Future<bool> _isEmulatorCore() async {
    if (!Platform.isAndroid) return false;
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

    bool isX86 = androidInfo.supportedAbis
            .any((abi) => abi.toLowerCase().contains('x86')) ||
        androidInfo.board.toLowerCase().contains('x86') ||
        androidInfo.hardware.toLowerCase().contains('x86');
    if (isX86) return true;

    String fp = androidInfo.fingerprint.toLowerCase();
    String hw = androidInfo.hardware.toLowerCase();
    if (fp.contains("generic") ||
        fp.contains("vbox") ||
        hw.contains("goldfish") ||
        hw.contains("ranchu")) {
      return true;
    }

    final List<String> emulatorPaths = [
      '/system/lib/libc_malloc_debug_qemu.so',
      '/sys/qemu_trace',
      '/system/bin/nox-prop',
      '/system/app/LDAppStore',
      '/data/data/com.bluestacks.home'
    ];
    for (String path in emulatorPaths) {
      if (File(path).existsSync() || Directory(path).existsSync()) return true;
    }
    return false;
  }

  static Future<void> _forceSignOut() async {
    await GoogleSignIn().signOut();
    await FirebaseAuth.instance.signOut();
  }

  static void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// نافذة الحظر الأمني الصارمة (طرد قسري)
  static void showSecurityBlockDialog(BuildContext context, String reasonKey) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Column(
              children: [
                const Icon(Icons.gpp_bad_rounded,
                    color: Colors.redAccent, size: 65),
                const SizedBox(height: 15),
                Text(tr('security_alert_title'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 22)),
              ],
            ),
            content: Text(
              "${tr('security_alert_prefix')} ${tr(reasonKey)}.\n\n${tr('security_alert_desc')}",
              style: const TextStyle(
                  color: Colors.white70, fontSize: 15, height: 1.6),
              textAlign: TextAlign.center,
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white),
                  icon: const Icon(Icons.exit_to_app_rounded),
                  label: Text(tr('exit_app_button')),
                  onPressed: () =>
                      Platform.isAndroid ? SystemNavigator.pop() : exit(0),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// نافذة قفل الجهاز المتعدد (Multi-account) مع زر إرسال الطلب
  static void _showDeviceLockedDialog(BuildContext context) {
    bool isRequestSending = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope(
              canPop: false,
              child: AlertDialog(
                backgroundColor: const Color(0xFF1A1A2E),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                title: const Icon(Icons.phonelink_lock,
                    color: Colors.redAccent, size: 50),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(tr('device_mismatch_title'),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 15),
                    Text(tr('device_mismatch_body'),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14),
                        textAlign: TextAlign.center),
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
                              foregroundColor: Colors.white),
                          icon: isRequestSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : const Icon(Icons.send),
                          label: Text(tr('send_reset_request')),
                          onPressed: isRequestSending
                              ? null
                              : () async {
                                  setDialogState(() => isRequestSending = true);
                                  try {
                                    final user =
                                        FirebaseAuth.instance.currentUser;
                                    String secureId = await getDeviceId();
                                    await FirebaseFirestore.instance
                                        .collection('reset_requests')
                                        .add({
                                      'email': user?.email ?? "unknown",
                                      'userId': user?.uid ?? "unknown",
                                      'device_id': secureId,
                                      'status': 'pending',
                                      'timestamp': FieldValue.serverTimestamp(),
                                    });

                                    // 1. فحص سياق النافذة قبل إغلاقها
                                    if (!ctx.mounted) return;
                                    Navigator.pop(ctx);

                                    // 2. ✅ فحص سياق الشاشة قبل إظهار رسالة النجاح
                                    if (!context.mounted) return;
                                    _showSnack(
                                        context, tr('request_sent_success'));

                                    await Future.delayed(
                                        const Duration(milliseconds: 1500));
                                    await _forceSignOut();
                                  } catch (e) {
                                    setDialogState(
                                        () => isRequestSending = false);

                                    // 3. ✅ فحص سياق الشاشة قبل إظهار رسالة الخطأ
                                    if (!context.mounted) return;
                                    _showSnack(context, tr('error_occurred'));
                                  }
                                },
                        ),
                      ),
                      TextButton(
                        onPressed: () async {
                          await _forceSignOut();
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                        },
                        child: Text(tr('close'),
                            style: const TextStyle(color: Colors.white54)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
  // ==========================================
  // 4. نظام التقارير الأمنية والحظر التدريجي
  // ==========================================

  static Future<void> sendSecurityReport(String reason) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userRef =
        FirebaseFirestore.instance.collection('users').doc(user.uid);

    try {
      // 1. تسجيل المخالفة في مجموعة التقارير للإدارة
      await FirebaseFirestore.instance.collection('security_reports').add({
        'uid': user.uid,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 2. زيادة عداد المخالفات في ملف المستخدم
      await userRef.update({'violation_count': FieldValue.increment(1)});

      // 3. فحص الحظر التلقائي (إذا كرر المخالفات 3 مرات مثلاً يتم حظره فوراً)
      final doc = await userRef.get();
      if (doc.exists) {
        int count = (doc.data()?['violation_count'] ?? 0).toInt();
        if (count >= 3) {
          // لا يمكن للعميل تعديل حقل isBanned بسبب قواعد الحماية، 
          // لذلك نكتفي بطرده محلياً، وتسجيل التقرير في security_reports للأدمن.

          // طرد المستخدم فوراً بعد الحظر
          await _forceSignOut();
        }
      }
    } catch (e) {
      debugPrint("❌ Error sending security report: $e");
    }
  }
}
