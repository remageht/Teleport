import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/devices.dart';

/// Общий сценарий печати ценников: на десктопе — сразу в файл,
/// на телефоне — шит выбора спаренного Bluetooth-принтера
/// (MAC запоминается).
class PrinterSheet {
  static const _macKey = 'printer_mac';

  static Future<void> printLabels(
    BuildContext context,
    List<({String name, double price, String? barcode})> labels,
  ) async {
    if (labels.isEmpty) return;
    final printer = ReceiptPrinter();
    if (kIsWeb ||
        Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS) {
      final msg = await printer.printLabels(labels);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
    final devices = await printer.scanDevices();
    if (!context.mounted) return;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Нет спаренных принтеров — спарьте в настройках Bluetooth')));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final saved = prefs.getString(_macKey);
    final mac = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  'Принтер для ${labels.length == 1 ? 'ценника' : 'ценников: ${labels.length}'}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final d in devices)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(_nameOf(d)),
                subtitle: Text(_macOf(d)),
                trailing: _macOf(d) == saved
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(c, _macOf(d)),
              ),
          ],
        ),
      ),
    );
    if (mac == null || mac.isEmpty) return;
    final ok = await printer.connect(mac);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не подключился к принтеру')));
      return;
    }
    await prefs.setString(_macKey, mac);
    final msg = await printer.printLabels(labels);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// Печать произвольного текста (Z-отчёт): выбор принтера как у ценников.
  static Future<void> printText(
    BuildContext context,
    String title,
    String text,
  ) async {
    final printer = ReceiptPrinter();
    if (kIsWeb ||
        Platform.isWindows ||
        Platform.isLinux ||
        Platform.isMacOS) {
      final msg = await printer.printText(title, text);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));
      }
      return;
    }
    final devices = await printer.scanDevices();
    if (!context.mounted) return;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Нет спаренных принтеров — спарьте в настройках Bluetooth')));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    if (!context.mounted) return;
    final saved = prefs.getString(_macKey);
    final mac = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title,
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            for (final d in devices)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(_nameOf(d)),
                subtitle: Text(_macOf(d)),
                trailing: _macOf(d) == saved
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () => Navigator.pop(c, _macOf(d)),
              ),
          ],
        ),
      ),
    );
    if (mac == null || mac.isEmpty) return;
    final ok = await printer.connect(mac);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не подключился к принтеру')));
      return;
    }
    await prefs.setString(_macKey, mac);
    final msg = await printer.printText(title, text);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  static String _macOf(String d) {
    final m = RegExp(r'\(([^)]+)\)').firstMatch(d);
    return m?.group(1) ?? d;
  }

  static String _nameOf(String d) {
    final i = d.lastIndexOf('(');
    return i <= 0 ? d : d.substring(0, i).trim();
  }
}
