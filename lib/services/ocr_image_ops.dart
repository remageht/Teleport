import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img_lib;

/// Чистые операции обработки фото перед подачей в OCR-движок.
///
/// Ничего не знает про Flutter-плагины: только `image` и математика,
/// поэтому легко тестируется на десктопе без Android.
/// Используется [TessInvoiceOcr]; референс-пайплайн:
/// EXIF-поворот → серый → апскейл мелких → растяжка контраста →
/// выравнивание наклона (deskew) → адаптивная бинаризация.
class OcrImageOps {
  OcrImageOps._();

  /// Длинная сторона, к которой приводим фото.
  /// Меньше — Tesseract теряет мелкий текст накладной,
  /// больше — впустую тратит время.
  static const int targetLongSide = 2000;

  /// Если фото меньше этого по длинной стороне — апскейлим (но не более x2.5).
  static const int minLongSide = 1500;

  // ---------------------------------------------------------------------
  // Пайплайн целиком
  // ---------------------------------------------------------------------

  /// Полный пайплайн подготовки:
  /// 1. EXIF-ориентация; 2. серый; 3. апскейл мелких / даунскейл больших;
  /// 4. растяжка контраста; 5. deskew; 6. (опц.) адаптивная бинаризация;
  /// 7. (опц.) удаление линий таблицы.
  ///
  /// [binarize] = true отдаёт чёрно-белый PNG (лучше для печатных
  /// накладных), false — серый JPEG (мягче для мятых/бликующих фото).
  /// [removeLines] убирает сетку таблицы — без этого Tesseract
  /// «захлёбывается» разлинованной накладной (проверено бенчем).
  /// [targetLong] переопределяет длинную сторону (для бенча/отладки).
  static img_lib.Image prepare(
    img_lib.Image src, {
    bool binarize = true,
    bool removeLines = true,
    int? targetLong,
  }) {
    var img = img_lib.bakeOrientation(src);
    img = img_lib.grayscale(img);
    img = resizeToTarget(img, target: targetLong ?? targetLongSide);
    img = img_lib.normalize(img, min: 0, max: 255);
    final angle = findSkewAngle(img);
    if (angle.abs() >= 0.75) {
      img = img_lib.copyRotate(img, angle: angle);
    }
    if (binarize) {
      img = adaptiveThreshold(img);
    }
    if (removeLines) {
      final mask = binarize ? img : adaptiveThreshold(img);
      img = removeTableLines(mask, paint: binarize ? null : img);
    }
    return img;
  }

  /// Приводим длинную сторону к [target]; мелкие фото апскейлим,
  /// но не более чем в 2.5 раза (сильный апскейл только мылит).
  static img_lib.Image resizeToTarget(img_lib.Image img,
      {int target = targetLongSide}) {
    final long = max(img.width, img.height);
    if (long == target) return img;
    var scale = target / long;
    if (scale > 2.5) scale = 2.5;
    if (long < minLongSide || long > target) {
      // Точный расчёт обеих сторон с округлением.
      final w = (img.width * scale).round().clamp(1, 1 << 14);
      final h = (img.height * scale).round().clamp(1, 1 << 14);
      return img_lib.copyResize(
        img,
        width: w,
        height: h,
        interpolation: img_lib.Interpolation.linear,
      );
    }
    return img;
  }

  // ---------------------------------------------------------------------
  // Deskew (выравнивание наклона)
  // ---------------------------------------------------------------------

  /// Оценка угла наклона текста в градусах (CW).
  /// Возвращает угол для `copyRotate`, при котором строки выравниваются;
  /// 0.0 — если наклона нет или картинка пустая.
  ///
  /// Метод: бинаризуем уменьшенную копию (длинная сторона [proxySide]),
  /// крутим её маленькими шагами и ищем угол с максимальной дисперсией
  /// профиля по строкам (у выровненного текста строки «звонкие»).
  static double findSkewAngle(img_lib.Image gray, {int proxySide = 800}) {
    var proxy = gray;
    final long = max(proxy.width, proxy.height);
    if (long > proxySide) {
      final scale = proxySide / long;
      proxy = img_lib.copyResize(
        proxy,
        width: (proxy.width * scale).round().clamp(1, 1 << 14),
        height: (proxy.height * scale).round().clamp(1, 1 << 14),
        interpolation: img_lib.Interpolation.average,
      );
    }
    final w = proxy.width, h = proxy.height;
    final bin = Uint8List(w * h);
    var dark = 0;
    for (final p in proxy) {
      final l = p.luminance.toInt();
      final v = l < 128 ? 1 : 0;
      bin[p.y * w + p.x] = v;
      dark += v;
    }
    if (dark < (w * h) * 0.002 || dark > (w * h) * 0.8) {
      return 0.0; // почти пусто или почти залито — крутить нечего
    }

    var bestAngle = 0.0;
    var bestScore = -1.0;
    void scan(double from, double to, double step) {
      for (var a = from; a <= to + 1e-9; a += step) {
        final s = _profileScore(bin, w, h, a);
        if (s > bestScore) {
          bestScore = s;
          bestAngle = a;
        }
      }
    }

    scan(-5.0, 5.0, 1.0); // грубо
    scan(bestAngle - 0.75, bestAngle + 0.75, 0.25); // уточнение
    final result = bestAngle.clamp(-6.0, 6.0);
    return result.abs() < 0.5 ? 0.0 : result;
  }

  /// Дисперсия сумм тёмных пикселей по строкам для повёрнутой картины.
  /// Чем ровнее строки текста, тем «звонче» профиль и выше дисперсия.
  static double _profileScore(Uint8List bin, int w, int h, double angleDeg) {
    final rad = angleDeg * pi / 180.0;
    final cosA = cos(rad), sinA = sin(rad);
    final cx = w / 2.0, cy = h / 2.0;
    final rows = Int32List(h);
    for (var y = 0; y < h; y++) {
      final dy = y - cy;
      for (var x = 0; x < w; x++) {
        if (bin[y * w + x] == 0) continue;
        final dx = x - cx;
        final sy = (cy + dx * sinA + dy * cosA).round();
        if (sy < 0 || sy >= h) continue;
        rows[sy]++;
      }
    }
    var sum = 0.0;
    for (var y = 0; y < h; y++) {
      sum += rows[y];
    }
    final mean = sum / h;
    var varSum = 0.0;
    for (var y = 0; y < h; y++) {
      final d = rows[y] - mean;
      varSum += d * d;
    }
    return varSum / h;
  }

  // ---------------------------------------------------------------------
  // Адаптивная бинаризация (Bradley / Wellner, через интегральное изображение)
  // ---------------------------------------------------------------------

  /// Бинаризация с локальным порогом: пиксель чёрный, если он темнее
  /// `0.85 * среднего` по окну [window]. Устойчива к теням и градиенту
  /// освещения (фото накладной на столе у окна — обычный случай).
  static img_lib.Image adaptiveThreshold(
    img_lib.Image gray, {
    int? window,
    double t = 0.85,
  }) {
    final w = gray.width, h = gray.height;
    final win = window ?? max(15, (max(w, h) / 25).round());
    final half = win ~/ 2;

    // Яркость одним массивом — без getPixel в горячих циклах.
    final lum = Uint8List(w * h);
    var i = 0;
    for (final p in gray) {
      lum[i++] = p.luminance.toInt().clamp(0, 255);
    }

    // Интегральное изображение (double на строку — переполнение исключено).
    final integral = Float64List((w + 1) * (h + 1));
    for (var y = 0; y < h; y++) {
      var rowSum = 0.0;
      final row = y * w;
      final intRow = (y + 1) * (w + 1);
      final prevRow = y * (w + 1);
      for (var x = 0; x < w; x++) {
        rowSum += lum[row + x];
        integral[intRow + (x + 1)] = integral[prevRow + (x + 1)] + rowSum;
      }
    }

    // Результат — байтами RGB (серый), одним fromBytes.
    final outBytes = Uint8List(w * h * 3);
    var o = 0;
    for (var y = 0; y < h; y++) {
      final y0 = max(0, y - half), y1 = min(h - 1, y + half);
      final intTop = y0 * (w + 1), intBottom = (y1 + 1) * (w + 1);
      for (var x = 0; x < w; x++) {
        final x0 = max(0, x - half), x1 = min(w - 1, x + half);
        final area = (x1 - x0 + 1) * (y1 - y0 + 1);
        final sum = integral[intBottom + (x1 + 1)] -
            integral[intTop + (x1 + 1)] -
            integral[intBottom + x0] +
            integral[intTop + x0];
        final v = lum[y * w + x] < t * (sum / area) ? 0 : 255;
        outBytes[o++] = v;
        outBytes[o++] = v;
        outBytes[o++] = v;
      }
    }
    return img_lib.Image.fromBytes(
      width: w,
      height: h,
      bytes: outBytes.buffer,
      order: img_lib.ChannelOrder.rgb,
    );
  }

  // ---------------------------------------------------------------------
  // Удаление линий таблицы
  // ---------------------------------------------------------------------

  /// Убирает длинные прямые линии (сетка таблиц, разделители): находит
  /// протяжённые горизонтальные и вертикальные пробеги «чернил» и
  /// закрашивает их белым полосой ±[thick] пикселей.
  ///
  /// [detect] — по чему искать линии (обычно бинарная копия, но метод
  /// работает и с серым), [paint] — куда закрашивать; если не задан —
  /// закрашиваем в сам [detect]. Возвращает изображение с закраской.
  ///
  /// Порог «длинности»: [hFrac] ширины для горизонталей и [vFrac]
  /// высоты для вертикалей — пробеги короче не трогаем, чтобы не
  /// выедать подчёркивания и длинные штрихи в тексте.
  static img_lib.Image removeTableLines(
    img_lib.Image detect, {
    img_lib.Image? paint,
    double hFrac = 0.12,
    double vFrac = 0.05,
    int maxGap = 2,
    int thick = 2,
  }) {
    final target = paint ?? detect;
    final w = detect.width, h = detect.height;

    final ink = Uint8List(w * h);
    var i = 0;
    for (final p in detect) {
      ink[i++] = p.luminance < 160 ? 1 : 0;
    }

    final hMin = max(30, (w * hFrac).round());
    final vMin = max(30, (h * vFrac).round());

    // Пробеги с допуском на разрывы до [maxGap] (шум JPEG, скан).
    void scan(int size, int limit, int Function(int, int) at, int minLen,
        void Function(int, int, int) onLine) {
      for (var s = 0; s < limit; s++) {
        var runStart = -1, lastInk = -1, gaps = 0;
        for (var t = 0; t <= size; t++) {
          final on = t < size && ink[at(s, t)] == 1;
          if (on) {
            if (runStart < 0) runStart = t;
            lastInk = t;
            gaps = 0;
          } else if (runStart >= 0) {
            if (++gaps > maxGap) {
              if (lastInk - runStart + 1 >= minLen) {
                onLine(s, runStart, lastInk);
              }
              runStart = -1;
            }
          }
        }
      }
    }

    void fillRow(int y, int x0, int x1) {
      for (var yy = max(0, y - thick); yy <= min(h - 1, y + thick); yy++) {
        for (var x = max(0, x0); x <= min(w - 1, x1); x++) {
          target.setPixelRgba(x, yy, 255, 255, 255, 255);
        }
      }
    }

    void fillCol(int x, int y0, int y1) {
      for (var xx = max(0, x - thick); xx <= min(w - 1, x + thick); xx++) {
        for (var y = max(0, y0); y <= min(h - 1, y1); y++) {
          target.setPixelRgba(xx, y, 255, 255, 255, 255);
        }
      }
    }

    scan(w, h, (y, x) => y * w + x, hMin, fillRow);
    scan(h, w, (x, y) => y * w + x, vMin, fillCol);
    return target;
  }
}
