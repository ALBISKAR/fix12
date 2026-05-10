import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; //
import 'package:easy_localization/easy_localization.dart'; //

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  // دالة لفتح الرابط الخارجي
  Future<void> _launchPrivacyUrl() async {
    final Uri url = Uri.parse('https://sites.google.com/view/syria-earn');
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw Exception('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        // استخدام المفتاح من ملفات الـ JSON ليدعم العربية والتركية
        title: Text(tr('privacy_policy')), 
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("1. ${tr('collect_data')}"),
            _bodyText(tr('collect_data_desc')),
            
            _sectionTitle("2. ${tr('use_data')}"),
            _bodyText(tr('use_data_desc')),
            
            _sectionTitle("3. ${tr('ads')}"),
            _bodyText(tr('ads_desc')),

            const SizedBox(height: 30),
          
            // زر رابط سياسة الخصوصية الكاملة
            Center(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber.withValues(alpha: 0.1),
                  foregroundColor: Colors.amber,
                  side: const BorderSide(color: Colors.amber),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _launchPrivacyUrl,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(tr('read_full_policy'), 
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),

            const SizedBox(height: 30),
            Center(
              child: Text("${tr('last_update')}: 2026",
                  style: const TextStyle(color: Colors.white24, fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(title,
          style: const TextStyle(
              color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _bodyText(String text) {
    return Text(text,
        style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5));
  }
}