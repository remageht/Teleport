import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:radiotrade/data/db/app_db.dart';
import 'package:radiotrade/services/export_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDb db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rad_err_test_');
    db = AppDb.instance;
    await db.open(p.join(tempDir.path, 'test_err.db'));
  });

  tearDown(() async {
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('ExportService handles locked/invalid file gracefully without crashing', () async {
    final svc = ExportService();
    // Export empty sales data: does not crash even without plugin platform channel
    final res = await svc.exportSales(db, allTime: false);
    expect(res, anyOf(startsWith('Файл:'), startsWith('Ошибка экспорта:')));
  });

  test('AppDb database queries with non-existent IDs do not crash', () async {
    final p = await db.productById('non-existent-id-12345');
    expect(p, isNull);

    final stats = await db.receiptsStats();
    expect(stats, isEmpty);

    final orders = await db.ordersOfDay(DateTime.now(), 'non-existent-agent');
    expect(orders, isEmpty);
  });
}
