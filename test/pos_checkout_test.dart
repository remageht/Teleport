import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:radiotrade/features/orders/widgets/pos_cash_checkout_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'pos_auto_print_receipt': true});
  });

  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: child,
      ),
    );
  }

  testWidgets('PosCashCheckoutSheet computes change and adapts to compact 320x480 screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    PosCheckoutResult? result;

    await tester.pumpWidget(
      buildTestWidget(
        Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await PosCashCheckoutSheet.show(
                  context,
                  total: 1350.0,
                  clientName: 'Иванов Иван',
                );
              },
              child: const Text('Открыть кассу'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Открываем модальный шит
    await tester.tap(find.text('Открыть кассу'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Оплата наличными'), findsOneWidget);
    expect(find.text('Иванов Иван'), findsOneWidget);
    expect(find.text('1350.00 ₽'), findsOneWidget);

    // По умолчанию сумма = точной сумме, сдача 0
    expect(find.text('Сдача:'), findsOneWidget);
    expect(find.text('0 ₽'), findsOneWidget);

    // Добавляем +1 000 ₽ через быстрый чип
    final plus1000 = find.text('+1 000 ₽');
    expect(plus1000, findsOneWidget);
    await tester.ensureVisible(plus1000);
    await tester.tap(plus1000);
    await tester.pumpAndSettle();

    // 1350 + 1000 = 2350, сдача должна быть 1000 ₽
    expect(find.text('1000 ₽'), findsOneWidget);

    // Вводим недостаточную сумму 1000 ₽ в поле ввода
    final textField = find.byType(TextField);
    await tester.ensureVisible(textField);
    await tester.enterText(textField, '1000');
    await tester.pumpAndSettle();

    // Должно появиться предупреждение "Не хватает:" и сумма нехватки 350 ₽
    expect(find.text('Не хватает:'), findsOneWidget);
    expect(find.text('350 ₽'), findsOneWidget);

    // Нажимаем чип "Без сдачи"
    final exactChip = find.text('Без сдачи');
    await tester.ensureVisible(exactChip);
    await tester.tap(exactChip);
    await tester.pumpAndSettle();

    expect(find.text('Сдача:'), findsOneWidget);
    expect(find.text('0 ₽'), findsOneWidget);

    // Проверяем чекбокс печати чека
    final checkbox = find.byType(CheckboxListTile);
    expect(checkbox, findsOneWidget);

    // Подтверждаем оплату
    final confirmButton = find.text('Принять оплату и провести');
    expect(confirmButton, findsOneWidget);
    await tester.ensureVisible(confirmButton);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Проверяем возвращенный результат
    expect(result, isNotNull);
    expect(result!.confirmed, isTrue);
    expect(result!.tendered, 1350.0);
    expect(result!.change, 0.0);
    expect(result!.printReceipt, isTrue);
  });
}
