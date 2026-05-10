import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

class WithdrawalHistoryScreen extends StatelessWidget {
  const WithdrawalHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      appBar: AppBar(
        title: Text(tr('withdraw_history')), // "سجل السحوبات"
        backgroundColor: const Color(0xFF4527A0),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4527A0), Colors.black],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: StreamBuilder<QuerySnapshot>(
          // جلب طلبات السحب الخاصة بهذا المستخدم فقط مرتبة حسب الوقت
          stream: FirebaseFirestore.instance
              .collection('withdrawals')
              .where('uid', isEqualTo: uid)
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.amber));
            }

            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Text(tr('no_withdrawals'), 
                style: const TextStyle(color: Colors.white70)),
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.all(15),
              itemCount: snapshot.data!.docs.length,
              itemBuilder: (context, index) {
                var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                String status = data['status'] ?? 'pending';
                
                return Card(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: ListTile(
                    leading: _buildStatusIcon(status),
                    title: Text("${data['points_deducted']} ${tr('points')}",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text("${data['method']} - ${data['main_info']}",
                        style: const TextStyle(color: Colors.white54, fontSize: 12)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(tr(status), // ترجمة الحالة (pending, accepted, rejected)
                            style: TextStyle(color: _getStatusColor(status), fontWeight: FontWeight.bold)),
                        if (data['timestamp'] != null)
                          Text(
                            DateFormat('yyyy-MM-dd').format((data['timestamp'] as Timestamp).toDate()),
                            style: const TextStyle(color: Colors.white30, fontSize: 10),
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
    );
  }

  // دالة لاختيار لون الحالة
  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted': return Colors.greenAccent;
      case 'rejected': return Colors.redAccent;
      default: return Colors.orangeAccent;
    }
  }

  // دالة لاختيار أيقونة الحالة
  Widget _buildStatusIcon(String status) {
    IconData icon;
    Color color;
    if (status == 'accepted') {
      icon = Icons.check_circle; color = Colors.green;
    } else if (status == 'rejected') {
      icon = Icons.cancel; color = Colors.red;
    } else {
      icon = Icons.pending; color = Colors.orange;
    }
    return Icon(icon, color: color, size: 30);
  }
}