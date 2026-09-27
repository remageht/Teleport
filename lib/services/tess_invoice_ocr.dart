import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';
import 'package:image/image.dart' as img_lib;
import 'package:path_provider/path_provider.dart';

import 'invoice_photo_ocr.dart';

/// Результат Tesseract-OCR накладной.
///
/// [lines]   — распознанные позиции после `parseLine`.
/// [rawText] — сырой вывод движка (для диалога «что увидел движок»).
typedef TessInvoiceResult = ({List<OcrLine> lines, String rawText});

/// Офлайн-распознавание накладной через Tesseract (rus+eng).
///
/// Предобработка фото:
/// - EXIF-поворот (`bakeOrientation`)
/// - перевод в оттенки серого
/// - масштабирование до 2000 px по длинной стороне (Tesseract лучше читает
///   нормализованное разрешение, не слишком маленькое и не огромное)
/// - сохранение с качеством JPEG 88
///
/// Стратегия поворота:
/// Пробуем 0° → 90° → 270° CW. Останавливаемся на первом варианте
/// с ≥ 3 распознанными строками; если ни один не дал ≥ 3 — берём
/// вариант с наибольшим числом строк.
class TessInvoiceOcr {
  /// Основная точка входа.
  ///
  /// [imagePath] — путь к исходному фото (не удаляется).
  static Future<TessInvoiceResult> recognize(String imagePath) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      return (lines: <OcrLine>[], rawText: '');
    }

    // 1. Предобработка: EXIF-поворот + серый + ресайз + JPEG 88
    File? preprocessed;
    try {
      preprocessed = await _preprocess(file);
    } catch (e) {
      debugPrint('TessInvoiceOcr: preprocess failed: $e');
    }

    final workPath = preprocessed?.path ?? imagePath;

    // 2. Попытки поворота 0° → 90° → 270°
    const angles = [0, 90, 270];
    var bestLines = <OcrLine>[];
    var bestRaw = '';

    File? rotFile;
    try {
      for (final angle in angles) {
        File? angleFile;
        try {
          if (angle == 0) {
            angleFile = File(workPath);
          } else {
            angleFile = await _rotate(File(workPath), angle);
            rotFile = angleFile; // удалим в finally
          }

          final raw = await FlutterTesseractOcr.extractText(
            angleFile.path,
            language: 'rus+eng',
            args: {'psm': '6'},
          );

          final lines = _parseRaw(raw);
          debugPrint(
              'TessInvoiceOcr: angle=$angle lines=${lines.length} raw=${raw.length}ch');

          if (lines.length > bestLines.length) {
            bestLines = lines;
            bestRaw = raw;
          }

          // Удаляем ротированный временник сразу
          if (angle != 0 && rotFile != null) {
            try {
              await rotFile.delete();
            } catch (_) {}
            rotFile = null;
          }

          if (bestLines.length >= 3) break; // достаточно, дальше не крутим
        } catch (e) {
          debugPrint('TessInvoiceOcr: angle=$angle error: $e');
          if (rotFile != null) {
            try {
              await rotFile.delete();
            } catch (_) {}
            rotFile = null;
          }
        }
      }
    } finally {
      // Убираем предобработанный временник
      if (preprocessed != null) {
        try {
          await preprocessed.delete();
        } catch (_) {}
      }
      // На случай если цикл прервался с необработанным rotFile
      if (rotFile != null) {
        try {
          await rotFile.delete();
        } catch (_) {}
      }
    }

    return (lines: bestLines, rawText: bestRaw);
  }

  // ---------------------------------------------------------------------------
  // Предобработка: EXIF-поворот + серый + ресайз + JPEG 88
  // ---------------------------------------------------------------------------
  static Future<File> _preprocess(File src) async {
    final bytes = await src.readAsBytes();
    var img = img_lib.decodeImage(bytes);
    if (img == null) throw StateError('Cannot decode image');

    // Применяем EXIF-ориентацию
    img = img_lib.bakeOrientation(img);

    // Серый — уменьшает шум и помогает движку
    img = img_lib.grayscale(img);

    // Масштабирование по длинной стороне до 2000 px
    const maxSide = 2000;
    if (img.width > maxSide || img.height > maxSide) {
      final scale = maxSide / max(img.width, img.height);
      img = img_lib.copyResize(
        img,
        width: (img.width * scale).round(),
        height: (img.height * scale).round(),
        interpolation: img_lib.Interpolation.linear,
      );
    }

    final tmpDir = await getTemporaryDirectory();
    final tmpPath =
        '${tmpDir.path}/tess_pre_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final tmpFile = File(tmpPath);
    await tmpFile.writeAsBytes(img_lib.encodeJpg(img, quality: 88));
    return tmpFile;
  }

  // ---------------------------------------------------------------------------
  // Поворот на [angle]° CW, сохранение во временный файл
  // ---------------------------------------------------------------------------
  static Future<File> _rotate(File src, int angle) async {
    final bytes = await src.readAsBytes();
    final img = img_lib.decodeImage(bytes);
    if (img == null) throw StateError('Cannot decode image for rotation');
    final rotated = img_lib.copyRotate(img, angle: angle);
    final tmpDir = await getTemporaryDirectory();
    final tmpPath =
        '${tmpDir.path}/tess_rot${angle}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final tmpFile = File(tmpPath);
    await tmpFile.writeAsBytes(img_lib.encodeJpg(rotated, quality: 88));
    return tmpFile;
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
