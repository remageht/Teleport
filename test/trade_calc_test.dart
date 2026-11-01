import 'package:flutter_test/flutter_test.dart';
import 'package:radiotrade/core/currency_provider.dart';
import 'package:radiotrade/models/trade.dart';

void main() {
  group('Trade calculations & Currency formatting', () {
    test('Order.total applies client discount percentage', () {
      final order = Order(
        id: 'ord-1',
        number: '№1',
        clientId: 'c1',
        clientName: 'Клиент',
        type: OrderType.preOrder,
        warehouseId: 'wh-1',
        agentId: 'a1',
        clientDiscountPct: 10.0,
        lines: [
          const OrderLine(
            productId: 'p1',
            sku: 'SKU1',
            name: 'Товар 1',
            qty: 2,
            price: 100,
          ), // 200
          const OrderLine(
            productId: 'p2',
            sku: 'SKU2',
            name: 'Товар 2',
            qty: 1,
            price: 300,
          ), // 300 -> lines total 500
        ],
      );

      // 500 * (1 - 10/100) = 450
      expect(order.total, equals(450.0));
      expect(order.toJson()['total'], equals(450.0));
      expect(order.toJson()['client_name'], equals('Клиент'));
      expect(order.toJson()['client_discount_pct'], equals(10.0));
    });

    test('CurrencyProvider formats negative numbers without space after minus', () {
      final currency = CurrencyProvider();
      final negativeRub = currency.formatRub(-1234.50);
      expect(negativeRub, equals('-1 234.50 ₽'));
      expect(negativeRub.startsWith('- '), isFalse);
    });

    test('CurrencyProvider handles NaN and Infinity safely', () {
      final currency = CurrencyProvider();
      expect(currency.convert(double.nan), equals(0.0));
      expect(currency.convert(double.infinity), equals(0.0));
      expect(currency.formatRub(double.nan), equals('0 ₽'));
    });
  });
}
