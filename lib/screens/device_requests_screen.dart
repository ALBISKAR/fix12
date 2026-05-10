import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class DeviceRequestsScreen extends StatefulWidget {
  const DeviceRequestsScreen({super.key});

  @override
  State<DeviceRequestsScreen> createState() => _DeviceRequestsScreenState();
}

class _DeviceRequestsScreenState extends State<DeviceRequestsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text("طلبات إعادة الضبط").tr(),
        backgroundColor: Colors.amber,
        foregroundColor: Colors.black,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('reset_requests')
            .where('status', isEqualTo: 'pending')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: Colors.amber));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
                child: Text("لا توجد طلبات حالياً",
                    style: TextStyle(color: Colors.white70)));
          }

          var docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              var data = docs[index].data() as Map<String, dynamic>;
              String docId = docs[index].id;

              return Card(
                color: Colors.white10,
                margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(15),
                  title: Text(data['email'] ?? "بدون إيميل",
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  subtitle: Padding(
                    padding: const EdgeInsets.all(8.0), // ✅ صحيح
                    child: Text(
                        "ID الجديد: ${data['device_id'] ?? 'غير معروف'}",
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12)),
                  ),
                  trailing: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: () => _approveRequest(
                        context, data['email'], data['device_id'], docId),
                    child: const Text("قبول").tr(),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // 🛠️ دالة الموافقة وإعادة ضبط الجهاز
// 🛠️ دالة الموافقة وإعادة ضبط الجهاز وفك الحظر
  Future<void> _approveRequest(BuildContext context, String email,
      String newDeviceId, String requestId) async {
    try {
      // 1. البحث عن المستند الخاص بالمستخدم في مجموعة users باستخدام البريد الإلكتروني
      var userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (userQuery.docs.isNotEmpty) {
        // 2. تحديث بيانات الجهاز وفك الحظر في مستند المستخدم
        // قمنا بتحديث كلا الحقلين (device_id و deviceId) لضمان التوافق مع كل أجزاء الكود
        await userQuery.docs.first.reference.update({
          'device_id': newDeviceId,
          'deviceId': newDeviceId,
          'isBanned': false, // إلغاء الحظر العام
          'isLocked': false, // فتح قفل الحساب
          'last_login': FieldValue.serverTimestamp(), // تسجيل وقت التفعيل
        });

        // 3. تحديث حالة الطلب في مجموعة 'reset_requests' من "معلق" إلى "مقبول"
        await FirebaseFirestore.instance
            .collection('reset_requests')
            .doc(requestId)
            .update({
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
        });

        // 4. محاولة إرسال إشعار للمستخدم لإبلاغه بالقبول
        try {
          await _sendNotificationToUser(email, "تم قبول طلبك! 🎉",
              "يمكنك الآن تسجيل الدخول بجهازك الجديد والبدء في الربح.");
        } catch (notifError) {
          debugPrint("فشل إرسال الإشعار ولكن تم التفعيل بنجاح: $notifError");
        }

        // 🛡️ حارس أمني لضمان أن الشاشة لا تزال مفتوحة قبل استخدام context
        if (!context.mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("تم تفعيل الجهاز بنجاح وفك الحظر ✅"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ));
      } else {
        // إذا لم يتم العثور على مستخدم بهذا الإيميل
        throw "عذراً، لم يتم العثور على حساب مرتب بهذا البريد الإلكتروني.";
      }
    } catch (e) {
      debugPrint("خطأ أثناء معالجة الطلب: $e");

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("خطأ: ${e.toString()} ❌"),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating));
    }
  }

  // 🔔 دالة إرسال الإشعار للمستخدم
  Future<void> _sendNotificationToUser(
      String email, String title, String body) async {
    const String serverKey = 'AIzaSyDw2o4boLXWVKQ4WTW7fSfKkXsAJE5DR8I';
    const String fcmUrl = 'https://fcm.googleapis.com/fcm/send';

    final Map<String, dynamic> notificationData = {
      'notification': {
        'title': title,
        'body': body,
        'sound': 'default',
      },
      'priority': 'high',
      // يفضل هنا الإرسال لـ Topic مرتبط بإيميل المستخدم أو الـ UID الخاص به
      'to': '/topics/user_${email.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}',
    };

    await http.post(
      Uri.parse(fcmUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'key=$serverKey',
      },
      body: jsonEncode(notificationData),
    );
  }
}
