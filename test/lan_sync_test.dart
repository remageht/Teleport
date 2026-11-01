import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:radiotrade/data/db/app_db.dart';
import 'package:radiotrade/services/lan_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _AllowLocalHttpOverrides extends HttpOverrides {}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = _AllowLocalHttpOverrides();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  tearDown(() async {
    await LanSync.instance.stopServer();
  });

  test('LanSync is a singleton', () {
    final a = LanSync();
    final b = LanSync.instance;
    expect(identical(a, b), isTrue);
  });

  test('LanSync server rejects unauthenticated requests and accepts authorized ones', () async {
    final tempDir = await Directory.systemTemp.createTemp('rt_lan_test_');
    final dbPath = '${tempDir.path}/test.db';
    final db = AppDb.instance;
    await db.open(dbPath);

    final lan = LanSync.instance;
    lan.setAuthToken('secret_pin_1234');
    await lan.startServer(db);
    expect(lan.isServer, isTrue);

    final client = HttpClient();

    // 1. Request with WRONG token
    final reqBad = await client.postUrl(Uri.parse('http://127.0.0.1:${LanSync.port}/sync'));
    reqBad.headers.contentType = ContentType.json;
    reqBad.headers.set('x-sync-token', 'wrong_token');
    reqBad.write(jsonEncode({'products': [], 'orders': []}));
    final resBad = await reqBad.close();
    expect(resBad.statusCode, equals(HttpStatus.unauthorized));

    // 2. Request with CORRECT token
    final reqGood = await client.postUrl(Uri.parse('http://127.0.0.1:${LanSync.port}/sync'));
    reqGood.headers.contentType = ContentType.json;
    reqGood.headers.set('x-sync-token', 'secret_pin_1234');
    reqGood.write(jsonEncode({'products': [], 'orders': []}));
    final resGood = await reqGood.close();
    expect(resGood.statusCode, equals(HttpStatus.ok));

    client.close(force: true);
    await lan.stopServer();
    expect(lan.isServer, isFalse);

    await db.close();
    await tempDir.delete(recursive: true);
  });
}
