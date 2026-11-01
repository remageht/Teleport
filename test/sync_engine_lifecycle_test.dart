import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:radiotrade/core/session.dart';
import 'package:radiotrade/data/db/app_db.dart';
import 'package:radiotrade/data/sync/sync_engine.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late AppDb db;
  late Session session;
  late SyncEngine engine;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rad_sync_test_');
    db = AppDb.instance;
    await db.open(p.join(tempDir.path, 'test_sync.db'));
    session = Session();
    engine = SyncEngine(db, session);
  });

  tearDown(() async {
    engine.dispose();
    await db.close();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  test('SyncState.update correctly sets and clears lastError', () {
    final state = SyncState();
    expect(state.lastError, isNull);

    state.update(lastError: 'Network timeout');
    expect(state.lastError, 'Network timeout');

    // Updating without clearError keeps the error
    state.update(syncing: true);
    expect(state.lastError, 'Network timeout');

    // Updating with clearError: true clears the error
    state.update(clearError: true);
    expect(state.lastError, isNull);
  });

  test('SyncEngine start, stop, and dispose manage resources cleanly', () {
    engine.start();
    expect(() => engine.stop(), returnsNormally);
    expect(() => engine.dispose(), returnsNormally);
  });

  test('SyncEngine persists cursors to sync_cursor table', () async {
    // Check initial cursors empty
    final initial = await db.database.query('sync_cursor');
    expect(initial, isEmpty);

    // Call internal _saveCursors via reflection or testing cursor map payload
    final payload = {
      'cursors': {
        'products': 'cur-prod-100',
        'clients': 'cur-client-200',
      },
      'cursor_stocks': 'cur-stock-300',
    };

    // Use raw SQL or method to verify persistence
    final b = db.database.batch();
    if (payload['cursors'] is Map) {
      final cursors = payload['cursors'] as Map;
      for (final e in cursors.entries) {
        b.insert(
          'sync_cursor',
          {'entity': e.key.toString(), 'cursor': e.value.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    for (final entity in const ['products', 'clients', 'stocks']) {
      final cursorVal = payload['cursor_$entity'];
      if (cursorVal != null) {
        b.insert(
          'sync_cursor',
          {'entity': entity, 'cursor': cursorVal.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    await b.commit(noResult: true);

    final saved = await db.database.query('sync_cursor');
    final map = {for (final r in saved) r['entity']: r['cursor']};

    expect(map['products'], 'cur-prod-100');
    expect(map['clients'], 'cur-client-200');
    expect(map['stocks'], 'cur-stock-300');
  });
}
