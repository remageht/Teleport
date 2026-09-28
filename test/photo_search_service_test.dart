import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img_lib;
import 'package:radiotrade/models/catalog.dart';
import 'package:radiotrade/services/photo_search_service.dart';

void main() {
  group('PhotoSearchService perceptual hashing tests', () {
    test('identical images yield 100% similarity', () {
      // Создаём тестовое изображение 64x64 с геометрическими формами и цветами
      final img = img_lib.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final r = (x * 4) % 256;
          final g = (y * 4) % 256;
          final b = ((x + y) * 2) % 256;
          img.setPixelRgb(x, y, r, g, b);
        }
      }

      final sig1 = PhotoSearchService.computeSignature(img);
      final sig2 = PhotoSearchService.computeSignature(img);

      final sim = PhotoSearchService.compareSignatures(sig1, sig2);
      expect(sim, closeTo(1.0, 0.0001),
          reason: 'Одинаковые изображения должны давать 100% схожесть');
    });

    test('slightly cropped and resized images maintain high similarity (>75%)', () {
      // Исходное изображение 100x100
      final base = img_lib.Image(width: 100, height: 100);
      for (var y = 0; y < 100; y++) {
        for (var x = 0; x < 100; x++) {
          final isCircle = ((x - 50) * (x - 50) + (y - 50) * (y - 50)) < 900;
          if (isCircle) {
            base.setPixelRgb(x, y, 220, 20, 60); // красный круг
          } else {
            base.setPixelRgb(x, y, 30, 144, 255); // синий фон
          }
        }
      }

      // Обрезаем 5% по краям и масштабируем до 80x80
      final cropped = img_lib.copyCrop(base, x: 5, y: 5, width: 90, height: 90);
      final resized = img_lib.copyResize(cropped, width: 80, height: 80);

      final sigBase = PhotoSearchService.computeSignature(base);
      final sigResized = PhotoSearchService.computeSignature(resized);

      final sim = PhotoSearchService.compareSignatures(sigBase, sigResized);
      expect(sim, greaterThan(0.75),
          reason: 'Слегка обрезанное и отмасштабированное изображение должно быть очень похоже (>75%)');
    });

    test('completely different images have low similarity (<60%)', () {
      // Изображение 1: сине-зелёный вертикальный градиент
      final img1 = img_lib.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          img1.setPixelRgb(x, y, 0, x * 4, 255 - x * 4);
        }
      }

      // Изображение 2: ярко-красный круг на чёрном фоне
      final img2 = img_lib.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final inCircle = ((x - 32) * (x - 32) + (y - 32) * (y - 32)) < 400;
          img2.setPixelRgb(x, y, inCircle ? 255 : 0, 0, 0);
        }
      }

      final sig1 = PhotoSearchService.computeSignature(img1);
      final sig2 = PhotoSearchService.computeSignature(img2);

      final sim = PhotoSearchService.compareSignatures(sig1, sig2);
      expect(sim, lessThan(0.60),
          reason: 'Совершенно разные картинки должны иметь низкую схожесть (<60%)');
    });

    test('multi-orientation matching recognizes 90-degree rotated image', () {
      // Асимметричный рисунок (L-образная форма)
      final img = img_lib.Image(width: 64, height: 64);
      for (var y = 0; y < 64; y++) {
        for (var x = 0; x < 64; x++) {
          final isL = (x >= 10 && x <= 20 && y >= 10 && y <= 50) ||
              (x >= 10 && x <= 50 && y >= 40 && y <= 50);
          img.setPixelRgb(x, y, isL ? 255 : 30, isL ? 255 : 30, isL ? 0 : 30);
        }
      }

      final rotated90 = img_lib.copyRotate(img, angle: 90);

      final sig0 = PhotoSearchService.computeSignature(img);
      final sigRot = PhotoSearchService.computeSignature(rotated90);

      // При прямом сравнении сигнатур 0° и 90° будет заметное расхождение
      final unrotatedSim = PhotoSearchService.compareSignatures(sig0, sigRot);
      expect(unrotatedSim, lessThan(0.85));

      // Но при выравнивании ориентации на 90° они сходятся
      final sig0Rotated = PhotoSearchService.computeSignature(img_lib.copyRotate(img, angle: 90));
      final rotSim = PhotoSearchService.compareSignatures(sig0Rotated, sigRot);
      expect(rotSim, closeTo(1.0, 0.05),
          reason: 'Повёрнутая версия запроса совпадает с повёрнутой картинкой');
    });

    test('searchSimilar end-to-end ranked results', () async {
      final tmpDir = await Directory.systemTemp.createTemp('photo_search_test_');
      try {
        // Создаём 3 разных картинки на диске
        final p1File = File('${tmpDir.path}/p1.jpg');
        final p2File = File('${tmpDir.path}/p2.jpg');
        final queryFile = File('${tmpDir.path}/query.jpg');

        // Картинка 1: диагональный узор
        final img1 = img_lib.Image(width: 48, height: 48);
        for (var y = 0; y < 48; y++) {
          for (var x = 0; x < 48; x++) {
            img1.setPixelRgb(x, y, (x * 5) % 256, (y * 5) % 256, 100);
          }
        }
        await p1File.writeAsBytes(img_lib.encodeJpg(img1));

        // Картинка 2: шахматная доска
        final img2 = img_lib.Image(width: 48, height: 48);
        for (var y = 0; y < 48; y++) {
          for (var x = 0; x < 48; x++) {
            final check = ((x ~/ 8) + (y ~/ 8)) % 2 == 0;
            img2.setPixelRgb(x, y, check ? 240 : 10, check ? 240 : 10, check ? 240 : 10);
          }
        }
        await p2File.writeAsBytes(img_lib.encodeJpg(img2));

        // Запрос: слегка изменённая версия картинки 1 (чуть смещённая)
        final imgQuery = img_lib.copyCrop(img1, x: 2, y: 2, width: 44, height: 44);
        await queryFile.writeAsBytes(img_lib.encodeJpg(imgQuery));

        final candidateProducts = [
          const Product(id: 'prod-1', sku: 'SKU1', name: 'Товар 1 (Похожий)', photoPath: ''),
          Product(id: 'prod-2', sku: 'SKU2', name: 'Товар 2 (Диагональ)', photoPath: p1File.path),
          Product(id: 'prod-3', sku: 'SKU3', name: 'Товар 3 (Шахматы)', photoPath: p2File.path),
          const Product(id: 'prod-4', sku: 'SKU4', name: 'Товар 4 (Битый путь)', photoPath: '/invalid/path.jpg'),
        ];

        final results = await PhotoSearchService.searchSimilar(
          queryImagePath: queryFile.path,
          candidates: candidateProducts,
          limit: 5,
        );

        expect(results, isNotEmpty);
        expect(results.length, 2, reason: 'Товары без файлов фото должны быть пропущены');
        // Товар 2 (img1) должен быть на 1 месте с высоким процентом
        expect(results.first.product.id, 'prod-2');
        expect(results.first.similarityPct, greaterThan(80.0));
        // Товар 3 (шахматы) должен иметь значительно меньшую схожесть
        expect(results[1].product.id, 'prod-3');
        expect(results.first.similarityPct, greaterThan(results[1].similarityPct + 15.0));
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });
  });
}
