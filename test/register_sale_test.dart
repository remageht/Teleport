import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:radiotrade/data/db/app_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('registerSale deducts stock sequentially from cells without multi-deduct', () async {
    final tempDir = await Directory.systemTemp.createTemp('rt_test_');
    final dbPath = '${tempDir.path}/test.db';
    final db = AppDb.instance;
    await db.open(dbPath);

    // Insert test product
    final prod = await db.addProduct(name: 'Товар 1', price: 100);

    // Insert stock in two different cells:
    // Cell A: 5 qty
    // Cell B: 10 qty
    // Total stock = 15
    await db.database.insert('stocks', {
      'product_id': prod.id,
      'warehouse_id': 'wh-shop',
      'cell': 'Ячейка A',
      'qty': 5.0,
      'reserved': 0,
    });
    await db.database.insert('stocks', {
      'product_id': prod.id,
      'warehouse_id': 'wh-shop',
      'cell': 'Ячейка B',
      'qty': 10.0,
      'reserved': 0,
    });

    // Sell 2 units.
    // Previously, 2 was deducted from BOTH A and B (total 4 deducted).
    // With sequential deduction, 2 is deducted from B (10 -> 8), A remains 5.
    await db.registerSale(prod.id, 2.0);

    final totalStock = await db.availableQty(prod.id, 'wh-shop');
    expect(totalStock, equals(13.0)); // 15 - 2 = 13

    // Now sell 9 units:
    // Remaining in B was 8 -> B becomes 0, and 1 is taken from A (5 -> 4).
    await db.registerSale(prod.id, 9.0);

    final remainingTotal = await db.availableQty(prod.id, 'wh-shop');
    expect(remainingTotal, equals(4.0)); // 13 - 9 = 4

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
