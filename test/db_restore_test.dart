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

  test('restoreFrom cleans WAL and SHM and restores valid database state', () async {
    final tempDir = await Directory.systemTemp.createTemp('rt_restore_test_');
    final dbPath = '${tempDir.path}/main.db';
    final backupPath = '${tempDir.path}/backup.db';

    final db = AppDb.instance;
    await db.open(dbPath);

    // Seed 1 product into original database
    await db.addProduct(name: 'Товар из бэкапа', price: 50);

    // Make backup copy
    await db.walCheckpoint();
    await File(dbPath).copy(backupPath);

    // Add a second product to current database
    await db.addProduct(name: 'Новый несохранённый товар', price: 99);

    // Create fake dirty wal and shm files
    final walFile = File('$dbPath-wal');
    final shmFile = File('$dbPath-shm');
    await walFile.writeAsString('dirty-wal-content');
    await shmFile.writeAsString('dirty-shm-content');
    expect(await walFile.exists(), isTrue);
    expect(await shmFile.exists(), isTrue);

    // Restore from backup
    await db.restoreFrom(File(backupPath));

    // After restore, the restored database must have only the backup product
    final rows = await db.database.query('products');
    expect(rows.any((p) => p['name'] == 'Товар из бэкапа'), isTrue);
    expect(rows.any((p) => p['name'] == 'Новый несохранённый товар'), isFalse);

    // Old dirty WAL must be gone
    if (await walFile.exists()) {
      final content = await walFile.readAsString();
      expect(content, isNot(equals('dirty-wal-content')));
    }

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
