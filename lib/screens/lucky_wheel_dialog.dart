import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_fortune_wheel/flutter_fortune_wheel.dart';
import 'package:confetti/confetti.dart';
import 'package:easy_localization/easy_localization.dart'; // 1. استيراد الحزمة

class LuckyWheelDialog extends StatefulWidget {
  final Function(int) onRewardEarned;
  const LuckyWheelDialog({super.key, required this.onRewardEarned});

  @override
  State<LuckyWheelDialog> createState() => _LuckyWheelDialogState();
}

class _LuckyWheelDialogState extends State<LuckyWheelDialog> with SingleTickerProviderStateMixin {
  StreamController<int> selected = StreamController<int>();
  late ConfettiController _confettiController;
  bool _isSpinning = false;
  late AnimationController _btnAnimController;
  late Animation<double> _btnScaleAnimation;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));

    _btnAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    
    _btnScaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _btnAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    selected.close();
    _confettiController.dispose();
    _btnAnimController.dispose();
    super.dispose();
  }

  int _calculateResult() {
    final random = Random();
    final value = random.nextDouble(); // A value between 0.0 and 1.0

    if (value < 0.01) { // 1% chance for 9 or 10
      return random.nextInt(2) + 9; // Returns 9 or 10
    } else if (value < 0.10) { // 9% chance for 5 to 8 (0.10 = 0.01 + 0.09)
      return random.nextInt(4) + 5; // Returns 5, 6, 7, or 8
    } else { // 90% chance for 1 to 4
      return random.nextInt(4) + 1; // Returns 1, 2, 3, or 4
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      content: SizedBox(
        width: 320,
        height: 380,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // إضافة هالة مضيئة حول العجلة للتأثير البصري
            Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [
                    Colors.amber.withValues(alpha: 0.2),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 260,
              height: 260,
              child: FortuneWheel(
                animateFirst: false, // 🛑 إيقاف الدوران التلقائي عند فتح النافذة
                selected: selected.stream,
                items: [
                  for (int i = 1; i <= 10; i++)
                    FortuneItem(
                      child: Text(
                        "$i",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: 3,
                              color: Colors.black.withValues(alpha: 0.5),
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
                // تخصيص مظهر المؤشر (السهم)
                // استخدام الإعدادات الافتراضية إذا لم تكن الخاصية مخصصة متوفرة
              ),
            ),
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              // زيادة عدد وتنوع_confetti
              emissionFrequency: 0.05,
              numberOfParticles: 50,
              // ألوان_confetti زاهية
              colors: [
                Colors.red,
                Colors.orange,
                Colors.yellow,
                Colors.green,
                Colors.blue,
                Colors.purple,
                Colors.pink,
                Colors.teal,
              ],
            ),
          ],
        ),
      ),
      actions: [
        ScaleTransition(
          scale: _btnScaleAnimation,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              padding: EdgeInsets.symmetric(horizontal: 40, vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
              elevation: 8,
              // إضافة تأثير لمسة عند الضغط
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: _isSpinning
                ? null
                : () {
                    _btnAnimController.stop(); // 🛑 إيقاف النبض فور النقر
                    setState(() => _isSpinning = true);
                    int result = _calculateResult();
                    selected.add(result - 1);

                    // احفظ الـ messenger و navigator قبل async gap
                    ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);

                    Future.delayed(const Duration(seconds: 4), () {
                      if (!mounted) return;

                      _confettiController.play();
                      widget.onRewardEarned(result);

                      Future.delayed(const Duration(seconds: 2), () {
                        if (!mounted) return;
                        navigator.pop();
                      });
                    });
                  },
                child: Text(
                  tr('spin_wheel'),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
        ),
      ],
      // إضافة تأثير ظهور للحوار
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      elevation: 24,
    );
  }
}
