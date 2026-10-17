import 'dart:convert';

/// Словарь слов для Tesseract (`*.user-words`) из каталога магазина.
///
/// Tesseract при инициализации языка читает файл `rus.user-words`
/// рядом с `rus.traineddata` и подтягивает распознавание в сторону
/// этих слов. Для накладных это сильно снижает число ошибок в
/// брендах и артикулах (GoPower, ZA675, 6LR61, Nicedevice…).
///
/// Функция чистая (вход — строка JSON сида), поэтому тестируется
/// без файловой системы; генерация в файлы — tool/gen_tess_user_words.dart.
class TessUserWords {
  TessUserWords._();

  /// Максимум слов в файле: Tesseract грузит их при init,
  /// тысячи слов — это нормально, десятки тысяч тормозят старт.
  static const int maxWords = 4000;

  /// Дополнительная лексика накладных (кириллица), которой нет
  /// в каталоге радиодеталей.
  static const List<String> extraRus = [
    'батарейка', 'батарейки', 'батареи', 'аккумулятор', 'аккумуляторы',
    'кабель', 'кабели', 'приставка', 'удлинитель', 'тройник', 'патч-корд',
    'шнур', 'крона', 'щелочная', 'солевая', 'цинковая', 'воздушно-цинковая',
    'металлический', 'суперпрочный', 'бельевой', 'зарядное', 'устройство',
    'питания', 'розетка', 'выключатель', 'адаптер', 'переходник', 'антенна',
    'телефон', 'телефонов', 'цифрового', 'радиотелефонов', 'евровилка',
    'серый', 'черный', 'красный', 'белый', 'синий', 'зеленый', 'желтый',
    'в', 'пакете', 'блок', 'шт', 'наименований', 'поставщик', 'покупатель',
  ];

  /// Дополнительная лексика накладных (латиница): бренды и коды.
  static const List<String> extraEng = [
    'GoPower', 'Renata', 'Energizer', 'Duracell', 'Varta', 'Camelion',
    'Kosmos', 'Robiton', 'Selenga', 'Nicedevice', 'Smartbuy', 'MORE',
    'CHOICE', 'REXANT', 'Horizont', 'ULTRA', 'ALKALINE', 'Zinc', 'Air',
    'microUSB', 'USB', 'AUX', 'DVB-T', 'DVB-T2', 'HD980D', 'T624',
    'UK28a', 'GP02M', 'ZA675', 'ZA13', 'LR03', 'LR6', '6LR61', '6F22',
    'SH1', 'BL1', 'BL4', 'BL6', 'BC', 'AWG', 'CCA', 'PVC',
  ];

  /// Собирает списки слов для файлов `rus.user-words` / `eng.user-words`.
  ///
  /// [seedJson] — содержимое assets/telemaster_seed.json.
  static ({List<String> rus, List<String> eng}) generate(String seedJson) {
    final rus = <String>{};
    final eng = <String>{};

    final data = jsonDecode(seedJson);
    if (data is Map<String, dynamic>) {
      final products = data['products'];
      if (products is List) {
        for (final p in products) {
          if (p is Map && p['name'] is String) {
            _addName(p['name'] as String, rus, eng);
          }
        }
      }
    }

    for (final w in extraRus) {
      _addToken(w, rus, eng);
    }
    for (final w in extraEng) {
      _addToken(w, rus, eng);
    }

    final rusList = rus.toList()..sort();
    final engList = eng.toList()..sort();
    return (
      rus: rusList.take(maxWords).toList(),
      eng: engList.take(maxWords).toList(),
    );
  }

  /// Токен: начинается с буквы или цифры, далее буквы/цифры/дефис.
  /// Такие коды, как 6LR61 или ZA675, тоже подходят.
  static final _tokenRe =
      RegExp(r'[A-Za-zА-Яа-яЁё0-9][A-Za-zА-Яа-яЁё0-9\-]{1,30}');

  static void _addName(String name, Set<String> rus, Set<String> eng) {
    for (final m in _tokenRe.allMatches(name)) {
      _addToken(m.group(0)!, rus, eng);
    }
  }

  static void _addToken(String raw, Set<String> rus, Set<String> eng) {
    final t = raw.trim();
    if (t.length < 3) return;
    if (RegExp(r'^\d+$').hasMatch(t)) return; // один цифры — штрихкод/цена
    final hasCyr = RegExp(r'[А-Яа-яЁё]').hasMatch(t);
    final hasLat = RegExp(r'[A-Za-z]').hasMatch(t);
    if (!hasCyr && !hasLat) return;
    if (hasCyr) rus.add(t.toLowerCase());
    if (hasLat) eng.add(t);
  }
}
