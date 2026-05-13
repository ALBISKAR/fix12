import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. تهيئة الخدمات الأساسية بترتيب صحيح
  await Firebase.initializeApp();
  await EasyLocalization.ensureInitialized();

  // تهيئة الإعلانات (AdManager يحتوي الآن على App Open)
  MobileAds.instance.initialize();
  AdManager.initialize();

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

// دالة إعداد التنبيهات (تم فصلها لتنظيف الـ main)
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

// استخدام WidgetsBindingObserver لمراقبة حالة التطبيق (فتح/إغلاق) لإظهار إعلان الفتح
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

  // هذه الدالة المسؤولة عن إظهار إعلان فتح التطبيق عند العودة إليه
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AdManager.showAppOpenAd();
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
        return Scaffold(
          body: Column(
            children: [
              Expanded(child: child!), // التطبيق يأخذ المساحة المتبقية
              const GlobalBottomAd(), // الإعلانات في الأسفل تماماً
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
