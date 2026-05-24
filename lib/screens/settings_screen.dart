import 'package:syria_earn_pro/screens/friends_list_screen.dart';
import 'package:syria_earn_pro/screens/notifications_screen.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:syria_earn_pro/screens/admin_dashboard.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final TextEditingController _nameController = TextEditingController();
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = user?.displayName ?? "";
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  // --- 1. الدوال البرمجية (Logic) ---

  Future<void> _launchSocial(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showSnackBar(
            tr('technical_issue'), Colors.orange); // استخدام مفتاح عام للمشاكل
      }
    } catch (e) {
      _showSnackBar(tr('withdraw_error'), Colors.redAccent);
    }
  }

  Future<void> _updateName() async {
    if (user == null || _nameController.text.trim().isEmpty) return;
    if (mounted) setState(() => _isUpdating = true);

    try {
      await user!.updateDisplayName(_nameController.text.trim());
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .update({
        'name': _nameController.text.trim(),
        'lastNameChange': FieldValue.serverTimestamp(),
      });

      _showSnack(tr('message_sent_success')); // تم التحديث بنجاح
    } catch (e) {
      _showSnack(tr('withdraw_error'));
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  Future<void> _deleteAccount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      _showSnack(tr('processing'));

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .delete();

      await user.delete();

      if (!mounted) return;

      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      _showSnack(tr('delete_account_success'));
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _showSnack(tr('reauth_required_for_delete'));
      } else {
        _showSnack("${tr('withdraw_error')}: ${e.message}");
      }
    } catch (e) {
      _showSnack(tr('withdraw_error'));
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  // --- 2. بناء الواجهة (UI) ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: Text(tr('settings_center'),
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            // 🔐 البوابة السرية للمسؤول
            GestureDetector(
              onLongPress: () {
                // 👈 استبدل YOUR_ADMIN_UID بمعرفك الحقيقي الموجود في Firebase Console
                if (user?.uid == 'OeEwi4nMZrPjRLRiqWf1373btQT2') {
                  HapticFeedback.heavyImpact(); // اهتزاز قوي للتأكيد
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const AdminDashboard()),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  "${tr('user_id')}: ${user?.uid ?? '---'}",
                  style: const TextStyle(
                    color: Colors.white24, // تمويه النص ليكون باهتاً
                    fontSize: 11,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(color: Colors.white10, indent: 30, endIndent: 30),
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser?.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();

                var userData = snapshot.data!.data() as Map<String, dynamic>?;
                String referralCode = userData?['my_referral_code'] ?? "";

// 🛠️ الإصلاح الذكي (Self-Healing): إذا كان الكود مفقوداً يتم إنشاؤه وحفظه فوراً
                if (referralCode.isEmpty || referralCode == "---") {
                  referralCode = FirebaseAuth.instance.currentUser != null &&
                          FirebaseAuth.instance.currentUser!.uid.length >= 6
                      ? FirebaseAuth.instance.currentUser!.uid
                          .substring(0, 6)
                          .toUpperCase()
                      : "USER00";

                  // حفظه في الفايربيس في الخلفية لضمان إصلاح حساب المستخدم بالكامل
                  FirebaseFirestore.instance
                      .collection('users')
                      .doc(FirebaseAuth.instance.currentUser?.uid)
                      .set({'my_referral_code': referralCode},
                          SetOptions(merge: true));
                }

                // ✅ 1. أضفنا StreamBuilder جديد لجلب إعدادات التطبيق (config) لقراءة النقاط
                return StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('app_settings')
                      .doc('config')
                      .snapshots(),
                  builder: (context, configSnapshot) {
                    // ✅ 2. استخراج قيمة الإحالة من الفايربيس (مع وضع 50 كقيمة افتراضية)
                    int inviterPoints = 50;
                    if (configSnapshot.hasData && configSnapshot.data!.exists) {
                      var configData =
                          configSnapshot.data!.data() as Map<String, dynamic>?;
                      inviterPoints =
                          configData?['referral_reward_inviter'] ?? 50;
                    }

                    return Column(
                      children: [
                        _buildSettingsTile(
                          icon: Icons.card_giftcard,
                          iconColor: Colors.purpleAccent,
                          title: "${tr('ref_code')}: $referralCode",
                          // ✅ 3. دمج النص المترجم مع النقاط المسحوبة من الفايربيس
                          subtitle: "${tr('ref_subtitle')} (+$inviterPoints)",
                          trailing: FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('users')
                                .where('referred_by', isEqualTo: referralCode)
                                .limit(50)
                                .get(),
                            builder: (context, countSnapshot) {
                              int count = countSnapshot.data?.docs.length ?? 0;

                              return GestureDetector(
                                onTap: () {
                                  if (count > 0) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => FriendsListScreen(
                                            referralCode: referralCode),
                                      ),
                                    );
                                  } else {
                                    _showSnack(tr('no_friends_yet'));
                                  }
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 500),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: count > 0
                                        ? Colors.purpleAccent
                                            .withValues(alpha: 0.15)
                                        : Colors.white.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: count > 0
                                          ? Colors.purpleAccent
                                              .withValues(alpha: 0.5)
                                          : Colors.transparent,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      GestureDetector(
                                        onTap: () async {
                                          String shareMsg =
                                              "${tr('share_msg_header')}\n\n"
                                              "${tr('ref_code')}: $referralCode\n\n"
                                              "${tr('share_msg_download')}:\n"
                                              "https://play.google.com/store/apps/details?id=your.package.name";

                                          await SharePlus.instance.share(
                                            ShareParams(text: shareMsg),
                                          );
                                          HapticFeedback.lightImpact();
                                        },
                                        child: Icon(
                                          Icons.share_rounded,
                                          size: 15,
                                          color: count > 0
                                              ? Colors.white
                                              : Colors.white38,
                                        ),
                                      ),
                                      Container(
                                        height: 12,
                                        width: 1,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        color:
                                            Colors.white.withValues(alpha: 0.1),
                                      ),
                                      Icon(
                                        Icons.people_alt_rounded,
                                        size: 14,
                                        color: count > 0
                                            ? Colors.purpleAccent
                                            : Colors.white38,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        "$count",
                                        style: TextStyle(
                                          color: count > 0
                                              ? Colors.white
                                              : Colors.white38,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                          onTap: () {
                            if (referralCode != "---") {
                              Clipboard.setData(
                                  ClipboardData(text: referralCode));
                              _showSnack(tr('code_copied_success'));
                              HapticFeedback.mediumImpact();
                            }
                          },
                        ),
                      ],
                    );
                  },
                ); // نهاية الـ StreamBuilder الخاص بالـ config
              },
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user?.uid)
                  .collection('notifications')
                  .where('isRead',
                      isEqualTo: false) // جلب الإشعارات غير المقروءة فقط
                  .snapshots(),
              builder: (context, snapshot) {
                int unreadCount = snapshot.data?.docs.length ?? 0;

                return _buildSettingsTile(
                  icon: Icons.notifications_none_rounded,
                  iconColor: Colors.purpleAccent,
                  title: tr('notifications_center'),
                  subtitle: tr('notif_subtitle_hint'),
                  // إضافة Badge (نقطة حمراء) إذا كان هناك إشعارات غير مقروءة
                  trailing: unreadCount > 0
                      ? Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                              color: Colors.red, shape: BoxShape.circle),
                          child: Text(
                            unreadCount.toString(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        )
                      : const Icon(Icons.arrow_forward_ios,
                          size: 16, color: Colors.white24),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const NotificationsScreen()),
                  ),
                );
              },
            ),
            _buildSettingsTile(
              icon: Icons.chat_outlined,
              iconColor: Colors.greenAccent,
              title: tr('whatsapp_support'),
              subtitle: tr('whatsapp_subtitle'),
              onTap: () => _launchSocial("https://wa.me/905314735240"),
            ),
            _buildSettingsTile(
              icon: Icons.send_rounded,
              iconColor: Colors.blueAccent,
              title: tr('telegram_channel'),
              subtitle: tr('telegram_subtitle'),
              onTap: () => _launchSocial("https://t.me/syria_earn_pro"),
            ),
            _buildSettingsTile(
              icon: Icons.manage_accounts_outlined,
              iconColor: Colors.amber,
              title: tr('update_profile'),
              subtitle: tr('update_profile_subtitle'),
              onTap: () => _showUpdateNameDialog(),
            ),
            _buildSettingsTile(
              icon: Icons.verified_user_outlined,
              iconColor: Colors.tealAccent,
              title: tr('privacy_policy'),
              subtitle: tr('privacy_subtitle'),
              onTap: () => Navigator.pushNamed(context, '/privacy'),
            ),
            _buildSettingsTile(
              icon: Icons.headset_mic_outlined,
              iconColor: Colors.blueAccent,
              title: tr('contact_us'),
              subtitle: tr('message_hint'),
              onTap: () => Navigator.pushNamed(context, '/contact'),
            ),
            const Divider(
                color: Colors.white10, height: 40, indent: 30, endIndent: 30),
            _buildSettingsTile(
              icon: Icons.logout_rounded,
              iconColor: Colors.orangeAccent,
              title: tr('logout'),
              subtitle: tr('logout_subtitle'),
              onTap: _signOut,
            ),
            _buildSettingsTile(
              icon: Icons.delete_forever_rounded,
              iconColor: Colors.redAccent,
              title: tr('delete_account_btn'),
              subtitle: tr('delete_account_subtitle'),
              onTap: _showDeleteDialog,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 25, vertical: 2),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 24),
      ),
      title: Text(title,
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 11)),
      trailing: trailing ??
          const Icon(Icons.arrow_forward_ios_rounded,
              color: Colors.white10, size: 14),
    );
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.purpleAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showUpdateNameDialog() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final userDoc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (!mounted) return;

    final userData = userDoc.data();
    if (userData != null && userData.containsKey('lastNameChange')) {
      final lastChange = (userData['lastNameChange'] as Timestamp).toDate();
      if (DateTime.now().difference(lastChange).inDays < 3) {
        _showSnack(tr('name_change_limit'));
        return;
      }
    }

    final TextEditingController nameController =
        TextEditingController(text: _nameController.text);

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white12)),
          title: Text(tr('edit_name_title'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
          content: TextField(
            controller: nameController,
            maxLength: 15,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
                hintText: tr('recipient_full_name'),
                hintStyle: const TextStyle(color: Colors.white24)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: Text(tr('close'),
                    style: const TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: _isUpdating
                  ? null
                  : () async {
                      setDialogState(() => _isUpdating = true);
                      _nameController.text = nameController.text;
                      await _updateName();
                      if (!dialogCtx.mounted) return;
                      Navigator.pop(dialogCtx);
                      setDialogState(() => _isUpdating = false);
                    },
              child: _isUpdating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text(tr('save'),
                      style: const TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text(tr('confirm_delete_title'),
            style: const TextStyle(color: Colors.white)),
        content: Text(tr('confirm_delete_msg'),
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('close'),
                  style: const TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            child: Text(tr('delete_account_btn'),
                style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
