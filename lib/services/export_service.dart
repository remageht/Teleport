import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db/app_db.dart';

/// Экспорт продаж в Excel (.xlsx): лист «Продажи» (построчно) и
/// лист «Накладная» (сводка по дням с итогами).
/// На телефоне после сохранения открывается меню «Поделиться»,
/// на ПК файл кладётся в Документы.
class ExportService {
  Future<String> exportSales(AppDb db, {required bool allTime}) async {
    final todayStart = DateTime(
            DateTime.now().year, DateTime.now().month, DateTime.now().day)
        .toIso8601String();
    final rows = await db.database.rawQuery('''
            SELECT o.id, o.number, o.client_name, o.pay_type, o.created_at,
                   l.line_no, l.qty, l.price, l.discount_pct,
                   p.name AS product
            FROM orders o
            JOIN order_lines l ON l.order_id = o.id
            LEFT JOIN products p ON p.id = l.product_id
            ${allTime ? '' : 'WHERE o.created_at >= ?'}
            ORDER BY o.created_at DESC
          ''', allTime ? null : [todayStart]);

    final orders = await db.database.query('orders',
        where: allTime ? null : 'created_at >= ?',
        orderBy: 'created_at DESC',
        whereArgs: allTime ? null : [todayStart]);

    final excel = Excel.createExcel();
    final sales = excel['Продажи'];
    sales.appendRow([
      TextCellValue('Дата'),
      TextCellValue('№'),
      TextCellValue('Покупатель'),
      TextCellValue('Товар'),
      TextCellValue('Кол-во'),
      TextCellValue('Цена'),
      TextCellValue('Скидка %'),
      TextCellValue('Сумма строки'),
      TextCellValue('Оплата'),
    ]);
    for (final r in rows) {
      final dt = DateTime.tryParse(r['created_at'] as String? ?? '');
      sales.appendRow([
        TextCellValue(dt != null
            ? '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}'
            : ''),
        TextCellValue('${r['number'] ?? ''}'),
        TextCellValue('${r['client_name'] ?? ''}'),
        TextCellValue('${r['product'] ?? ''}'),
        DoubleCellValue((r['qty'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((r['price'] as num?)?.toDouble() ?? 0),
        DoubleCellValue((r['discount_pct'] as num?)?.toDouble() ?? 0),
        DoubleCellValue(((r['qty'] as num?)?.toDouble() ?? 0) *
            ((r['price'] as num?)?.toDouble() ?? 0) *
            (1 - ((r['discount_pct'] as num?)?.toDouble() ?? 0) / 100)),
        TextCellValue(_payName('${r['pay_type'] ?? ''}')),
      ]);
    }

    // Накладная: суммы по дням.
    final invoice = excel['Накладная'];
    invoice.appendRow([
      TextCellValue('Дата'),
      TextCellValue('Заказов'),
      TextCellValue('Позиций'),
      TextCellValue('Итого, ₽'),
    ]);
    final byDay = <String, List<double>>{};
    for (final o in orders) {
      final dt = DateTime.tryParse(o['created_at'] as String? ?? '');
      if (dt == null) continue;
      final key =
          '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
      final cnt = await db.database.rawQuery(
          'SELECT COUNT(*) AS c FROM order_lines WHERE order_id = ?',
          [o['id']]);
      final day = byDay.putIfAbsent(key, () => [0, 0, 0]);
      day[0] += 1;
      day[1] += ((cnt.first['c'] as int?) ?? 0).toDouble();
      day[2] += (o['total'] as num?)?.toDouble() ?? 0;
    }
    var grand = 0.0;
    byDay.forEach((day, v) {
      invoice.appendRow([
        TextCellValue(day),
        DoubleCellValue(v[0]),
        DoubleCellValue(v[1]),
        DoubleCellValue(v[2]),
      ]);
      grand += v[2];
    });
    invoice.appendRow([
      TextCellValue('ИТОГО'),
      TextCellValue(''),
      TextCellValue(''),
      DoubleCellValue(grand),
    ]);

    try {
      excel.delete('Sheet1');
    } catch (_) {}
    final bytes = excel.encode();
    if (bytes == null) return 'Не удалось сформировать файл';

    final dir = await getApplicationDocumentsDirectory();
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    final file =
        File(p.join(dir.path, 'prodazhi_$stamp${allTime ? '_vse' : ''}.xlsx'));
    await file.writeAsBytes(bytes);

    // Телефон: сразу предложить отправить (WhatsApp/Telegram/почта).
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await Share.shareXFiles([XFile(file.path)],
          text: 'Продажи ТЕЛЕМАСТЕР');
    }
    return 'Файл: ${file.path}';
  }

  String _payName(String v) => switch (v) {
        'cash' => 'наличные',
        'card' => 'карта',
        'transfer' => 'перевод',
        'deferred' => 'долг',
        _ => v,
      };

  /// Выгрузка выбранных товаров: артикул, название, каталог, остаток, цена.
  Future<String> exportProducts(AppDb db, List<String> ids) async {
    if (ids.isEmpty) return 'Нечего выгружать: ничего не выбрано';
    final ph = List.filled(ids.length, '?').join(',');
    final rows = await db.database.rawQuery('''
      SELECT p.sku, p.name, p.description, p.barcode, p.unit,
             IFNULL(c.name, 'Без каталога') AS cat,
             IFNULL(pi.price, 0) AS price,
             IFNULL(s.qty, 0) AS qty
      FROM products p
      LEFT JOIN categories c ON c.id = p.category_id
      LEFT JOIN price_items pi
        ON pi.product_id = p.id AND pi.price_list_id = 'pl-base'
      LEFT JOIN (
        SELECT product_id, SUM(qty) AS qty FROM stocks
        WHERE warehouse_id = 'wh-shop' GROUP BY product_id
      ) s ON s.product_id = p.id
      WHERE p.id IN ($ph) ORDER BY p.name
    ''', ids);

    final excel = Excel.createExcel();
    final sheet = excel['Товары'];
    sheet.appendRow([
      TextCellValue('Артикул'),
      TextCellValue('Название'),
      TextCellValue('Описание'),
      TextCellValue('Каталог'),
      TextCellValue('Штрихкод'),
      TextCellValue('Ед.'),
      TextCellValue('Остаток'),
      TextCellValue('Цена, ₽'),
      TextCellValue('Сумма остатка, ₽'),
    ]);
    for (final r in rows) {
      final qty = (r['qty'] as num?)?.toDouble() ?? 0;
      final price = (r['price'] as num?)?.toDouble() ?? 0;
      sheet.appendRow([
        TextCellValue('${r['sku'] ?? ''}'),
        TextCellValue('${r['name'] ?? ''}'),
        TextCellValue('${r['description'] ?? ''}'),
        TextCellValue('${r['cat'] ?? ''}'),
        TextCellValue('${r['barcode'] ?? ''}'),
        TextCellValue('${r['unit'] ?? ''}'),
        DoubleCellValue(qty),
        DoubleCellValue(price),
        DoubleCellValue(qty * price),
      ]);
    }
    try {
      excel.delete('Sheet1');
    } catch (_) {}
    final bytes = excel.encode();
    if (bytes == null) return 'Не удалось сформировать файл';

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    return _saveAndShare(
        bytes, 'tovary_${rows.length}_$stamp.xlsx', 'Товары ТЕЛЕМАСТЕР');
  }

  /// Прайс для покупателей: листы по каталогам (только в наличии),
  /// цена с учётом выбранного прайса и скидок каталогов.
  Future<String> exportBuyerPrice(AppDb db, {String? priceListId}) async {
    final listId = priceListId ?? 'pl-base';
    final cats = await db.database
        .query('categories', orderBy: 'position');
    final excel = Excel.createExcel();
    final usedNames = <String>{};
    var total = 0;

    Future<void> fillSheet(String title, String? catId) async {
      final rows = await db.database.rawQuery('''
        SELECT p.sku, p.name,
               ROUND(IFNULL(pi.price, 0)
                 * (1 - IFNULL(pl.discount_pct, 0) / 100.0)
                 * (1 - IFNULL(c.discount_pct, 0) / 100.0), 2) AS price,
               IFNULL(s.qty, 0) AS qty
        FROM products p
        LEFT JOIN categories c ON c.id = p.category_id
        LEFT JOIN price_lists pl ON pl.id = ?
        LEFT JOIN price_items pi
          ON pi.product_id = p.id AND pi.price_list_id = 'pl-base'
        LEFT JOIN (
          SELECT product_id, SUM(qty - reserved) AS qty FROM stocks
          GROUP BY product_id
        ) s ON s.product_id = p.id
        WHERE p.is_active = 1
          AND IFNULL(pi.price, 0) > 0
          AND IFNULL(s.qty, 0) > 0
          ${catId == null ? 'AND p.category_id IS NULL' : 'AND p.category_id = ?'}
        ORDER BY p.name
      ''', catId == null ? [listId] : [listId, catId]);
      if (rows.isEmpty) return;
      var name = title
          .replaceAll(RegExp(r'[/\\?*\[\]:]'), ' ')
          .trim();
      if (name.length > 28) name = name.substring(0, 28);
      if (name.isEmpty) name = 'Каталог';
      var n = name;
      var i = 2;
      while (usedNames.contains(n)) {
        n = '$name $i';
        i++;
      }
      usedNames.add(n);
      final sheet = excel[n];
      sheet.appendRow([
        TextCellValue('Артикул'),
        TextCellValue('Название'),
        TextCellValue('Цена, ₽'),
        TextCellValue('В наличии, шт'),
      ]);
      for (final r in rows) {
        sheet.appendRow([
          TextCellValue('${r['sku'] ?? ''}'),
          TextCellValue('${r['name'] ?? ''}'),
          DoubleCellValue(
              (r['price'] as num?)?.toDouble() ?? 0),
          DoubleCellValue(
              (r['qty'] as num?)?.toDouble() ?? 0),
        ]);
        total++;
      }
    }

    for (final c in cats) {
      await fillSheet(
          '${c['name'] ?? 'Каталог'}', c['id'] as String?);
    }
    await fillSheet('Без каталога', null);
    if (total == 0) return 'Нечего выгружать: нет товаров в наличии с ценами';
    try {
      excel.delete('Sheet1');
    } catch (_) {}
    final bytes = excel.encode();
    if (bytes == null) return 'Не удалось сформировать файл';

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return _saveAndShare(
        bytes, 'prays_$stamp.xlsx', 'Прайс ТЕЛЕМАСТЕР');
  }

  /// Сохранить байты в Документы, на телефоне — открыть «Поделиться».
  Future<String> _saveAndShare(
      List<int> bytes, String fileName, String shareText) async {    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes);
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await Share.shareXFiles([XFile(file.path)], text: shareText);
    }
    return 'Файл: ${file.path}';
  }
}
