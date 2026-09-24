import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/db/app_db.dart';

/// Прямая синхронизация ПК ⇄ телефон по Wi-Fi без облака:
/// одно устройство включает сервер (HttpServer, порт 8180),
/// второе вводит его адрес и жмёт «Синхронизировать».
class LanSync {
  static const port = 8180;

  HttpServer? _server;
  bool get isServer => _server != null;

  final ValueNotifier<String> status = ValueNotifier('');

  /// Локальные IPv4-адреса этого устройства (их вводят на другой стороне).
  Future<List<String>> localAddresses() async {
    final result = <String>[];
    final ifs = await NetworkInterface.list();
    for (final i in ifs) {
      for (final a in i.addresses) {
        if (a.type == InternetAddressType.IPv4 && !a.isLoopback) {
          result.add(a.address);
        }
      }
    }
    return result;
  }

  /// Включить сервер синхронизации.
  Future<void> startServer(AppDb db) async {
    if (_server != null) return;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    status.value = 'Сервер включён (порт $port)';
    _server!.listen((req) async {
      try {
        if (req.method != 'POST' || req.uri.path != '/sync') {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        final body = await utf8.decoder.bind(req).join();
        await db.mergePayload(
            Map<String, Object?>.from(jsonDecode(body) as Map));
        final answer = await db.exportPayload();
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(answer));
        await req.response.close();
        status.value =
            'Обмен выполнен ${DateTime.now().toIso8601String().substring(11, 16)}';
      } catch (e) {
        status.value = 'Ошибка обмена: $e';
        req.response.statusCode = 500;
        await req.response.close();
      }
    });
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    status.value = 'Сервер выключен';
  }

  /// Подключиться к другому устройству и обменяться данными.
  /// Возвращает краткий итог.
  Future<String> syncWith(AppDb db, String hostPort) async {
    final parts = hostPort.trim().split(':');
    final host = parts.first;
    final portStr = parts.length > 1 ? parts[1] : '$port';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .postUrl(Uri.parse('http://$host:$portStr/sync'));
      req.headers.contentType = ContentType.json;
      final payload = await db.exportPayload();
      req.write(jsonEncode(payload));
      final res = await req.close();
      if (res.statusCode != 200) {
        return 'Ошибка: HTTP ${res.statusCode}';
      }
      final body = await utf8.decoder.bind(res).join();
      await db.mergePayload(
          Map<String, Object?>.from(jsonDecode(body) as Map));
      final n = ((jsonDecode(body) as Map)['products'] as List).length;
      return 'Готово: принято позиций $n';
    } on SocketException catch (e) {
      return 'Не подключилось: $host:$portStr (${e.message})';
    } catch (e) {
      return 'Ошибка: $e';
    } finally {
      client.close(force: true);
    }
  }
}
