import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Фон всех экранов: светлый — тёплая бумага с едва заметным красным
/// свечением сверху (как шапка сайта); тёмный — глубокий navy с тихими
/// aurora-свечениями (малиновое сверху, индиго снизу). Всё статично,
/// без блюра и анимаций — дёшево для GPU.
class AppBackground extends StatelessWidget {
  final Widget child;

  const AppBackground({super.key, required this.child});

  static const _lightBase = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF8EDD8),
      Color(0xFFF1E2C4),
      Color(0xFFE4CFA6),
    ],
    stops: [0.0, 0.45, 1.0],
  );

  static const _darkBase = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF0B1120),
      Color(0xFF0A0F1C),
      Color(0xFF0A0F1C),
    ],
    stops: [0.0, 0.4, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration:
          BoxDecoration(gradient: isDark ? _darkBase : _lightBase),
      child: Stack(
        children: [
          if (!isDark) ...[
            const Positioned(
              top: -140,
              left: 0,
              right: 0,
              child: _Glow(
                size: 380,
                color: AppTheme.brand,
                opacity: 0.09,
              ),
            ),
            const Positioned(
              bottom: -160,
              left: -80,
              right: -80,
              child: _Glow(
                size: 420,
                color: Color(0xFFD9A441),
                opacity: 0.06,
              ),
            ),
          ] else ...[
            const Positioned(
              top: -150,
              left: -90,
              child: _Glow(
                size: 400,
                color: Color(0xFFC8102E),
                opacity: 0.20,
              ),
            ),
            const Positioned(
              bottom: -170,
              right: -100,
              child: _Glow(
                size: 440,
                color: Color(0xFF3B4ED8),
                opacity: 0.18,
              ),
            ),
          ],
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// Мягкое радиальное пятно, растворяющееся в прозрачность.
class _Glow extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _Glow({
    required this.size,
    required this.color,
    required this.opacity,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: 0),
            ],
            stops: const [0.0, 0.7],
          ),
        ),
      ),
    );
  }
}
