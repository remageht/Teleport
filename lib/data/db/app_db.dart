import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/catalog.dart';
import '../../models/trade.dart';
import '../../services/devices.dart';

/// Локальная SQLite-БД. Offline-first: все данные лежат здесь,
/// сервер только источник/приёмник синхронизации.
///
/// Безопасность обновлений: перед миграцией на новую версию схемы
/// делается автоматический бэкап файла (папка backups, хранятся 3
/// последних), после — проверка целостности (есть таблица товаров).
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  /// Текущая версия схемы. Поднимать вместе с version в openDatabase.
  static const kDbVersion = 7;

  Database? _db;
  Database get database => _db!;
  String? _dbPath;

  /// Путь к файлу БД — для резервного копирования.
  String get dbPath => _dbPath!;

  Future<Database> open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationSupportDirectory();
    _dbPath = p.join(dir.path, 'radiotrade.db');    // Переезд 1.0.0: новый ID приложения = новая папка данных.
    // Если своей базы ещё нет, подхватываем самую свежую старую.
    if (Platform.isWindows && !File(_dbPath!).existsSync()) {
      await Directory(p.dirname(_dbPath!)).create(recursive: true);
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        File? best;
        for (final rel in [
          p.join('com.example', 'TelePort', 'radiotrade.db'),
          p.join('com.example', 'radiotrade', 'radiotrade.db'),
        ]) {
          final f = File(p.join(appData, rel));
          if (f.existsSync() &&
              (best == null ||
                  f.statSync().size > best.statSync().size)) {
            best = f;
          }
        }
        if (best != null) {
          try {
            await best.copy(_dbPath!);
          } catch (_) {}
        }
      }
    }
    // Бэкап перед возможной миграцией — данные человека не должны слететь.
    try {
      final prefs = await SharedPreferences.getInstance();
      await backupBeforeUpgrade(
          dir.path, prefs.getInt('db_version') ?? 0);
    } catch (_) {}
    _db = await openDatabase(
      _dbPath!,
      version: kDbVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, v) async {
        await _createAll(db, seed: true);
        await _ensureCategories(db);
        await _ensurePriceLists(db);
      },
      // Миграции БЕЗ пересоздания — пользовательские товары и фото сохраняются.
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 3) {
          await db.execute(
              'ALTER TABLE products ADD COLUMN photo_path TEXT');
        }
        if (oldV < 4) {
          await db.execute(
              "ALTER TABLE products ADD COLUMN updated_at TEXT DEFAULT ''");
        }
        if (oldV < 5) {
          await _ensureCategories(db);
        }
        if (oldV < 6) {
          await db.execute(
              'ALTER TABLE price_lists ADD COLUMN discount_pct REAL DEFAULT 0');
          await db.execute(
              'ALTER TABLE categories ADD COLUMN discount_pct REAL DEFAULT 0');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS moves (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              product_id TEXT NOT NULL, type TEXT NOT NULL,
              qty REAL DEFAULT 0, price REAL DEFAULT 0,
              note TEXT, created_at TEXT
            )''');
          await db.execute(
              'CREATE INDEX IF NOT EXISTS idx_moves_product ON moves(product_id)');
          await _ensurePriceLists(db);
        }
        if (oldV < 7) {
          // Журнал приходных накладных + привязка движений к накладной.
          await db.execute('''
            CREATE TABLE IF NOT EXISTS receipt_docs (
              id TEXT PRIMARY KEY, number TEXT, supplier TEXT,
              photo_path TEXT, total REAL DEFAULT 0,
              created_at TEXT
            )''');
          await db.execute(
              'ALTER TABLE moves ADD COLUMN receipt_id TEXT DEFAULT NULL');
        }
      },
    );
    // После открытия: проверка целостности + запоминание версии схемы.
    try {
      await _db!.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'products'");
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('db_version', kDbVersion);
    } catch (_) {}
    return _db!;
  }

  /// Автобэкап перед миграцией схемы: копия файла в backups/
  /// (хранятся 3 последних). Вызывать до openDatabase при upgrade.
  Future<void> backupBeforeUpgrade(
      String dirPath, int knownVersion) async {
    if (knownVersion >= kDbVersion) return;
    final f = File(_dbPath!);
    if (!f.existsSync()) return;
    try {
      final bakDir = Directory(p.join(dirPath, 'backups'));
      await bakDir.create(recursive: true);
      final stamp =
          DateTime.now().toIso8601String().replaceAll(':', '-');
      await f.copy(p.join(
          bakDir.path, 'pre_v${kDbVersion}_$stamp.db'));
      final old = await bakDir
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      old.sort((a, b) => a.path.compareTo(b.path));
      // Храним 3 последних бэкапа, остальное удаляем.
      for (var i = 0; i < old.length - 3; i++) {
        try {
          await old[i].delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// Полная (пере)создача таблиц каталога + сид данных магазина.
  /// При миграции v1->v2 старые демо-товары заменяются реальными.
  Future<void> _createAll(Database db, {required bool seed}) async {
    for (final t in ['products', 'stocks', 'price_items', 'price_lists']) {
      await db.execute('DROP TABLE IF EXISTS $t');
    }
    await db.execute('''
      CREATE TABLE products (
        id TEXT PRIMARY KEY, sku TEXT NOT NULL, name TEXT NOT NULL,
        description TEXT,
        nominal TEXT, case_type TEXT, manufacturer TEXT, category_id TEXT,
        barcode TEXT, unit TEXT DEFAULT 'шт',
        sold_count INTEGER DEFAULT 0,
        photo_path TEXT,
        updated_at TEXT DEFAULT '',
        is_active INTEGER DEFAULT 1,
        sync_state TEXT DEFAULT 'synced'
      )''');
    await db.execute(
        'CREATE INDEX idx_products_barcode ON products(barcode)');
    await db.execute('CREATE INDEX idx_products_sku ON products(sku)');
    await db.execute('''
      CREATE TABLE stocks (
        product_id TEXT NOT NULL, warehouse_id TEXT NOT NULL,
        series TEXT, cell TEXT, qty REAL DEFAULT 0, reserved REAL DEFAULT 0,
        PRIMARY KEY (product_id, warehouse_id, series, cell)
      )''');
    await db.execute('''
      CREATE TABLE price_lists (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, is_default INTEGER DEFAULT 0,
        discount_pct REAL DEFAULT 0
      )''');
    await db.execute('''
      CREATE TABLE price_items (
        price_list_id TEXT NOT NULL, product_id TEXT NOT NULL, price REAL NOT NULL,
        PRIMARY KEY (price_list_id, product_id)
      )''');
    if (seed) await _seedTelemaster(db);
  }

  /// Загрузка каталога магазина из assets/telemaster_seed.json
  /// (сгенерирован из Excel: склад по коробкам + накладные).
  Future<void> _seedTelemaster(Database db) async {
    final raw = await rootBundle.loadString('assets/telemaster_seed.json');
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final items = data['products'] as List;
    final shopName = (data['shop'] as String?) ?? 'ТЕЛЕМАСТЕР';

    final b = db.batch();
    b.insert('price_lists',
        {'id': 'pl-base', 'name': 'Розничная', 'is_default': 1});
    b.insert('warehouses', {'id': 'wh-shop', 'name': shopName});
    b.delete('warehouses', where: "id != 'wh-shop'");
    b.insert('organizations', {'id': 'org1', 'name': shopName},
        conflictAlgorithm: ConflictAlgorithm.replace);
    b.delete('organizations', where: "id != 'org1'");

    // Остальные таблицы (создаются один раз, при миграции уже существуют).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS clients (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, inn TEXT, address TEXT,
        contact TEXT, phone TEXT, price_list_id TEXT,
        discount_pct REAL DEFAULT 0, debt REAL DEFAULT 0,
        credit_limit REAL DEFAULT 0, route_day INTEGER DEFAULT 0,
        sync_state TEXT DEFAULT 'synced'
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id TEXT PRIMARY KEY, number TEXT, client_id TEXT, client_name TEXT,
        type TEXT, status TEXT, warehouse_id TEXT, agent_id TEXT,
        pay_type TEXT, client_discount_pct REAL DEFAULT 0, total REAL DEFAULT 0,
        created_at TEXT, visit_id TEXT, sync_state TEXT DEFAULT 'pending'
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_lines (
        order_id TEXT NOT NULL, line_no INTEGER NOT NULL,
        product_id TEXT NOT NULL, qty REAL, price REAL,
        discount_pct REAL DEFAULT 0, total REAL,
        PRIMARY KEY (order_id, line_no)
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payments (
        id TEXT PRIMARY KEY, order_id TEXT, type TEXT, amount REAL,
        doc_no TEXT, created_at TEXT, sync_state TEXT DEFAULT 'pending'
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS visits (
        id TEXT PRIMARY KEY, client_id TEXT, agent_id TEXT, planned_at TEXT,
        fact_at TEXT, gps_lat REAL, gps_lng REAL, status TEXT DEFAULT 'planned',
        task TEXT, photo_paths TEXT, sync_state TEXT DEFAULT 'pending'
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, role TEXT DEFAULT 'agent',
        pin TEXT
      )''');
    await db.execute('CREATE TABLE IF NOT EXISTS warehouses '
        '(id TEXT PRIMARY KEY, name TEXT NOT NULL)');
    await db.execute('CREATE TABLE IF NOT EXISTS organizations '
        '(id TEXT PRIMARY KEY, name TEXT NOT NULL)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity TEXT NOT NULL, op TEXT NOT NULL,
        payload TEXT NOT NULL, created_at TEXT,
        attempts INTEGER DEFAULT 0, error TEXT
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS moves (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id TEXT NOT NULL, type TEXT NOT NULL,
        qty REAL DEFAULT 0, price REAL DEFAULT 0,
        note TEXT, receipt_id TEXT, created_at TEXT
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS receipt_docs (
        id TEXT PRIMARY KEY, number TEXT, supplier TEXT,
        photo_path TEXT, total REAL DEFAULT 0,
        created_at TEXT
      )''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_moves_product ON moves(product_id)');
    await db.execute('CREATE TABLE IF NOT EXISTS sync_cursor '
        '(entity TEXT PRIMARY KEY, cursor TEXT)');

    for (final it in items.cast<Map<String, dynamic>>()) {
      b.insert('products', {
        'id': it['id'],
        'sku': it['sku'],
        'name': it['name'],
        'description': it['desc'],
        'unit': it['unit'] ?? 'шт',
        'sold_count': it['sold'] ?? 0,
      });
      final qty = (it['qty'] as num?)?.toDouble() ?? 0;
      final cell = it['cell'] as String?;
      b.insert('stocks', {
        'product_id': it['id'],
        'warehouse_id': 'wh-shop',
        'series': null,
        'cell': cell,
        'qty': qty,
      });
      final price = (it['price'] as num?)?.toDouble() ?? 0;
      if (price > 0) {
        b.insert('price_items', {
          'price_list_id': 'pl-base',
          'product_id': it['id'],
          'price': price,
        });
      }
    }
    await b.commit(noResult: true);
  }

  // ---- Товары / остатки ----

  /// Поиск с ценой и остатком одним запросом (JOIN).
  Future<List<Product>> searchProducts(String q,
      {SortMode sort = SortMode.popular,
      bool onlyAvailable = false,
      bool onlySold = false,
      String? categoryId,
      int limit = 200}) async {
    var sql = '''
      SELECT p.*, IFNULL(pi.price, 0) AS price,
             IFNULL(s.available, 0) AS available,
             IFNULL((SELECT s2.cell FROM stocks s2 WHERE s2.product_id = p.id AND s2.qty > 0 ORDER BY s2.cell LIMIT 1), '') AS cell
      FROM products p
      LEFT JOIN price_items pi
        ON pi.product_id = p.id AND pi.price_list_id = 'pl-base'
      LEFT JOIN (
        SELECT product_id, SUM(qty - reserved) AS available
        FROM stocks GROUP BY product_id
      ) s ON s.product_id = p.id
      WHERE p.is_active = 1
    ''';
    final args = <Object>[];
    if (q.isNotEmpty) {
      // Поиск по артикулу, названию, описанию, номиналу, корпусу, штрихкоду.
      sql += ''' AND (p.sku LIKE ? OR p.name LIKE ? OR IFNULL(p.description,'') LIKE ?
                 OR IFNULL(p.nominal,'') LIKE ? OR IFNULL(p.case_type,'') LIKE ?
                 OR IFNULL(p.manufacturer,'') LIKE ? OR IFNULL(p.barcode,'') LIKE ?)''';
      final like = '%$q%';
      args.addAll([like, like, like, like, like, like, like]);
    }
    if (onlyAvailable) {
      sql += ' AND IFNULL(s.available, 0) > 0';
    }
    if (onlySold) {
      sql += ' AND p.sold_count > 0';
    }
    if (categoryId != null) {
      // 'none' = товары без каталога.
      if (categoryId == 'none') {
        sql += ' AND p.category_id IS NULL';
      } else {
        sql += ' AND p.category_id = ?';
        args.add(categoryId);
      }
    }
    sql += switch (sort) {
      SortMode.popular =>
        ' ORDER BY p.sold_count DESC, IFNULL(s.available,0) DESC, p.name',
      SortMode.name => ' ORDER BY p.name',
      SortMode.stock => ' ORDER BY IFNULL(s.available,0) DESC, p.name',
      SortMode.price => ' ORDER BY price DESC',
    };
    sql += ' LIMIT ?';
    args.add(limit);
    final rows = await database.rawQuery(sql, args);
    return rows.map(Product.fromRow).toList();
  }

  Future<Product?> findByBarcode(String code) async {
    final rows = await database.rawQuery('''
      SELECT p.*, IFNULL(pi.price,0) AS price,
             IFNULL((SELECT SUM(qty-reserved) FROM stocks WHERE product_id = p.id),0) AS available,
             IFNULL((SELECT s2.cell FROM stocks s2 WHERE s2.product_id = p.id AND s2.qty > 0 ORDER BY s2.cell LIMIT 1), '') AS cell
      FROM products p
      LEFT JOIN price_items pi ON pi.product_id = p.id AND pi.price_list_id = 'pl-base'
      WHERE p.barcode = ? OR p.sku = ? LIMIT 1
    ''', [code, code]);
    return rows.isEmpty ? null : Product.fromRow(rows.first);
  }

  Future<double> availableQty(String productId, String warehouseId) async {
    final rows = await database.rawQuery(
      'SELECT SUM(qty - reserved) AS av FROM stocks WHERE product_id = ? AND warehouse_id = ?',
      [productId, warehouseId],
    );
    return (rows.first['av'] as num?)?.toDouble() ?? 0;
  }

  Future<List<Stock>> stockCells(String productId) async {
    final rows = await database
        .query('stocks', where: 'product_id = ?', whereArgs: [productId]);
    return rows.map(Stock.fromRow).toList();
  }

  /// Резервирование товара.
  Future<void> reserve(String productId, String warehouseId, double qty) async {
    await database.rawInsert('''
      INSERT INTO stocks (product_id, warehouse_id, series, cell, qty, reserved)
      VALUES (?, ?, NULL, NULL, 0, ?)
      ON CONFLICT(product_id, warehouse_id, series, cell)
      DO UPDATE SET reserved = reserved + ?
    ''', [productId, warehouseId, qty, qty]);
  }

  /// Добавить новый товар вручную (склад). Возвращает созданный Product.
  Future<Product> addProduct({
    required String name,
    String? description,
    double qty = 0,
    double price = 0,
    String? barcode,
  }) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final id = 'usr-$ts';
    final sku = 'TLU${ts % 100000}';
    final b = database.batch();
    b.insert('products', {
      'id': id, 'sku': sku, 'name': name, 'description': description,
      'barcode': barcode, 'photo_path': null, 'sold_count': 0,
    });
    b.insert('stocks', {
      'product_id': id, 'warehouse_id': 'wh-shop',
      'cell': 'Новые товары', 'qty': qty, 'reserved': 0,
    });
    if (price > 0) {
      b.insert('price_items',
          {'price_list_id': 'pl-base', 'product_id': id, 'price': price});
    }
    await b.commit(noResult: true);
    await touch(id);
    return Product(
        id: id, sku: sku, name: name, description: description,
        barcode: barcode, price: price, available: qty);
  }

  /// Удалить товар из базы (товар + остатки + цена).
  Future<void> deleteProduct(String id) async {
    final b = database.batch();
    b.delete('products', where: 'id = ?', whereArgs: [id]);
    b.delete('stocks', where: 'product_id = ?', whereArgs: [id]);
    b.delete('price_items', where: 'product_id = ?', whereArgs: [id]);
    await b.commit(noResult: true);
  }

  /// Сохранить путь к фото товара.
  Future<void> setPhotoPath(String id, String path) async {
    await database.update('products', {'photo_path': path},
        where: 'id = ?', whereArgs: [id]);
  }

  // ---- Обмен между устройствами (ПК ⇄ телефон) ----

  /// Выгрузка данных для синхронизации: товары + заказы (упрощённо).
  Future<Map<String, Object?>> exportPayload() async {
    final products = await database.rawQuery('''
      SELECT p.id, p.sku, p.name, p.description, p.sold_count, p.updated_at,
             IFNULL(s.qty, 0) AS qty, IFNULL(pi.price, 0) AS price
      FROM products p
      LEFT JOIN (SELECT product_id, SUM(qty) AS qty FROM stocks
                 WHERE warehouse_id = 'wh-shop' GROUP BY product_id) s
        ON s.product_id = p.id
      LEFT JOIN price_items pi
        ON pi.product_id = p.id AND pi.price_list_id = 'pl-base'
      WHERE p.is_active = 1
    ''');
    final orders = await database.query('orders');
    return {'products': products, 'orders': orders};
  }

  /// Влить входящие данные: товары — по updated_at (кто свежее),
  /// sold_count/qty — максимум, заказы — upsert по id.
  Future<void> mergePayload(Map<String, Object?> payload) async {
    final products = (payload['products'] as List?) ?? const [];
    for (final raw in products) {
      final it = Map<String, Object?>.from(raw as Map);
      final id = it['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final updatedAt = (it['updated_at'] as String?) ?? '';
      final local = await database.query('products',
          where: 'id = ?', whereArgs: [id], limit: 1);
      if (local.isEmpty) {
        // Новый товар с другого устройства.
        final ts = DateTime.now().millisecondsSinceEpoch;
        await database.insert('products', {
          'id': id,
          'sku': (it['sku'] as String?) ?? 'SYNC$ts',
          'name': (it['name'] as String?) ?? 'Без названия',
          'description': it['description'] as String?,
          'sold_count': (it['sold_count'] as num?)?.toInt() ?? 0,
          'updated_at': updatedAt,
        });
        await setStockQty(id, (it['qty'] as num?)?.toDouble() ?? 0);
        final price = (it['price'] as num?)?.toDouble() ?? 0;
        if (price > 0) {
          await database.insert(
              'price_items',
              {'price_list_id': 'pl-base', 'product_id': id, 'price': price},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      } else {
        final l = local.first;
        final localUpdated = (l['updated_at'] as String?) ?? '';
        final soldRemote = (it['sold_count'] as num?)?.toInt() ?? 0;
        final soldLocal = (l['sold_count'] as int?) ?? 0;
        final updates = <String, Object?>{
          'sold_count': soldRemote > soldLocal ? soldRemote : soldLocal,
        };
        if (updatedAt.compareTo(localUpdated) > 0) {
          updates['name'] = (it['name'] as String?) ?? l['name'];
          updates['description'] =
              it['description'] as String? ?? l['description'];
          updates['updated_at'] = updatedAt;
        }
        await database
            .update('products', updates, where: 'id = ?', whereArgs: [id]);
        // Остаток: берём максимум (простое правило для ручной торговли).
        final qtyRemote = (it['qty'] as num?)?.toDouble() ?? 0;
        final qtyLocal = await availableQty(id, 'wh-shop');
        if (qtyRemote > qtyLocal) {
          await setStockQty(id, qtyRemote);
        }
        final price = (it['price'] as num?)?.toDouble() ?? 0;
        if (price > 0) {
          await database.insert(
              'price_items',
              {'price_list_id': 'pl-base', 'product_id': id, 'price': price},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    }
    final orders = (payload['orders'] as List?) ?? const [];
    for (final raw in orders) {
      final o = Map<String, Object?>.from(raw as Map);
      final id = o['id'] as String?;
      if (id == null) continue;
      await database.insert('orders', o,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Пометить товар изменённым (для победы «кто свежее» при обмене).
  Future<void> touch(String id) async {
    await database.update(
        'products',
        {'updated_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id]);
  }

  // ---- Каталоги (категории товаров) ----

  /// Стандартные каталоги + автосортировка всех товаров по названиям.
  Future<void> _ensureCategories(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS categories (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER DEFAULT 0,
        discount_pct REAL DEFAULT 0
      )''');
    final existing = await db.query('categories');
    if (existing.isNotEmpty) return;

    const cats = [
      ('cat-mcu', 'Микроконтроллеры'),
      ('cat-chip', 'Микросхемы'),
      ('cat-rc', 'Резисторы и конденсаторы'),
      ('cat-sensor', 'Датчики и модули'),
      ('cat-conn', 'Разъёмы и клеммы'),
      ('cat-tool', 'Инструмент и пайка'),
      ('cat-power', 'Питание и АКБ'),
      ('cat-auto', 'Автоматика и защита'),
      ('cat-light', 'Освещение'),
      ('cat-cable', 'Кабели и провода'),
      ('cat-other', 'Прочее'),
    ];
    final b = db.batch();
    for (var i = 0; i < cats.length; i++) {
      b.insert('categories', {
        'id': cats[i].$1, 'name': cats[i].$2, 'position': i,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await b.commit(noResult: true);

    // Автоматически разложить существующие товары по каталогам.
    final rows = await db.query('products', columns: ['id', 'name', 'description']);
    final ub = db.batch();
    for (final r in rows) {
      final cat = _matchCategory(
          '${r['name'] ?? ''} ${r['description'] ?? ''}'.toLowerCase());
      if (cat != null) {
        ub.update('products', {'category_id': cat},
            where: 'id = ?', whereArgs: [r['id']]);
      }
    }
    await ub.commit(noResult: true);
  }

  String? _matchCategory(String s) {
    bool has(List<String> keys) => keys.any(s.contains);
    if (has(['микроконтроллер', 'stm32', 'arduino', 'esp ', 'атмег', 'atmega'])) {
      return 'cat-mcu';
    }
    if (has(['микросхем', 'tda', 'lm3', 'lm2', 'ne555', 'усилител', 'таймер',
             'in8', 'ka2', 'ka3', 'драйвер', 'стабилизатор', 'inno'])) {
      return 'cat-chip';
    }
    if (has(['резистор', 'конденсатор', 'дроссел', 'катушк', 'индуктивн',
             'трансформатор', 'мкф', 'нф', 'ком'])) {
      return 'cat-rc';
    }
    if (has(['датчик', 'сенсор', 'ntc', 'bms', 'модул', 'плат', 'реле',
             'преобразовател', 'dc-dc', 'контроллер', 'триггер'])) {
      return 'cat-sensor';
    }
    if (has(['разъем', 'разъём', 'коннектор', 'клемм', 'наконечник', 'xt60',
             'xt90', 'mc4', 'переходник', 'адаптер', 'usb', 'розетк', 'вилк',
             'гнездо', 'dc022'])) {
      return 'cat-conn';
    }
    if (has(['паяльник', 'паяльная', 'флюс', 'припой', 'термопаст', 'клещ',
             'стриппер', 'кримпер', 'отвертк', 'инструмент', 'пресс', 'пая'])) {
      return 'cat-tool';
    }
    if (has(['аккумулятор', 'батарейк', '18650', 'nanfu', 'заряд'])) {
      return 'cat-power';
    }
    if (has(['автомат', 'выключател', 'рубильник', 'авдт', 'предохранител',
             'тумблер', 'кнопк', 'переключател', 'умз', 'дин-рейку', 'укк',
             'щит', 'частотомер', 'счетчик'])) {
      return 'cat-auto';
    }
    if (has(['светодиод', 'led', 'лампа', 'светильник', 'фонар'])) {
      return 'cat-light';
    }
    if (has(['провод', 'кабель', 'шнур'])) {
      return 'cat-cable';
    }
    return 'cat-other';
  }

  Future<List<Map<String, Object?>>> categories() async {
    return database.query('categories', orderBy: 'position');
  }

  /// Каталоги со счётчиком позиций (для отдельного списка).
  Future<List<({String id, String name, int count})>>
      categoriesWithCounts() async {
    final rows = await database.rawQuery('''
      SELECT c.id AS id, c.name AS name, COUNT(p.id) AS cnt
      FROM categories c
      LEFT JOIN products p
        ON p.category_id = c.id AND p.is_active = 1
      GROUP BY c.id ORDER BY c.position
    ''');
    return rows
        .map((r) => (
              id: r['id'] as String,
              name: r['name'] as String? ?? '',
              count: (r['cnt'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Сколько позиций без каталога.
  Future<int> uncategorizedCount() async {
    final rows = await database.rawQuery(
        'SELECT COUNT(*) AS c FROM products WHERE is_active = 1 AND category_id IS NULL');
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<void> addCategory(String name) async {
    final id = 'cat-${DateTime.now().millisecondsSinceEpoch}';
    final rows = await database.rawQuery('SELECT COUNT(*) AS c FROM categories');
    final count = (rows.first['c'] as int?) ?? 0;
    await database.insert('categories',
        {'id': id, 'name': name.trim(), 'position': count});
  }

  Future<void> renameCategory(String id, String name) async {
    await database.update('categories', {'name': name.trim()},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Скидка на весь каталог, % (применяется поверх прайса).
  Future<void> setCategoryDiscount(String id, double pct) async {
    await database.update('categories', {'discount_pct': pct},
        where: 'id = ?', whereArgs: [id]);
  }

  // ---- Прайсы и скидки ----

  /// Базовые прайсы, если их нет: розница 0%, опт −10%, своим −15%.
  Future<void> _ensurePriceLists(Database db) async {
    for (final row in [
      {
        'id': 'pl-base',
        'name': 'Розничная',
        'is_default': 1,
        'discount_pct': 0
      },
      {
        'id': 'pl-opt',
        'name': 'Оптовая',
        'is_default': 0,
        'discount_pct': 10
      },
      {
        'id': 'pl-vip',
        'name': 'Своим',
        'is_default': 0,
        'discount_pct': 15
      },
    ]) {
      await db.insert('price_lists', row,
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<List<Map<String, Object?>>> priceLists() async {
    return database.query('price_lists', orderBy: 'is_default DESC, name');
  }

  Future<void> setPriceListDiscount(String id, double pct) async {
    await database.update('price_lists', {'discount_pct': pct},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addPriceList(String name, double pct) async {
    final id = 'pl-${DateTime.now().millisecondsSinceEpoch}';
    await database.insert('price_lists', {
      'id': id,
      'name': name.trim(),
      'is_default': 0,
      'discount_pct': pct,
    });
  }

  Future<void> renamePriceList(String id, String name) async {
    await database.update('price_lists', {'name': name.trim()},
        where: 'id = ?', whereArgs: [id]);
  }

  /// Удалить прайс (кроме базового); клиенты переводятся на розницу.
  Future<void> deletePriceList(String id) async {
    if (id == 'pl-base') return;
    final b = database.batch();
    b.delete('price_lists', where: 'id = ?', whereArgs: [id]);
    b.delete('price_items',
        where: 'price_list_id = ?', whereArgs: [id]);
    b.update('clients', {'price_list_id': 'pl-base'},
        where: 'price_list_id = ?', whereArgs: [id]);
    await b.commit(noResult: true);
  }

  Future<void> setClientPriceList(String clientId, String? priceListId) async {
    await database.update('clients', {'price_list_id': priceListId},
        where: 'id = ?', whereArgs: [clientId]);
  }

  /// Итоговая цена: базовая − скидка прайса − скидка каталога.
  Future<double> effectivePrice(String productId,
      {String? priceListId}) async {
    final base = await priceFor(productId);
    if (base <= 0) return 0;
    var disc = 0.0;
    if (priceListId != null && priceListId != 'pl-base') {
      final r = await database.query('price_lists',
          columns: ['discount_pct'],
          where: 'id = ?',
          whereArgs: [priceListId],
          limit: 1);
      if (r.isNotEmpty) {
        disc += (r.first['discount_pct'] as num?)?.toDouble() ?? 0;
      }
    }
    final pr = await database.rawQuery(
        'SELECT c.discount_pct AS d FROM products p '
        'LEFT JOIN categories c ON c.id = p.category_id WHERE p.id = ?',
        [productId]);
    if (pr.isNotEmpty) {
      disc += (pr.first['d'] as num?)?.toDouble() ?? 0;
    }
    if (disc < 0) disc = 0;
    if (disc > 90) disc = 90;
    return ((base * (1 - disc / 100)) * 100).round() / 100;
  }

  // ---- Движения товара (приёмка / продажи / инвентаризация) ----

  Future<void> logMove({
    required String productId,
    required String type, // receipt | sale | count
    required double qty,
    double price = 0,
    String? note,
    String? receiptId,
  }) async {
    await database.insert('moves', {
      'product_id': productId,
      'type': type,
      'qty': qty,
      'price': price,
      'note': note,
      'receipt_id': receiptId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> movesOf(String productId,
      {int limit = 20}) async {
    return database.query('moves',
        where: 'product_id = ?',
        whereArgs: [productId],
        orderBy: 'id DESC',
        limit: limit);
  }

  /// Приёмка: плюс к остатку (в первую ячейку или «Новые товары»)
  /// + запись в историю движений.
  Future<void> receiveGoods({
    required String productId,
    required double qty,
    double buyPrice = 0,
    String? cell,
    String? note,
    String? receiptId,
  }) async {
    final rows = await database.query('stocks',
        columns: ['cell'],
        where: "product_id = ? AND warehouse_id = 'wh-shop'",
        whereArgs: [productId],
        limit: 1);
    final target = rows.isEmpty
        ? ((cell == null || cell.trim().isEmpty)
            ? 'Новые товары'
            : cell.trim())
        : rows.first['cell'] as String?;
    if (rows.isEmpty) {
      await database.insert('stocks', {
        'product_id': productId,
        'warehouse_id': 'wh-shop',
        'series': null,
        'cell': target,
        'qty': qty,
        'reserved': 0,
      });
    } else {
      await database.rawUpdate(
          'UPDATE stocks SET qty = qty + ? WHERE product_id = ? '
          "AND warehouse_id = 'wh-shop' AND IFNULL(cell,'') = IFNULL(?, '')",
          [qty, productId, target]);
    }
    await logMove(
        productId: productId,
        type: 'receipt',
        qty: qty,
        price: buyPrice,
        note: note,
        receiptId: receiptId);
    await touch(productId);
  }

  // ---- Накладные (журнал приёмок) ----

  Future<String> createReceipt(
      {String? number, String? supplier, String? photoPath}) async {
    final id = 'rc-${DateTime.now().millisecondsSinceEpoch}';
    await database.insert('receipt_docs', {
      'id': id,
      'number': number,
      'supplier': supplier,
      'photo_path': photoPath,
      'total': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
    return id;
  }

  Future<List<Map<String, Object?>>> receipts() async {
    return database.query('receipt_docs', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, Object?>>> receiptMoves(String receiptId) async {
    return database.rawQuery('''
      SELECT m.*, p.name AS pname, p.sku AS sku
      FROM moves m LEFT JOIN products p ON p.id = m.product_id
      WHERE m.receipt_id = ? ORDER BY m.id
    ''', [receiptId]);
  }

  Future<void> setReceiptPhoto(String id, String path) async {
    await database.update('receipt_docs', {'photo_path': path},
        where: 'id = ?', whereArgs: [id]);
  }

  // ---- Поиск дублей (накладные, приёмка) ----

  /// Нормализация названия для сравнения: верхниий регистр,
  /// только буквы и цифры.
  static String normName(String s) =>
      s.toUpperCase().replaceAll(RegExp(r'[^A-ZА-Я0-9]'), '');

  /// Товар целиком по id (с ценой и остатком).
  Future<Product?> productById(String id) async {
    final rows = await database.rawQuery('''
      SELECT p.*, IFNULL(pi.price,0) AS price,
             IFNULL((SELECT SUM(qty-reserved) FROM stocks WHERE product_id = p.id),0) AS available,
             IFNULL((SELECT s2.cell FROM stocks s2 WHERE s2.product_id = p.id AND s2.qty > 0 ORDER BY s2.cell LIMIT 1), '') AS cell
      FROM products p
      LEFT JOIN price_items pi ON pi.product_id = p.id AND pi.price_list_id = 'pl-base'
      WHERE p.id = ? LIMIT 1
    ''', [id]);
    return rows.isEmpty ? null : Product.fromRow(rows.first);
  }

  /// Подбор позиции из базы под строку накладной:
  /// exact — полное совпадение нормализованного названия (количество
  /// просто плюсуется), similar — до 4 похожих на выбор.
  /// OCR с фото возвращает латиницу вместо кириллицы, поэтому каждое
  /// название базы сравнивается дважды: как есть и в транслите.
  Future<({Product? exact, List<Product> similar})> matchProduct(
      String name) async {
    final norm = normName(name);
    if (norm.isEmpty) return (exact: null, similar: <Product>[]);
    final rows = await database
        .query('products', where: 'is_active = 1', limit: 2000);
    Product? exact;
    String exactNorm = '';
    final scored = <String, double>{};
    final tokens = norm
        .split(RegExp(r'(?<=[A-ZА-Я])(?=\d)|(?<=\d)(?=[A-ZА-Я])|_'))
        .where((t) => t.length >= 2)
        .toList();
    double coverage(String haystack) {
      var hit = 0;
      for (final t in tokens) {
        if (haystack.contains(t)) hit += t.length;
      }
      return hit / norm.length;
    }

    for (final r in rows) {
      final id = r['id'] as String;
      final dbName = (r['name'] as String?) ?? '';
      final n = normName(dbName);
      if (n.isEmpty) continue;
      // Вторая форма — транслит (для OCR-латиницы).
      final nt = normName(ReceiptPrinter.translit(dbName));
      if (n == norm || nt == norm) {
        exact = await productById(id);
        exactNorm = n;
        continue;
      }
      final score =
          coverage(n) > coverage(nt) ? coverage(n) : coverage(nt);
      if (score >= 0.5 &&
          (exact == null ||
              (n != exactNorm && nt != normName(exact.name)))) {
        final prev = scored[id] ?? 0;
        if (score > prev) scored[id] = score;
      }
    }
    final top = scored.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final similar = <Product>[];
    for (final e in top.take(4)) {
      final p = await productById(e.key);
      if (p != null && p.id != exact?.id) similar.add(p);
    }
    return (exact: exact, similar: similar);
  }

  // ---- Свои штрихкоды ----

  /// Сгенерировать уникальный внутренний код вида TP123456.
  Future<String> generateBarcode() async {
    for (var i = 0; i < 10; i++) {
      final ts = DateTime.now().millisecondsSinceEpoch + i;
      final code = 'TP${(ts % 1000000).toString().padLeft(6, '0')}';
      final ex = await database.query('products',
          columns: ['id'],
          where: 'barcode = ?',
          whereArgs: [code],
          limit: 1);
      if (ex.isEmpty) return code;
    }
    return 'TP${DateTime.now().microsecondsSinceEpoch % 100000000}';
  }

  Future<void> setBarcode(String id, String code) async {
    await database.update(
        'products', {'barcode': code.trim()},
        where: 'id = ?', whereArgs: [id]);
    await touch(id);
  }

  /// Удалить каталог; его товары остаются, просто становятся без каталога.
  Future<void> deleteCategory(String id) async {
    final b = database.batch();
    b.delete('categories', where: 'id = ?', whereArgs: [id]);
    b.update('products', {'category_id': null},
        where: 'category_id = ?', whereArgs: [id]);
    await b.commit(noResult: true);
  }

  Future<void> setProductCategory(String productId, String? categoryId) async {
    await database.update('products', {'category_id': categoryId},
        where: 'id = ?', whereArgs: [productId]);
    await touch(productId);
  }

  /// Массово назначить каталог выбранным товарам.
  Future<void> setProductsCategory(
      List<String> ids, String? categoryId) async {
    if (ids.isEmpty) return;
    final b = database.batch();
    final now = DateTime.now().toIso8601String();
    for (final id in ids) {
      b.update('products',
          {'category_id': categoryId, 'updated_at': now},
          where: 'id = ?', whereArgs: [id]);
    }
    await b.commit(noResult: true);
  }

  /// Массово удалить товары (товар + остатки + цены).
  Future<void> deleteProducts(List<String> ids) async {
    if (ids.isEmpty) return;
    final b = database.batch();
    for (final id in ids) {
      b.delete('products', where: 'id = ?', whereArgs: [id]);
      b.delete('stocks', where: 'product_id = ?', whereArgs: [id]);
      b.delete('price_items', where: 'product_id = ?', whereArgs: [id]);
    }
    await b.commit(noResult: true);
  }

  /// Массово поставить точную цену выбранным товарам.
  Future<void> setProductsPrice(List<String> ids, double price) async {
    if (ids.isEmpty) return;
    final b = database.batch();
    for (final id in ids) {
      b.insert(
          'price_items',
          {
            'price_list_id': 'pl-base',
            'product_id': id,
            'price': price,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
    for (final id in ids) {
      await touch(id);
    }
  }

  /// Массовая наценка (+%) или скидка (−%) от текущих цен.
  /// Товары без цены (0) пропускаются. Возвращает, скольким обновили.
  Future<int> applyMarkup(List<String> ids, double pct) async {
    if (ids.isEmpty) return 0;
    final ph = List.filled(ids.length, '?').join(',');
    final rows = await database.rawQuery(
        'SELECT product_id, price FROM price_items '
        'WHERE price_list_id = ? AND product_id IN ($ph)',
        ['pl-base', ...ids]);
    final b = database.batch();
    var n = 0;
    for (final r in rows) {
      final cur = (r['price'] as num?)?.toDouble() ?? 0;
      if (cur <= 0) continue;
      final next = (cur * (1 + pct / 100) * 100).round() / 100;
      b.insert(
          'price_items',
          {
            'price_list_id': 'pl-base',
            'product_id': r['product_id'],
            'price': next,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
      n++;
    }
    await b.commit(noResult: true);
    for (final r in rows) {
      await touch(r['product_id'] as String);
    }
    return n;
  }

  /// Полное редактирование товара (название, описание, место, цена, каталог).
  Future<void> updateProduct({
    required String id,
    required String name,
    String? description,
    String? cell,
    double? price,
    String? categoryId,
  }) async {
    final b = database.batch();
    b.update('products', {
      'name': name.trim(),
      'description': description,
      'category_id': categoryId,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
    if (cell != null) {
      b.update('stocks', {'cell': cell.trim()},
          where: 'product_id = ?', whereArgs: [id]);
    }
    if (price != null && price > 0) {
      b.insert('price_items', {
        'price_list_id': 'pl-base', 'product_id': id, 'price': price,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await b.commit(noResult: true);
  }

  /// Продажи по дням (для графика на «Дне»).
  Future<List<({String day, double total, int count})>> salesByDay(
      {int days = 7}) async {
    final rows = await database.rawQuery('''
      SELECT substr(created_at, 1, 10) AS d, SUM(total) AS t, COUNT(*) AS c
      FROM orders GROUP BY d ORDER BY d DESC LIMIT ?
    ''', [days]);
    return rows
        .map((r) => (
              day: r['d'] as String? ?? '',
              total: (r['t'] as num?)?.toDouble() ?? 0,
              count: (r['c'] as int?) ?? 0,
            ))
        .toList();
  }

  /// Продажи (шт) по каталогам — для диаграммы на «Дне».
  Future<List<({String name, int qty})>> salesByCategory() async {
    final rows = await database.rawQuery('''
      SELECT IFNULL(c.name, 'Без каталога') AS name, SUM(l.qty) AS qty
      FROM order_lines l
      JOIN products p ON p.id = l.product_id
      LEFT JOIN categories c ON c.id = p.category_id
      GROUP BY c.id ORDER BY qty DESC LIMIT 6
    ''');
    return rows
        .map((r) => (
              name: r['name'] as String? ?? 'Без каталога',
              qty: ((r['qty'] as num?)?.toDouble() ?? 0).toInt(),
            ))
        .where((e) => e.qty > 0)
        .toList();
  }

  /// Самые покупаемые товары (для блока «Часто берут»).
  Future<List<Product>> popularProducts({int limit = 5}) async {
    final rows = await database.rawQuery('''
      SELECT p.*, IFNULL(pi.price,0) AS price,
             IFNULL(s.available,0) AS available,
             IFNULL((SELECT s2.cell FROM stocks s2 WHERE s2.product_id = p.id AND s2.qty > 0 ORDER BY s2.cell LIMIT 1), '') AS cell
      FROM products p
      LEFT JOIN price_items pi ON pi.product_id = p.id AND pi.price_list_id = 'pl-base'
      LEFT JOIN (SELECT product_id, SUM(qty-reserved) AS available FROM stocks GROUP BY product_id) s
        ON s.product_id = p.id
      WHERE p.sold_count > 0
      ORDER BY p.sold_count DESC LIMIT ?
    ''', [limit]);
    return rows.map(Product.fromRow).toList();
  }

  /// Обновить остаток одной позиции (инвентаризация / приёмка).
  Future<void> setStockQty(String productId, double qty, {String? cell}) async {
    await database.rawInsert('''
      INSERT INTO stocks (product_id, warehouse_id, series, cell, qty, reserved)
      VALUES (?, 'wh-shop', NULL, ?, ?, 0)
      ON CONFLICT(product_id, warehouse_id, series, cell)
      DO UPDATE SET qty = ?
    ''', [productId, cell, qty, qty]);
  }

  /// Учесть возврат товара: плюс остаток, минус счётчик популярности,
  /// запись в историю движений.
  Future<void> registerReturn(String productId, double qty,
      {double price = 0, String? note}) async {
    final rows = await database.query('stocks',
        columns: ['cell'],
        where: "product_id = ? AND warehouse_id = 'wh-shop'",
        whereArgs: [productId],
        limit: 1);
    if (rows.isEmpty) {
      await database.insert('stocks', {
        'product_id': productId,
        'warehouse_id': 'wh-shop',
        'series': null,
        'cell': 'Возвраты',
        'qty': qty,
        'reserved': 0,
      });
    } else {
      await database.rawUpdate(
          'UPDATE stocks SET qty = qty + ? WHERE product_id = ? '
          "AND warehouse_id = 'wh-shop' AND IFNULL(cell,'') = IFNULL(?, '')",
          [qty, productId, rows.first['cell']]);
    }
    await database.execute(
        'UPDATE products SET sold_count = MAX(0, sold_count - ?) WHERE id = ?',
        [qty.toInt(), productId]);
    await logMove(
        productId: productId,
        type: 'return',
        qty: qty,
        price: price,
        note: note);
    await touch(productId);
  }

  /// Сколько уже вернули по заказу (по примечанию с номером).
  Future<double> returnedQty(String orderNumber, String productId) async {
    final rows = await database.rawQuery(
        "SELECT SUM(qty) AS q FROM moves WHERE product_id = ? AND type = 'return' "
        'AND IFNULL(note,\'\') LIKE ?',
        [productId, '%$orderNumber%']);
    return (rows.first['q'] as num?)?.toDouble() ?? 0;
  }

  /// Учесть продажу: минус остаток, плюс счётчик популярности,
  /// запись в историю движений.
  Future<void> registerSale(String productId, double qty,
      {double price = 0, String? note}) async {
    await database.execute('''
      UPDATE stocks SET qty = MAX(0, qty - ?)
      WHERE product_id = ? AND warehouse_id = 'wh-shop'
    ''', [qty, productId]);
    await database.execute(
        'UPDATE products SET sold_count = sold_count + ? WHERE id = ?',
        [qty.toInt(), productId]);
    await logMove(
        productId: productId,
        type: 'sale',
        qty: qty,
        price: price,
        note: note);
    await touch(productId);
  }

  Future<double> priceFor(String productId, [String? priceListId]) async {
    final rows = await database.query('price_items',
        where: 'product_id = ? AND price_list_id = ?',
        whereArgs: [productId, priceListId ?? 'pl-base'],
        limit: 1);
    return (rows.first['price'] as num?)?.toDouble() ?? 0;
  }

  // ---- Клиенты ----

  Future<List<Client>> clientsByDay(int weekday) async {
    final rows =
        await database.query('clients', where: 'route_day = ?', whereArgs: [weekday]);
    return rows.map(Client.fromRow).toList();
  }

  Future<List<Client>> allClients() async {
    final rows = await database.query('clients', orderBy: 'name');
    return rows.map(Client.fromRow).toList();
  }

  // ---- Заказы ----

  Future<void> saveOrder(Order o) async {
    final db = database;
    await db.insert('orders', o.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await db.delete('order_lines', where: 'order_id = ?', whereArgs: [o.id]);
    var n = 0;
    final b = db.batch();
    for (final l in o.lines) {
      b.insert('order_lines', l.toRow(o.id, n++));
    }
    await b.commit(noResult: true);
    await db.insert('outbox', {
      'entity': 'order',
      'op': 'insert',
      'payload': jsonEncode(o.toJson()),
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Order>> ordersOfDay(DateTime day, String agentId) async {
    final from = DateTime(day.year, day.month, day.day).toIso8601String();
    final to = DateTime(day.year, day.month, day.day + 1).toIso8601String();
    final rows = await database.rawQuery(
      'SELECT * FROM orders WHERE agent_id = ? AND created_at >= ? AND created_at < ? ORDER BY created_at DESC',
      [agentId, from, to],
    );
    final result = <Order>[];
    for (final r in rows) {
      final lines = await database
          .query('order_lines', where: 'order_id = ?', whereArgs: [r['id']]);
      result.add(Order(
        id: r['id'] as String,
        number: (r['number'] as String?) ?? '',
        clientId: r['client_id'] as String,
        clientName: (r['client_name'] as String?) ?? '',
        type: r['type'] == 'realization' ? OrderType.realization : OrderType.preOrder,
        status: _status(r['status'] as String?),
        warehouseId: (r['warehouse_id'] as String?) ?? '',
        agentId: (r['agent_id'] as String?) ?? '',
        payType: PayType.values.firstWhere(
            (t) => t.name == r['pay_type'],
            orElse: () => PayType.deferred),
        clientDiscountPct: (r['client_discount_pct'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ?? day,
        syncState: r['sync_state'] as String? ?? 'synced',
        lines: lines
            .map((l) => OrderLine(
                  productId: l['product_id'] as String,
                  sku: '',
                  name: '',
                  qty: (l['qty'] as num?)?.toDouble() ?? 0,
                  price: (l['price'] as num?)?.toDouble() ?? 0,
                  discountPct: (l['discount_pct'] as num?)?.toDouble() ?? 0,
                ))
            .toList(),
      ));
    }
    return result;
  }

  OrderStatus _status(String? s) => OrderStatus.values
      .firstWhere((v) => v.name == s, orElse: () => OrderStatus.draft);

  // ---- Отчёты ----

  Future<double> daySales(DateTime day, String agentId) async {
    final orders = await ordersOfDay(day, agentId);
    return orders.fold<double>(0.0, (s, o) => s + o.total);
  }

  Future<double> totalDebt() async {
    final rows = await database.rawQuery('SELECT SUM(debt) AS d FROM clients');
    return (rows.first['d'] as num?)?.toDouble() ?? 0;
  }

  // ---- Визиты ----

  Future<void> saveVisit(Visit v) async {
    await database.insert('visits', {
      'id': v.id,
      'client_id': v.clientId,
      'agent_id': v.agentId,
      'planned_at': v.plannedAt.toIso8601String(),
      'fact_at': v.factAt?.toIso8601String(),
      'gps_lat': v.gpsLat,
      'gps_lng': v.gpsLng,
      'status': v.status,
      'task': v.task,
      'photo_paths': v.photoPaths.join('|'),
      'sync_state': 'pending',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ---- Магазин и данные (настройки) ----

  /// Сводка для экрана настроек: позиции, штуки, заказы, размер файла БД.
  Future<({int products, int pieces, int orders, double dbMb})>
      storeStats() async {
    final pr = await database.rawQuery(
        'SELECT COUNT(*) AS c FROM products WHERE is_active = 1');
    final st = await database.rawQuery(
        "SELECT SUM(qty) AS q FROM stocks WHERE warehouse_id = 'wh-shop'");
    final or = await database
        .rawQuery('SELECT COUNT(*) AS c FROM orders');
    var mb = 0.0;
    try {
      mb = await File(dbPath).length().then((n) => n / 1048576);
    } catch (_) {}
    return (
      products: (pr.first['c'] as int?) ?? 0,
      pieces: ((st.first['q'] as num?)?.toDouble() ?? 0).toInt(),
      orders: (or.first['c'] as int?) ?? 0,
      dbMb: mb,
    );
  }

  /// Обнулить счётчики «Часто берут» (убрать тестовые продажи).
  Future<void> resetPopularity() async {
    await database.execute('UPDATE products SET sold_count = 0');
  }

  /// Удалить все заказы и их строки (подготовка к живой работе).
  Future<void> clearOrders() async {
    final b = database.batch();
    b.delete('order_lines');
    b.delete('orders');
    b.delete('payments');
    b.delete('outbox', where: 'entity = ?', whereArgs: ['order']);
    await b.commit(noResult: true);
  }

  /// Восстановить базу из файла копии: замена с откатом при ошибке.
  Future<void> restoreFrom(File src) async {
    await close();
    _db = null;
    final dst = File(_dbPath!);
    final bak = File('$_dbPath.bak');
    if (await dst.exists()) {
      await dst.copy(bak.path);
    }
    try {
      await src.copy(dst.path);
      await open();
      await database.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'products'");
      if (await bak.exists()) await bak.delete();
    } catch (e) {
      if (await bak.exists()) {
        await bak.copy(dst.path);
        await open();
      }
      rethrow;
    }
  }

  Future<void> close() async => await _db?.close();
}

/// Режим сортировки каталога.
enum SortMode { popular, name, stock, price }
