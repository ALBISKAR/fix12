import 'package:flutter/material.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GlobalBottomAd extends StatelessWidget {
  const GlobalBottomAd({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔐 فحص المسؤول لمنع تحميل الإعلان نهائياً
    final String? currentUid = FirebaseAuth.instance.currentUser?.uid;
    
    // تأكد من مطابقة المعرف الخاص بك
    if (currentUid == 'OeEwi4nMZrPjRLRiqWf1373btQT2') {
      return const SizedBox.shrink(); 
    }

    return Container(
      width: double.infinity,
      height: 50,
      color: Colors.transparent,
      alignment: Alignment.center,
      // 🔽 استدعاء النظام الموحد الجديد
      child: AdManager.smartBanner(null), 
    );
  }
}