import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Голосовой ввод для поиска: надиктовать название товара.
/// Работает только на телефоне (системное распознавание речи),
/// на ПК и в вебе показывает заглушку. Возвращает текст или null.
Future<String?> showVoiceSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _VoiceSheet(),
  );
}

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();
  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final _stt = SpeechToText();
  String _text = '';
  String? _error;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
      if (mounted) {
        setState(() =>
            _error = 'Голосовой поиск работает только на телефоне');
      }
      return;
    }
    bool ok = false;
    try {
      ok = await _stt.initialize(
        onStatus: (s) {
          if (mounted) {
            setState(
                () => _listening = s == 'listening');
          }
        },
        onError: (e) {
          if (mounted) {
            setState(() {
              _listening = false;
              _error = 'Не слышу: ${e.errorMsg}';
            });
          }
        },
      );
    } catch (e) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      setState(() => _error =
          'Распознавание недоступно (нет микрофона или сервиса речи)');
      return;
    }
    await _listen();
  }

  Future<void> _listen() async {
    if (!_stt.isAvailable) return;
    setState(() {
      _error = null;
      _listening = true;
    });
    try {
      await _stt.listen(
        listenOptions: SpeechListenOptions(
            localeId: 'ru_RU', partialResults: true),
        onResult: (r) {
          if (mounted) setState(() => _text = r.recognizedWords);
        },
      );
    } catch (_) {
      // Нет русской локали — пробуем системную.
      try {
        await _stt.listen(
          listenOptions:
              SpeechListenOptions(partialResults: true),
          onResult: (r) {
            if (mounted) setState(() => _text = r.recognizedWords);
          },
        );
      } catch (e) {
        if (mounted) {
          setState(() {
            _listening = false;
            _error = 'Не вышло слушать: $e';
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _stt.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _listening
                    ? Colors.red.withValues(alpha: 0.15)
                    : Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest,
              ),
              child: Icon(
                _listening ? Icons.mic : Icons.mic_none_outlined,
                size: 40,
                color: _listening
                    ? Colors.red
                    : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _error ??
                  (_text.isEmpty
                      ? (_listening
                          ? 'Слушаю… говорите название'
                          : 'Нажмите микрофон и говорите')
                      : '«$_text»'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _listening ? null : _listen,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Ещё раз'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _text.trim().isEmpty
                        ? null
                        : () =>
                            Navigator.pop(context, _text.trim()),
                    icon: const Icon(Icons.search),
                    label: const Text('Найти'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
