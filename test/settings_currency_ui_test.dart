import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:radiotrade/core/currency_provider.dart';
import 'package:radiotrade/core/session.dart';
import 'package:radiotrade/core/theme_provider.dart';
import 'package:radiotrade/data/db/app_db.dart';
import 'package:radiotrade/features/settings/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget createSettingsTestApp({
  required ThemeProvider theme,
  required CurrencyProvider currency,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ChangeNotifierProvider<CurrencyProvider>.value(value: currency),
      Provider<AppDb>.value(value: AppDb.instance),
      ChangeNotifierProvider<Session>.value(value: Session()),
    ],
    child: const MaterialApp(
      home: SettingsScreen(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Меню настроек: отображение блока валюты и переключение',
      (tester) async {
    // Размер типичного мобильного экрана
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = ThemeProvider();
    await theme.load();
    final currency = CurrencyProvider();
    await currency.load();

    await tester.pumpWidget(createSettingsTestApp(
      theme: theme,
      currency: currency,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 1. Проверяем наличие заголовка раздела
    expect(find.text('Валюта и конвертация цен'), findsOneWidget);
    expect(find.text('Конвертация цен'), findsOneWidget);
    expect(find.text('Выключена (все цены в ₽)'), findsOneWidget);

    // 2. Включаем конвертацию через свитч
    await tester.tap(find.text('Конвертация цен'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(currency.isEnabled, isTrue);

    // 3. Проверяем отображение всех чипсов валют
    expect(find.text('USD (\$)'), findsOneWidget);
    expect(find.text('EUR (€)'), findsOneWidget);
    expect(find.text('CNY (¥)'), findsOneWidget);
    expect(find.text('KZT (₸)'), findsOneWidget);
    expect(find.text('BYN (Br)'), findsOneWidget);
    expect(find.text('USDT (₮)'), findsOneWidget);

    // 4. Проверяем наличие кнопок и полей
    expect(find.text('Курс ЦБ РФ'), findsOneWidget);
    expect(find.text('Калькулятор'), findsOneWidget);
    expect(find.text('Формат цен в приложении:'), findsOneWidget);
    expect(find.text('Двойной (~валюта)'), findsOneWidget);
    expect(find.text('Только валюта'), findsOneWidget);

    // 5. Переключаем валюту на EUR
    await tester.tap(find.text('EUR (€)'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(currency.code, equals('EUR'));

    // 6. Нажимаем «Калькулятор» и проверяем появление диалога
    await tester.ensureVisible(find.text('Калькулятор'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Калькулятор'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Калькулятор валют'), findsOneWidget);
    expect(find.text('Сумма в рублях'), findsOneWidget);
    expect(find.text('В валюте (Евро)'), findsOneWidget);
    expect(find.text('+1 000 ₽'), findsOneWidget);
    expect(find.text('+5 000 ₽'), findsOneWidget);

    // Закрываем диалог
    await tester.tap(find.text('Готово'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Калькулятор валют'), findsNothing);
  });
}
