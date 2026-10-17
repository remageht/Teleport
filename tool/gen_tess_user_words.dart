// Генератор файлов слов для Tesseract из каталога магазина.
//
// Запуск из корня репозитория:
//   dart run tool/gen_tess_user_words.dart
//
// Обновляет assets/tessdata/rus.user-words и eng.user-words.
// Запускать после изменения assets/telemaster_seed.json — файлы
// кладутся в git и попадают в сборку через assets/tessdata_config.json.
import 'dart:io';

import 'package:radiotrade/services/tess_user_words.dart';

void main() {
  final seed = File('assets/telemaster_seed.json').readAsStringSync();
  final words = TessUserWords.generate(seed);
  File('assets/tessdata/rus.user-words')
      .writeAsStringSync('${words.rus.join('\n')}\n');
  File('assets/tessdata/eng.user-words')
      .writeAsStringSync('${words.eng.join('\n')}\n');
  stdout.writeln('rus.user-words: ${words.rus.length} words');
  stdout.writeln('eng.user-words: ${words.eng.length} words');
}
