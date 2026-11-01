import 'package:flutter/material.dart';

/// Нижний лист со сканером штрихкода/QR. На устройствах без камеры
/// (десктоп) предлагает ручной ввод.
Future<String?> showBarcodeScanSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _BarcodeSheet(),
  );
}

class _BarcodeSheet extends StatefulWidget {
  const _BarcodeSheet();
  @override
  State<_BarcodeSheet> createState() => _BarcodeSheetState();
}

class _BarcodeSheetState extends State<_BarcodeSheet> {
  final _manual = TextEditingController();
  final bool _cameraFailed = false;

  @override
  void dispose() {
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        top: 16, left: 16, right: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Сканирование штрихкода',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // Камерный сканер подключается пакетом mobile_scanner:
              // MobileScanner(onDetect: ...) -> Navigator.pop(context, code).
              child: _cameraFailed
                  ? Container(
                      color: Colors.black12,
                      alignment: Alignment.center,
                      child: const Text('Камера недоступна — введите код вручную'),
                    )
                  : const _CameraPlaceholder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _manual,
            decoration: const InputDecoration(
              labelText: 'Код вручную / HID-сканер',
              suffixIcon: Icon(Icons.keyboard),
            ),
            onSubmitted: (v) {
              final trimmed = v.trim();
              Navigator.pop(context, trimmed.isEmpty ? null : trimmed);
            },
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              final trimmed = _manual.text.trim();
              Navigator.pop(context, trimmed.isEmpty ? null : trimmed);
            },
            child: const Text('Принять'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

/// Заглушка виджета камеры; в Android/iOS-сборке заменяется на MobileScanner.
class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black87,
        alignment: Alignment.center,
        child: const Icon(Icons.qr_code_scanner, color: Colors.white70, size: 64),
      );
}
