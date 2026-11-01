import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:radiotrade/core/currency_provider.dart';
import 'package:radiotrade/core/session.dart';
import 'package:radiotrade/core/theme_provider.dart';
import 'package:radiotrade/data/db/app_db.dart';
import 'package:radiotrade/data/sync/sync_engine.dart';
import 'package:radiotrade/features/home/home_shell.dart';
import 'package:radiotrade/features/orders/order_edit_screen.dart';
import 'package:radiotrade/features/settings/widgets/currency_calculator_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String dbPath;
  late AppDb db;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tempDir = await Directory.systemTemp.createTemp('rt_compact_test_');
    dbPath = '${tempDir.path}/test.db';
    db = AppDb.instance;
    await db.open(dbPath);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestApp(Widget child) {
    final session = Session();
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<CurrencyProvider>(create: (_) => CurrencyProvider()),
        ChangeNotifierProvider<Session>.value(value: session),
        Provider<AppDb>.value(value: db),
        ChangeNotifierProvider<SyncState>(create: (_) => SyncState()),
        Provider<SyncEngine>(create: (_) => SyncEngine(db, session)),
      ],
      child: MaterialApp(
        home: child,
      ),
    );
  }

  testWidgets('OrderEditScreen renders without overflow on 320x480 TSD screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestApp(const OrderEditScreen(client: null)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Проверяем, что нет переполнений
    expect(tester.takeException(), isNull);

    // Проверяем компактные подписи в SegmentedButton ('Нал', 'СБП')
    expect(find.text('Нал'), findsOneWidget);
    expect(find.text('Карта'), findsOneWidget);
    expect(find.text('СБП'), findsOneWidget);
    expect(find.text('Долг'), findsOneWidget);

    // Проверяем строку итога и кнопку
    expect(find.textContaining('Итого:'), findsOneWidget);
    expect(find.text('Провести'), findsOneWidget);
  });

  testWidgets('HomeShell NavigationBar adapts to compact 320x480 screen without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(buildTestApp(const HomeShell()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);

    final navBar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navBar.labelBehavior, NavigationDestinationLabelBehavior.onlyShowSelected);

    // Размонтируем HomeShell, чтобы сработал dispose() и отменился таймер SyncEngine
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('CurrencyCalculatorDialog opens and renders on 320x480 screen without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      buildTestApp(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => CurrencyCalculatorDialog.show(context),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Калькулятор валют'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
  });
}
