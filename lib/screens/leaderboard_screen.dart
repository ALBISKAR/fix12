import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1E),
      appBar: AppBar(
        title: Text(tr('leaderboard_title')),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Column(
        children: [
          // 1. قسم الإحصائيات الحية مع الأنميشن
          _buildGlobalStats(),

          const SizedBox(height: 10),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                tr('top_players'),
                style: const TextStyle(
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                    fontSize: 18),
              ),
            ),
          ),

          // 2. قائمة المتصدرين
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .orderBy('points', descending: true)
                  .limit(10)
                  .snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: snap.data!.docs.length,
                  itemBuilder: (context, i) {
                    var d = snap.data!.docs[i].data() as Map<String, dynamic>;
                    return Card(
                      color: Colors.white.withValues(alpha: 0.05),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        leading: _buildRankBadge(i + 1),
                        title: Text(
                          d['name'] ?? tr('unknown_player'),
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${d['points']}",
                              style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16),
                            ),
                            const SizedBox(width: 5),
                            Text(tr('points_unit'),
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalStats() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('app_settings')
          .doc('config')
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox(height: 100);
        var data = snap.data!.data() as Map<String, dynamic>;

        return Container(
          margin: const EdgeInsets.all(15),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white10),
              boxShadow: [
                BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.02),
                    blurRadius: 20,
                    spreadRadius: 2)
              ]),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const LivePulse(),
                      const SizedBox(width: 8),
                      Text(
                        tr('live_stats').toUpperCase(),
                        style: TextStyle(
                            color: Colors.greenAccent.withValues(alpha: 0.8),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2),
                      ),
                    ],
                  ),
                  const LiveClock(),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  _statItem(
                      tr('total_users'),
                      data['total_users']?.toString() ?? "0",
                      Icons.people_outline),
                  _statDivider(),
                  _statItem(
                      tr('total_points'),
                      data['total_points_distributed']?.toString() ?? "0",
                      Icons.stars_rounded),
                ],
              ),
              const Divider(color: Colors.white10, height: 30),
              Row(
                children: [
                  _statItem(
                      tr('weekly_points'),
                      data['weekly_points']?.toString() ?? "0",
                      Icons.calendar_today_outlined),
                  _statDivider(),
                  _statItem(
                      tr('daily_points'),
                      data['daily_points']?.toString() ?? "0",
                      Icons.bolt_rounded),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.amber.withValues(alpha: 0.8), size: 20),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Text(
              value,
              key: ValueKey<String>(value),
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  fontFamily: 'monospace'),
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(height: 40, width: 1, color: Colors.white10);
  }

  Widget _buildRankBadge(int rank) {
    Color color = Colors.grey;
    if (rank == 1) color = Colors.amber;
    if (rank == 2) color = Colors.blueGrey;
    if (rank == 3) color = Colors.brown;

    return CircleAvatar(
      backgroundColor: color,
      radius: 15,
      child: Text("$rank",
          style: const TextStyle(
              color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}

// الودجت المتحركة للدائرة النابضة
class LivePulse extends StatefulWidget {
  const LivePulse({super.key});

  @override
  State<LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<LivePulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _controller,
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(
          color: Colors.greenAccent,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.greenAccent, blurRadius: 4, spreadRadius: 1)
          ],
        ),
      ),
    );
  }
}

class LiveClock extends StatefulWidget {
  const LiveClock({super.key});

  @override
  State<LiveClock> createState() => _LiveClockState();
}

class _LiveClockState extends State<LiveClock> {
  late Timer _timer;
  String _currentTime = "";

  @override
  void initState() {
    super.initState();
    _updateTime();
    // تحديث الوقت كل ثانية واحدة
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateTime();
    });
  }

  void _updateTime() {
    if (mounted) {
      setState(() {
        _currentTime = DateFormat('HH:mm:ss').format(DateTime.now());
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel(); // إيقاف المؤقت عند الخروج من الشاشة
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _currentTime,
      style: const TextStyle(
        color: Colors.white24,
        fontSize: 10,
        fontFamily: 'monospace', // لضمان ثبات عرض الأرقام أثناء الحركة
      ),
    );
  }
}
