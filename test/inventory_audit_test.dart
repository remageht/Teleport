import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:radiotrade/core/app_theme.dart';
import 'package:radiotrade/data/db/app_db.dart';
import 'package:radiotrade/features/warehouse/inventory_screen.dart';
import 'package:radiotrade/models/catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDb db;
  late String dbPath;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    HttpOverrides.global = null;
    final tempDir = await Directory.systemTemp.createTemp('rt_inv_audit_test_');
    dbPath = '${tempDir.path}/test.db';
    db = AppDb.instance;
    await db.open(dbPath);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final rawDb = db.database;
    await rawDb.delete('products');
    await rawDb.delete('stocks');
    await rawDb.delete('moves');
    await rawDb.delete('price_items');

    // Создаем тестовые данные: товар с остатком 10 шт
    await rawDb.insert('products', {
      'id': 'test-prod-1',
      'sku': 'SKU001',
      'name': 'Резистор 10кОм SMD',
      'barcode': '123456789012',
      'sold_count': 0,
      'is_active': 1,
    });
    await rawDb.insert('stocks', {
      'product_id': 'test-prod-1',
      'warehouse_id': 'wh-shop',
      'cell': 'A-01',
      'qty': 10.0,
      'reserved': 0.0,
    });
    await rawDb.insert('price_items', {
      'price_list_id': 'pl-base',
      'product_id': 'test-prod-1',
      'price': 15.0,
    });
  });

  tearDownAll(() async {
    await db.close();
  });

  Widget buildTestApp(Widget child) {
    return MultiProvider(
      providers: [
        Provider<AppDb>.value(value: db),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: child,
      ),
    );
  }

  test('AppDb applyInventoryAudit correctly updates stock and creates move entry', () async {
    // Начальный остаток: 10 шт
    final initialAvail = await db.availableQty('test-prod-1', 'wh-shop');
    expect(initialAvail, 10.0);

    // Проводим ревизию: факт = 13 шт (излишек +3)
    await db.applyInventoryAudit([
      (
        productId: 'test-prod-1',
        warehouseId: 'wh-shop',
        actualQty: 13.0,
        expectedQty: 10.0,
        cell: 'A-01',
      ),
    ]);

    // Проверяем обновленный остаток
    final updatedAvail = await db.availableQty('test-prod-1', 'wh-shop');
    expect(updatedAvail, 13.0);

    // Проверяем запись в таблице moves
    final rawDb = db.database;
    final moves = await rawDb.query('moves', where: 'product_id = ?', whereArgs: ['test-prod-1']);
    expect(moves.length, 1);
    expect(moves.first['type'], 'count');
    expect(moves.first['qty'], 3.0);
    expect((moves.first['note'] as String).contains('Излишек при ревизии (+3)'), isTrue);
  });

  testWidgets('InventoryScreen renders, increments actual count, and adapts to 320x480 screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const testProd = Product(
      id: 'test-prod-1',
      sku: 'SKU001',
      name: 'Резистор 10кОм SMD',
      barcode: '123456789012',
      available: 10.0,
      price: 15.0,
      cell: 'A-01',
    );

    List<InventoryAuditItem>? appliedItems;

    await tester.pumpWidget(
      buildTestApp(
        InventoryScreen(
          initialProducts: const [testProd],
          onApplyAudit: (items) async {
            appliedItems = items;
          },
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Ревизия склада'), findsOneWidget);
    expect(find.text('Резистор 10кОм SMD'), findsOneWidget);
    expect(find.text('Учёт: 10 шт'), findsOneWidget);

    // Нажимаем кнопку инкремента "+"
    final plusBtn = find.byIcon(Icons.add_circle_outline);
    expect(plusBtn, findsOneWidget);
    await tester.tap(plusBtn);
    await tester.pump();

    // Факт должен стать 11 шт, излишек +1
    expect(find.text('11'), findsOneWidget);
    expect(find.text('Излишек: +1 шт'), findsOneWidget);

    // Проверяем нижнюю панель
    expect(find.text('Сверено: 1 из 1'), findsOneWidget);
    expect(find.text('+15 ₽'), findsOneWidget); // 1 шт * 15 ₽

    // Нажимаем «Применить результаты ревизии»
    final applyBtn = find.text('Применить результаты ревизии');
    expect(applyBtn, findsOneWidget);
    await tester.tap(applyBtn);
    await tester.pump();

    // В диалоге подтверждения нажимаем «Применить»
    final confirmBtn = find.text('Применить');
    expect(confirmBtn, findsOneWidget);
    await tester.tap(confirmBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2000));

    // Проверяем, что onApplyAudit был вызван с правильными параметрами
    expect(appliedItems, isNotNull);
    expect(appliedItems!.length, 1);
    expect(appliedItems!.first.productId, 'test-prod-1');
    expect(appliedItems!.first.actualQty, 11.0);
    expect(appliedItems!.first.expectedQty, 10.0);
    expect(appliedItems!.first.cell, 'A-01');
  });
}
