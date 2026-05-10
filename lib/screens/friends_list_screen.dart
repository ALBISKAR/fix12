import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FriendsListScreen extends StatelessWidget {
  final String referralCode;

  const FriendsListScreen({super.key, required this.referralCode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1117), // نفس لون خلفية تطبيقك
      appBar: AppBar(
        title: Text(tr('my_friends'), style: TextStyle(fontSize: 18)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // البحث عن المستخدمين الذين يحملون كود الإحالة الخاص بك
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('referred_by', isEqualTo: referralCode)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.purpleAccent));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var friendData = snapshot.data!.docs[index].data() as Map<String, dynamic>;
              String name = friendData['name'] ?? "مستخدم جديد";
              String email = friendData['email'] ?? "";
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.white10),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.purpleAccent.withValues(alpha: 0.2),
                    child: Text(name[0].toUpperCase(), 
                        style: const TextStyle(color: Colors.purpleAccent, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(email, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  trailing: const Icon(Icons.check_circle, color: Colors.greenAccent, size: 18),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.group_add_outlined, size: 80, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 15),
          Text(tr('no_friends_yet'), style: const TextStyle(color: Colors.white38, fontSize: 16)),
          Text(tr('share_your_code'), style: const TextStyle(color: Colors.white24, fontSize: 12)),
        ],
      ),
    );
  }
}