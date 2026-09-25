import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/app_theme.dart';
import 'core/session.dart';
import 'core/theme_provider.dart';
import 'data/db/app_db.dart';
import 'data/sync/sync_engine.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_shell.dart';
import 'services/telegram_backup.dart';

/// Ожидающее действие из ярлыка (обрабатывает HomeShell при старте).
String? pendingShortcut;

/// Точка входа. Инициализирует БД, синхронизатор и запускает приложение.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // На Windows/Linux/macOS sqlite через FFI, на мобильных — платформенная реализация.
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final db = AppDb.instance;
  await db.open();
  final session = Session();
  final syncEngine = SyncEngine(db, session);
  final theme = ThemeProvider();
  await theme.load();

  // Личное пользование: автоматический вход без PIN.
  session.login(
    userId: 'me',
    userName: 'ТЕЛЕМАСТЕР',
    role: Role.admin,
    mode: WorkMode.vanSelling,
    warehouseId: 'wh-shop',
  );

  // Ярлыки с рабочего стола (Новая продажа / Склад). Безопасно: try/catch.
  try {
    const qa = QuickActions();
    qa.setShortcutItems(const [
      ShortcutItem(
          type: 'action_sale',
          localizedTitle: 'Новая продажа',
          icon: 'ic_launcher'),
      ShortcutItem(
          type: 'action_stock',
          localizedTitle: 'Склад',
          icon: 'ic_launcher'),
    ]);
    qa.initialize((type) => pendingShortcut = type);
  } catch (_) {}

  // Автокопия базы в Telegram раз в сутки (если включена в настройках).
  // ignore: unawaited_futures
  _autoTgBackup(db);

  runApp(MultiProvider(
    providers: [
      Provider<AppDb>.value(value: db),
      ChangeNotifierProvider<Session>.value(value: session),
      ChangeNotifierProvider<SyncState>.value(value: syncEngine.state),
      Provider<SyncEngine>.value(value: syncEngine),
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
    ],
    child: const RadioTradeApp(),
  ));
}

/// Фоновая автокопия базы в Telegram (раз в сутки, если включена).
Future<void> _autoTgBackup(AppDb db) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('tg_auto') ?? false)) return;
    final last = p.getInt('tg_last') ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - last <
        24 * 3600 * 1000) {
      return;
    }
    final token = p.getString('tg_bot') ?? '';
    final chat = p.getString('tg_chat') ?? '';
    if (token.isEmpty || chat.isEmpty) return;
    await TelegramBackup.sendDb(
        botToken: token, chatId: chat, dbPath: db.dbPath);
    await p.setInt(
        'tg_last', DateTime.now().millisecondsSinceEpoch);
  } catch (_) {}
}

class RadioTradeApp extends StatelessWidget {
  const RadioTradeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return MaterialApp(
      title: 'ТелеПорт',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: context.watch<ThemeProvider>().mode,
      builder: (context, child) {
        // Глобальный масштаб текста из настроек.
        final t = context.watch<ThemeProvider>();
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(t.textScale)),
          child: child!,
        );
      },
      locale: const Locale('ru', 'RU'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ru', 'RU')],
      home: session.user == null ? const LoginScreen() : const HomeShell(),
    );
  }
}
