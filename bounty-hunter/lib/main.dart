import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'providers/hunter_provider.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.instance.initialize();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF1A1A1A),
  ));

  runApp(const _Bootstrap());
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final SettingsProvider _settings;
  late final HunterProvider _hunter;

  @override
  void initState() {
    super.initState();
    _settings = SettingsProvider();
    _hunter = HunterProvider(_settings);
    _settings.load().then((_) {
      _hunter.onSettingsChanged();
      if (_settings.hasKey) _hunter.startPolling();
    });
    // Deep-link from notifications
    NotificationService.pendingLaunch = _handleNotifLaunch;
  }

  void _handleNotifLaunch(String? payload) {
    // The URL is opened when the main navigator is ready — payload handled at widget level
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _hunter),
      ],
      child: const BountyHunterApp(),
    );
  }
}

class BountyHunterApp extends StatelessWidget {
  const BountyHunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Torn Helper',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme() {
    const seed = Color(0xFFEF5350);
    final cs = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF1E1E1E),
    ).copyWith(
      surface: const Color(0xFF1E1E1E),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: cs,
      scaffoldBackgroundColor: const Color(0xFF121212),
      cardColor: const Color(0xFF1E1E1E),
      dividerColor: const Color(0xFF2A2A2A),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1A1A1A),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      tabBarTheme: const TabBarTheme(
        labelColor: Color(0xFFEF5350),
        unselectedLabelColor: Colors.grey,
        indicatorColor: Color(0xFFEF5350),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
        ),
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: Color(0xFF252525),
        side: BorderSide(color: Color(0xFF3A3A3A)),
        labelStyle: TextStyle(color: Color(0xFFAAAAAA)),
      ),
      dialogTheme: const DialogTheme(
        backgroundColor: Color(0xFF1E1E1E),
        titleTextStyle:
            TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
        contentTextStyle: TextStyle(color: Color(0xFFAAAAAA), fontSize: 14),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Color(0xFF333333),
        contentTextStyle: TextStyle(color: Colors.white),
      ),
    );
  }
}
