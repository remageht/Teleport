import 'package:flutter/material.dart';

/// Роли пользователей.
enum Role { agent, supervisor, admin }

/// Режим работы торгового представителя.
enum WorkMode { preSelling, vanSelling }

/// Текущая сессия: кто вошёл, в каком режиме, какой склад/организация.
class Session extends ChangeNotifier {
  String? userId;
  String? userName;
  Role role = Role.agent;
  WorkMode mode = WorkMode.preSelling;

  String? warehouseId; // «мобильный склад» для van-selling
  String? organizationId;
  String? authToken; // токен от 1С-шлюза

  bool get isLoggedIn => userId != null;
  String? get user => userId;

  void login({
    required String userId,
    required String userName,
    required Role role,
    required WorkMode mode,
    String? warehouseId,
    String? organizationId,
    String? authToken,
  }) {
    this.userId = userId;
    this.userName = userName;
    this.role = role;
    this.mode = mode;
    this.warehouseId = warehouseId;
    this.organizationId = organizationId;
    this.authToken = authToken;
    notifyListeners();
  }

  void switchMode(WorkMode m) {
    mode = m;
    notifyListeners();
  }

  void logout() {
    userId = null;
    userName = null;
    notifyListeners();
  }
}
