import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:confetti/confetti.dart';

class SocialMediaScreen extends StatefulWidget {
  final int initialTabIndex;
  const SocialMediaScreen({super.key, this.initialTabIndex = 0});

  @override
  State<SocialMediaScreen> createState() => _SocialMediaScreenState();
}

class _SocialMediaScreenState extends State<SocialMediaScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  DateTime? _socialTaskStartTime;
  bool _isWaitingForSocialTask = false;
  int _pendingSocialPoints = 0;
  int _pendingSocialSeconds = 30;
  String _pendingSocialCampaignId = "";
  String _pendingSocialType = "";

  final AudioPlayer _audioPlayer = AudioPlayer();
  late ConfettiController _confettiController;

  bool get isAdmin => FirebaseAuth.instance.currentUser?.uid == 'OeEwi4nMZrPjRLRiqWf1373btQT2';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _confettiController = ConfettiController(duration: const Duration(seconds: 2));
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _confettiController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (_isWaitingForSocialTask && _socialTaskStartTime != null) {
        _isWaitingForSocialTask = false;
        final int timeSpentOutside = DateTime.now().difference(_socialTaskStartTime!).inSeconds;
        if (timeSpentOutside >= _pendingSocialSeconds) {
          _finalizeSocialPoints(_pendingSocialPoints, _pendingSocialCampaignId, _pendingSocialType);
        } else {
          _showErrorSnackBar(tr('not_enough_time_social', args: [_pendingSocialSeconds.toString()]));
        }
        _socialTaskStartTime = null;
      }
    }
  }

  void _showSuccessSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  void _showErrorSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _openSocialLink(String url, int points, String campaignId, String type, int requiredSeconds) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        _pendingSocialPoints = points;
        _pendingSocialSeconds = requiredSeconds;
        _pendingSocialCampaignId = campaignId;
        _pendingSocialType = type;
        _isWaitingForSocialTask = true;
        _socialTaskStartTime = DateTime.now();

        if (mounted) {
          _showSuccessSnackBar(tr('redirecting_wait', args: [requiredSeconds.toString()]));
        }
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) _showErrorSnackBar(tr('cannot_open_link'));
      }
    } catch (e) {
      _isWaitingForSocialTask = false;
      if (mounted) _showErrorSnackBar(tr('error_occurred'));
    }
  }

  void _finalizeSocialPoints(int points, String campaignId, String type) async {
    String uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    if (uid.isEmpty) return;

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();

      DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      batch.update(userRef, {
        'points': FieldValue.increment(points),
        'claimed_campaigns': FieldValue.arrayUnion([campaignId]),
        'points_history': FieldValue.arrayUnion([
          {
            'type': type,
            'amount': points,
            'timestamp': DateTime.now().toIso8601String(),
          }
        ])
      });

      // زيادة عدد النقرات في مهمة التواصل الاجتماعي ذاتها
      DocumentReference taskRef = FirebaseFirestore.instance.collection('social_tasks').doc(campaignId);
      batch.update(taskRef, {'current_completions': FieldValue.increment(1)});

      await batch.commit();

      if (mounted) {
        _confettiController.play();
        _audioPlayer.play(AssetSource('sounds/success.mp3')).catchError((_) => debugPrint("Sound error"));
        _showSuccessSnackBar("${tr('success_rate')} $points ${tr('points')}");
      }
    } catch (e) {
      if (mounted) _showErrorSnackBar(tr('error_occurred'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: () => _showAddTaskBottomSheet(context),
              backgroundColor: Colors.amber,
              icon: const Icon(Icons.add, color: Colors.black),
              label: const Text("إضافة مهمة", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          : null,
      appBar: AppBar(
        title: Text(tr('social_media')),
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white54,
          isScrollable: true,
          tabs: [
            Tab(icon: FaIcon(FontAwesomeIcons.youtube), text: tr('youtube')),
            Tab(icon: FaIcon(FontAwesomeIcons.instagram), text: tr('instagram')),
            Tab(icon: FaIcon(FontAwesomeIcons.facebook), text: tr('facebook')),
            Tab(icon: const Icon(Icons.more_horiz), text: tr('other_platforms')),
          ],
        ),
      ),
      body: Stack(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser?.uid).snapshots(),
            builder: (context, userSnap) {
              if (!userSnap.hasData) {
                return const Center(child: CircularProgressIndicator(color: Colors.amber));
              }
              final userData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
              final List<dynamic> claimedCampaigns = userData['claimed_campaigns'] ?? [];

              return TabBarView(
                controller: _tabController,
                children: [
                  _buildTasksList('youtube', claimedCampaigns),
                  _buildTasksList('instagram', claimedCampaigns),
                  _buildTasksList('facebook', claimedCampaigns),
                  _buildTasksList('other', claimedCampaigns),
                ],
              );
            }
          ),
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 40,
              gravity: 0.2,
              colors: const [Colors.green, Colors.blue, Colors.pink, Colors.orange, Colors.purple],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTasksList(String platform, List<dynamic> claimedCampaigns) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('social_tasks')
          .where('platform', isEqualTo: platform)
          .where('isActive', isEqualTo: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.amber));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(tr('campaigns_coming_soon'), style: const TextStyle(color: Colors.white70)),
          );
        }

        var docs = snapshot.data!.docs.toList();

        // فرز المهام بحيث تظهر المهام المنتهية في الأسفل
        docs.sort((a, b) {
          var dataA = a.data() as Map<String, dynamic>;
          var dataB = b.data() as Map<String, dynamic>;
          
          int maxA = dataA['max_completions'] ?? 0;
          int currA = dataA['current_completions'] ?? 0;
          DateTime? expiryA;
          if (dataA['expiry_date'] is Timestamp) {
            expiryA = (dataA['expiry_date'] as Timestamp).toDate();
          } else if (dataA['expiry_date'] is String) {
            expiryA = DateTime.tryParse(dataA['expiry_date']);
          }
          bool isExpiredA = expiryA != null && DateTime.now().isAfter(expiryA);
          bool isExhaustedA = (maxA > 0 && currA >= maxA) || isExpiredA;
          
          int maxB = dataB['max_completions'] ?? 0;
          int currB = dataB['current_completions'] ?? 0;
          DateTime? expiryB;
          if (dataB['expiry_date'] is Timestamp) {
            expiryB = (dataB['expiry_date'] as Timestamp).toDate();
          } else if (dataB['expiry_date'] is String) {
            expiryB = DateTime.tryParse(dataB['expiry_date']);
          }
          bool isExpiredB = expiryB != null && DateTime.now().isAfter(expiryB);
          bool isExhaustedB = (maxB > 0 && currB >= maxB) || isExpiredB;
          
          if (isExhaustedA && !isExhaustedB) return 1; // نقل a للأسفل
          if (!isExhaustedA && isExhaustedB) return -1; // إبقاء a في الأعلى
          
          // إذا تساوت الحالتان (كلاهما نشط، أو كلاهما منتهي)، نرتب حسب النقاط (الأكبر أولاً)
          int pointsA = dataA['points'] ?? 0;
          int pointsB = dataB['points'] ?? 0;
          return pointsB.compareTo(pointsA);
        });

        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            var data = docs[index].data() as Map<String, dynamic>;
            String docId = docs[index].id;
            
            String title = data['title'] ?? "";
            String subtitle = data['subtitle'] ?? "";
            int points = data['points'] ?? 0;
            int seconds = data['seconds'] ?? 30;
            String url = data['url'] ?? "";
            int maxCompletions = data['max_completions'] ?? 0;
            int currentCompletions = data['current_completions'] ?? 0;
            
            DateTime? expiryDate;
            if (data['expiry_date'] is Timestamp) {
              expiryDate = (data['expiry_date'] as Timestamp).toDate();
            } else if (data['expiry_date'] is String) {
              expiryDate = DateTime.tryParse(data['expiry_date']);
            }

            bool isExpired = expiryDate != null && DateTime.now().isAfter(expiryDate);
            bool isMaxExhausted = maxCompletions > 0 && currentCompletions >= maxCompletions;
            bool isExhausted = isMaxExhausted || isExpired;

            double? progressRatio;
            if (maxCompletions > 0) {
              progressRatio = (currentCompletions / maxCompletions).clamp(0.0, 1.0);
            }

            // إظهار نص تفاعلي يوضح حالة المهمة
            if (isExpired) {
              subtitle = tr('task_expired');
            } else if (isMaxExhausted) {
              subtitle = tr('task_completed_limit');
            } else {
              if (maxCompletions > 0) {
                int remaining = maxCompletions - currentCompletions;
                subtitle = "$subtitle\n${tr('task_remaining', args: [remaining.toString()])}";
              }
              if (expiryDate != null) {
                Duration diff = expiryDate.difference(DateTime.now());
                String timeStr = "";
                if (diff.inDays > 0) {
                  timeStr = "${diff.inDays} ${tr('days_word')}";
                } else if (diff.inHours > 0) {
                  timeStr = "${diff.inHours} ${tr('hours_word')}";
                } else if (diff.inMinutes > 0) {
                  timeStr = "${diff.inMinutes} ${tr('minutes_word')}";
                } else {
                  timeStr = tr('less_than_a_minute');
                }
                subtitle = "$subtitle\n${tr('task_ends_in', args: [timeStr])}";
              }
            }

            bool isClaimed = claimedCampaigns.contains(docId);

            FaIconData iconData;
            Color iconColor;
            if (platform == 'youtube') {
              iconData = FontAwesomeIcons.youtube;
              iconColor = Colors.red;
            } else if (platform == 'instagram') {
              iconData = FontAwesomeIcons.instagram;
              iconColor = Colors.purpleAccent;
            } else if (platform == 'facebook') {
              iconData = FontAwesomeIcons.facebook;
              iconColor = Colors.blue;
            } else {
              iconData = FontAwesomeIcons.globe;
              iconColor = Colors.orange;
            }

            return _buildTaskCard(
              title,
              isClaimed ? tr('already_supported') : subtitle,
              points,
              iconData,
              iconColor,
              () {
                AdManager.showSmartAd();
                if (isExhausted) {
                  _showErrorSnackBar(isExpired ? tr('task_time_ended') : tr('task_limit_reached'));
                  return;
                }
                if (isClaimed) {
                  _showErrorSnackBar(tr('already_got_reward'));
                  return;
                }
                if (url.isEmpty) {
                  _showErrorSnackBar(tr('campaigns_coming_soon'));
                  return;
                }
                _openSocialLink(url, points, docId, "${platform}_reward", seconds);
              },
              isPremium: !isClaimed,
              isExhausted: isExhausted,
              progressRatio: progressRatio,
              onLongPress: isAdmin ? () => _showEditTaskBottomSheet(context, docId, data) : null,
            );
          },
        );
      },
    );
  }

  Widget _buildTaskCard(String title, String sub, int pts, FaIconData icon, Color iconColor, VoidCallback action, {bool isPremium = false, bool isExhausted = false, double? progressRatio, VoidCallback? onLongPress}) {
    bool isHighReward = pts > 5 && !isExhausted;

    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: isHighReward
            ? [
                BoxShadow(
                  color: Colors.amberAccent.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                )
              ]
            : [],
      ),
      child: Card(
        margin: EdgeInsets.zero,
        color: const Color(0xFF1E1E2E),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: isExhausted
                ? Colors.white10
                : (isHighReward ? Colors.amberAccent : (isPremium ? Colors.amber.withValues(alpha: 0.5) : Colors.white10)),
            width: isHighReward ? 1.5 : 1.0,
          ),
        ),
        elevation: isHighReward ? 0 : 4,
        child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        leading: FaIcon(icon, color: isExhausted ? Colors.white24 : (isPremium ? iconColor : Colors.grey), size: 46),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(title,
                  style: TextStyle(
                      color: isExhausted ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 0.5)),
            ),
            if (pts > 3 && !isExhausted) ...[
              const SizedBox(width: 8),
              const PulsingFireIcon(),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(sub, style: TextStyle(color: isExhausted ? Colors.white24 : Colors.white70, fontSize: 13, height: 1.4)),
              if (progressRatio != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progressRatio,
                          backgroundColor: Colors.white10,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isExhausted ? Colors.redAccent.withValues(alpha: 0.5) : Colors.amber,
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${(progressRatio * 100).toInt()}%",
                      style: TextStyle(
                          color: isExhausted ? Colors.white24 : Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isExhausted ? Colors.white10 : Colors.greenAccent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isExhausted ? Colors.white10 : Colors.greenAccent.withValues(alpha: 0.3)),
          ),
          child: Text("+$pts",
              style: TextStyle(
                  color: isExhausted ? Colors.white38 : Colors.greenAccent,
                  fontWeight: FontWeight.w900,
                  fontSize: 16)),
        ),
        onTap: action,
        onLongPress: onLongPress,
      ),
      ),
    );
  }

  void _showAddTaskBottomSheet(BuildContext context) {
    final titleCtrl = TextEditingController();
    final subCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final pointsCtrl = TextEditingController(text: '10');
    final secondsCtrl = TextEditingController(text: '30');
    final maxCtrl = TextEditingController(text: '100'); // 0 = غير محدود
    final daysCtrl = TextEditingController(text: '0'); // 0 = غير محدود
    String selectedPlatform = 'youtube';
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20, right: 20, top: 20
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("➕ إضافة مهمة جديدة", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPlatform,
                    decoration: InputDecoration(
                      labelText: "المنصة",
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true, fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    dropdownColor: const Color(0xFF1A1A2E),
                    style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
                    items: const [
                      DropdownMenuItem(value: 'youtube', child: Text("يوتيوب")),
                      DropdownMenuItem(value: 'instagram', child: Text("انستغرام")),
                      DropdownMenuItem(value: 'facebook', child: Text("فيسبوك")),
                      DropdownMenuItem(value: 'other', child: Text("أخرى")),
                    ],
                    onChanged: (val) => setState(() => selectedPlatform = val!),
                  ),
                  const SizedBox(height: 10),
                  _buildAdminTextField(titleCtrl, "عنوان المهمة (مثال: اشترك في القناة)"),
                  _buildAdminTextField(subCtrl, "الوصف (مثال: شاهد الفيديو واشترك)"),
                  _buildAdminTextField(urlCtrl, "الرابط (URL)"),
                  Row(
                    children: [
                      Expanded(child: _buildAdminTextField(pointsCtrl, "النقاط", isNumber: true)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildAdminTextField(secondsCtrl, "الثواني المطلوبة", isNumber: true)),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildAdminTextField(maxCtrl, "الحد الأقصى (0 = مفتوح)", isNumber: true)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildAdminTextField(daysCtrl, "ينتهي بعد X أيام (0 = أبدي)", isNumber: true)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: isSaving ? null : () async {
                        if (titleCtrl.text.isEmpty || urlCtrl.text.isEmpty) {
                          _showErrorSnackBar("يرجى إدخال العنوان والرابط على الأقل!");
                          return;
                        }
                        setState(() => isSaving = true);
                        
                        int days = int.tryParse(daysCtrl.text) ?? 0;
                        
                        try {
                          await FirebaseFirestore.instance.collection('social_tasks').add({
                            'platform': selectedPlatform,
                            'title': titleCtrl.text.trim(),
                            'subtitle': subCtrl.text.trim(),
                            'url': urlCtrl.text.trim(),
                            'points': int.tryParse(pointsCtrl.text) ?? 5,
                            'seconds': int.tryParse(secondsCtrl.text) ?? 30,
                            'max_completions': int.tryParse(maxCtrl.text) ?? 0,
                            'current_completions': 0,
                            'isActive': true,
                            'created_at': FieldValue.serverTimestamp(),
                            if (days > 0) 'expiry_date': Timestamp.fromDate(DateTime.now().add(Duration(days: days))),
                          });
                          
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            _showSuccessSnackBar("تمت إضافة المهمة بنجاح ✅");
                          }
                        } catch (e) {
                          setState(() => isSaving = false);
                          _showErrorSnackBar("حدث خطأ أثناء الإضافة");
                        }
                      },
                      child: isSaving 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Text("نشر المهمة الآن 🚀", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                    )
                  )
                ],
              )
            )
          );
        });
      }
    );
  }

  void _showEditTaskBottomSheet(BuildContext context, String docId, Map<String, dynamic> data) {
    final titleCtrl = TextEditingController(text: data['title'] ?? '');
    final subCtrl = TextEditingController(text: data['subtitle'] ?? '');
    final urlCtrl = TextEditingController(text: data['url'] ?? '');
    final pointsCtrl = TextEditingController(text: (data['points'] ?? 10).toString());
    final secondsCtrl = TextEditingController(text: (data['seconds'] ?? 30).toString());
    final maxCtrl = TextEditingController(text: (data['max_completions'] ?? 0).toString());
    
    String daysLeft = '0';
    if (data['expiry_date'] != null) {
      DateTime? expiry;
      if (data['expiry_date'] is Timestamp) {
        expiry = (data['expiry_date'] as Timestamp).toDate();
      } else if (data['expiry_date'] is String) {
        expiry = DateTime.tryParse(data['expiry_date']);
      }
      if (expiry != null && expiry.isAfter(DateTime.now())) {
        daysLeft = expiry.difference(DateTime.now()).inDays.toString();
      }
    }
    final daysCtrl = TextEditingController(text: daysLeft);

    String selectedPlatform = data['platform'] ?? 'youtube';
    if (!['youtube', 'instagram', 'facebook', 'other'].contains(selectedPlatform)) {
      selectedPlatform = 'youtube';
    }
    
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              left: 20, right: 20, top: 20
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("✏️ تعديل المهمة", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        onPressed: () async {
                          bool confirm = await showDialog(
                            context: ctx,
                            builder: (c) => AlertDialog(
                              backgroundColor: const Color(0xFF1A1A2E),
                              title: const Text("تأكيد الحذف", style: TextStyle(color: Colors.redAccent)),
                              content: const Text("هل أنت متأكد من حذف هذه المهمة نهائياً؟", style: TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("إلغاء", style: TextStyle(color: Colors.white54))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                  onPressed: () => Navigator.pop(c, true),
                                  child: const Text("حذف", style: TextStyle(color: Colors.white)),
                                ),
                              ],
                            )
                          ) ?? false;
                          
                          if (confirm) {
                            await FirebaseFirestore.instance.collection('social_tasks').doc(docId).delete();
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              _showSuccessSnackBar("تم حذف المهمة بنجاح 🗑️");
                            }
                          }
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedPlatform,
                    decoration: InputDecoration(
                      labelText: "المنصة",
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true, fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    dropdownColor: const Color(0xFF1A1A2E),
                    style: const TextStyle(color: Colors.amber, fontSize: 16, fontWeight: FontWeight.bold),
                    items: const [
                      DropdownMenuItem(value: 'youtube', child: Text("يوتيوب")),
                      DropdownMenuItem(value: 'instagram', child: Text("انستغرام")),
                      DropdownMenuItem(value: 'facebook', child: Text("فيسبوك")),
                      DropdownMenuItem(value: 'other', child: Text("أخرى")),
                    ],
                    onChanged: (val) => setState(() => selectedPlatform = val!),
                  ),
                  const SizedBox(height: 10),
                  _buildAdminTextField(titleCtrl, "عنوان المهمة (مثال: اشترك في القناة)"),
                  _buildAdminTextField(subCtrl, "الوصف (مثال: شاهد الفيديو واشترك)"),
                  _buildAdminTextField(urlCtrl, "الرابط (URL)"),
                  Row(
                    children: [
                      Expanded(child: _buildAdminTextField(pointsCtrl, "النقاط", isNumber: true)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildAdminTextField(secondsCtrl, "الثواني المطلوبة", isNumber: true)),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: _buildAdminTextField(maxCtrl, "الحد الأقصى (0 = مفتوح)", isNumber: true)),
                      const SizedBox(width: 10),
                      Expanded(child: _buildAdminTextField(daysCtrl, "ينتهي بعد X أيام (0 = أبدي)", isNumber: true)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                      ),
                      onPressed: isSaving ? null : () async {
                        if (titleCtrl.text.isEmpty || urlCtrl.text.isEmpty) {
                          _showErrorSnackBar("يرجى إدخال العنوان والرابط على الأقل!");
                          return;
                        }
                        setState(() => isSaving = true);
                        
                        int days = int.tryParse(daysCtrl.text) ?? 0;
                        
                        try {
                          Map<String, dynamic> updateData = {
                            'platform': selectedPlatform,
                            'title': titleCtrl.text.trim(),
                            'subtitle': subCtrl.text.trim(),
                            'url': urlCtrl.text.trim(),
                            'points': int.tryParse(pointsCtrl.text) ?? 5,
                            'seconds': int.tryParse(secondsCtrl.text) ?? 30,
                            'max_completions': int.tryParse(maxCtrl.text) ?? 0,
                          };

                          if (days > 0) {
                            updateData['expiry_date'] = Timestamp.fromDate(DateTime.now().add(Duration(days: days)));
                          } else {
                            updateData['expiry_date'] = FieldValue.delete();
                          }

                          await FirebaseFirestore.instance.collection('social_tasks').doc(docId).update(updateData);
                          
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            _showSuccessSnackBar("تم تعديل المهمة بنجاح ✅");
                          }
                        } catch (e) {
                          setState(() => isSaving = false);
                          _showErrorSnackBar("حدث خطأ أثناء التعديل");
                        }
                      },
                      child: isSaving 
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                          : const Text("حفظ التعديلات 💾", style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                    )
                  )
                ],
              )
            )
          );
        });
      }
    );
  }

  Widget _buildAdminTextField(TextEditingController ctrl, String label, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: isNumber ? TextInputType.number : TextInputType.text,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54, fontSize: 13),
          filled: true,
          fillColor: Colors.white10,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.amber)),
        ),
      ),
    );
  }
}

// ودجت الأيقونة المتحركة (النار) لتشجيع المستخدمين
class PulsingFireIcon extends StatefulWidget {
  const PulsingFireIcon({super.key});

  @override
  State<PulsingFireIcon> createState() => _PulsingFireIconState();
}

class _PulsingFireIconState extends State<PulsingFireIcon> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    // إعداد حركة النبض (تكبير وتصغير مستمر) لتلفت الانتباه
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
    _animation = Tween<double>(begin: 1.0, end: 1.3).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _animation,
      child: const Text("🔥", style: TextStyle(fontSize: 18)),
    );
  }
}