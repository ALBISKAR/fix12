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
  String _searchQuery = "";
  int _currentPage = 0;
  List<DocumentSnapshot?> _pageHistory = [null];
  final int _usersPerPage = 50;

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
          .limit(50) // 🚀 تحسين الأداء: تحميل 50 طلب كحد أقصى لمنع استهلاك الذاكرة وتشنج الشاشة
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
                        onPressed: () {
                          if (collection == 'reset_requests') {
                            _approveResetRequest(
                                context,
                                data['email'] ?? '',
                                data['device_id'] ?? '',
                                doc.id);
                          } else {
                            doc.reference.update({'status': 'approved'});
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
        _buildStatsHeader(), // إضافة شريط الإحصائيات هنا
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          child: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "ابحث بالاسم أو البريد الإلكتروني...",
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.amber),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.05),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => setState(() {
              _searchQuery = val;
              _currentPage = 0;
              _pageHistory = [null];
            }),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _buildUserQuery().snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              var docs = snapshot.data!.docs;
              bool hasNext = docs.length == _usersPerPage;
              DocumentSnapshot? lastDoc = docs.isNotEmpty ? docs.last : null;

              return Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        var userDoc = docs[index];
                        var userData = userDoc.data() as Map<String, dynamic>;
                        bool isBanned = userData['isBanned'] ?? false;
                        return Card(
                          color: Colors.white.withValues(alpha: 0.05),
                          child: ListTile(
                            onTap: () => _showUserDetails(userDoc.id),
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
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios, size: 18),
                          color: Colors.amber,
                          disabledColor: Colors.white24,
                          onPressed: _currentPage > 0 ? () {
                            setState(() => _currentPage--);
                          } : null,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 15),
                          child: Text("الصفحة ${_currentPage + 1}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_ios, size: 18),
                          color: Colors.amber,
                          disabledColor: Colors.white24,
                          onPressed: hasNext ? () {
                            setState(() {
                              if (_pageHistory.length <= _currentPage + 1) {
                                _pageHistory.add(lastDoc);
                              } else {
                                _pageHistory[_currentPage + 1] = lastDoc;
                              }
                              _currentPage++;
                            });
                          } : null,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // --- بناء شريط الإحصائيات (سريع ولا يستهلك قراءات فايربيس) ---
  Widget _buildStatsHeader() {
    return FutureBuilder(
      future: Future.wait([
        FirebaseFirestore.instance.collection('users').count().get(),
        FirebaseFirestore.instance.collection('withdrawals').where('status', isEqualTo: 'pending').count().get(),
        FirebaseFirestore.instance.collection('reset_requests').where('status', isEqualTo: 'pending').count().get(),
      ]),
      builder: (context, AsyncSnapshot<List<AggregateQuerySnapshot>> snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(15.0),
            child: Center(child: CircularProgressIndicator(color: Colors.amber)),
          );
        }
        int totalUsers = snapshot.data![0].count ?? 0;
        int pendingWithdrawals = snapshot.data![1].count ?? 0;
        int pendingResets = snapshot.data![2].count ?? 0;
        
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              _statCard("المستخدمين", totalUsers.toString(), Icons.group, Colors.blueAccent),
              const SizedBox(width: 8),
              _statCard("سحوبات معلقة", pendingWithdrawals.toString(), Icons.monetization_on, Colors.greenAccent),
              const SizedBox(width: 8),
              _statCard("طلبات أجهزة", pendingResets.toString(), Icons.phonelink_lock, Colors.orangeAccent),
            ],
          ),
        );
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
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

  Future<void> _approveResetRequest(BuildContext context, String email,
      String newDeviceId, String requestId) async {
    try {
      var userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        await userQuery.docs.first.reference.update({
          'device_id': newDeviceId,
          'deviceId': newDeviceId, // ضمان التوافق
          'isBanned': false,
          'isLocked': false,
        });

        await FirebaseFirestore.instance
            .collection('reset_requests')
            .doc(requestId)
            .update({
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
        });

        if (!context.mounted) return;
        _showSuccessMessage("تم تفعيل الجهاز وفك الحظر بنجاح ✅");
      } else {
        _showError("لم يتم العثور على حساب بهذا البريد الإلكتروني.");
      }
    } catch (e) {
      _showError("خطأ أثناء معالجة الطلب: ${e.toString()}");
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(message), backgroundColor: Colors.green));
  }

  void _editConfigDialog(String key, dynamic currentValue) {
    TextEditingController editController =
        TextEditingController(text: currentValue.toString());
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              title: Text("تعديل $key",
                  style: const TextStyle(color: Colors.amber)),
              content: TextField(
                  controller: editController,
                  style: const TextStyle(color: Colors.white)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("إلغاء")),
                ElevatedButton(
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                    onPressed: () => _updateConfigAndPop(
                        key,
                        editController.text,
                        currentValue,
                        ctx), // نرسل القيمة الأصلية لمعرفة نوعها
                    child: const Text("حفظ",
                        style: TextStyle(color: Colors.black))),
              ],
            ));
  }

  Future<void> _updateConfigAndPop(String key, String newValue,
      dynamic originalValue, BuildContext dialogCtx) async {
    dynamic finalValue = newValue;

    // 🔥 الذكاء هنا: الحفاظ على نوع البيانات الأصلي في Firebase 🔥
    if (originalValue is int) {
      finalValue =
          int.tryParse(newValue) ?? originalValue; // تحويل إلى رقم صحيح
    } else if (originalValue is double) {
      finalValue =
          double.tryParse(newValue) ?? originalValue; // تحويل إلى رقم عشري
    } else if (originalValue is bool) {
      finalValue =
          newValue.toLowerCase() == 'true'; // تحويل إلى قيمة منطقية (صح/خطأ)
    }

    try {
      await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .update({key: finalValue});

      if (!dialogCtx.mounted) return;
      Navigator.pop(dialogCtx);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("تم تعديل الإعدادات بنجاح ✅"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating));
      }
    } catch (e) {
      if (!dialogCtx.mounted) return;
      ScaffoldMessenger.of(dialogCtx).showSnackBar(SnackBar(
          content: Text("حدث خطأ: $e"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating));
    }
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

  Query _buildUserQuery() {
    Query query = FirebaseFirestore.instance.collection('users');
    if (_searchQuery.trim().isNotEmpty) {
      String search = _searchQuery.trim();
      // تحديد نوع البحث بناءً على وجود علامة @ للإيميل
      if (search.contains('@')) {
        query = query.where('email', isEqualTo: search);
      } else {
        query = query
            .where('name', isGreaterThanOrEqualTo: search)
            .where('name', isLessThanOrEqualTo: '$search\uf8ff');
      }
    } else {
      query = query.orderBy('points', descending: true);
    }
    
    query = query.limit(_usersPerPage);
    if (_pageHistory.length > _currentPage && _pageHistory[_currentPage] != null) {
      query = query.startAfterDocument(_pageHistory[_currentPage]!);
    }
    return query;
  }

  void _showUserDetails(String uid) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              const TabBar(
                indicatorColor: Colors.amber,
                labelColor: Colors.amber,
                unselectedLabelColor: Colors.white54,
                tabs: [
                  Tab(icon: Icon(Icons.manage_accounts), text: "البيانات"),
                  Tab(icon: Icon(Icons.history), text: "سجل النقاط"),
                ],
              ),
              Expanded(
                child: StreamBuilder<DocumentSnapshot>(
                  stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator(color: Colors.amber));
                    }
                    var userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
                    var history = userData['points_history'] as List? ?? [];
                    List sortedHistory = history.reversed.toList();

                    return TabBarView(
                      children: [
                        // Tab 1: كل بيانات المستخدم (مع إمكانية التعديل)
                        ListView(
                          padding: const EdgeInsets.all(15),
                          children: [
                            ...userData.keys.map((key) {
                              if (key == 'points_history') return const SizedBox();
                              
                              var rawValue = userData[key];
                              String displayValue = rawValue.toString();
                              if (rawValue is Timestamp) {
                                displayValue = DateFormat('yyyy/MM/dd - hh:mm a').format(rawValue.toDate());
                              }

                              bool isComplex = rawValue is List || rawValue is Map;
                              return Card(
                                color: Colors.white.withValues(alpha: 0.05),
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(key, style: const TextStyle(color: Colors.amber, fontSize: 13)),
                                  subtitle: Text(displayValue, style: const TextStyle(color: Colors.white)),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (!isComplex)
                                        IconButton(
                                          icon: const Icon(Icons.edit, color: Colors.blueAccent),
                                          onPressed: () => _editUserFieldDialog(uid, key, rawValue),
                                        ),
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                                        onPressed: () => _deleteUserField(uid, key),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 15),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.amber,
                                  padding: const EdgeInsets.symmetric(vertical: 12)),
                              icon: const Icon(Icons.add, color: Colors.black),
                              label: const Text("إضافة حقل جديد",
                                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                              onPressed: () => _addNewFieldDialog(uid),
                            ),
                          ],
                        ),
                        // Tab 2: سجل النقاط المطور (محمي ضد أخطاء التواريخ)
                        sortedHistory.isEmpty
                            ? const Center(child: Text("لا توجد سجلات لهذا المستخدم", style: TextStyle(color: Colors.white24)))
                            : ListView.builder(
                                itemCount: sortedHistory.length,
                                itemBuilder: (context, i) {
                                  var item = sortedHistory[i] as Map<String, dynamic>;
                                  String formattedDate = "غير معروف";
                                  if (item['timestamp'] != null) {
                                    DateTime date;
                                    if (item['timestamp'] is Timestamp) {
                                      date = (item['timestamp'] as Timestamp).toDate();
                                    } else {
                                      date = DateTime.tryParse(item['timestamp'].toString()) ?? DateTime.now();
                                    }
                                    formattedDate = DateFormat('yyyy/MM/dd - hh:mm a').format(date);
                                  }
                                  int amount = (item['amount'] ?? 0).toInt();
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
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _editUserFieldDialog(String uid, String key, dynamic currentValue) async {
    if (currentValue is Timestamp) {
      DateTime initialDate = currentValue.toDate();
      DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: initialDate,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (pickedDate != null && mounted) {
        TimeOfDay? pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(initialDate),
        );
        if (pickedTime != null && mounted) {
          DateTime finalDateTime = DateTime(
            pickedDate.year, pickedDate.month, pickedDate.day,
            pickedTime.hour, pickedTime.minute,
          );
          try {
            await FirebaseFirestore.instance.collection('users').doc(uid).update({
              key: Timestamp.fromDate(finalDateTime),
            });
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("تم تعديل الوقت بنجاح ✅"), backgroundColor: Colors.green));
          } catch (e) {
            if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red));
          }
        }
      }
      return;
    }

    TextEditingController editController = TextEditingController(text: currentValue.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text("تعديل $key", style: const TextStyle(color: Colors.amber)),
        content: TextField(controller: editController, style: const TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            onPressed: () async {
              dynamic finalValue = editController.text;
              // محاولة اكتشاف نوع الحقل تلقائياً لحفظه بشكل صحيح في قاعدة البيانات
              if (currentValue is int) {
                finalValue = int.tryParse(editController.text) ?? currentValue;
              } else if (currentValue is double) {
                finalValue = double.tryParse(editController.text) ?? currentValue;
              } else if (currentValue is bool) {
                finalValue = editController.text.toLowerCase() == 'true';
              }

              try {
                await FirebaseFirestore.instance.collection('users').doc(uid).update({key: finalValue});
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red));
                }
              }
            },
            child: const Text("حفظ", style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );
  }

  void _deleteUserField(String uid, String key) async {
    bool confirm = await showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A2E),
                  title: const Text("تأكيد الحذف", style: TextStyle(color: Colors.redAccent)),
                  content: Text("هل أنت متأكد من حذف الحقل '$key'؟", style: const TextStyle(color: Colors.white70)),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
                    ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text("حذف", style: TextStyle(color: Colors.white))),
                  ],
                )) ??
        false;

    if (confirm) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          key: FieldValue.delete(),
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("تم حذف الحقل بنجاح ✅"), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("خطأ أثناء الحذف: $e"), backgroundColor: Colors.red));
        }
      }
    }
  }

  void _addNewFieldDialog(String uid) {
    TextEditingController keyController = TextEditingController();
    TextEditingController valueController = TextEditingController();
    String selectedType = 'String';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            title: const Text("إضافة حقل جديد", style: TextStyle(color: Colors.amber)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: keyController,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                        labelText: "اسم الحقل", labelStyle: TextStyle(color: Colors.white70))),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  dropdownColor: const Color(0xFF1A1A2E),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                      labelText: "نوع الحقل", labelStyle: TextStyle(color: Colors.white70)),
                  items: ['String', 'Number', 'Boolean', 'Timestamp']
                      .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                      .toList(),
                  onChanged: (val) => setState(() => selectedType = val!),
                ),
                const SizedBox(height: 10),
                if (selectedType != 'Timestamp')
                  TextField(
                      controller: valueController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                          labelText: "القيمة", labelStyle: TextStyle(color: Colors.white70))),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("إلغاء", style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                onPressed: () async {
                  String key = keyController.text.trim();
                  if (key.isEmpty) return;

                  dynamic finalValue;
                  if (selectedType == 'String') {
                    finalValue = valueController.text;
                  } else if (selectedType == 'Number') {
                    finalValue = num.tryParse(valueController.text) ?? 0;
                  } else if (selectedType == 'Boolean') {
                    finalValue = valueController.text.toLowerCase() == 'true';
                  } else if (selectedType == 'Timestamp') {
                    finalValue = FieldValue.serverTimestamp();
                  }

                  try {
                    await FirebaseFirestore.instance.collection('users').doc(uid).update({
                      key: finalValue,
                    });
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
                          content: Text("تمت الإضافة بنجاح ✅"), backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text("خطأ: $e"), backgroundColor: Colors.red));
                    }
                  }
                },
                child: const Text("إضافة", style: TextStyle(color: Colors.black)),
              ),
            ],
          );
        });
      },
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
