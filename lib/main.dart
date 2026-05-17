import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

// Imports الشاشات والخدمات
import 'package:syria_earn_pro/screens/home_screen.dart';
import 'package:syria_earn_pro/screens/login_screen.dart';
import 'package:syria_earn_pro/screens/withdraw_screen.dart';
import 'package:syria_earn_pro/screens/settings_screen.dart';
import 'package:syria_earn_pro/screens/splash_screen.dart';
import 'package:syria_earn_pro/services/ad_manager.dart';
import 'package:syria_earn_pro/widgets/global_bottom_ad.dart';
import 'package:syria_earn_pro/screens/privacy_policy_screen.dart';
import 'package:syria_earn_pro/screens/contact_us_screen.dart';
import 'package:syria_earn_pro/providers/theme_provider.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// الـ UID الخاص بحساب الأدمن
const String adminUidConst = 'OeEwi4nMZrPjRLRiqWf1373btQT2';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. تهيئة الفايربيس واللغات أولاً لضمان تحميل الداتا
  await Firebase.initializeApp();
  await EasyLocalization.ensureInitialized();
  // 2. 🛡️ جدار الحماية ضد تطبيقات النسخ والبيئات الوهمية (Cloners Detection)
  await _checkAppCloningProtection();

  // 3. 🛡️ الإصلاح الحرج: ننتظر قليلاً حتى تكتمل دورة الفايربيس للتحقق من هوية الأدمن بشكل دقيق
  final user = FirebaseAuth.instance.currentUser;
  bool isUserAdmin = user != null && user.uid == adminUidConst;

  if (!isUserAdmin) {
    // تشغيل نظام الإعلانات فقط وحصرياً للمستخدمين العاديين لحماية حسابك
    MobileAds.instance.initialize();
    AdManager.initialize();
  } else {
    debugPrint(
        "🚫 Security Alert: Admin detected! Bypassing MobileAds initialization securely.");
  }

  // إعداد قنوات التنبيهات
  await _setupNotificationChannels();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('ar'),
        Locale('tr'),
        Locale('en'),
        Locale('es'),
        Locale('hi')
      ],
      path: 'assets/translations',
      child: ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: const MyApp(),
      ),
    ),
  );
}

// 🛡️ دالة مكافحة واصطياد برامج النسخ (Parallel Space / App Cloner)
Future<void> _checkAppCloningProtection() async {
  try {
    if (Platform.isAndroid) {
      // فحص الكلمات المشبوهة في مسار المجلد الحالي للتثبيت
      final List<String> clonerKeywords = [
        'parallel',
        'dualspace',
        'clone',
        'virtual',
        'multiple',
        '2face',
        'multi_account'
      ];

      String currentDataDir = Directory.current.path.toLowerCase();

      for (String keyword in clonerKeywords) {
        if (currentDataDir.contains(keyword)) {
          // 🚨 تم كشف تشغيل التطبيق داخل بيئة منسوخة خبيثة! نغلق الهاتف فوراً
          SystemNavigator.pop();
          exit(0);
        }
      }
    }
  } catch (_) {}
}

Future<void> _setupNotificationChannels() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'reward_timer_id',
    'تنبيهات المكافآت',
    importance: Importance.max,
  );
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // التحقق الديناميكي من الأدمن عند الرجوع للتطبيق لمنع ظهور الإعلانات المفتوحة بالخطأ
    final user = FirebaseAuth.instance.currentUser;
    bool isUserAdmin = user != null && user.uid == adminUidConst;

    if (state == AppLifecycleState.resumed && !isUserAdmin) {
      AdManager.showAppOpenAdOnce();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Syria Earn Pro',
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
        primaryColor: const Color(0xFF4527A0),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF4527A0),
          secondary: Colors.deepPurpleAccent,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF5F7FA),
          elevation: 0,
          foregroundColor: Color(0xFF2D3436),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.indigo,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
        ),
      ),
      builder: (context, child) {
        // فحص مستمر داخل الشجرة لاستثناء الأدمن من الإعلانات المنبثقة السفلية
        final user = FirebaseAuth.instance.currentUser;
        bool isUserAdmin = user != null && user.uid == adminUidConst;

        return Scaffold(
          body: Column(
            children: [
              Expanded(child: child!),
              if (!isUserAdmin) const GlobalBottomAd(),
            ],
          ),
        );
      },
      initialRoute: '/',
      routes: {
        '/': (context) => const SplashScreen(),
        '/login': (context) => const LoginScreen(),
        '/contact': (context) => const ContactUsScreen(),
        '/home': (context) => const HomeScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/withdraw': (context) => const WithdrawScreen(),
        '/privacy': (context) => const PrivacyPolicyScreen(),
      },
    );
  }
}
