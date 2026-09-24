import 'package:flutter/material.dart';

/// Переиспользуемые анимационные виджеты (без внешних пакетов).

/// Число, «набегающее» от нуля до значения — для счётчиков дашборда.
class CountUpText extends StatelessWidget {
  final num value;
  final String Function(num v) format;
  final TextStyle? style;
  final Duration duration;

  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 900),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: duration,
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text(format(v), style: style),
    );
  }
}

/// Бесконечно пульсирующая иконка (🔥 у популярных товаров).
class PulsingIcon extends StatefulWidget {
  final IconData icon;
  final Color color;
  final double size;

  const PulsingIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 16,
  });

  @override
  State<PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.85, end: 1.15)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Icon(widget.icon, size: widget.size, color: widget.color),
    );
  }
}

/// Анимированный горизонтальный бар (для ТОП-графика).
class AnimBar extends StatelessWidget {
  final String label;
  final String value;
  final double fraction; // 0..1 относительно максимума
  final Color color;
  final VoidCallback? onTap;

  const AnimBar({
    super.key,
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 3),
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction.clamp(0.04, 1.0)),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              builder: (_, f, __) => Stack(
                children: [
                  Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: f,
                    child: Container(
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Полноэкранный «успех» после продажи: галочка + сумма,
/// конфетти-точки, авто-возврат.
class SuccessScreen extends StatefulWidget {
  final String title;
  final String subtitle;

  const SuccessScreen(
      {super.key, required this.title, required this.subtitle});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final check = CurvedAnimation(parent: _c, curve: Curves.elasticOut);
    final dots = [
      (Colors.orange, const Offset(-70, -90)),
      (Colors.green, const Offset(80, -70)),
      (Colors.blue, const Offset(-90, 60)),
      (Colors.pink, const Offset(95, 75)),
      (Colors.purple, const Offset(0, -110)),
      (Colors.teal, const Offset(-20, 105)),
    ];
    return Scaffold(
      backgroundColor: scheme.primary,
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Конфетти-точки разлетаются от центра.
            for (final (color, off) in dots)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, t, __) => Transform.translate(
                  offset: Offset(off.dx * t, off.dy * t),
                  child: Opacity(
                    opacity: 1 - t,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration:
                          BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                  ),
                ),
              ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: check,
                  child: CircleAvatar(
                    radius: 44,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.check_rounded,
                        size: 52, color: scheme.primary),
                  ),
                ),
                const SizedBox(height: 18),
                FadeTransition(
                  opacity: _c,
                  child: Text(widget.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 6),
                FadeTransition(
                  opacity: _c,
                  child: Text(widget.subtitle,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 16)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
