import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тема и масштаб интерфейса с сохранением между запусками.
class ThemeProvider extends ChangeNotifier {
  ThemeMode mode = ThemeMode.dark;

  /// Масштаб: 0 — мелко, 1 — обычно, 2 — крупно.
  int scale = 1;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString('theme_mode') ?? 'dark';
    mode = switch (v) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    scale = prefs.getInt('ui_scale') ?? 1;
    notifyListeners();
  }

  Future<void> set(ThemeMode m) async {
    mode = m;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', m.name);
  }

  Future<void> setScale(int s) async {
    scale = s.clamp(0, 2);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('ui_scale', scale);
  }

  /// Максимальная ширина карточки в сетке склада.
  /// Меньше значение — плотнее сетка (больше колонок).
  double get gridExtent => switch (scale) {
        0 => 155,
        2 => 265,
        _ => 210,
      };

  /// Пропорции карточки (ширина/высота) — крупнее масштаб ниже карточка.
  double get cardAspect => switch (scale) {
        0 => 0.75,
        2 => 0.62,
        _ => 0.68,
      };

  /// Глобальный масштаб текста.
  double get textScale => switch (scale) {
        0 => 0.9,
        2 => 1.12,
        _ => 1.0,
      };
}
