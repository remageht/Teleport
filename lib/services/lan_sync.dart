import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/db/app_db.dart';

/// Прямая синхронизация ПК ⇄ телефон по Wi-Fi без облака:
/// одно устройство включает сервер (HttpServer, порт 8180),
/// второе вводит его адрес и жмёт «Синхронизировать».
class LanSync {
  static const port = 8180;
  static const defaultToken = 'teleport_local_sync';

  static final LanSync instance = LanSync._internal();
  LanSync._internal();
  factory LanSync() => instance;

  HttpServer? _server;
  bool get isServer => _server != null;

  String _authToken = defaultToken;
  String get authToken => _authToken;
  void setAuthToken(String token) {
    final t = token.trim();
    _authToken = t.isEmpty ? defaultToken : t;
  }

  final ValueNotifier<String> status = ValueNotifier('');

  /// Локальные IPv4-адреса этого устройства (их вводят на другой стороне).
  Future<List<String>> localAddresses() async {
    final result = <String>[];
    try {
      final ifs = await NetworkInterface.list();
      for (final i in ifs) {
        for (final a in i.addresses) {
          if (a.type == InternetAddressType.IPv4 && !a.isLoopback) {
            result.add(a.address);
          }
        }
      }
    } catch (_) {}
    return result;
  }

  /// Включить сервер синхронизации.
  Future<void> startServer(AppDb db, {String? token}) async {
    if (_server != null) return;
    if (token != null) setAuthToken(token);
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      status.value = 'Сервер включён (порт $port)';
      _server!.listen((req) async {
        try {
          if (req.method != 'POST' || req.uri.path != '/sync') {
            req.response.statusCode = HttpStatus.notFound;
            await req.response.close();
            return;
          }

          // Проверка токена аутентификации
          final clientToken = req.headers.value('x-sync-token');
          if (clientToken != _authToken) {
            req.response.statusCode = HttpStatus.unauthorized;
            req.response.headers.contentType = ContentType.json;
            req.response.write(
                jsonEncode({'error': 'Unauthorized: invalid sync token'}));
            await req.response.close();
            status.value = 'Отклонена неавторизованная попытка подключения';
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
          req.response.statusCode = HttpStatus.internalServerError;
          await req.response.close();
        }
      });
    } catch (e) {
      status.value = 'Не удалось запустить сервер: $e';
      _server = null;
    }
  }

  Future<void> stopServer() async {
    await _server?.close(force: true);
    _server = null;
    status.value = 'Сервер выключен';
  }

  /// Подключиться к другому устройству и обменяться данными.
  /// Возвращает краткий итог.
  Future<String> syncWith(AppDb db, String hostPort, {String? token}) async {
    final parts = hostPort.trim().split(':');
    final host = parts.first;
    final portStr = parts.length > 1 ? parts[1] : '$port';
    final tokenToSend =
        token?.trim().isNotEmpty == true ? token!.trim() : _authToken;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .postUrl(Uri.parse('http://$host:$portStr/sync'));
      req.headers.contentType = ContentType.json;
      req.headers.set('x-sync-token', tokenToSend);
      final payload = await db.exportPayload();
      req.write(jsonEncode(payload));
      final res = await req.close();
      if (res.statusCode == HttpStatus.unauthorized) {
        return 'Ошибка: неверный ключ / токен авторизации';
      }
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
