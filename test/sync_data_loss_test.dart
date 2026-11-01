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

  test('sync pull preserves local photo_path, description, phone, and contact', () async {
    final tempDir = await Directory.systemTemp.createTemp('rt_sync_test_');
    final dbPath = '${tempDir.path}/test.db';
    final db = AppDb.instance;
    await db.open(dbPath);

    // 1. Create a local product with a photo and description
    await db.database.insert('products', {
      'id': 'p-test-1',
      'sku': 'SKU-OLD',
      'name': 'Локальный товар',
      'description': 'Кастомное локальное описание',
      'photo_path': '/data/user/0/photos/p1.jpg',
      'sold_count': 12,
      'unit': 'шт',
      'sync_state': 'synced',
    });

    // 2. Create a local client with phone, address, and contact
    await db.database.insert('clients', {
      'id': 'c-test-1',
      'name': 'Иван Иванов',
      'phone': '+7 999 123-45-67',
      'address': 'ул. Ленина 1',
      'contact': 'Менеджер Пётр',
      'debt': 100.0,
      'discount_pct': 5.0,
      'sync_state': 'synced',
    });

    // 3. Simulate applying incoming server payload using batch with ON CONFLICT DO UPDATE SET
    final b = db.database.batch();
    b.rawInsert('''
      INSERT INTO products (
        id, sku, name, nominal, case_type, manufacturer, barcode, unit, sync_state
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'synced')
      ON CONFLICT(id) DO UPDATE SET
        sku = excluded.sku,
        name = excluded.name,
        nominal = excluded.nominal,
        case_type = excluded.case_type,
        manufacturer = excluded.manufacturer,
        barcode = COALESCE(excluded.barcode, products.barcode),
        unit = excluded.unit,
        sync_state = 'synced'
    ''', [
      'p-test-1',
      'SKU-NEW',
      'Обновлённый товар',
      '100uF',
      'SMD',
      'Yageo',
      '1234567890',
      'шт',
    ]);

    b.rawInsert('''
      INSERT INTO clients (
        id, name, debt, price_list_id, discount_pct, sync_state
      ) VALUES (?, ?, ?, ?, ?, 'synced')
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        debt = excluded.debt,
        price_list_id = excluded.price_list_id,
        discount_pct = excluded.discount_pct,
        sync_state = 'synced'
    ''', [
      'c-test-1',
      'Иван Иванов (Сервер)',
      150.0,
      'pl-vip',
      7.0,
    ]);
    await b.commit(noResult: true);

    // 4. Verify that local photo_path and description are PRESERVED
    final prodRows = await db.database.query('products', where: 'id = ?', whereArgs: ['p-test-1']);
    expect(prodRows.length, equals(1));
    final prod = prodRows.first;
    expect(prod['name'], equals('Обновлённый товар'));
    expect(prod['sku'], equals('SKU-NEW'));
    expect(prod['photo_path'], equals('/data/user/0/photos/p1.jpg')); // Not wiped!
    expect(prod['description'], equals('Кастомное локальное описание')); // Not wiped!
    expect(prod['sold_count'], equals(12)); // Not wiped!

    // 5. Verify that local client contact info is PRESERVED
    final clientRows = await db.database.query('clients', where: 'id = ?', whereArgs: ['c-test-1']);
    expect(clientRows.length, equals(1));
    final client = clientRows.first;
    expect(client['name'], equals('Иван Иванов (Сервер)'));
    expect(client['phone'], equals('+7 999 123-45-67')); // Not wiped!
    expect(client['address'], equals('ул. Ленина 1')); // Not wiped!
    expect(client['contact'], equals('Менеджер Пётр')); // Not wiped!
    expect(client['debt'], equals(150.0));

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
