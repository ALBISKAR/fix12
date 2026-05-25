import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:easy_localization/easy_localization.dart';
import 'lucky_wheel_dialog.dart';
import '../services/ad_manager.dart'; // تأكد من الاستيراد

class VideosTabScreen extends StatefulWidget {
  // 1. تغيير إلى StatefulWidget
  final int unityRemaining;
  final int admobRemaining;
  final int unitySecondsLeft;
  final int admobSecondsLeft;
  final bool isWaiting;
  final VoidCallback onUnityTap;
  final VoidCallback onAdMobTap;
  final Function(int) onPointsEarned;

  const VideosTabScreen({
    super.key,
    required this.unityRemaining,
    required this.admobRemaining,
    required this.unitySecondsLeft,
    required this.admobSecondsLeft,
    required this.isWaiting,
    required this.onUnityTap,
    required this.onAdMobTap,
    required this.onPointsEarned,
  });

  @override
  State<VideosTabScreen> createState() => _VideosTabScreenState();
}

class _VideosTabScreenState extends State<VideosTabScreen> {
  // 2. إنشاء الـ State

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  void _showLuckyWheelDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => LuckyWheelDialog(
        onRewardEarned: (points) {
          widget.onPointsEarned(points); // استخدام widget. للوصول للمتغيرات
        },
      ),
    );
  }

  void _openLuckyWheel(BuildContext context, VoidCallback baseTapAction) {
    // 1. حالة الأدمن: فتح مباشر
    if (AdManager.isAdmin) {
      _showLuckyWheelDialog(context);
      return;
    }

    // 2. حالة المستخدم العادي: ربط بانتهاء الإعلان
    AdManager.onAdClosedCallback = () {
      // ✅ فحص الأمان الأول: هل لا تزال الشاشة موجودة؟
      if (!context.mounted) return;

      Future.microtask(() {
        // ✅ فحص الأمان الثاني: هل لا تزال الشاشة موجودة بعد المهام المؤجلة؟
        if (!context.mounted) return;

        _showLuckyWheelDialog(context);
      });

      // تصفير الكولباك لضمان عدم التكرار
      AdManager.onAdClosedCallback = null;
    };

    // 3. تشغيل الإعلان
    baseTapAction();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildVideoServerCard(
          title: tr('unity_ad'),
          sub: widget.unitySecondsLeft > 0 // الوصول للمتغيرات عبر widget.
              ? tr('wait_time', args: [_formatTime(widget.unitySecondsLeft)])
              : tr('lucky_wheel_prompt'),
          icon: FontAwesomeIcons.unity,
          remaining: widget.unityRemaining,
          isPremium: true,
          onTap: () => _openLuckyWheel(context, widget.onUnityTap),
        ),
        const SizedBox(height: 20),
        _buildVideoServerCard(
          title: tr('admob_ad'),
          sub: widget.admobSecondsLeft > 0
              ? tr('wait_time', args: [_formatTime(widget.admobSecondsLeft)])
              : tr('win_chance_sub'),
          icon: FontAwesomeIcons.google,
          remaining: widget.admobRemaining,
          isPremium: false,
          onTap: () => _openLuckyWheel(context, widget.onAdMobTap),
        ),
      ],
    );
  }

  // الدالة _buildVideoServerCard تبقى كما هي (داخل الـ State)
  Widget _buildVideoServerCard({
    required String title,
    required String sub,
    required dynamic icon,
    required VoidCallback onTap,
    required int remaining,
    bool isPremium = false,
  }) {
    // نفس الكود الخاص بك هنا
    return Card(
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
            color: isPremium
                ? Colors.amber.withValues(alpha: 0.5)
                : Colors.cyan.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        leading: FaIcon(icon,
            color: isPremium ? Colors.amber : Colors.cyanAccent, size: 40),
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Text(sub, style: const TextStyle(color: Colors.white70)),
        trailing: Icon(Icons.refresh,
            color: remaining > 0 ? Colors.amber : Colors.grey),
        onTap: remaining > 0 ? onTap : null,
      ),
    );
  }

  @override
  void dispose() {
    // ✅ مسح الكولباك عند إغلاق الشاشة لمنع استدعاءات خاطئة
    AdManager.onAdClosedCallback = null;
    super.dispose();
  }
}
