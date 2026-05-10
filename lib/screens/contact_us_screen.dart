import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:check_vpn_connection/check_vpn_connection.dart';

class ContactUsScreen extends StatefulWidget {
  const ContactUsScreen({super.key});

  @override
  State<ContactUsScreen> createState() => _ContactUsScreenState();
}

class _ContactUsScreenState extends State<ContactUsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _messageController = TextEditingController();
  bool _isSending = false;
  String selectedIssue = 'withdraw_issue';

Future<void> _sendMessage() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      // 1. جلب حالة الحماية من Firestore (مستند config)
      final configDoc = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      bool isVpnEnabledInConfig = configDoc.data()?['is_vpn_protection_enabled'] ?? true;

      // 2. التحقق من الـ VPN
      if (isVpnEnabledInConfig) {
        final isVpnActive = await CheckVpnConnection.isVpnActive();
        if (!mounted) return;

        if (isVpnActive) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('close_vpn')), backgroundColor: Colors.red),
          );
          return;
        }
      }
    } catch (e) {
      debugPrint("Error fetching VPN config: $e");
    }

    // تفعيل مؤشر التحميل
    setState(() => _isSending = true);
    final user = FirebaseAuth.instance.currentUser;

    try {
      // 3. إرسال الرسالة إلى Firestore
      await FirebaseFirestore.instance.collection('support_tickets').add({
        'uid': user?.uid,
        'email': user?.email ?? 'anonymous',
        'type': selectedIssue, // 👈 استخدمنا selectedIssue لضمان تطابق الاختيار من القائمة
        'message': _messageController.text.trim(),
        'status': 'open',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr('message_sent_success')),
            backgroundColor: Colors.green),
      );
      
      // العودة للشاشة السابقة بعد النجاح
      Navigator.pop(context);
    } catch (e) {
      debugPrint("Error sending message: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('error_occurred')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('contact_us'))),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              DropdownButton<String>(
                value: selectedIssue, // تأكد أن هذه القيمة هي "withdraw_issue"
                items: [
                  DropdownMenuItem(
                    value:
                        "withdraw_issue", // 👈 القيمة البرمجية الثابتة (يجب أن تطابق selectedIssue)
                    child: Text(tr(
                        'withdraw_issue')), // 👈 النص المترجم الذي يراه المستخدم
                  ),
                  DropdownMenuItem(
                    value: "account_issue",
                    child: Text(tr('account_issue')),
                  ),
                ],
                onChanged: (String? newValue) {
                  // 👈 تأكد من إضافة علامة الاستفهام هنا
                  if (newValue != null) {
                    // 👈 فحص التأكد من أن القيمة ليست فارغة
                    setState(() {
                      selectedIssue =
                          newValue; // 👈 الآن سيختفي الخطأ لأننا تأكدنا أنها String
                    });
                  }
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _messageController,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: tr('message_hint'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => v!.isEmpty ? tr('field_required') : null,
              ),
              const SizedBox(height: 30),
              _isSending
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                      onPressed: _sendMessage,
                      child: Text(tr('send_message')),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
