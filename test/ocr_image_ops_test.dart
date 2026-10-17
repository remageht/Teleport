import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:radiotrade/services/ocr_image_ops.dart';

/// Дисперсия сумм тёмных пикселей по строкам — метрика «выровненности»
/// текста (та же, что внутри deskew).
double rowProfileVariance(img.Image im) {
  final rows = List<int>.filled(im.height, 0);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      if (im.getPixel(x, y).luminance < 128) rows[y]++;
    }
  }
  final mean = rows.reduce((a, b) => a + b) / rows.length;
  var v = 0.0;
  for (final r in rows) {
    v += (r - mean) * (r - mean);
  }
  return v / rows.length;
}

img.Image stripedPage() {
  final im = img.Image(width: 600, height: 400);
  img.fill(im, color: img.ColorRgb8(255, 255, 255));
  for (var y = 60; y < 360; y += 40) {
    for (var dy = 0; dy < 10; dy++) {
      img.drawLine(im,
          x1: 40,
          y1: y + dy,
          x2: 560,
          y2: y + dy,
          color: img.ColorRgb8(0, 0, 0));
    }
  }
  return im;
}

void main() {
  group('OcrImageOps.adaptiveThreshold', () {
    test('светлый градиентный фон → белый, тонкие штрихи → чёрные', () {
      final im = img.Image(width: 200, height: 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 200; x++) {
          final bg = 180 + (55 * x / 199).round();
          // «Строки текста»: тонкие (4px) тёмные штрихи, как настоящие буквы,
          // а не большой залитый прямоугольник — у Bradley окно 15px.
          final dark = y > 46 && y < 50;
          final v = dark ? 60 : bg;
          im.setPixelRgb(x, y, v, v, v);
        }
      }
      final bin = OcrImageOps.adaptiveThreshold(im);
      expect(bin.getPixel(10, 10).r.toInt(), 255, reason: 'фон слева');
      expect(bin.getPixel(190, 90).r.toInt(), 255, reason: 'фон справа');
      expect(bin.getPixel(100, 48).r.toInt(), 0, reason: 'штрих текста');
    });
  });

  group('OcrImageOps.resizeToTarget', () {
    test('мелкое фото апскейлится с потолком x2.5', () {
      final tiny = img.Image(width: 400, height: 300);
      final r1 = OcrImageOps.resizeToTarget(tiny);
      expect(max(r1.width, r1.height), 1000,
          reason: '400 px × 2.5 = 1000: больше — только мыло');

      final mid = img.Image(width: 1000, height: 800);
      final r2 = OcrImageOps.resizeToTarget(mid);
      expect(max(r2.width, r2.height), OcrImageOps.targetLongSide);
    });

    test('крупное фото сжимается до целевой стороны', () {
      final big = img.Image(width: 4000, height: 3000);
      final r = OcrImageOps.resizeToTarget(big);
      expect(max(r.width, r.height), OcrImageOps.targetLongSide);
    });
  });

  group('OcrImageOps.findSkewAngle', () {
    test('выпрямленный лист → почти ноль', () {
      final angle = OcrImageOps.findSkewAngle(img.grayscale(stripedPage()));
      expect(angle.abs(), lessThan(1.0));
    });

    test('наклон ~4°: угол найден и применение выравнивает', () {
      final tilted = img.copyRotate(stripedPage(), angle: 4);
      final gray = img.grayscale(tilted);
      final angle = OcrImageOps.findSkewAngle(gray);
      expect(angle.abs(), greaterThan(2.5));
      expect(angle.abs(), lessThan(5.5));

      final before = rowProfileVariance(tilted);
      final corrected = img.copyRotate(tilted, angle: angle);
      final after = rowProfileVariance(corrected);
      expect(after, greaterThan(before),
          reason: 'после выравнивания профиль строк «звонче»');
    });
  });

  group('OcrImageOps.prepare', () {
    test('бинарный выход состоит из 0 и 255', () {
      final out = OcrImageOps.prepare(stripedPage(), binarize: true);
      for (var y = 0; y < out.height; y += 7) {
        for (var x = 0; x < out.width; x += 11) {
          final v = out.getPixel(x, y).r.toInt();
          expect(v == 0 || v == 255, isTrue,
              reason: 'пиксель ($x,$y) = $v');
        }
      }
    });

    test('серый выход без бинаризации', () {
      final out = OcrImageOps.prepare(stripedPage(), binarize: false);
      final mid = out.getPixel(300, 20).r.toInt();
      expect(mid, greaterThan(200), reason: 'фон остаётся светлым');
    });
  });
}
