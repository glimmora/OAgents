import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:oagents/screens/home_screen.dart';
import 'package:oagents/services/chat_controller.dart';
import 'package:oagents/services/credential_store.dart';
import 'package:oagents/services/opencode_client.dart';
import 'package:oagents/services/runtime_bridge.dart';

void main() {
  runApp(const OAgentsApp());
}

/// MaterialApp OAgents: tema gelap, Provider setup, home = HomeScreen.
class OAgentsApp extends StatelessWidget {
  const OAgentsApp({super.key});

  static const Color _primary = Color(0xFF1A2330);
  static const Color _accent = Color(0xFFD4875A);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<CredentialStore>(create: (_) => CredentialStore()),
        Provider<RuntimeBridge>(
          create: (context) {
            final bridge = RuntimeBridge()
              ..credentials = context.read<CredentialStore>();
            return bridge;
          },
        ),
        Provider<OpencodeClient>(
          create: (context) => OpencodeClient(
            bridge: context.read<RuntimeBridge>(),
          ),
        ),
        ChangeNotifierProvider<ChatController>(
          create: (context) => ChatController(
            client: context.read<OpencodeClient>(),
          ),
        ),
        FutureProvider<SharedPreferences?>(
          initialData: null,
          create: (_) => SharedPreferences.getInstance(),
        ),
      ],
      child: Consumer<SharedPreferences?>(
        builder: (context, prefs, _) {
          final controller = context.read<ChatController>();
          if (prefs != null && !controller.ready) {
            // Muat sesi terakhir sekali setelah prefs tersedia.
            Future<void>(() async {
              await controller.ensurePrefsLoaded(prefs);
              await controller.loadLastSession();
            });
          }
          return MaterialApp(
            title: 'OAgents',
            debugShowCheckedModeBanner: false,
            theme: _buildTheme(),
            home: const HomeScreen(),
          );
        },
      ),
    );
  }

  static ThemeData _buildTheme() {
    final base = ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
        primary: _accent,
        surface: _primary,
        error: const Color(0xFFE57373),
      ),
      scaffoldBackgroundColor: _primary,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        elevation: 0,
        color: _primary.withValues(alpha: 1),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _primary.withValues(alpha: 0.95),
        indicatorColor: _accent.withValues(alpha: 0.28),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected)
                ? _accent
                : Colors.white.withValues(alpha: 0.55),
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return TextStyle(
            fontSize: 12,
            color: states.contains(WidgetState.selected)
                ? _accent
                : Colors.white.withValues(alpha: 0.55),
          );
        }),
      ),
    );
    return base;
  }
}
