import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:radiotrade/services/invoice_photo_ocr.dart';
import 'package:radiotrade/services/ocr_image_ops.dart';
import 'package:radiotrade/services/tess_invoice_ocr.dart';

/// Локальный бенч OCR на синтетической накладной с известным эталоном
/// (tool/ocr_bench_invoice.json) + опционально на реальных фото.
///
/// Запуск:
///   $env:OCR_BENCH='1'; flutter test test/ocr_bench_real_photos_test.dart
///
/// Реальные фото можно добавить через OCR_BENCH_PHOTOS (папка с jpg/png);
/// для них метрики точности не считаются — только число строк.
///
/// Без OCR_BENCH=1 тест пропускается (в CI tesseract.exe нет).
const _tessExe = r'C:\Program Files\Tesseract-OCR\tesseract.exe';
const _psScript = r'tool\gen_synthetic_invoice.ps1';
const _invoiceJson = r'tool\ocr_bench_invoice.json';
const _benchDir = r'build\ocr_bench';

typedef _Variant = ({String name, String kind, int side, bool words});

// ---------------------------------------------------------------------------
// Генерация и деградация изображений
// ---------------------------------------------------------------------------

/// Запускает PS1-генератор синтетической накладной.
File _generateCleanInvoice() {
  File(_benchDir).parent.createSync(recursive: true);
  Directory(_benchDir).createSync(recursive: true);
  const out = r'build\ocr_bench\invoice_clean.png';
  final res = Process.runSync('powershell.exe', [
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    _psScript,
    '-Json',
    _invoiceJson,
    '-Out',
    out,
  ]);
  final file = File(out);
  if (res.exitCode != 0 || !file.existsSync()) {
    throw StateError('generator failed: ${res.stderr}');
  }
  return file;
}

/// «Фото»: поворот 2.2°, тень-градиент, гауссов шум, лёгкое размытие,
/// JPEG 75. Фиксированный seed — бенч воспроизводим.
File _degradeToPhoto(File clean) {
  final decoded = img.decodeImage(clean.readAsBytesSync())!;

  // 1. Наклон, как при съёмке «на глаз».
  final rotated = img.copyRotate(decoded, angle: 2.2);
  final canvas = img.Image(width: rotated.width, height: rotated.height);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, rotated);
  var im = canvas;

  // 2. Неравномерное освещение: к правому-нижнему углу темнее до -22%.
  for (final p in im) {
    final k = 1.0 -
        (p.y / im.height) * 0.16 -
        (p.x / im.width) * 0.06;
    p
      ..r = (p.r * k).clamp(0, 255)
      ..g = (p.g * k).clamp(0, 255)
      ..b = (p.b * k).clamp(0, 255);
  }

  // 3. Шум сенсора и 4. лёгкое размытие объектива.
  img.noise(im, 8, type: img.NoiseType.gaussian, random: Random(42));
  im = img.gaussianBlur(im, radius: 1);

  // 5. JPEG-сжатие, как из камеры телефона.
  final out = File('$_benchDir\\invoice_photo.jpg');
  out.writeAsBytesSync(img.encodeJpg(im, quality: 75));
  return out;
}

// ---------------------------------------------------------------------------
// Сравнение с эталоном
// ---------------------------------------------------------------------------

String _norm(String s) =>
    s.toUpperCase().replaceAll(RegExp(r'[^A-ZА-ЯЁ0-9]'), '');

/// Dice-коэффициент по биграммам нормализованных строк.
double _dice(String a, String b) {
  if (a == b) return 1.0;
  if (a.length < 2 || b.length < 2) return a == b ? 1.0 : 0.0;
  final ga = <String>{};
  final gb = <String>{};
  for (var i = 0; i < a.length - 1; i++) {
    ga.add(a.substring(i, i + 2));
  }
  for (var i = 0; i < b.length - 1; i++) {
    gb.add(b.substring(i, i + 2));
  }
  final inter = ga.intersection(gb).length;
  return 2.0 * inter / (ga.length + gb.length);
}

typedef _Metrics = ({
  int lines,
  int pairs,
  int junk,
  double total,
  double totalDelta,
});

_Metrics _metrics(List<OcrLine> got, List<Map<String, dynamic>> expected,
    double expectedTotal) {
  // Числовые пары (qty, price) как мультимножество: сколько эталонных
  // пар нашлось среди распознанных строк (независимо от искажений имени).
  final gotPairs = got
      .map((g) => (qty: g.qty, price: g.price))
      .toList();
  var pairs = 0;
  for (final e in expected) {
    final q = (e['qty'] as num).toDouble();
    final p = (e['price'] as num).toDouble();
    final idx = gotPairs.indexWhere(
        (g) => (g.qty - q).abs() < 0.01 && (g.price - p).abs() < 0.02);
    if (idx >= 0) {
      pairs++;
      gotPairs.removeAt(idx);
    }
  }

  var junk = 0;
  for (final g in got) {
    final gn = _norm(g.name);
    var bestDice = 0.0;
    for (final e in expected) {
      final d = _dice(gn, _norm(e['name'] as String));
      if (d > bestDice) bestDice = d;
    }
    if (bestDice < 0.5) junk++;
  }
  final total = got.fold<double>(0, (s, l) => s + l.qty * l.price);
  return (
    lines: got.length,
    pairs: pairs,
    junk: junk,
    total: total,
    totalDelta: (total - expectedTotal).abs(),
  );
}

// ---------------------------------------------------------------------------
// Пайплайны предобработки
// ---------------------------------------------------------------------------

File _prepare(File photo, Directory tmp, _Variant v) {
  final decoded = img.decodeImage(photo.readAsBytesSync())!;
  final stem = photo.uri.pathSegments.last.replaceAll(RegExp(r'\.\w+$'), '');

  if (v.kind == 'jpg') {
    // Старый пайплайн из master: EXIF + серый + ресайз ≤2000 + JPEG 88.
    var im = img.bakeOrientation(decoded);
    im = img.grayscale(im);
    if (im.width > 2000 || im.height > 2000) {
      final scale = 2000 / (im.width > im.height ? im.width : im.height);
      im = img.copyResize(im,
          width: (im.width * scale).round(),
          height: (im.height * scale).round());
    }
    final f = File('${tmp.path}/old_$stem.jpg');
    f.writeAsBytesSync(img.encodeJpg(im, quality: 88));
    return f;
  }

  final prepared = OcrImageOps.prepare(
    decoded,
    binarize: v.kind == 'bin' || v.kind == 'lines',
    removeLines: v.kind == 'lines' || v.kind == 'gray',
    targetLong: v.side,
  );
  final ext = v.kind == 'norm' ? 'jpg' : 'png';
  final f = File('${tmp.path}/${v.kind}${v.side}_$stem.$ext');
  f.writeAsBytesSync(v.kind == 'norm'
      ? img.encodeJpg(prepared, quality: 92)
      : img.encodePng(prepared));
  return f;
}

String _tesseract(File image, Directory tessdata) {
  final res = Process.runSync(
    _tessExe,
    [
      image.path,
      'stdout',
      '-l',
      'rus+eng',
      '--psm',
      '6',
      '--tessdata-dir',
      tessdata.path,
      '-c',
      'preserve_interword_spaces=1',
      '-c',
      'user_defined_dpi=300',
    ],
    // Tesseract CLI всегда пишет UTF-8; без этого Windows-консоль
    // декодирует вывод как cp1251 и кириллица превращается в кашу.
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  return res.exitCode == 0 ? res.stdout as String : '';
}

void main() {
  final exeExists = File(_tessExe).existsSync();
  final run = Platform.environment['OCR_BENCH'] == '1';

  test(
    'бенч: синтетическая накладная (эталон) + фото-деградация',
    () {
      // Эталон из JSON.
      final data = jsonDecode(File(_invoiceJson).readAsStringSync())
          as Map<String, dynamic>;
      final expected = (data['products'] as List)
          .cast<Map<String, dynamic>>();
      final expectedTotal = expected.fold<double>(
          0, (s, e) => s + (e['qty'] as num) * (e['price'] as num));

      final tmp = Directory.systemTemp.createTempSync('ocr_bench_');
      final plain = Directory('${tmp.path}/tessdata')..createSync();
      final words = Directory('${tmp.path}/tessdata_words')..createSync();
      for (final d in [plain, words]) {
        for (final name in ['rus.traineddata', 'eng.traineddata']) {
          File('assets/tessdata/$name').copySync('${d.path}/$name');
        }
      }
      for (final name in ['rus.user-words', 'eng.user-words']) {
        File('assets/tessdata/$name').copySync('${words.path}/$name');
      }

      final clean = _generateCleanInvoice();
      final photo = _degradeToPhoto(clean);

      const variants = <_Variant>[
        (name: 'old', kind: 'jpg', side: 2000, words: false),
        (name: 'lines-2000', kind: 'lines', side: 2000, words: true),
        (name: 'lines-2600', kind: 'lines', side: 2600, words: true),
        (name: 'gray-2600', kind: 'gray', side: 2600, words: true),
      ];

      print('=== OCR БЕНЧ: эталонная сумма = '
          '${expectedTotal.toStringAsFixed(2)} ₽ ===');
      final results = <String, _Metrics>{};
      for (final image in [('clean', clean), ('photo', photo)]) {
        print('\n--- ${image.$1} (${image.$2.uri.pathSegments.last}) ---');
        for (final v in variants) {
          final swPrep = Stopwatch()..start();
          final prep = _prepare(image.$2, tmp, v);
          swPrep.stop();
          final swOcr = Stopwatch()..start();
          final raw = _tesseract(prep, v.words ? words : plain);
          swOcr.stop();
          final m = _metrics(TessInvoiceOcr.parseRaw(raw), expected,
              expectedTotal);
          results['${v.name}/${image.$1}'] = m;
          print('${v.name.padRight(9)} '
              'prep=${swPrep.elapsedMilliseconds.toString().padLeft(4)}ms '
              'ocr=${swOcr.elapsedMilliseconds.toString().padLeft(4)}ms '
              'lines=${m.lines.toString().padLeft(2)}/18 '
              'pairs=${m.pairs.toString().padLeft(2)}/18 '
              'junk=${m.junk.toString().padLeft(2)} '
              'total=${m.total.toStringAsFixed(2)} '
              'Δ=${m.totalDelta.toStringAsFixed(2)}');
        }
      }

      // Регресс-пороги выбранного пайплайна (bin + removeLines + 2000).
      final c = results['lines-2000/clean']!;
      expect(c.lines, greaterThanOrEqualTo(18),
          reason: 'clean: все строки должны найтись');
      expect(c.totalDelta, lessThan(1.0),
          reason: 'clean: итог обязан сойтись');
      expect(c.pairs, greaterThanOrEqualTo(16),
          reason: 'clean: почти все qty×price пары');
      final p = results['lines-2000/photo']!;
      expect(p.lines, greaterThanOrEqualTo(14),
          reason: 'photo: допускаем потерю пары строк на деградациях');
      expect(p.pairs, greaterThanOrEqualTo(12));
      expect(p.totalDelta, lessThan(150.0),
          reason: 'photo: итог без грубых промахов');

      // Реальные фото (без эталона) — опционально, только число строк.
      final realDir = Platform.environment['OCR_BENCH_PHOTOS'];
      if (realDir != null) {
        final dir = Directory(realDir);
        if (dir.existsSync()) {
          final files = dir
              .listSync()
              .whereType<File>()
              .where((f) => RegExp(r'\.(jpe?g|png)$',
                      caseSensitive: false)
                  .hasMatch(f.path))
              .take(6);
          for (final f in files) {
            print('\n--- real: ${f.uri.pathSegments.last} ---');
            for (final v in variants) {
              final prep = _prepare(f, tmp, v);
              final raw = _tesseract(prep, v.words ? words : plain);
              final lines = TessInvoiceOcr.parseRaw(raw);
              print('${v.name.padRight(9)} lines=${lines.length}');
            }
          }
        }
      }

      tmp.deleteSync(recursive: true);
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: !run
        ? 'skipped: set OCR_BENCH=1 to run'
        : (!exeExists
            ? 'skipped: tesseract.exe not found at $_tessExe'
            : false),
  );
}
