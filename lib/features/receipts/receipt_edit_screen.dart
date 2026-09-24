import 'dart:io';

import 'package:excel/excel.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../../data/db/app_db.dart';
import '../../../models/catalog.dart';
import '../../../services/invoice_photo_ocr.dart';
import '../shared/app_background.dart';

/// Строка накладной на этапе разбора.
class _ImpLine {
  String rawName;
  double qty;
  double price;
  Product? exact;
  List<Product> candidates = const [];
  String pick = 'new'; // id товара или 'new'
  _ImpLine({
    required this.rawName,
    required this.qty,
    required this.price,
  });
}

/// Новая накладная: Excel поставщика или ручные строки,
/// склейка дублей (точное совпадение плюсуется, похожее — на выбор),
/// проведение в остатки + история + фото бумажной накладной.
class ReceiptEditScreen extends StatefulWidget {
  const ReceiptEditScreen({super.key});
  @override
  State<ReceiptEditScreen> createState() => _ReceiptEditScreenState();
}

class _ReceiptEditScreenState extends State<ReceiptEditScreen> {
  String? _fileName;
  List<String> _headers = [];
  List<List<String>> _rawRows = [];
  int _nameIdx = -1, _qtyIdx = -1, _priceIdx = -1, _sumIdx = -1;
  final List<_ImpLine> _lines = [];
  bool _recognized = false;
  bool _busy = false;
  final _supplier = TextEditingController();
  final _number = TextEditingController();
  String? _photoPath;

  @override
  void dispose() {
    _supplier.dispose();
    _number.dispose();
    super.dispose();
  }

  double _num(String s) {
    final t = s
        .replaceAll(RegExp(r'[^0-9.,-]'), '')
        .replaceAll(',', '.');
    if (t.isEmpty || t == '-' || t == '.') return 0;
    return double.tryParse(t) ?? 0;
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(
        label: 'Накладная Excel',
        extensions: ['xlsx', 'xls', 'csv']);
    final f = await openFile(acceptedTypeGroups: [group]);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('В файле нет листов')));
      }
      return;
    }
    // Самый большой лист — это накладная.
    var best = excel.tables.entries.first;
    for (final e in excel.tables.entries) {
      if ((e.value.rows.length) > (best.value.rows.length)) {
        best = e;
      }
    }
    final rows = best.value.rows;
    // Шапка — первая строка с 2+ непустыми ячейками.
    var headerAt = 0;
    for (var i = 0; i < rows.length && i < 10; i++) {
      final nonEmpty =
          rows[i].where((c) => '${c?.value ?? ''}'.trim().isNotEmpty);
      if (nonEmpty.length >= 2) {
        headerAt = i;
        break;
      }
    }
    final headers = rows[headerAt]
        .map((c) => '${c?.value ?? ''}'.trim())
        .toList();
    final data = <List<String>>[];
    for (var i = headerAt + 1; i < rows.length; i++) {
      data.add(rows[i].map((c) => '${c?.value ?? ''}'.trim()).toList());
    }
    setState(() {
      _fileName = f.name;
      _headers = headers;
      _rawRows = data;
      _recognized = false;
      _lines.clear();
    });
    _automap();
    _rebuildLines();
  }

  void _automap() {
    int find(List<String> keys, {List<String>? skip}) {
      for (var i = 0; i < _headers.length; i++) {
        final h = _headers[i].toLowerCase();
        if (skip != null && skip.any(h.contains)) continue;
        if (keys.any(h.contains)) return i;
      }
      return -1;
    }

    _sumIdx = find(['сумм', 'итого', 'всего', 'стоимость', 'total']);
    _priceIdx = find(['цена', 'закуп', 'price'], skip: ['сумм', 'итого']);
    _qtyIdx = find(
        ['кол-во', 'кол во', 'колич', 'к-во', 'кво', 'шт', 'qty']);
    _nameIdx = find(
        ['наимен', 'назван', 'товар', 'номенклат', 'позиц', 'продукц']);
    if (_nameIdx < 0 && _headers.isNotEmpty) _nameIdx = 0;
  }

  void _rebuildLines() {
    _lines.clear();
    if (_nameIdx < 0) return;
    for (final r in _rawRows) {
      String cell(int i) =>
          (i >= 0 && i < r.length) ? r[i] : '';
      final name = cell(_nameIdx);
      if (name.isEmpty) continue;
      final qty = _qtyIdx >= 0 ? _num(cell(_qtyIdx)) : 1.0;
      if (qty <= 0) continue;
      double price = 0;
      if (_priceIdx >= 0) {
        price = _num(cell(_priceIdx));
      } else if (_sumIdx >= 0) {
        price = _num(cell(_sumIdx)) / qty;
      }
      _lines.add(_ImpLine(rawName: name, qty: qty, price: price));
    }
    setState(() => _recognized = false);
  }

  /// Сопоставить строки с базой: точное — автоматом, похожее — на выбор.
  Future<void> _recognize() async {
    final db = context.read<AppDb>();
    setState(() => _busy = true);
    for (final l in _lines) {
      final m = await db.matchProduct(l.rawName);
      l.exact = m.exact;
      l.candidates = m.similar;
      l.pick = m.exact?.id ?? 'new';
    }
    if (mounted) {
      setState(() {
        _recognized = true;
        _busy = false;
      });
    }
  }

  void _addManualLine() {
    setState(() {
      _lines.add(_ImpLine(rawName: '', qty: 1, price: 0));
      _recognized = false;
    });
  }

  Future<String> _persistPhoto(String srcPath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/invoices');
      if (!await dir.exists()) await dir.create(recursive: true);
      final dest =
          '${dir.path}/rc_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(srcPath).copy(dest);
      return dest;
    } catch (_) {
      return srcPath;
    }
  }

  Future<void> _pickPhoto() async {
    try {
      final x =
          await ImagePicker().pickImage(source: ImageSource.camera);
      if (x == null) return;
      final saved = await _persistPhoto(x.path);
      setState(() => _photoPath = saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Камера недоступна: $e')));
      }
    }
  }

  /// Распознать позиции с фото: OCR -> строки -> общий матчинг с базой.
  /// Кириллицу может кривить — строки правятся руками перед проведением.
  /// Галерея идёт через системный файловый picker: на части прошивок
  /// штатная галерея image_picker падает с PlatformException.
  Future<void> _ocrPhoto() async {
    final src = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Фото накладной'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Снять камерой'),
              onTap: () => Navigator.pop(c, 'camera'),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library_outlined),
              title: const Text('Выбрать файл'),
              onTap: () => Navigator.pop(c, 'file'),
            ),
          ],
        ),
      ),
    );
    if (src == null) return;
    String? path;
    try {
      if (src == 'camera') {
        final x = await ImagePicker()
            .pickImage(source: ImageSource.camera);
        path = x?.path;
      } else {
        const group = XTypeGroup(
            label: 'Фото', extensions: ['jpg', 'jpeg', 'png']);
        final f =
            await openFile(acceptedTypeGroups: [group]);
        path = f?.path;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не вышло взять фото: $e')));
      }
      return;
    }
    if (path == null) return;
    setState(() => _busy = true);
    List<OcrLine> found = [];
    String? docNum;
    String? docSup;
    try {
      final res = await InvoicePhotoOcr.recognizeFull(path);
      found = res.lines;
      docNum = res.number;
      docSup = res.supplier;
    } catch (e) {
      found = [];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не распозналось: $e')));
      }
    }
    if (!mounted) return;
    final saved = await _persistPhoto(path);
    setState(() {
      _busy = false;
      _photoPath = saved;
      if (_number.text.trim().isEmpty && docNum != null) {
        _number.text = docNum;
      }
      if (_supplier.text.trim().isEmpty && docSup != null) {
        _supplier.text = docSup;
      }
      for (final f in found) {
        _lines.add(_ImpLine(
            rawName: f.name, qty: f.qty, price: f.price));
      }
      _recognized = false;
    });
    if (mounted && found.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Строк с фото: ${found.length} — проверь и жми «Распознать позиции»')));
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Позиций не нашёл — попробуй чётче фото или вбей вручную')));
    }
  }

  double get _total =>
      _lines.fold(0, (s, l) => s + l.qty * l.price);

  Future<void> _conduct() async {
    for (final l in _lines) {
      if (l.rawName.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Есть строки без названия')));
        }
        return;
      }
      if (l.qty <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('«${l.rawName}»: количество?')));
        }
        return;
      }
    }
    if (_lines.isEmpty) return;
    final db = context.read<AppDb>();
    setState(() => _busy = true);
    final rid = await db.createReceipt(
      number:
          _number.text.trim().isEmpty ? null : _number.text.trim(),
      supplier: _supplier.text.trim().isEmpty
          ? null
          : _supplier.text.trim(),
      photoPath: _photoPath,
    );
    for (final l in _lines) {
      String pid;
      if (l.pick == 'new') {
        final created = await db.addProduct(
          name: l.rawName.trim(),
          qty: 0,
        );
        pid = created.id;
      } else {
        pid = l.pick;
      }
      await db.receiveGoods(
        productId: pid,
        qty: l.qty,
        buyPrice: l.price,
        note: [
          if (_supplier.text.trim().isNotEmpty)
            _supplier.text.trim(),
          if (_number.text.trim().isNotEmpty)
            'накл. ${_number.text.trim()}',
        ].join(', '),
        receiptId: rid,
      );
    }
    if (mounted) {
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Принято: ${_lines.length} поз. на ${_total.toStringAsFixed(0)} ₽')));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новая накладная')),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _busy ? null : _pickFile,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(_fileName ?? 'Excel поставщика'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Строка вручную',
                  onPressed: _busy ? null : _addManualLine,
                  icon: const Icon(Icons.add),
                ),
                IconButton.filledTonal(
                  tooltip: 'Фото бумажной накладной',
                  onPressed: _busy ? null : _pickPhoto,
                  icon: Icon(_photoPath == null
                      ? Icons.photo_camera_outlined
                      : Icons.check_circle),
                ),
                IconButton.filledTonal(
                  tooltip: 'Распознать позиции с фото',
                  onPressed: _busy ? null : _ocrPhoto,
                  icon: const Icon(
                      Icons.document_scanner_outlined),
                ),
              ],
            ),
            if (_photoPath != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(_photoPath!), height: 140,
                    width: double.infinity, fit: BoxFit.cover),
              ),
            ],
            // Сопоставление колонок.
            if (_headers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Колонки файла',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _mapRow('Название', _nameIdx,
                          (v) => setState(() {
                                _nameIdx = v ?? -1;
                                _rebuildLines();
                              })),
                      _mapRow('Кол-во', _qtyIdx,
                          (v) => setState(() {
                                _qtyIdx = v ?? -1;
                                _rebuildLines();
                              })),
                      _mapRow('Цена', _priceIdx,
                          (v) => setState(() {
                                _priceIdx = v ?? -1;
                                _rebuildLines();
                              })),
                      _mapRow('Сумма', _sumIdx,
                          (v) => setState(() {
                                _sumIdx = v ?? -1;
                                _rebuildLines();
                              })),
                      const SizedBox(height: 4),
                      Text('Строк: ${_lines.length}',
                          style:
                              Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
            if (_lines.isNotEmpty && !_recognized) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _recognize,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2))
                    : const Icon(Icons.search),
                label: Text(_busy
                    ? 'Сопоставляю…'
                    : 'Распознать позиции (${_lines.length})'),
              ),
            ],
            // Строки с результатом сопоставления.
            for (var i = 0; i < _lines.length; i++) ...[
              const SizedBox(height: 8),
              _LineCard(
                line: _lines[i],
                recognized: _recognized,
                onName: (v) => _lines[i].rawName = v,
                onQty: (v) => _lines[i].qty = v,
                onPrice: (v) => _lines[i].price = v,
                onPick: (v) => setState(() => _lines[i].pick = v),
                onDelete: () =>
                    setState(() => _lines.removeAt(i)),
              ),
            ],
            if (_lines.isNotEmpty) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _supplier,
                decoration: const InputDecoration(
                    labelText: 'Поставщик',
                    prefixIcon: Icon(Icons.local_shipping_outlined)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _number,
                decoration: const InputDecoration(
                    labelText: 'Номер накладной',
                    prefixIcon: Icon(Icons.tag_outlined)),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed:
                    (_busy || !_recognized && _fileName != null)
                        ? null
                        : _conduct,
                icon: const Icon(Icons.check),
                label: Text(
                    'Провести приёмку · ${_total.toStringAsFixed(0)} ₽'),
              ),
              const SizedBox(height: 4),
              Text(
                _fileName != null && !_recognized
                    ? 'Сначала «Распознать позиции»'
                    : 'Точные совпадения плюсуются к существующим, новые создаются',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _mapRow(
      String label, int value, ValueChanged<int?> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              items: [
                const DropdownMenuItem(
                    value: -1, child: Text('— нет —')),
                for (var i = 0; i < _headers.length; i++)
                  DropdownMenuItem(
                    value: i,
                    child: Text(
                        _headers[i].isEmpty ? 'Кол. ${i + 1}' : _headers[i],
                        overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Карточка строки: название, кол-во, цена, результат сопоставления.
class _LineCard extends StatefulWidget {
  final _ImpLine line;
  final bool recognized;
  final ValueChanged<String> onName;
  final ValueChanged<double> onQty;
  final ValueChanged<double> onPrice;
  final ValueChanged<String> onPick;
  final VoidCallback onDelete;
  const _LineCard({
    required this.line,
    required this.recognized,
    required this.onName,
    required this.onQty,
    required this.onPrice,
    required this.onPick,
    required this.onDelete,
  });
  @override
  State<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends State<_LineCard> {
  late final TextEditingController _name;
  late final TextEditingController _qty;
  late final TextEditingController _price;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.line.rawName);
    _qty = TextEditingController(
        text: widget.line.qty.toStringAsFixed(
            widget.line.qty % 1 == 0 ? 0 : 2));
    _price = TextEditingController(
        text: widget.line.price.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    super.dispose();
  }

  double _p(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final l = widget.line;
    final isDup = widget.recognized && l.pick != 'new';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                        labelText: 'Название в накладной'),
                    onChanged: widget.onName,
                  ),
                ),
                IconButton(
                  tooltip: 'Убрать строку',
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _qty,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Кол-во'),
                    onChanged: (v) => widget.onQty(_p(v)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(
                            decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Закупка, ₽'),
                    onChanged: (v) =>
                        widget.onPrice(_p(v)),
                  ),
                ),
              ],
            ),
            if (widget.recognized) ...[
              const SizedBox(height: 6),
              if (isDup)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Найден в базе — количество плюсуется',
                    style: TextStyle(
                        color: Colors.green.shade800,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                )
              else
                DropdownButton<String>(
                  value: l.pick,
                  isExpanded: true,
                  items: [
                    if (l.exact != null)
                      DropdownMenuItem(
                        value: l.exact!.id,
                        child: Text(
                            '→ ${l.exact!.name} (в базе)',
                            overflow: TextOverflow.ellipsis),
                      ),
                    for (final c in l.candidates)
                      if (c.id != l.exact?.id)
                        DropdownMenuItem(
                          value: c.id,
                          child: Text('→ ${c.name}',
                              overflow: TextOverflow.ellipsis),
                        ),
                    const DropdownMenuItem(
                        value: 'new',
                        child: Text('+ Новый товар')),
                  ],
                  onChanged: (v) {
                    if (v != null) widget.onPick(v);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
