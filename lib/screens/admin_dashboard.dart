import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  bool _isAuthorized = false;
  final TextEditingController _pinController = TextEditingController();
  final String _adminPin = "438093";
  final String _allowedUid = "OeEwi4nMZrPjRLRiqWf1373btQT2";

  // --- دوال التحكم والأمن ---
  void _checkPin() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null && currentUser.uid == _allowedUid) {
      if (_pinController.text == _adminPin) {
        HapticFeedback.mediumImpact();
        setState(() => _isAuthorized = true);
      } else {
        _showError("الرمز السري غير صحيح! ❌");
      }
    } else {
      _showError("عذراً، لا تملك صلاحية الوصول لهذا النظام 🚫");
    }
  }

  void _showError(String message) {
    _pinController.clear();
    HapticFeedback.vibrate();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) return _buildLoginPinScreen();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F1E),
        appBar: AppBar(
          title: const Text("لوحة التحكم المركزية"),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: const Icon(Icons.admin_panel_settings, color: Colors.amber),
          actions: [
            IconButton(
              onPressed: () => setState(() => _isAuthorized = false),
              icon:
                  const Icon(Icons.power_settings_new, color: Colors.redAccent),
            )
          ],
          bottom: const TabBar(
            indicatorColor: Colors.amber,
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.settings_suggest), text: "الإعدادات"),
              Tab(icon: Icon(Icons.notifications_active), text: "الإشعارات"),
              Tab(icon: Icon(Icons.receipt_long), text: "الطلبات"),
              Tab(icon: Icon(Icons.people_alt), text: "المستخدمين"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDynamicConfigTab(),
            _buildGlobalNotificationsTab(),
            _buildRequestsTab(),
            _buildUsersListTab(),
          ],
        ),
      ),
    );
  }

  // --- التبويب 1: الإعدادات ---
  Widget _buildDynamicConfigTab() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        Map<String, dynamic> configData =
            snapshot.data!.data() as Map<String, dynamic>;
        List<String> keys = configData.keys.toList();
        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: keys.length,
          itemBuilder: (context, index) {
            String key = keys[index];
            var value = configData[key];
            return Card(
              color: Colors.white.withValues(alpha: 0.05),
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                title: Text(key,
                    style: const TextStyle(color: Colors.amber, fontSize: 13)),
                subtitle: Text(value.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 16)),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blueAccent),
                  onPressed: () => _editConfigDialog(key, value),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- التبويب 2: الإشعارات ---
  Widget _buildGlobalNotificationsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('global_notifications')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.docs.isEmpty) {
          return const Center(
              child: Text("لا توجد إشعارات",
                  style: TextStyle(color: Colors.white24)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            return Card(
              color: Colors.white.withValues(alpha: 0.05),
              child: ExpansionTile(
                title: const Text("إشعار النظام العالمي",
                    style: TextStyle(color: Colors.amber)),
                children: data.keys
                    .where((key) => key.startsWith('message_'))
                    .map((key) {
                  return ListTile(
                    title: Text(
                        key.replaceFirst('message_', 'اللغة: ').toUpperCase(),
                        style: const TextStyle(color: Colors.white70)),
                    subtitle: Text(data[key].toString(),
                        style: const TextStyle(color: Colors.white)),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit, color: Colors.blueAccent),
                      onPressed: () =>
                          _editNotificationDialog(doc.id, key, data[key]),
                    ),
                  );
                }).toList(),
              ),
            );
          },
        );
      },
    );
  }

  // --- التبويب 3: الطلبات (سحب + فك قفل) ---
  Widget _buildRequestsTab() {
    return ListView(
      padding: const EdgeInsets.all(15),
      children: [
        _buildSectionHeader("طلبات السحب المعلقة 📥"),
        _buildGenericRequestList('withdrawals'),
        const SizedBox(height: 25),
        _buildSectionHeader("طلبات فك القفل 🔓"),
        _buildGenericRequestList('reset_requests'),
      ],
    );
  }

  Widget _buildGenericRequestList(String collection) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(collection)
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Text("لا توجد طلبات معالجة",
              style: TextStyle(color: Colors.white24));
        }
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, i) {
            var doc = snapshot.data!.docs[i];
            var data = doc.data() as Map<String, dynamic>;
            return Card(
              color: Colors.white.withValues(alpha: 0.05),
              child: ListTile(
                title: Text(
                    collection == 'withdrawals'
                        ? "سحب: ${data['amount'] ?? '0'}"
                        : "فك قفل: ${data['email'] ?? 'مجهول'}",
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: Text("الجهاز: ${data['device_id'] ?? 'غير معروف'}"),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.redAccent),
                        onPressed: () =>
                            doc.reference.update({'status': 'rejected'})),
                    IconButton(
                        icon: const Icon(Icons.check_circle,
                            color: Colors.greenAccent),
                        onPressed: () async {
                          await doc.reference.update({'status': 'approved'});
                          if (collection == 'reset_requests' &&
                              data['userId'] != null) {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(data['userId'])
                                .update(
                                    {'isBanned': false, 'status': 'active'});
                          }
                        }),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // --- التبويب 4: المستخدمين ---
  Widget _buildUsersListTab() {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .orderBy('points', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              return ListView.builder(
                itemCount: snapshot.data!.docs.length,
                itemBuilder: (context, index) {
                  var userDoc = snapshot.data!.docs[index];
                  var userData = userDoc.data() as Map<String, dynamic>;
                  bool isBanned = userData['isBanned'] ?? false;
                  return Card(
                    color: Colors.white.withValues(alpha: 0.05),
                    child: ListTile(
                      onTap: () => _showUserHistory(
                          userDoc.id, userData['name'] ?? "مستخدم"),
                      title: Text(userData['name'] ?? "مستخدم",
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text("${userData['points'] ?? 0} نقطة"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.monetization_on,
                                  color: Colors.greenAccent),
                              onPressed: () => _editUserPointsDialog(
                                  userDoc.id,
                                  (userData['points'] ?? 0).toString(),
                                  userData['name'] ?? "مستخدم")),
                          IconButton(
                              icon: Icon(
                                  isBanned ? Icons.lock_open : Icons.block,
                                  color: isBanned ? Colors.green : Colors.red),
                              onPressed: () => _toggleBan(userDoc.id, isBanned,
                                  userData['name'] ?? "مستخدم")),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // --- وظائف مساعدة ---
  Future<void> _toggleBan(
      String uid, bool currentStatus, String userName) async {
    bool confirm = await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A2E),
                  title: Text(currentStatus ? "فك حظر" : "حظر المستخدم"),
                  content: Text("تأكيد العملية لـ $userName؟"),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("إلغاء")),
                    ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("تأكيد")),
                  ],
                )) ??
        false;

    if (confirm) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isBanned': !currentStatus,
        'status': !currentStatus ? 'banned' : 'active',
      });
    }
  }

  void _editUserPointsDialog(
      String uid, String currentPoints, String userName) {
    TextEditingController controller =
        TextEditingController(text: currentPoints);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text("تعديل نقاط: $userName",
            style: const TextStyle(color: Colors.amber)),
        content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: "الرصيد الجديد",
                labelStyle: TextStyle(color: Colors.white70))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () async {
              int newPoints = int.tryParse(controller.text) ?? -1;
              if (newPoints < 0) {
                _showError("قيمة غير صحيحة");
                return;
              }

              int oldPoints = int.tryParse(currentPoints) ?? 0;
              int difference = newPoints - oldPoints;

              try {
                // تحديث النقاط + تسجيل العملية في السجل
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .update({
                  'points': newPoints,
                  'points_history': FieldValue.arrayUnion([
                    {
                      'type': 'admin_manual_update',
                      'amount': difference,
                      'timestamp': FieldValue.serverTimestamp(),
                    }
                  ])
                });

                // تأمين السياق قبل الإغلاق
                if (!ctx.mounted) return;
                Navigator.pop(ctx);

                // إظهار رسالة النجاح
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("تم تحديث النقاط بنجاح ✅"),
                    backgroundColor: Colors.green,
                    behavior: SnackBarBehavior.floating));
              } catch (e) {
                if (!ctx.mounted) return;
                _showError("حدث خطأ أثناء التحديث");
              }
            },
            child: const Text("حفظ", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _editConfigDialog(String key, dynamic currentValue) {
    TextEditingController editController =
        TextEditingController(text: currentValue.toString());
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              title: Text("تعديل $key"),
              content: TextField(
                  controller: editController,
                  style: const TextStyle(color: Colors.white)),
              actions: [
                ElevatedButton(
                    onPressed: () =>
                        _updateConfigAndPop(key, editController.text, ctx),
                    child: const Text("حفظ")),
              ],
            ));
  }

  void _editNotificationDialog(
      String docId, String fieldKey, String currentValue) {
    TextEditingController editController =
        TextEditingController(text: currentValue);
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              title: Text("تعديل الرسالة ($fieldKey)"),
              content: TextField(
                  controller: editController,
                  style: const TextStyle(color: Colors.white)),
              actions: [
                ElevatedButton(
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('global_notifications')
                          .doc(docId)
                          .update({fieldKey: editController.text});
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text("حفظ")),
              ],
            ));
  }

  Future<void> _updateConfigAndPop(
      String key, dynamic value, BuildContext dialogCtx) async {
    await FirebaseFirestore.instance
        .collection('app_settings')
        .doc('config')
        .update({key: value});
    if (!dialogCtx.mounted) return;
    Navigator.pop(dialogCtx);
  }

void _showUserHistory(String uid, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // لجعل النافذة قابلة للتمدد
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7, // ارتفاع النافذة 70% من الشاشة
        child: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator(color: Colors.amber));
            }
            
            var userData = snapshot.data!.data() as Map<String, dynamic>?;
            var history = userData?['points_history'] as List? ?? [];
            // عكس القائمة لعرض أحدث العمليات في الأعلى
            List sortedHistory = history.reversed.toList();

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text("سجل نقاط: $name",
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  child: sortedHistory.isEmpty
                      ? const Center(
                          child: Text("لا توجد سجلات لهذا المستخدم",
                              style: TextStyle(color: Colors.white24)))
                      : ListView.builder(
                          itemCount: sortedHistory.length,
                          itemBuilder: (context, i) {
                            var item = sortedHistory[i] as Map<String, dynamic>;
                            
                            // التعامل مع التاريخ (تحويل Timestamp إلى نص)
                            String formattedDate = "غير معروف";
                            if (item['timestamp'] != null) {
                              DateTime date = (item['timestamp'] as Timestamp).toDate();
                              formattedDate = DateFormat('yyyy/MM/dd - hh:mm a').format(date);
                            }

                            int amount = item['amount'] ?? 0;
                            String type = item['type'] ?? "عملية";

                            return ListTile(
                              title: Text(type, style: const TextStyle(color: Colors.white, fontSize: 14)),
                              subtitle: Text(formattedDate, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              trailing: Text(
                                amount >= 0 ? "+$amount" : "$amount",
                                style: TextStyle(
                                    color: amount >= 0 ? Colors.greenAccent : Colors.redAccent,
                                    fontWeight: FontWeight.bold),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoginPinScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.admin_panel_settings,
                  size: 100, color: Colors.amber),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 32),
                decoration: const InputDecoration(hintText: "****"),
              ),
              ElevatedButton(onPressed: _checkPin, child: const Text("دخول")),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(title,
            style: const TextStyle(
                color: Colors.amber, fontWeight: FontWeight.bold)));
  }
}
