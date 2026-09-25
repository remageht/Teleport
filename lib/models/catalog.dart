// Доменные модели приложения. Маппятся в/из строк SQLite.
library;

class Product {
  final String id; // GUID из 1С / локальный id
  final String sku; // артикул
  final String name;
  final String? description; // описание / примечание
  final String? nominal; // 10кОм, 100нФ, 5V1...
  final String? caseType; // 0805, SOT-23, TO-220, DIP-8...
  final String? manufacturer;
  final String? categoryId;
  final String? barcode;
  final String unit; // шт, лента, упак
  final int soldCount; // сколько раз покупали (популярность)
  final double minQty; // порог остатка: ниже — «заканчивается»
  final String? photoPath; // реальное фото товара (снятое камерой)
  final bool isActive;
  final String syncState; // pending | synced | conflict

  // Транзитные поля — заполняются JOIN-запросом, не хранятся в таблице.
  final double price; // цена из прайс-листа (0 = по запросу)
  final double available; // доступный остаток по всем складам
  final String? cell; // первая ячейка с остатком (для карточки)

  const Product({
    required this.id,
    required this.sku,
    required this.name,
    this.description,
    this.nominal,
    this.caseType,
    this.manufacturer,
    this.categoryId,
    this.barcode,
    this.unit = 'шт',
    this.soldCount = 0,
    this.minQty = 0,
    this.photoPath,
    this.isActive = true,
    this.syncState = 'synced',
    this.price = 0,
    this.available = 0,
    this.cell,
  });

  Map<String, Object?> toRow() => {
        'id': id,
        'sku': sku,
        'name': name,
        'description': description,
        'nominal': nominal,
        'case_type': caseType,
        'manufacturer': manufacturer,
        'category_id': categoryId,
        'barcode': barcode,
        'unit': unit,
        'sold_count': soldCount,
        'min_qty': minQty,
        'photo_path': photoPath,
        'is_active': isActive ? 1 : 0,
        'sync_state': syncState,
      };

  static Product fromRow(Map<String, Object?> r) => Product(
        id: r['id'] as String,
        sku: (r['sku'] as String?) ?? '',
        name: (r['name'] as String?) ?? '',
        description: r['description'] as String?,
        nominal: r['nominal'] as String?,
        caseType: r['case_type'] as String?,
        manufacturer: r['manufacturer'] as String?,
        categoryId: r['category_id'] as String?,
        barcode: r['barcode'] as String?,
        unit: (r['unit'] as String?) ?? 'шт',
        soldCount: (r['sold_count'] as int?) ?? 0,
        minQty: (r['min_qty'] as num?)?.toDouble() ?? 0,
        photoPath: r['photo_path'] as String?,
        isActive: (r['is_active'] as int? ?? 1) == 1,
        syncState: (r['sync_state'] as String?) ?? 'synced',
        price: (r['price'] as num?)?.toDouble() ?? 0,
        available: (r['available'] as num?)?.toDouble() ?? 0,
        cell: r.containsKey('cell') ? r['cell'] as String? : null,
      );
}

/// Остаток по складу/серии/ячейке.
class Stock {
  final String productId;
  final String warehouseId;
  final String? series; // серия/партия
  final String? cell; // ячейка склада (Коробка 3 · 2-5)
  final double qty;
  final double reserved;

  const Stock({
    required this.productId,
    required this.warehouseId,
    this.series,
    this.cell,
    this.qty = 0,
    this.reserved = 0,
  });

  double get available => qty - reserved;

  Map<String, Object?> toRow() => {
        'product_id': productId,
        'warehouse_id': warehouseId,
        'series': series,
        'cell': cell,
        'qty': qty,
        'reserved': reserved,
      };

  static Stock fromRow(Map<String, Object?> r) => Stock(
        productId: r['product_id'] as String,
        warehouseId: r['warehouse_id'] as String,
        series: r['series'] as String?,
        cell: r['cell'] as String?,
        qty: (r['qty'] as num?)?.toDouble() ?? 0,
        reserved: (r['reserved'] as num?)?.toDouble() ?? 0,
      );
}

class Client {
  final String id;
  final String name;
  final String? inn;
  final String? address;
  final String? contact;
  final String? phone;
  final String? priceListId;
  final double discountPct; // индивидуальная скидка
  final double debt;
  final double creditLimit;
  final int routeDay; // 1=Пн ... 7=Вс, 0 = без маршрута
  final String syncState;

  const Client({
    required this.id,
    required this.name,
    this.inn,
    this.address,
    this.contact,
    this.phone,
    this.priceListId,
    this.discountPct = 0,
    this.debt = 0,
    this.creditLimit = 0,
    this.routeDay = 0,
    this.syncState = 'synced',
  });

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'inn': inn,
        'address': address,
        'contact': contact,
        'phone': phone,
        'price_list_id': priceListId,
        'discount_pct': discountPct,
        'debt': debt,
        'credit_limit': creditLimit,
        'route_day': routeDay,
        'sync_state': syncState,
      };

  static Client fromRow(Map<String, Object?> r) => Client(
        id: r['id'] as String,
        name: r['name'] as String,
        inn: r['inn'] as String?,
        address: r['address'] as String?,
        contact: r['contact'] as String?,
        phone: r['phone'] as String?,
        priceListId: r['price_list_id'] as String?,
        discountPct: (r['discount_pct'] as num?)?.toDouble() ?? 0,
        debt: (r['debt'] as num?)?.toDouble() ?? 0,
        creditLimit: (r['credit_limit'] as num?)?.toDouble() ?? 0,
        routeDay: (r['route_day'] as int?) ?? 0,
        syncState: (r['sync_state'] as String?) ?? 'synced',
      );
}
