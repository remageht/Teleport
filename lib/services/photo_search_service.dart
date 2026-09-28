import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img_lib;

import '../models/catalog.dart';

/// Результат поиска товара по фото со степенью схожести.
class PhotoSearchResult {
  final Product product;

  /// Процент схожести (0.0 — 100.0%).
  final double similarityPct;

  const PhotoSearchResult({
    required this.product,
    required this.similarityPct,
  });
}

/// Сигнатура изображения для перцептивного сравнения.
/// Включает:
/// - dHash (градиенты по горизонтали и вертикали, 512 бит)
/// - aHash (силуэт/макроформа относительно средней яркости, 64 бита)
/// - pHash (низкочастотные коэффициенты DCT, 64 бита)
/// - Цветовая сетка 4x4 RGB (16 блоков x 3 канала = 48 значений)
class ImageSignature {
  /// Горизонтальный dHash (4 слова по 64 бита = 256 бит).
  final List<int> dHashH;

  /// Вертикальный dHash (4 слова по 64 бита = 256 бит).
  final List<int> dHashV;

  /// aHash (64 бита средней яркости).
  final int aHash;

  /// DCT pHash (64 бита).
  final int pHash;

  /// Цветовая сетка 4x4 RGB.
  final Uint8List colorGrid;

  const ImageSignature({
    required this.dHashH,
    required this.dHashV,
    required this.aHash,
    required this.pHash,
    required this.colorGrid,
  });
}

/// Сервис офлайн-поиска товаров по фото на основе перцептивного хэширования
/// (dHash + aHash + pHash + color grid) без использования сторонних нейросетей/моделей.
///
/// Все тяжёлые вычисления (чтение файлов, декодирование, масштабирование,
/// DCT-преобразование и расчёт расстояний Хэмминга) выполняются в фоновом
/// изоляте через [compute], не блокируя UI-поток приложения.
class PhotoSearchService {
  static const int minRecommendedPhotos = 10;

  /// Подсчёт установленных битов в 64-битном целом (алгоритм Брайана Кернигана,
  /// безопасный для отрицательных чисел в Dart VM).
  static int popcount64(int v) {
    var x = v;
    var count = 0;
    if (x < 0) {
      count++;
      x &= 0x7FFFFFFFFFFFFFFF;
    }
    while (x > 0) {
      x &= (x - 1);
      count++;
    }
    return count;
  }

  /// Предрасчитанная таблица косинусов для 1D DCT (32 отсчёта x 8 частот).
  static final Float64List _cosTable = _initCosTable();

  static Float64List _initCosTable() {
    final table = Float64List(32 * 8);
    for (var u = 0; u < 8; u++) {
      for (var x = 0; x < 32; x++) {
        table[u * 32 + x] = cos((2 * x + 1) * u * pi / 64.0);
      }
    }
    return table;
  }

  /// Вычисление dHash (горизонтальные и вертикальные разности яркости).
  /// Возвращает пару (dHashH, dHashV) по 256 бит каждый (по 4 x 64-бит числа).
  static (List<int>, List<int>) computeDHash(img_lib.Image image) {
    // 1. Горизонтальный dHash (17 x 16 -> 16 разностей в строке x 16 строк = 256 бит)
    final imgH = img_lib.copyResize(
      image,
      width: 17,
      height: 16,
      interpolation: img_lib.Interpolation.linear,
    );
    final wordsH = List<int>.filled(4, 0);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final lumL = imgH.getPixel(x, y).luminance;
        final lumR = imgH.getPixel(x + 1, y).luminance;
        if (lumL > lumR) {
          final bitIndex = y * 16 + x;
          final chunk = bitIndex ~/ 64;
          final bit = bitIndex % 64;
          wordsH[chunk] |= (1 << bit);
        }
      }
    }

    // 2. Вертикальный dHash (16 x 17 -> 16 разностей в столбце x 16 столбцов = 256 бит)
    final imgV = img_lib.copyResize(
      image,
      width: 16,
      height: 17,
      interpolation: img_lib.Interpolation.linear,
    );
    final wordsV = List<int>.filled(4, 0);
    for (var y = 0; y < 16; y++) {
      for (var x = 0; x < 16; x++) {
        final lumT = imgV.getPixel(x, y).luminance;
        final lumB = imgV.getPixel(x, y + 1).luminance;
        if (lumT > lumB) {
          final bitIndex = y * 16 + x;
          final chunk = bitIndex ~/ 64;
          final bit = bitIndex % 64;
          wordsV[chunk] |= (1 << bit);
        }
      }
    }

    return (wordsH, wordsV);
  }

  /// Вычисление aHash (average hash, 64 бита).
  /// Картинка уменьшается до 8x8, вычисляется средняя яркость, бит = 1 если pixel >= mean.
  static int computeAHash(img_lib.Image image) {
    final small = img_lib.copyResize(
      image,
      width: 8,
      height: 8,
      interpolation: img_lib.Interpolation.average,
    );

    var sum = 0.0;
    final lums = Float64List(64);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final lum = small.getPixel(x, y).luminance.toDouble();
        lums[y * 8 + x] = lum;
        sum += lum;
      }
    }
    final mean = sum / 64.0;

    var hash = 0;
    for (var i = 0; i < 64; i++) {
      if (lums[i] >= mean) {
        hash |= (1 << i);
      }
    }
    return hash;
  }

  /// Вычисление DCT pHash (64 бита).
  /// Картинка уменьшается до 32x32, вычисляется 8x8 DCT, находится медиана AC-компонент.
  static int computePHash(img_lib.Image image) {
    final small = img_lib.copyResize(
      image,
      width: 32,
      height: 32,
      interpolation: img_lib.Interpolation.linear,
    );

    // Матрица яркостей 32x32
    final lums = Float64List(32 * 32);
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        lums[y * 32 + x] = small.getPixel(x, y).luminance.toDouble();
      }
    }

    // Сепарабельное 2D DCT (32x32 -> 8x8 низких частот):
    // 1-й проход: построчно по X (32 -> 8)
    final rowDct = Float64List(32 * 8);
    for (var y = 0; y < 32; y++) {
      final rowOffset = y * 32;
      for (var u = 0; u < 8; u++) {
        final cosOffset = u * 32;
        var sum = 0.0;
        for (var x = 0; x < 32; x++) {
          sum += lums[rowOffset + x] * _cosTable[cosOffset + x];
        }
        rowDct[y * 8 + u] = sum;
      }
    }

    // 2-й проход: по столбцам по Y (32 -> 8)
    final dct = Float64List(64);
    for (var u = 0; u < 8; u++) {
      for (var v = 0; v < 8; v++) {
        final cosOffset = v * 32;
        var sum = 0.0;
        for (var y = 0; y < 32; y++) {
          sum += rowDct[y * 8 + u] * _cosTable[cosOffset + y];
        }
        dct[v * 8 + u] = sum;
      }
    }

    // Собираем 63 AC-компоненты (без DC компонента в (0,0))
    final acValues = Float64List(63);
    for (var i = 1; i < 64; i++) {
      acValues[i - 1] = dct[i];
    }
    acValues.sort();
    final median = acValues[31];

    // Формируем 64-битный хэш
    var hash = 0;
    for (var i = 0; i < 64; i++) {
      if (dct[i] > median) {
        hash |= (1 << i);
      }
    }

    return hash;
  }

  /// Вычисление цветовой сетки 4x4 RGB (16 блоков x 3 канала = 48 байт).
  static Uint8List computeColorGrid(img_lib.Image image) {
    final small = img_lib.copyResize(
      image,
      width: 4,
      height: 4,
      interpolation: img_lib.Interpolation.average,
    );

    final grid = Uint8List(48);
    var idx = 0;
    for (var y = 0; y < 4; y++) {
      for (var x = 0; x < 4; x++) {
        final pixel = small.getPixel(x, y);
        grid[idx++] = pixel.r.toInt().clamp(0, 255);
        grid[idx++] = pixel.g.toInt().clamp(0, 255);
        grid[idx++] = pixel.b.toInt().clamp(0, 255);
      }
    }
    return grid;
  }

  /// Построение полной сигнатуры (dHash + aHash + pHash + colorGrid).
  static ImageSignature computeSignature(img_lib.Image image) {
    final (dhH, dhV) = computeDHash(image);
    final ah = computeAHash(image);
    final ph = computePHash(image);
    final col = computeColorGrid(image);
    return ImageSignature(
      dHashH: dhH,
      dHashV: dhV,
      aHash: ah,
      pHash: ph,
      colorGrid: col,
    );
  }

  /// Сравнение двух сигнатур. Возвращает сходство от 0.0 (абсолютно разные) до 1.0 (идентичные).
  static double compareSignatures(ImageSignature a, ImageSignature b) {
    // 1. dHash расстояние (максимум 512 бит)
    var dHashDiff = 0;
    for (var i = 0; i < 4; i++) {
      dHashDiff += popcount64(a.dHashH[i] ^ b.dHashH[i]);
      dHashDiff += popcount64(a.dHashV[i] ^ b.dHashV[i]);
    }
    final dHashDist = dHashDiff / 512.0;

    // 2. aHash расстояние (максимум 64 бита)
    final aHashDiff = popcount64(a.aHash ^ b.aHash);
    final aHashDist = aHashDiff / 64.0;

    // 3. pHash расстояние (максимум 64 бита)
    final pHashDiff = popcount64(a.pHash ^ b.pHash);
    final pHashDist = pHashDiff / 64.0;

    // 4. Цветовое расстояние (Manhattan diff, максимум 48 * 255 = 12240)
    var colorDiff = 0;
    for (var i = 0; i < 48; i++) {
      colorDiff += (a.colorGrid[i] - b.colorGrid[i]).abs();
    }
    final colorDist = colorDiff / 12240.0;

    // Взвешенное суммарное перцептивное расстояние:
    // 30% dHash (градиенты и текстура)
    // 25% aHash (макро-форма и силуэт)
    // 25% pHash (доминирующий частотный спектр)
    // 20% Color (цветовая гамма)
    final totalDist = 0.30 * dHashDist +
        0.25 * aHashDist +
        0.25 * pHashDist +
        0.20 * colorDist;

    // Калибровка перцептивного сходства:
    // Случайные/несвязанные картинки имеют totalDist >= 0.35 - 0.45.
    // Сходные картинки имеют totalDist < 0.15.
    // Приводим расстояние [0.0 ... 0.45] к шкале сходства [1.0 ... 0.0].
    const maxThreshold = 0.45;
    if (totalDist >= maxThreshold) return 0.0;
    return (1.0 - (totalDist / maxThreshold)).clamp(0.0, 1.0);
  }

  /// Точка входа для поиска похожих товаров:
  /// Получает путь к целевому фото [queryImagePath] и список кандидатов [candidates].
  /// Возвращает топ-[limit] наиболее похожих товаров, отсортированных по убыванию схожести.
  /// Работает строго в изоляте через [compute].
  static Future<List<PhotoSearchResult>> searchSimilar({
    required String queryImagePath,
    required List<Product> candidates,
    int limit = 5,
  }) async {
    final queryFile = File(queryImagePath);
    if (!queryFile.existsSync()) return [];

    // Фильтруем кандидатов, у которых действительно существует файл фото
    final validCandidates = candidates.where((p) {
      final path = p.photoPath;
      return path != null && path.trim().isNotEmpty && File(path).existsSync();
    }).toList();

    if (validCandidates.isEmpty) return [];

    // Подготовка входных данных для изолята
    final candidateInputs = validCandidates
        .map((p) => (id: p.id, photoPath: p.photoPath!))
        .toList();

    final isolateResults = await compute(
      _searchInIsolate,
      _IsolateSearchInput(
        queryImagePath: queryImagePath,
        candidates: candidateInputs,
        limit: limit,
      ),
    );

    // Сопоставляем результаты обратно с объектами Product
    final candidateMap = {for (final p in validCandidates) p.id: p};
    final out = <PhotoSearchResult>[];

    for (final r in isolateResults) {
      final product = candidateMap[r.id];
      if (product != null) {
        out.add(PhotoSearchResult(
          product: product,
          similarityPct: r.similarityPct,
        ));
      }
    }

    return out;
  }
}

/// Параметры для передачи в изолят.
class _IsolateSearchInput {
  final String queryImagePath;
  final List<({String id, String photoPath})> candidates;
  final int limit;

  const _IsolateSearchInput({
    required this.queryImagePath,
    required this.candidates,
    required this.limit,
  });
}

/// Результат одного кандидата из изолята.
class _CandidateMatch {
  final String id;
  final double similarityPct;

  const _CandidateMatch(this.id, this.similarityPct);
}

/// Функция верхнего уровня для исполнения внутри Isolate via compute().
List<_CandidateMatch> _searchInIsolate(_IsolateSearchInput input) {
  final queryFile = File(input.queryImagePath);
  if (!queryFile.existsSync()) return [];

  final queryBytes = queryFile.readAsBytesSync();
  var queryImage = img_lib.decodeImage(queryBytes);
  if (queryImage == null) return [];

  // Нормализуем EXIF-ориентацию
  queryImage = img_lib.bakeOrientation(queryImage);

  // Сгенерируем 4 ориентации для запроса (0°, 90°, 180°, 270°),
  // чтобы альбомный снимок уверенно находил портретное фото в базе
  final querySignatures = <ImageSignature>[
    PhotoSearchService.computeSignature(queryImage),
  ];
  for (final angle in [90, 180, 270]) {
    final rotated = img_lib.copyRotate(queryImage, angle: angle);
    querySignatures.add(PhotoSearchService.computeSignature(rotated));
  }

  final matches = <_CandidateMatch>[];

  for (final cand in input.candidates) {
    try {
      final candFile = File(cand.photoPath);
      if (!candFile.existsSync()) continue;

      final candBytes = candFile.readAsBytesSync();
      var candImage = img_lib.decodeImage(candBytes);
      if (candImage == null) continue;

      candImage = img_lib.bakeOrientation(candImage);
      final candSig = PhotoSearchService.computeSignature(candImage);

      // Ищем максимальное сходство среди 4 углов поворота запроса
      var maxSim = 0.0;
      for (final qSig in querySignatures) {
        final sim = PhotoSearchService.compareSignatures(qSig, candSig);
        if (sim > maxSim) {
          maxSim = sim;
        }
      }

      matches.add(_CandidateMatch(cand.id, maxSim * 100.0));
    } catch (_) {
      // При повреждённом файле одного кандидата не падаем
      continue;
    }
  }

  // Сортируем по убыванию схожести
  matches.sort((a, b) => b.similarityPct.compareTo(a.similarityPct));

  if (matches.length > input.limit) {
    return matches.sublist(0, input.limit);
  }
  return matches;
}
