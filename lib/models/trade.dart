enum OrderType { preOrder, realization } // заказ (pre-selling) / реализация (van-selling)

enum OrderStatus { draft, sent, confirmed, rejected }

enum PayType { cash, card, transfer, deferred }

class OrderLine {
  final String productId;
  final String sku;
  final String name;
  final double qty;
  final double price;
  final double discountPct;

  const OrderLine({
    required this.productId,
    required this.sku,
    required this.name,
    required this.qty,
    required this.price,
    this.discountPct = 0,
  });

  double get total => qty * price * (1 - discountPct / 100);

  Map<String, Object?> toRow(String orderId, int lineNo) => {
        'order_id': orderId,
        'line_no': lineNo,
        'product_id': productId,
        'qty': qty,
        'price': price,
        'discount_pct': discountPct,
        'total': total,
      };
}

class Order {
  final String id;
  final String number;
  final String clientId;
  final String clientName;
  final OrderType type;
  OrderStatus status;
  final String warehouseId;
  final String agentId;
  PayType payType;
  final double clientDiscountPct;
  final DateTime createdAt;
  final String? visitId;
  final List<OrderLine> lines;
  final String syncState;

  Order({
    required this.id,
    required this.number,
    required this.clientId,
    required this.clientName,
    required this.type,
    this.status = OrderStatus.draft,
    required this.warehouseId,
    required this.agentId,
    this.payType = PayType.deferred,
    this.clientDiscountPct = 0,
    DateTime? createdAt,
    this.visitId,
    List<OrderLine>? lines,
    this.syncState = 'pending',
  })  : createdAt = createdAt ?? DateTime.now(),
        lines = lines ?? [];

  double get total => lines.fold(0, (s, l) => s + l.total);

  Map<String, Object?> toRow() => {
        'id': id,
        'number': number,
        'client_id': clientId,
        'client_name': clientName,
        'type': type.name,
        'status': status.name,
        'warehouse_id': warehouseId,
        'agent_id': agentId,
        'pay_type': payType.name,
        'client_discount_pct': clientDiscountPct,
        'total': total,
        'created_at': createdAt.toIso8601String(),
        'visit_id': visitId,
        'sync_state': syncState,
      };

  /// JSON для outbox / отправки в 1С.
  Map<String, Object?> toJson() => {
        'id': id,
        'number': number,
        'client_id': clientId,
        'type': type.name,
        'warehouse_id': warehouseId,
        'agent_id': agentId,
        'pay_type': payType.name,
        'total': total,
        'created_at': createdAt.toIso8601String(),
        'lines': lines
            .map((l) => {
                  'product_id': l.productId,
                  'qty': l.qty,
                  'price': l.price,
                  'discount_pct': l.discountPct,
                })
            .toList(),
      };
}

class Payment {
  final String id;
  final String orderId;
  final PayType type;
  final double amount;
  final String? docNo;
  final DateTime createdAt;
  final String syncState;

  const Payment({
    required this.id,
    required this.orderId,
    required this.type,
    required this.amount,
    this.docNo,
    required this.createdAt,
    this.syncState = 'pending',
  });

  Map<String, Object?> toJson() => {
        'id': id,
        'order_id': orderId,
        'type': type.name,
        'amount': amount,
        'doc_no': docNo,
        'created_at': createdAt.toIso8601String(),
      };
}

class Visit {
  final String id;
  final String clientId;
  final String agentId;
  final DateTime plannedAt;
  DateTime? factAt;
  final double? gpsLat;
  final double? gpsLng;
  String status; // planned | done | skipped
  final String? task;
  final List<String> photoPaths;
  final String syncState;

  Visit({
    required this.id,
    required this.clientId,
    required this.agentId,
    required this.plannedAt,
    this.factAt,
    this.gpsLat,
    this.gpsLng,
    this.status = 'planned',
    this.task,
    List<String>? photoPaths,
    this.syncState = 'pending',
  }) : photoPaths = photoPhotos(photoPaths);

  static List<String> photoPhotos(List<String>? p) => p ?? [];

  Map<String, Object?> toJson() => {
        'id': id,
        'client_id': clientId,
        'agent_id': agentId,
        'planned_at': plannedAt.toIso8601String(),
        'fact_at': factAt?.toIso8601String(),
        'gps_lat': gpsLat,
        'gps_lng': gpsLng,
        'status': status,
        'task': task,
        'photos': photoPaths,
      };
}
