import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path_provider/path_provider.dart';

import 'invoice_photo_ocr.dart';
import 'ocr_image_ops.dart';

/// Результат Tesseract-OCR накладной.
///
/// [lines]   — распознанные позиции после `parseLine`.
/// [rawText] — сырой вывод движка (для диалога «что увидел движок»).
typedef TessInvoiceResult = ({List<OcrLine> lines, String rawText});

/// Офлайн-распознавание накладной через Tesseract (rus+eng).
///
/// Предобработка идёт в фоновом изоляте ([compute]): декодирование 12 Мп
/// JPEG на UI-изоляте давало фризы на средних телефонах.
///
/// Пайплайн: EXIF-поворот → серый → апскейл/даунскейл до 2000px →
/// растяжка контраста → deskew → адаптивная бинаризация
/// (см. [OcrImageOps.prepare]).
///
/// Три варианта поворота (0°/90°/270°) готовятся из одного декода и
/// распознаются по очереди с коротким замыканием на ≥ 3 строках.
/// Если строк всё ещё мало — повторный проход с psm 4 (колонки).
class TessInvoiceOcr {
  /// Аргументы Tesseract: сохраняем пробелы между колонками
  /// (парсер режет хвост по ним) и явно задаём DPI.
  static const Map<String, String> _baseArgs = {
    'psm': '6',
    'preserve_interword_spaces': '1',
    'user_defined_dpi': '300',
  };

  /// Минимум строк, при котором не крутим дальше и не добавляем psm-проход.
  static const int _enoughLines = 3;

  /// Основная точка входа.
  ///
  /// [imagePath] — путь к исходному фото (не удаляется).
  static Future<TessInvoiceResult> recognize(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      return (lines: <OcrLine>[], rawText: '');
    }

    // 1. Подготовка вариантов 0°/90°/270° в фоновом изоляте.
    List<String> variants = const [];
    try {
      final tmpDir = await getTemporaryDirectory();
      variants = await compute(_prepareVariants, (
        srcPath: file.path,
        tmpDirPath: tmpDir.path,
      ));
    } catch (e) {
      debugPrint('TessInvoiceOcr: prepare failed: $e');
    }
    final paths = variants.isEmpty ? [file.path] : variants;

    // 2. Распознавание: пробуем каждый вариант, держим лучший.
    var bestLines = <OcrLine>[];
    var bestRaw = '';
    String? bestPath;
    try {
      for (final p in paths) {
        final raw = await _extract(p, _baseArgs);
        if (raw == null) continue;
        final lines = _parseRaw(raw);
        debugPrint('TessInvoiceOcr: ${p.split(Platform.pathSeparator).last} '
            'psm=6 lines=${lines.length}');
        if (lines.length > bestLines.length) {
          bestLines = lines;
          bestRaw = raw;
          bestPath = p;
        }
        if (bestLines.length >= _enoughLines) break;
      }

      // 3. Мало строк — пробуем «колонковый» psm 4 по лучшему варианту.
      // Таблица накладной из-за тонких вертикальных линий иногда режется
      // движком на колонки, и psm 6 их перемешивает.
      if (bestLines.length < _enoughLines && bestPath != null) {
        final raw = await _extract(bestPath, {
          ..._baseArgs,
          'psm': '4',
        });
        if (raw != null) {
          final lines = _parseRaw(raw);
          debugPrint(
              'TessInvoiceOcr: psm=4 lines=${lines.length}');
          if (lines.length > bestLines.length) {
            bestLines = lines;
            bestRaw = raw;
          }
        }
      }
    } finally {
      // Убираем все временные варианты.
      for (final p in variants) {
        try {
          await File(p).delete();
        } catch (_) {}
      }
    }

    return (lines: bestLines, rawText: bestRaw);
  }

  /// Один проход OCR с перехватом ошибок движка (на десктопе плагина нет).
  static Future<String?> _extract(
      String path, Map<String, String> args) async {
    try {
      return await FlutterTesseractOcr.extractText(
        path,
        language: 'rus+eng',
        args: args,
      );
    } catch (e) {
      debugPrint('TessInvoiceOcr: OCR error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Разбор сырого текста движка по строкам через общий parseLine
  // ---------------------------------------------------------------------------
  @visibleForTesting
  static List<OcrLine> parseRaw(String raw) => _parseRaw(raw);

  static List<OcrLine> _parseRaw(String raw) {
    final result = <OcrLine>[];
    final seen = <String>{};
    for (final line in raw.split('\n')) {
      final parsed = InvoicePhotoOcr.parseLine(line);
      if (parsed == null) continue;
      final key = parsed.name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
      if (seen.add(key)) {
        result.add(parsed);
      }
    }
    return result;
  }
}

/// Подготовка вариантов изображения в изоляте.
///
/// Возвращает пути к PNG: [0°, 90°, 270°]. Выполняется один декод,
/// дальше только повороты готовой бинарной картинки.
/// Возвращает пустой список при ошибке декодирования (вызывающий
/// использует оригинал файла).
List<String> _prepareVariants(
    ({String srcPath, String tmpDirPath}) args) {
  final bytes = File(args.srcPath).readAsBytesSync();
  final decoded = img_lib.decodeImage(bytes);
  if (decoded == null) return const [];

  final prepared = OcrImageOps.prepare(decoded, binarize: true);
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final result = <String>[];

  void writeVariant(String tag, img_lib.Image image) {
    final path = '${args.tmpDirPath}/tess_${tag}_$stamp.png';
    File(path).writeAsBytesSync(img_lib.encodePng(image, level: 1));
    result.add(path);
  }

  writeVariant('v0', prepared);
  writeVariant('v90', img_lib.copyRotate(prepared, angle: 90));
  writeVariant('v270', img_lib.copyRotate(prepared, angle: 270));
  return result;
}
