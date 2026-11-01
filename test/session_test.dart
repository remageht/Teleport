import 'package:flutter_test/flutter_test.dart';
import 'package:radiotrade/core/session.dart';

void main() {
  group('Session', () {
    test('login sets all fields and notifies listeners', () {
      final session = Session();
      var notifications = 0;
      session.addListener(() => notifications++);

      session.login(
        userId: 'u1',
        userName: 'Иван',
        role: Role.admin,
        mode: WorkMode.vanSelling,
        warehouseId: 'wh-1',
        organizationId: 'org-1',
        authToken: 'secret_token_123',
      );

      expect(session.isLoggedIn, isTrue);
      expect(session.userId, equals('u1'));
      expect(session.userName, equals('Иван'));
      expect(session.role, equals(Role.admin));
      expect(session.mode, equals(WorkMode.vanSelling));
      expect(session.warehouseId, equals('wh-1'));
      expect(session.organizationId, equals('org-1'));
      expect(session.authToken, equals('secret_token_123'));
      expect(notifications, equals(1));
    });

    test('logout resets all credentials, role, mode and tokens', () {
      final session = Session();
      session.login(
        userId: 'u1',
        userName: 'Иван',
        role: Role.admin,
        mode: WorkMode.vanSelling,
        warehouseId: 'wh-1',
        organizationId: 'org-1',
        authToken: 'secret_token_123',
      );

      session.logout();

      expect(session.isLoggedIn, isFalse);
      expect(session.userId, isNull);
      expect(session.userName, isNull);
      expect(session.role, equals(Role.agent));
      expect(session.mode, equals(WorkMode.preSelling));
      expect(session.warehouseId, isNull);
      expect(session.organizationId, isNull);
      expect(session.authToken, isNull);
    });
  });
}
