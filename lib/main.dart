import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'firebase_options.dart';
// ✅ استيراد حزمة السيرفر الجديد لإعلانات Start.io

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
import 'package:syria_earn_pro/utils/security_utils.dart'; // ✅ تأكد من استيراد دالة فحص الإنترنت الحقيقي

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// الـ UID الخاص بحساب الأدمن
const String adminUidConst = 'OeEwi4nMZrPjRLRiqWf1373btQT2';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. تهيئة الفايربيس واللغات أولاً لضمان تحميل الداتا
  await Firebase.initializeApp(
  options: DefaultFirebaseOptions.currentPlatform,
);

// 2. 🛡️ تفعيل Firebase App Check (الدرع النووي)
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kReleaseMode
        ? AndroidPlayIntegrityProvider() // كائن الإنتاج (يحظر المحاكيات)
        : AndroidDebugProvider(), // كائن التطوير (يسمح لك بالاختبار)
  );

  await EasyLocalization.ensureInitialized();

  // 2. 🛡️ جدار الحماية ضد تطبيقات النسخ والبيئات الوهمية (Cloners Detection)

  // 3. 🛡️ الإصلاح الحرج: ننتظر قليلاً حتى تكتمل دورة الفايربيس للتحقق من هوية الأدمن بشكل دقيق

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
  bool _isAppInBackground = false;
  DateTime? _backgroundTime;

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
    // 1. عندما يذهب التطبيق للخلفية، نقوم بتفعيل هذا المتغير
    if (state == AppLifecycleState.paused) {
      _isAppInBackground = true;
      _backgroundTime = DateTime.now();
    }

    final user = FirebaseAuth.instance.currentUser;
    bool isUserAdmin = user != null && user.uid == adminUidConst;

    // 2. لن يظهر الإعلان إلا إذا عاد التطبيق للواجهة وكان المتغير فعالاً وبقي في الخلفية لفترة
    if (state == AppLifecycleState.resumed && _isAppInBackground && !isUserAdmin) {
      _isAppInBackground = false; // 3. نعيد المتغير لوضعه الطبيعي لمنع التكرار
      // 4. لا نظهر الإعلان إذا عاد المستخدم بسرعة (أقل من 10 ثواني) لتجنب الإزعاج
      if (_backgroundTime != null && DateTime.now().difference(_backgroundTime!).inSeconds > 10) {
        AdManager.showAppOpenAdOnce();
      }
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
      // ✅ تم تغليف التطبيق بالكامل بجدار حماية الإنترنت لمنع الدخول بدون شبكة نشطة
      builder: (context, child) {
        return InternetGuardWrapper(
          child: Scaffold(
            body: builderContent(child),
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

  Widget builderContent(Widget? child) {
    final user = FirebaseAuth.instance.currentUser;
    bool isUserAdmin = user != null && user.uid == adminUidConst;

    return Column(
      children: [
        Expanded(child: child!),
        if (!isUserAdmin) const GlobalBottomAd(),
      ],
    );
  }
}

// 🌐 =========================================================================
// 🛡️ صمام الأمان: واجهة الحظر الإجبارية لمنع تشغيل التطبيق بدون إنترنت حقيقي
// =========================================================================
class InternetGuardWrapper extends StatefulWidget {
  final Widget child;

  const InternetGuardWrapper({super.key, required this.child});

  @override
  State<InternetGuardWrapper> createState() => _InternetGuardWrapperState();
}

class _InternetGuardWrapperState extends State<InternetGuardWrapper> {
  bool _hasInternet = true;
  bool _isLoading = true;
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();

    // الإنصات المتجدد لأي انقطاع مفاجئ في الشبكة أثناء تصفح التطبيق
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      _checkRealInternet();
    });
  }

  Future<void> _checkInitialConnection() async {
    await _checkRealInternet();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // استخدام دالة الفحص المركبة لضمان وجود حزم بيانات حقيقية وليس مجرد واي فاي وهمي
  Future<void> _checkRealInternet() async {
    bool isConnected = await SecurityUtils.hasInternetConnection();
    if (mounted) {
      setState(() {
        _hasInternet = isConnected;
      });
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A1A2E),
        body: Center(
          child: CircularProgressIndicator(color: Colors.amber),
        ),
      );
    }

    if (!_hasInternet) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Container(
          padding: const EdgeInsets.all(30),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.wifi_off_rounded,
                  color: Colors.redAccent,
                  size: 90,
                ),
                const SizedBox(height: 25),
                // ✅ تم تفعيل الترجمة لعنوان انقطاع الإنترنت
                Text(
                  tr('no_internet_title'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                // ✅ تم تفعيل الترجمة للرسالة التوضيحية للشاشة
                Text(
                  tr('no_internet_desc'),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 35),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.refresh_rounded,
                      fontWeight: FontWeight.bold),
                  // ✅ تم تفعيل الترجمة لزر إعادة المحاولة
                  label: Text(
                    tr('retry'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () {
                    setState(() {
                      _isLoading = true;
                    });
                    _checkInitialConnection();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
