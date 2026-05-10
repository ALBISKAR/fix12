import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';
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

  // 1. تشغيل اللغات والـ Firebase (أساسي للواجهة)
  await EasyLocalization.ensureInitialized();
  await Firebase.initializeApp();

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

  // 2. تشغيل الإعلانات بعد فترة قصيرة جداً لضمان ظهور الواجهة أولاً
  Future.delayed(const Duration(milliseconds: 500), () {
    MobileAds.instance.initialize();
    AdManager.initialize();
    // AdManager.connectTapjoy();
  });
}

// دالة منفصلة للإعدادات لضمان عدم حبس المستخدم في شاشة بيضاء
Future<void> setupServices() async {
  try {
    await Firebase.initializeApp();
    AdManager.initialize();
    AdManager.connectTapjoy(); // بدون await هنا لضمان السرعة

    // جلب الإعدادات (يفضل وضعها داخل Provider أو Bloc لاحقاً)
    FirebaseFirestore.instance
        .collection('app_settings')
        .doc('config')
        .get()
        .then((doc) {
      if (doc.exists) debugPrint("✅ Connected to Firestore Config");
    });

    // إعداد التنبيهات
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'reward_timer_id',
      'تنبيهات المكافآت',
      importance: Importance.max,
    );
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  } catch (e) {
    debugPrint("❌ Initialization Error: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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

      // ثيم التطبيق (فاتح)
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

      // ثيم التطبيق (مظلم)
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        primarySwatch: Colors.indigo,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.black,
          elevation: 0,
        ),
      ),

      // الإعلان السفلي الثابت في كل التطبيق
      builder: (context, child) {
        return Scaffold(
          body: Column(
            children: [
              Expanded(child: child!),
              const GlobalBottomAd(),
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
