import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../models/catalog.dart';

/// Категория товара: иконка, цвет.
class ProductCategory {
  final IconData icon;
  final Color color;
  const ProductCategory(this.icon, this.color);
}

const _cBlue = Color(0xFF42A5F5);
const _cAmber = Color(0xFFFFB300);
const _cGreen = Color(0xFF66BB6A);
const _cPurple = Color(0xFFAB47BC);
const _cTeal = Color(0xFF26A69A);
const _cRed = Color(0xFFEF5350);
const _cBrown = Color(0xFF8D6E63);
const _cIndigo = Color(0xFF5C6BC0);

/// Иконка/цвет по назначенному каталогу (id из БД).
const _catStyles = <String, (IconData, Color)>{
  'cat-mcu': (Icons.developer_board, _cTeal),
  'cat-chip': (Icons.grid_view, _cIndigo),
  'cat-rc': (Icons.linear_scale, _cAmber),
  'cat-sensor': (Icons.sensors, _cGreen),
  'cat-conn': (Icons.cable, _cIndigo),
  'cat-tool': (Icons.handyman, _cBrown),
  'cat-power': (Icons.battery_full, _cGreen),
  'cat-auto': (Icons.toggle_on, _cRed),
  'cat-light': (Icons.lightbulb, _cAmber),
  'cat-cable': (Icons.electrical_services, _cBrown),
  'cat-other': (Icons.category, Color(0xFF78909C)),
};

/// Категория по назначенному каталогу, иначе — по ключевым словам.
ProductCategory categoryOf(Product p) {
  final byId = _catStyles[p.categoryId];
  if (byId != null) {
    return ProductCategory(byId.$1, byId.$2);
  }
  final s =
      '${p.name} ${p.description ?? ''} ${p.nominal ?? ''} ${p.caseType ?? ''}'
          .toLowerCase();
  bool has(List<String> keys) => keys.any(s.contains);

  if (has(['резистор', 'resistor', 'сопротивлен'])) {
    return const ProductCategory(Icons.linear_scale, _cAmber);
  }
  if (has(['конденсатор', 'capacitor', 'мкф', 'нф'])) {
    return const ProductCategory(Icons.battery_charging_full, _cGreen);
  }
  if (has(['транзистор', 'транз', 'mosfet', 'bc547'])) {
    return const ProductCategory(Icons.settings_input_component, _cPurple);
  }
  if (has(['светодиод', 'led', 'лампа', 'светильник', 'фонар'])) {
    return const ProductCategory(Icons.lightbulb, _cAmber);
  }
  if (has(['паяльник', 'паяльная', 'флюс', 'припой', 'solder', 'термопаст'])) {
    return const ProductCategory(Icons.construction, _cRed);
  }
  if (has(['предохранитель', 'fuse'])) {
    return const ProductCategory(Icons.bolt, _cAmber);
  }
  if (has(['автомат', 'выключател', 'рубильник', 'авдт', 'тумблер', 'кнопк', 'переключател', 'триггер', 'switch'])) {
    return const ProductCategory(Icons.toggle_on, _cRed);
  }
  if (has(['разъем', 'разъём', 'коннектор', 'клемм', 'наконечник', 'xt60', 'xt90', 'mc4', 'переходник', 'адаптер', 'usb', 'зарядн', 'розетк', 'вилк'])) {
    return const ProductCategory(Icons.cable, _cIndigo);
  }
  if (has(['батарейк', 'аккумулятор', 'battery', '18650', 'nanfu'])) {
    return const ProductCategory(Icons.battery_full, _cGreen);
  }
  if (has(['реле', 'relay', 'контроллер', 'датчик', 'sensor', 'ntc', 'bms', 'плат', 'модул', 'преобразовател', 'dc-dc', 'заряд', 'block'])) {
    return const ProductCategory(Icons.memory, _cTeal);
  }
  if (has(['клещ', 'стриппер', 'кримпер', 'отвертк', 'инструмент', 'пресс'])) {
    return const ProductCategory(Icons.handyman, _cBrown);
  }
  if (has(['мультиметр', 'измерител', 'частотомер', 'счетчик', 'тестер'])) {
    return const ProductCategory(Icons.speed, _cBlue);
  }
  if (has(['провод', 'кабель', 'шнур', 'шнур', 'wire'])) {
    return const ProductCategory(Icons.electrical_services, _cBrown);
  }
  if (has(['дин-рейку', 'din', 'щит', 'укк', 'бокс', 'распределительн'])) {
    return const ProductCategory(Icons.dashboard, _cIndigo);
  }
  if (has(['дроссел', 'катушк', 'индуктивн', 'трансформатор'])) {
    return const ProductCategory(Icons.all_inclusive, _cPurple);
  }
  if (has(['микросхем', 'таймер', 'усилител', 'мк ', 'stm', 'ne555', 'tda', 'lm3', 'lm2', 'ka', 'in8', 'драйвер'])) {
    return const ProductCategory(Icons.developer_board, _cTeal);
  }
  return const ProductCategory(Icons.category, Color(0xFF78909C));
}

/// Сохранить снятое фото товара в папку приложения. Возвращает путь.
Future<String?> takeProductPhoto(String productId) async {
  final picker = ImagePicker();
  final x = await picker.pickImage(
      source: ImageSource.camera, maxWidth: 1024, imageQuality: 82);
  if (x == null) return null;
  final dir =
      await getApplicationSupportDirectory();
  final photos = Directory(p.join(dir.path, 'photos'));
  if (!photos.existsSync()) photos.createSync(recursive: true);
  final dest = p.join(photos.path, '$productId.jpg');
  await File(x.path).copy(dest);
  return dest;
}

/// Картинка товара: реальное фото (снятое камерой) либо объёмная
/// иконка категории с бликом. Некорректные случайные фото из сети
/// убраны — иконка всегда соответствует типу товара.
class ProductImage extends StatelessWidget {
  final Product product;
  final double size;
  final double radius;

  const ProductImage({
    super.key,
    required this.product,
    this.size = 56,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final cat = categoryOf(product);
    final photo = product.photoPath;
    final hasPhoto = photo != null && File(photo).existsSync();

    return Hero(
      tag: 'img-${product.id}',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Container(
          width: size,
          height: size,
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: hasPhoto
              ? Image.file(
                  File(photo),
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _painted(cat),
                )
              : _painted(cat),
        ),
      ),
    );
  }

  /// Объёмная иконка: градиент, блик сверху-слева, тень.
  Widget _painted(ProductCategory cat) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cat.color,
            Color.lerp(cat.color, Colors.black, 0.35)!,
          ],
        ),
      ),
      child: Stack(
        children: [
          // Блик — «стеклянный» объём.
          Positioned(
            top: -size * 0.4,
            left: -size * 0.25,
            child: Container(
              width: size * 0.9,
              height: size * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.18),
              ),
            ),
          ),
          Center(
            child: Icon(cat.icon, color: Colors.white, size: size * 0.48),
          ),
        ],
      ),
    );
  }
}
