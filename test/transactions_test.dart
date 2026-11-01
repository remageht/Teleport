import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:radiotrade/data/db/app_db.dart';
import 'package:radiotrade/models/trade.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDb db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rad_txn_test_');
    db = AppDb.instance;
    await db.open(p.join(tempDir.path, 'test_txn.db'));
  });

  tearDown(() async {
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('saveOrderWithStock saves realization order and deducts stock atomically', () async {
    final prod = await db.addProduct(
      name: 'Transistor KT315',
      qty: 15,
      price: 50,
    );

    final initialAvail = await db.availableQty(prod.id, 'wh-shop');
    expect(initialAvail, 15.0);

    final now = DateTime.now();
    final order = Order(
      id: 'ord-test-1',
      number: '01/100',
      clientId: 'retail',
      clientName: 'Розничный покупатель',
      type: OrderType.realization,
      warehouseId: 'wh-shop',
      agentId: 'agent-1',
      payType: PayType.cash,
      createdAt: now,
      lines: [
        OrderLine(
          productId: prod.id,
          sku: prod.sku,
          name: prod.name,
          qty: 5,
          price: 50,
        ),
      ],
    );

    await db.saveOrderWithStock(order, warehouseId: 'wh-shop');

    // Проверяем списание остатка
    final afterAvail = await db.availableQty(prod.id, 'wh-shop');
    expect(afterAvail, 10.0);

    // Проверяем историю движений
    final moves = await db.movesOf(prod.id);
    expect(moves.any((m) => m['type'] == 'sale' && (m['qty'] as num).toDouble() == 5.0), isTrue);

    // Проверяем запись в outbox
    final outbox = await db.database.query('outbox', where: 'entity = ?', whereArgs: ['order']);
    expect(outbox.length, 1);
  });

  test('mergePayload wraps operations in a single transaction', () async {
    final payload = {
      'products': [
        {
          'id': 'remote-p1',
          'sku': 'REM1',
          'name': 'Remote Product 1',
          'qty': 10,
          'price': 120.0,
          'sold_count': 3,
          'updated_at': DateTime.now().toIso8601String(),
        },
        {
          'id': 'remote-p2',
          'sku': 'REM2',
          'name': 'Remote Product 2',
          'qty': 5,
          'price': 250.0,
          'sold_count': 1,
          'updated_at': DateTime.now().toIso8601String(),
        },
      ],
      'orders': [
        {
          'id': 'remote-ord-1',
          'number': '99/1',
          'client_id': 'retail',
          'type': 'preOrder',
          'status': 'sent',
          'total': 370.0,
          'created_at': DateTime.now().toIso8601String(),
        }
      ]
    };

    await db.mergePayload(payload);

    final p1 = await db.productById('remote-p1');
    expect(p1, isNotNull);
    expect(p1!.name, 'Remote Product 1');

    final orders = await db.database.query('orders', where: 'id = ?', whereArgs: ['remote-ord-1']);
    expect(orders.length, 1);
  });

  test('createReceipt and receiveGoods execute atomically in transaction', () async {
    await db.database.transaction((txn) async {
      final rid = await db.createReceipt(
        number: 'INV-1234',
        supplier: 'Test Supplier',
        executor: txn,
      );

      final p = await db.addProduct(
        name: 'Resistor 10k',
        qty: 0,
        executor: txn,
      );

      await db.receiveGoods(
        productId: p.id,
        qty: 100,
        buyPrice: 1.5,
        receiptId: rid,
        executor: txn,
      );
    });

    final receipts = await db.receipts();
    expect(receipts.length, 1);
    expect(receipts.first['number'], 'INV-1234');
    expect((receipts.first['total'] as num).toDouble(), 150.0);
  });
}
