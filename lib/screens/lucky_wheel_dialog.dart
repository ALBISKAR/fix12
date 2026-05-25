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

class _LuckyWheelDialogState extends State<LuckyWheelDialog> {
  StreamController<int> selected = StreamController<int>();
  late ConfettiController _confettiController;
  bool _isSpinning = false;

  @override
  void initState() {
    super.initState();
    _confettiController =
        ConfettiController(duration: const Duration(seconds: 2));
  }

  @override
  void dispose() {
    selected.close();
    _confettiController.dispose();
    super.dispose();
  }

  int _calculateResult() {
    final random = Random().nextDouble();
    if (random < 0.60) return Random().nextInt(3) + 1;
    if (random < 0.90) return Random().nextInt(4) + 4;
    return Random().nextInt(3) + 8;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      content: SizedBox(
        height: 350,
        child: Stack(
          alignment: Alignment.center,
          children: [
            FortuneWheel(
              selected: selected.stream,
              items: [
                for (int i = 1; i <= 10; i++)
                  FortuneItem(
                      child: Text("$i",
                          style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
          onPressed: _isSpinning
              ? null
              : () {
                  setState(() => _isSpinning = true);
                  int result = _calculateResult();
                  selected.add(result - 1);

                  // احفظ الـ messenger و navigator قبل async gap
                  final messenger = ScaffoldMessenger.of(context);
                  final navigator = Navigator.of(context);

                  Future.delayed(const Duration(seconds: 4), () {
                    if (!mounted) return;

                    _confettiController.play();
                    widget.onRewardEarned(result);

                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                            tr('you_won_points', args: [result.toString()])),
                      ),
                    );

                    Future.delayed(const Duration(seconds: 2), () {
                      if (!mounted) return;
                      navigator.pop();
                    });
                  });
                },

          child: Text(tr('spin_wheel')), // 2. نص الزر مترجم
        ),
      ],
    );
  }
}
