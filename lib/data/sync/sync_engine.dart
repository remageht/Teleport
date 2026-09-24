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

  void update({bool? syncing, DateTime? lastSync, int? pending, String? lastError}) {
    this.syncing = syncing ?? this.syncing;
    this.lastSync = lastSync ?? this.lastSync;
    this.pending = pending ?? this.pending;
    if (lastError != null) this.lastError = lastError;
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
    _connectivitySub?.cancel();
  }

  Future<void> sync() async {
    if (state.syncing) return;
    state.update(syncing: true, lastError: null as String?);
    try {
      await _push();
      await _pull();
      final pending = await _pendingCount();
      state.update(syncing: false, lastSync: DateTime.now(), pending: pending);
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
  }

  Future<void> _applyProducts(List items) async {
    final b = db.database.batch();
    for (final it in items.cast<Map<String, dynamic>>()) {
      b.insert(
        'products',
        {
          'id': it['id'], 'sku': it['sku'] ?? '', 'name': it['name'] ?? '',
          'nominal': it['nominal'], 'case_type': it['case_type'],
          'manufacturer': it['manufacturer'], 'barcode': it['barcode'],
          'unit': it['unit'] ?? 'шт', 'sync_state': 'synced',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await b.commit(noResult: true);
  }

  Future<void> _applyClients(List items) async {
    final b = db.database.batch();
    for (final it in items.cast<Map<String, dynamic>>()) {
      b.insert(
        'clients',
        {
          'id': it['id'], 'name': it['name'] ?? '',
          'debt': (it['debt'] as num?)?.toDouble() ?? 0,
          'price_list_id': it['price_list_id'],
          'discount_pct': (it['discount_pct'] as num?)?.toDouble() ?? 0,
          'sync_state': 'synced',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
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
