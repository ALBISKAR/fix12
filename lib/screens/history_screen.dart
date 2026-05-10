import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final String uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        title: Text(tr('points_history')), // "سجل النقاط" مترجم
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var userData = snapshot.data!.data() as Map<String, dynamic>?;
          // جلب السجل من الحقل المخصص في Firestore
          var history = userData?['points_history'] as List? ?? [];
          List sortedHistory = history.reversed.toList(); // عرض الأحدث أولاً

          if (sortedHistory.isEmpty) {
            return Center(child: Text(tr('no_history_yet'), style: const TextStyle(color: Colors.white24)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: sortedHistory.length,
            itemBuilder: (context, i) {
              var item = sortedHistory[i] as Map<String, dynamic>;
              
              // تحويل التاريخ من Timestamp
              DateTime? date;
              if (item['timestamp'] is Timestamp) {
                date = (item['timestamp'] as Timestamp).toDate();
              }
              String formattedDate = date != null
                  ? DateFormat('yyyy/MM/dd - hh:mm a').format(date)
                  : "---";

              return Card(
                color: Colors.white.withAlpha(12), // تنسيق مشابه لبطاقات الأدمن
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.stars, color: Colors.amber),
                  title: Text(tr(item['type'] ?? 'unknown'), 
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(formattedDate, 
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  trailing: Text("+${item['amount'] ?? 0}", 
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                ),
              );
            },
          );
        },
      ),
    );
  }
}