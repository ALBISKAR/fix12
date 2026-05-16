import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:easy_localization/easy_localization.dart';

class VideosTabScreen extends StatelessWidget {
  final int unityRemaining;
  final int admobRemaining;
  final int unitySecondsLeft;
  final int admobSecondsLeft;
  final int unityPoints;
  final int admobPoints;
  final bool isWaiting;
  final VoidCallback onUnityTap;
  final VoidCallback onAdMobTap;

  const VideosTabScreen({
    super.key,
    required this.unityRemaining,
    required this.admobRemaining,
    required this.unitySecondsLeft,
    required this.admobSecondsLeft,
    required this.unityPoints,
    required this.admobPoints,
    required this.isWaiting,
    required this.onUnityTap,
    required this.onAdMobTap,
  });

  String _formatTime(int seconds) {
    int minutes = seconds ~/ 60;
    int remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildVideoServerCard(
          title: tr('unity_ad'),
          sub: unitySecondsLeft > 0 ? "${tr('wait')} ${_formatTime(unitySecondsLeft)}" : tr('video_ad_sub'),
          points: unityPoints,
          icon: FontAwesomeIcons.unity,
          remaining: unityRemaining,
          isPremium: true,
          onTap: onUnityTap,
        ),
        const SizedBox(height: 20),
        _buildVideoServerCard(
          title: tr('admob_ad'),
          sub: admobSecondsLeft > 0 ? "${tr('wait')} ${_formatTime(admobSecondsLeft)}" : tr('video_ad_sub'),
          points: admobPoints,
          icon: FontAwesomeIcons.google,
          remaining: admobRemaining,
          isPremium: false,
          onTap: onAdMobTap,
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildVideoServerCard({
    required String title,
    required String sub,
    required int points,
    required dynamic icon,
    required VoidCallback onTap,
    required int remaining,
    bool isPremium = false,
  }) {
    return Card(
      color: const Color(0xFF1E1E2E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: isPremium ? Colors.amber.withValues(alpha: 0.3) : Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        leading: ShaderMask(
          shaderCallback: (Rect bounds) => LinearGradient(
            colors: isPremium ? [Colors.amber, Colors.orangeAccent] : [Colors.blueAccent, Colors.cyanAccent],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: FaIcon(icon as FaIconData?, color: Colors.white, size: 42),
        ),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 5),
            Text(sub, style: const TextStyle(color: Colors.white70, fontSize: 16)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: remaining > 0 ? Colors.green.withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                "${tr('remaining')}: $remaining",
                style: TextStyle(color: remaining > 0 ? Colors.greenAccent : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
        trailing: Text("+$points", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, fontSize: 18)),
        onTap: remaining > 0 ? onTap : null,
      ),
    );
  }
}