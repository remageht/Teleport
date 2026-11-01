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
    tempDir = await Directory.systemTemp.createTemp('rad_nplusone_test_');
    db = AppDb.instance;
    await db.open(p.join(tempDir.path, 'test_nplusone.db'));
  });

  tearDown(() async {
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('receiptsStats aggregates lines count and total without N+1 queries', () async {
    final r1 = await db.createReceipt(supplier: 'Поставщик 1', number: 'DOC-1');
    final p1 = await db.addProduct(name: 'Товар 1', qty: 0, price: 100);
    final p2 = await db.addProduct(name: 'Товар 2', qty: 0, price: 200);

    await db.receiveGoods(productId: p1.id, qty: 5, buyPrice: 80, receiptId: r1);
    await db.receiveGoods(productId: p2.id, qty: 10, buyPrice: 150, receiptId: r1);

    final stats = await db.receiptsStats();
    expect(stats.containsKey(r1), isTrue);
    expect(stats[r1]!.lines, 2);
    expect(stats[r1]!.total, 5 * 80 + 10 * 150);
  });

  test('productsByIds and returnedQtysForOrder batch load data correctly', () async {
    final p1 = await db.addProduct(name: 'Resistor 10k', qty: 10, price: 15);
    final p2 = await db.addProduct(name: 'Capacitor 100uF', qty: 20, price: 30);

    final map = await db.productsByIds([p1.id, p2.id]);
    expect(map.length, 2);
    expect(map[p1.id]?.name, 'Resistor 10k');
    expect(map[p2.id]?.name, 'Capacitor 100uF');

    await db.registerReturn(p1.id, 2, price: 15, note: 'Возврат по чеку 01/555');
    final returns = await db.returnedQtysForOrder('01/555', [p1.id, p2.id]);
    expect(returns[p1.id], 2.0);
    expect(returns[p2.id], isNull);
  });

  test('ordersOfDay and daySales batch load order_lines', () async {
    final p1 = await db.addProduct(name: 'Diode 1N4007', qty: 50, price: 5);
    final now = DateTime.now();

    final order = Order(
      id: 'ord-batch-1',
      number: '01/200',
      clientId: 'retail',
      clientName: 'Розничный',
      type: OrderType.realization,
      warehouseId: 'wh-shop',
      agentId: 'agent-test',
      payType: PayType.cash,
      createdAt: now,
      lines: [
        OrderLine(
          productId: p1.id,
          sku: p1.sku,
          name: p1.name,
          qty: 10,
          price: 5,
        ),
      ],
    );
    await db.saveOrderWithStock(order);

    final orders = await db.ordersOfDay(now, 'agent-test');
    expect(orders.length, 1);
    expect(orders.first.lines.length, 1);
    expect(orders.first.lines.first.productId, p1.id);
    expect(orders.first.lines.first.qty, 10.0);

    final sales = await db.daySales(now, 'agent-test');
    expect(sales, 50.0);
  });

  test('generateBarcodes and setBarcodes batch operate cleanly', () async {
    final p1 = await db.addProduct(name: 'Batch Item 1', qty: 1, price: 10);
    final p2 = await db.addProduct(name: 'Batch Item 2', qty: 1, price: 20);

    final codes = await db.generateBarcodes(2);
    expect(codes.length, 2);
    expect(codes[0], isNot(equals(codes[1])));

    await db.setBarcodes({p1.id: codes[0], p2.id: codes[1]});

    final updated = await db.productsByIds([p1.id, p2.id]);
    expect(updated[p1.id]?.barcode, codes[0]);
    expect(updated[p2.id]?.barcode, codes[1]);
  });
}
