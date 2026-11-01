import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../core/session.dart';
import '../db/app_db.dart';

/// Состояние синхронизации для UI.
class SyncState extends ChangeNotifier {
  bool syncing = false;
  DateTime? lastSync;
  int pending = 0;
  String? lastError;

  void update({
    bool? syncing,
    DateTime? lastSync,
    int? pending,
    String? lastError,
    bool clearError = false,
  }) {
    if (syncing != null) this.syncing = syncing;
    if (lastSync != null) this.lastSync = lastSync;
    if (pending != null) this.pending = pending;
    if (clearError) {
      this.lastError = null;
    } else if (lastError != null) {
      this.lastError = lastError;
    }
    notifyListeners();
  }
}

/// Движок двусторонней синхронизации с 1С (УТ/УНФ/ERP) через HTTP-шлюз.
///
/// Pull: GET  {base}/pull?cursor=...  — справочники + остатки (upsert по GUID).
/// Push: POST {base}/push            — пачка из outbox; ответ помечает отправленное.
///
/// Триггеры: появление интернета, таймер (5 мин), ручная кнопка.
class SyncEngine {
  final AppDb db;
  final Session session;
  final SyncState state = SyncState();

  // Адрес шлюза 1С. В проде задаётся в настройках.
  String baseUrl = 'https://1c-gateway.example.com/api';
  http.Client? _client;
  Timer? _timer;
  StreamSubscription? _connectivitySub;
  bool _online = false;

  SyncEngine(this.db, this.session);

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => sync());
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((r) {
      final online = !r.contains(ConnectivityResult.none);
      if (online && !_online) sync(); // интернет появился — синхронизируем
      _online = online;
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _client?.close();
    _client = null;
  }

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stop();
    state.dispose();
  }

  Future<void> sync() async {
    if (state.syncing) return;
    state.update(syncing: true);
    try {
      await _push();
      await _pull();
      final pending = await _pendingCount();
      state.update(
        syncing: false,
        lastSync: DateTime.now(),
        pending: pending,
        clearError: true,
      );
    } catch (e) {
      state.update(syncing: false, lastError: e.toString());
    }
  }

  Future<int> _pendingCount() async {
    final rows = await db.database.rawQuery('SELECT COUNT(*) AS c FROM outbox');
    return rows.first['c'] as int? ?? 0;
  }

  /// Отправка накопленных изменений (заказы, оплаты, визиты).
  Future<void> _push() async {
    final rows = await db.database.query('outbox',
        orderBy: 'id', limit: 100);
    if (rows.isEmpty) return;
    final client = _client ??= http.Client();
    final res = await client.post(
      Uri.parse('$baseUrl/push'),
      headers: {
        'Content-Type': 'application/json',
        if (session.authToken != null) 'Authorization': 'Bearer ${session.authToken}',
      },
      body: jsonEncode({
        'agent_id': session.userId,
        'items': rows
            .map((r) => {
                  'local_id': r['id'],
                  'entity': r['entity'],
                  'op': r['op'],
                  'data': jsonDecode(r['payload'] as String),
                })
            .toList(),
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('Push failed: HTTP ${res.statusCode}');
    }
    final ack = jsonDecode(res.body) as Map<String, dynamic>;
    final accepted = (ack['accepted'] as List).cast<int>();
    // Пометить отправленное как подтверждённое (удалить из очереди),
    // обновить остатки, присланные сервером.
    final b = db.database.batch();
    for (final id in accepted) {
      b.delete('outbox', where: 'id = ?', whereArgs: [id]);
    }
    await b.commit(noResult: true);
    await _applyServerStocks(ack['stocks']);
  }

  /// Загрузка изменений с сервера (номенклатура, цены, остатки, клиенты).
  Future<void> _pull() async {
    final cursors = await db.database.query('sync_cursor');
    final cursorMap = {
      for (final c in cursors) c['entity'] as String: c['cursor'] as String?
    };
    final client = _client ??= http.Client();
    final res = await client.get(
      Uri.parse('$baseUrl/pull')
          .replace(queryParameters: {
            'agent_id': session.userId ?? '',
            'cursor_products': cursorMap['products'] ?? '',
            'cursor_clients': cursorMap['clients'] ?? '',
            'cursor_stocks': cursorMap['stocks'] ?? '',
          }),
      headers: {
        if (session.authToken != null) 'Authorization': 'Bearer ${session.authToken}',
      },
    );
    if (res.statusCode != 200) {
      throw Exception('Pull failed: HTTP ${res.statusCode}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    await _applyProducts(data['products'] as List? ?? []);
    await _applyClients(data['clients'] as List? ?? []);
    await _applyServerStocks(data['stocks']);
    await _saveCursors(data);
  }

  Future<void> _saveCursors(Map<String, dynamic> data) async {
    final b = db.database.batch();
    if (data['cursors'] is Map) {
      final cursors = data['cursors'] as Map;
      for (final e in cursors.entries) {
        if (e.value != null) {
          b.insert(
            'sync_cursor',
            {'entity': e.key.toString(), 'cursor': e.value.toString()},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    }
    for (final entity in const ['products', 'clients', 'stocks']) {
      final cursorVal = data['cursor_$entity'] ??
          (entity == 'products' ? data['cursor'] : null);
      if (cursorVal != null) {
        b.insert(
          'sync_cursor',
          {'entity': entity, 'cursor': cursorVal.toString()},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    await b.commit(noResult: true);
  }

  Future<void> _applyProducts(List items) async {
    final b = db.database.batch();
    for (final it in items.cast<Map<String, dynamic>>()) {
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
        it['id'],
        it['sku'] ?? '',
        it['name'] ?? '',
        it['nominal'],
        it['case_type'],
        it['manufacturer'],
        it['barcode'],
        it['unit'] ?? 'шт',
      ]);
    }
    await b.commit(noResult: true);
  }

  Future<void> _applyClients(List items) async {
    final b = db.database.batch();
    for (final it in items.cast<Map<String, dynamic>>()) {
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
        it['id'],
        it['name'] ?? '',
        (it['debt'] as num?)?.toDouble() ?? 0,
        it['price_list_id'],
        (it['discount_pct'] as num?)?.toDouble() ?? 0,
      ]);
    }
    await b.commit(noResult: true);
  }

  /// Остатки: сервер — источник истины, перезаписываем локальные qty.
  Future<void> _applyServerStocks(dynamic stocks) async {
    if (stocks is! List) return;
    final b = db.database.batch();
    for (final s in stocks.cast<Map<String, dynamic>>()) {
      b.insert(
        'stocks',
        {
          'product_id': s['product_id'],
          'warehouse_id': s['warehouse_id'],
          'series': s['series'],
          'cell': s['cell'],
          'qty': (s['qty'] as num?)?.toDouble() ?? 0,
          'reserved': (s['reserved'] as num?)?.toDouble() ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await b.commit(noResult: true);
  }
}
