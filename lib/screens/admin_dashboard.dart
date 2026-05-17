import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) return _buildLoginPinScreen();

    return DefaultTabController(
      length: 4, // تم التغيير إلى 4 ليشمل تبويب الإشعارات الجديد
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
            isScrollable: true, // لجعل التبويبات مرنة عند كثرتها
            tabs: [
              Tab(icon: Icon(Icons.settings_suggest), text: "الإعدادات"),
              Tab(
                  icon: Icon(Icons.notifications_active),
                  text: "الإشعارات"), // التبويب الجديد
              Tab(icon: Icon(Icons.receipt_long), text: "الطلبات"),
              Tab(icon: Icon(Icons.people_alt), text: "المستخدمين"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDynamicConfigTab(),
            _buildGlobalNotificationsTab(), // استدعاء التبويب الجديد
            _buildRequestsTab(),
            _buildUsersListTab(),
          ],
        ),
      ),
    );
  }

  // --- التبويب الجديد لتعديل رسائل الإشعارات العالمية ---
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
              child: Text("لا توجد إشعارات مسجلة",
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
              margin: const EdgeInsets.only(bottom: 15),
              child: ExpansionTile(
                iconColor: Colors.amber,
                collapsedIconColor: Colors.white54,
                title: const Text("إشعار النظام العالمي",
                    style: TextStyle(
                        color: Colors.amber, fontWeight: FontWeight.bold)),
                subtitle: Text("ID: ${doc.id}",
                    style:
                        const TextStyle(color: Colors.white24, fontSize: 10)),
                children: data.keys
                    .where((key) => key.startsWith('message_'))
                    .map((key) {
                  return ListTile(
                    title: Text(
                        key.replaceFirst('message_', 'اللغة: ').toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12)),
                    subtitle: Text(data[key].toString(),
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14)),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit,
                          color: Colors.blueAccent, size: 20),
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

  // نافذة تعديل رسالة محددة داخل الإشعار
  void _editNotificationDialog(
      String docId, String fieldKey, String currentValue) {
    TextEditingController editController =
        TextEditingController(text: currentValue);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text("تعديل الرسالة ($fieldKey)",
            style: const TextStyle(color: Colors.amber, fontSize: 16)),
        content: TextField(
          controller: editController,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "اكتب الرسالة هنا...",
            enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () async {
              await FirebaseFirestore.instance
                  .collection('global_notifications')
                  .doc(docId)
                  .update({
                fieldKey: editController.text,
                'timestamp': FieldValue.serverTimestamp()
              });

              if (!ctx.mounted) return;
              Navigator.pop(ctx);

              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text("تم تحديث الإشعار بنجاح ✅"),
                    behavior: SnackBarBehavior.floating),
              );
            },
            child: const Text("حفظ", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  // --- تبويب الإعدادات ---
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

  void _editConfigDialog(String key, dynamic currentValue) {
    if (currentValue is bool) {
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (context, setLocalState) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title:
                Text("تعديل $key", style: const TextStyle(color: Colors.amber)),
            content: SwitchListTile(
              title: Text(currentValue ? "مفعّل (True)" : "معطل (False)",
                  style: const TextStyle(color: Colors.white)),
              value: currentValue,
              activeThumbColor: Colors.amber,
              onChanged: (bool newValue) =>
                  setLocalState(() => currentValue = newValue),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("إلغاء")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                onPressed: () => _updateConfigAndPop(key, currentValue, ctx),
                child: const Text("حفظ", style: TextStyle(color: Colors.black)),
              ),
            ],
          ),
        ),
      );
    } else {
      TextEditingController editController =
          TextEditingController(text: currentValue.toString());
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title:
              Text("تعديل $key", style: const TextStyle(color: Colors.amber)),
          content: TextField(
            controller: editController,
            style: const TextStyle(color: Colors.white),
            keyboardType:
                currentValue is num ? TextInputType.number : TextInputType.text,
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("إلغاء")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: () {
                dynamic newValue = editController.text;
                if (currentValue is int) {
                  newValue = int.tryParse(editController.text) ?? currentValue;
                }
                if (currentValue is double) {
                  newValue =
                      double.tryParse(editController.text) ?? currentValue;
                }
                _updateConfigAndPop(key, newValue, ctx);
              },
              child: const Text("حفظ", style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _updateConfigAndPop(
      String key, dynamic value, BuildContext dialogCtx) async {
    await FirebaseFirestore.instance
        .collection('app_settings')
        .doc('config')
        .update({key: value});
    if (!dialogCtx.mounted) return;
    Navigator.pop(dialogCtx);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("تم التحديث بنجاح ✅"),
        behavior: SnackBarBehavior.floating));
  }

  // --- تبويب الطلبات ---
  Widget _buildRequestsTab() {
    return ListView(
      padding: const EdgeInsets.all(15),
      children: [
        _buildSectionHeader("طلبات السحب المعلقة 📥"),
        _buildGenericRequestList('withdrawals'),
        const SizedBox(height: 25),
        _buildSectionHeader("طلبات فك القفل 🔓"),
        _buildGenericRequestList('unlock_requests'),
      ],
    );
  }

  // --- تبويب المستخدمين ---
  Widget _buildUsersListTab() {
    return Column(
      children: [
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, snapshot) {
            int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(15),
              color: Colors.amber.withValues(alpha: 0.1),
              child: Text("إجمالي المستخدمين: $count",
                  style: const TextStyle(
                      color: Colors.amber, fontWeight: FontWeight.bold)),
            );
          },
        ),
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
                    margin:
                        const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    child: ListTile(
                      onTap: () => _showUserHistory(
                          userDoc.id, userData['name'] ?? "مخدم"),
                      leading: CircleAvatar(
                          backgroundColor: isBanned ? Colors.red : Colors.amber,
                          child: Text("${index + 1}",
                              style: const TextStyle(
                                  color: Colors.black, fontSize: 12))),
                      title: Text(userData['name'] ?? "مستعمل",
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text("${userData['points'] ?? 0} نقطة",
                          style: const TextStyle(color: Colors.amber)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 💰 زر تعديل النقاط الجديد للأدمن
                          IconButton(
                            icon: const Icon(Icons.monetization_on_rounded,
                                color: Colors.greenAccent),
                            onPressed: () => _editUserPointsDialog(
                              userDoc.id,
                              (userData['points'] ?? 0).toString(),
                              userData['name'] ?? "مستخدم",
                            ),
                          ),
                          // 🚫 زر الحظر والمنع القديم كما هو
                          IconButton(
                            icon: Icon(isBanned ? Icons.lock_open : Icons.block,
                                color: isBanned ? Colors.green : Colors.red),
                            onPressed: () => _toggleBan(userDoc.id, isBanned,
                                userData['name'] ?? "مستخدم"),
                          ),
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

  // 💰 نافذة مخصصة لتحديث وتعديل نقاط المستخدم وحفظ العملية داخل السجل الموحد
  void _editUserPointsDialog(
      String uid, String currentPoints, String userName) {
    TextEditingController pointsController = TextEditingController();
    bool isIncrement = true; // مؤشر لتحديد إذا كانت العملية شحن أو خصم

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text("تعديل نقاط: $userName",
              style: const TextStyle(color: Colors.amber, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("النقاط الحالية للمستخدم: $currentPoints",
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ChoiceChip(
                    label: const Text("إضافة نقاط ➕",
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                    selected: isIncrement,
                    selectedColor: Colors.greenAccent,
                    onSelected: (val) =>
                        setLocalState(() => isIncrement = true),
                  ),
                  ChoiceChip(
                    label: const Text("خصم نقاط ➖",
                        style: TextStyle(
                            color: Colors.black, fontWeight: FontWeight.bold)),
                    selected: !isIncrement,
                    selectedColor: Colors.redAccent,
                    onSelected: (val) =>
                        setLocalState(() => isIncrement = false),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              TextField(
                controller: pointsController,
                style: const TextStyle(color: Colors.white, fontSize: 20),
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: "عدد النقاط الجديد المراد تعديله...",
                  hintStyle:
                      const TextStyle(color: Colors.white30, fontSize: 12),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("إلغاء")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              onPressed: () async {
                int inputPoints = int.tryParse(pointsController.text) ?? 0;
                if (inputPoints <= 0) return;

                int finalChange = isIncrement ? inputPoints : -inputPoints;
                String logType =
                    isIncrement ? "admin_bonus" : "admin_deduction";

                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .update({
                  'points': FieldValue.increment(finalChange),
                  'points_history': FieldValue.arrayUnion([
                    {
                      'type': logType,
                      'amount': finalChange,
                      'timestamp':
                          Timestamp.now(), // طابع زمني حقيقي للسجل الموحد
                    }
                  ])
                });

                if (!ctx.mounted) return;
                Navigator.pop(ctx);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text("تم تعديل نقاط $userName بنجاح ✅"),
                      behavior: SnackBarBehavior.floating),
                );
              },
              child: const Text("حفظ", style: TextStyle(color: Colors.black)),
            ),
          ],
        ),
      ),
    );
  }

  // --- سجل النقاط للأدمن ---
  void _showUserHistory(String uid, String name) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StreamBuilder<DocumentSnapshot>(
        stream:
            FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          var userData = snapshot.data!.data() as Map<String, dynamic>?;
          var history = userData?['points_history'] as List? ?? [];
          List sortedHistory = history.reversed.toList();

          return Column(
            children: [
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text("سجل نقاط: $name",
                      style: const TextStyle(
                          color: Colors.amber,
                          fontSize: 18,
                          fontWeight: FontWeight.bold))),
              Expanded(
                child: sortedHistory.isEmpty
                    ? const Center(
                        child: Text("لا يوجد سجل عمليات لهذا المستخدم",
                            style: TextStyle(color: Colors.white24)))
                    : ListView.builder(
                        itemCount: sortedHistory.length,
                        itemBuilder: (context, i) {
                          var item = sortedHistory[i] as Map<String, dynamic>;
                          DateTime? date;
                          if (item['timestamp'] is Timestamp) {
                            date = (item['timestamp'] as Timestamp).toDate();
                          }
                          String formattedDate = date != null
                              ? DateFormat('yyyy/MM/dd - hh:mm a').format(date)
                              : "تاريخ غير معروف";

                          // فحص نوع العملية لعرض إشارة مناسبة ولون متناسق
                          bool isBonus = item['type'] == 'admin_bonus' ||
                              !(item['type']
                                      ?.toString()
                                      .contains('deduction') ??
                                  false);
                          int amount = item['amount'] ?? 0;

                          return ListTile(
                            title: Text(item['type'] ?? "مهمة غير معروفة",
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14)),
                            subtitle: Text(formattedDate,
                                style: const TextStyle(
                                    color: Colors.white38, fontSize: 11)),
                            trailing: Text(
                              amount >= 0 ? "+$amount" : "$amount",
                              style: TextStyle(
                                  color: isBonus
                                      ? Colors.greenAccent
                                      : Colors.redAccent,
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
    );
  }

  // --- إصلاح وظيفة الحظر المنبثقة ---
  Future<void> _toggleBan(
      String uid, bool currentStatus, String userName) async {
    bool confirm = await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: Text(currentStatus ? "فك حظر المستخدم" : "حظر المستخدم",
                style: TextStyle(
                    color: currentStatus ? Colors.green : Colors.red)),
            content: Text(
                "هل أنت متأكد من ${currentStatus ? 'إلغاء حظر' : 'حظر'} $userName؟",
                style: const TextStyle(color: Colors.white)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text("إلغاء")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: currentStatus ? Colors.green : Colors.red),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text("تأكيد"),
              ),
            ],
          ),
        ) ??
        false;

    if (confirm) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'isBanned': !currentStatus,
        'status': !currentStatus ? 'banned' : 'active',
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("تم تحديث حالة $userName بنجاح")));
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(title,
            style: const TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
                fontSize: 16)));
  }

// --- إصلاح الموافقة على الطلبات وفصل السحوبات عن فك القفل بشكل صحيح ---
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

            // 💡 فرز وعزل ديناميكي دقيق لعناوين الكروت حسب اسم الـ Collection
            String requestTitle = "";
            String requestSubtitle = "";

            if (collection == 'withdrawals') {
              requestTitle = "طلب سحب بقيمة: ${data['amount'] ?? '0'}";
              requestSubtitle = "وسيلة الدفع: ${data['method'] ?? 'غير محددة'}";
            } else {
              requestTitle = "طلب فك قفل الحساب 🔓";
              requestSubtitle =
                  "السبب: ${data['reason'] ?? 'تجاوز حظر نظام الأمان'}";
            }

            return Card(
              color: Colors.white.withValues(alpha: 0.05),
              child: ListTile(
                title: Text(
                  requestTitle,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
                subtitle: Text(
                  requestSubtitle,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
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
                        // 1. تحديث حالة الطلب الحالي
                        await doc.reference.update({'status': 'approved'});

                        // 2. إذا كنا بداخل طلبات فك القفل، نقوم بإرجاع حالة الحساب نشطة فوراً
                        if (collection == 'unlock_requests' &&
                            data['uid'] != null) {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(data['uid'])
                              .update({
                            'isBanned': false,
                            'status': 'active',
                          });
                        }
                      },
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

  Widget _buildLoginPinScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            children: [
              const Icon(Icons.admin_panel_settings,
                  size: 100, color: Colors.amber),
              const SizedBox(height: 40),
              TextField(
                controller: _pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 32, letterSpacing: 15),
                decoration: InputDecoration(
                    hintText: "****",
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.05),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none)),
                onSubmitted: (_) => _checkPin(),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                  onPressed: _checkPin,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      minimumSize: const Size(double.infinity, 60),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20))),
                  child: const Text("دخول النظام الآمن",
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                          fontSize: 18))),
            ],
          ),
        ),
      ),
    );
  }
}
