import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:easy_localization/easy_localization.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  // ✅ إضافة متغيرات جلب القيم من فايربيس
  int inviterReward = 50;
  int newUserReward = 25;

  @override
  void initState() {
    super.initState();
    _fetchReferralRewards(); // ✅ 2. جلب القيم عند فتح الشاشة
  }

  Future<void> _fetchReferralRewards() async {
    try {
      var config = await FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .get();

      if (config.exists && mounted) {
        setState(() {
          // ✅ 3. جلب الأسماء تماماً كما تظهر في صورتك (Firestore)
          inviterReward = config.data()?['referral_reward_inviter'] ?? 50;
          newUserReward = config.data()?['referral_reward_new_user'] ?? 25;
        });
      }
    } catch (e) {
      debugPrint("Error fetching rewards: $e");
    }
  }

  void _finishIntro() async {
    // حفظ حالة أن المستخدم شاهد المقدمة
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_intro_seen', true);

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Stack(
        children: [
          PageView(
            controller: _controller,
            onPageChanged: (index) => setState(() => _currentIndex = index),
children: [
  _buildPage(tr('intro_1_title'), tr('intro_1_desc'), Icons.play_circle_fill),
  _buildPage(tr('intro_2_title'), tr('intro_2_desc'), Icons.stars),
  _buildPage(tr('intro_3_title'), tr('intro_3_desc'), Icons.account_balance_wallet),
  
  // ✅ الصفحة الرابعة: جلب النصوص مع الأرقام الحقيقية من السيرفر
  _buildPage(
    tr('intro_referral_title'), 
    tr('intro_referral_desc', namedArgs: {
      'inviter': inviterReward.toString(),
      'new_user': newUserReward.toString()
    }), 
    Icons.group_add_rounded
  ),
],
          ),
          Positioned(
            bottom: 50,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                    onPressed: _finishIntro,
                    child: Text(tr('skip'),
                        style: const TextStyle(color: Colors.white54))),
                ElevatedButton(
                  onPressed: () {
                    // التعديل هنا ليكون الرقم 3 (لأننا أصبحنا 4 صفحات)
                    if (_currentIndex == 3) {
                      _finishIntro();
                    } else {
                      _controller.nextPage(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.ease);
                    }
                  },
                  // التعديل هنا أيضاً للزر الأخير
                  child: Text(_currentIndex == 3 ? tr('start') : tr('next')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage(String title, String desc, IconData icon) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 100, color: Colors.amber),
        const SizedBox(height: 30),
        Text(title,
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white)),
        const SizedBox(height: 15),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(desc,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70)),
        ),
      ],
    );
  }
}
