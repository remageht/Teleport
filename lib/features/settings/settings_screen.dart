import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/session.dart';
import '../../../core/theme_provider.dart';
import '../../../core/app_theme.dart';
import '../../../data/db/app_db.dart';
import '../../../services/lan_sync.dart';
import '../../../services/telegram_backup.dart';
import '../shared/app_background.dart';
import '../prices/price_lists_screen.dart';
import '../receipts/receipts_screen.dart';

/// Настройки: тема, Wi-Fi-синхронизация ПК ⇄ телефон, 1С-шлюз, выход.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _host;
  late final TextEditingController _tgBot;
  late final TextEditingController _tgChat;
  final lan = LanSync();
  String? _myAddress;
  String _syncResult = '';
  String _appVersion = '';
  bool _tgAuto = false;
  int _tgLast = 0;
  bool _tgBusy = false;
  ({int products, int pieces, int orders, double dbMb})? _stats;

  static const _tgBotKey = 'tg_bot';
  static const _tgChatKey = 'tg_chat';
  static const _tgAutoKey = 'tg_auto';
  static const _tgLastKey = 'tg_last';

  @override
  void initState() {
    super.initState();
    _host = TextEditingController();
    _tgBot = TextEditingController();
    _tgChat = TextEditingController();
    _detectAddress();
    _loadVersion();
    _loadStats();
    _loadTg();
  }

  Future<void> _loadTg() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _tgBot.text = p.getString(_tgBotKey) ?? '';
      _tgChat.text = p.getString(_tgChatKey) ?? '';
      _tgAuto = p.getBool(_tgAutoKey) ?? false;
      _tgLast = p.getInt(_tgLastKey) ?? 0;
    });
  }

  Future<void> _saveTg() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_tgBotKey, _tgBot.text.trim());
    await p.setString(_tgChatKey, _tgChat.text.trim());
  }

  String _tgDate() {
    final d =
        DateTime.fromMillisecondsSinceEpoch(_tgLast);
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _sendTgNow() async {
    final dbPath = context.read<AppDb>().dbPath;
    await _saveTg();
    final token = _tgBot.text.trim();
    final chat = _tgChat.text.trim();
    if (token.isEmpty || chat.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Введи токен бота и chat_id')));
      }
      return;
    }
    setState(() => _tgBusy = true);
    try {
      await TelegramBackup.sendDb(
        botToken: token,
        chatId: chat,
        dbPath: dbPath,
      );
      final p = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      await p.setInt(_tgLastKey, now);
      if (mounted) {
        setState(() {
          _tgBusy = false;
          _tgLast = now;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Копия улетела в Telegram')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _tgBusy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _appVersion =
            '${info.version} (${info.buildNumber})');
      }
    } catch (_) {}
  }

  Future<void> _loadStats() async {
    final s = await context.read<AppDb>().storeStats();
    if (mounted) setState(() => _stats = s);
  }

  /// Резервная копия БД: файл в Документы + «Поделиться» на телефоне.
  Future<void> _backup() async {
    final db = context.read<AppDb>();
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dst =
          File(p.join(dir.path, 'teleport_backup_$stamp.db'));
      await dst.writeAsBytes(await File(db.dbPath).readAsBytes());
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
        await Share.shareXFiles([XFile(dst.path)],
            text: 'Копия базы ТелеПорт $stamp');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Копия сохранена: ${dst.path}')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не вышло: $e')));
      }
    }
  }

  /// Восстановить базу из файла копии (.db).
  Future<void> _restore() async {
    final db = context.read<AppDb>();
    const group = XTypeGroup(label: 'База данных', extensions: ['db']);
    final file = await openFile(acceptedTypeGroups: [group]);
    final path = file?.path;
    if (path == null) return;
    if (!mounted) return;
    final ok = await _confirmDestructive(
      title: 'Восстановить из копии?',
      body: 'Текущая база будет заменена содержимым файла.\n'
          'После восстановления перезапустите приложение.',
      actionLabel: 'Восстановить',
    );
    if (!ok) return;
    try {
      await db.restoreFrom(File(path));
      await _loadStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Готово. Перезапустите приложение.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Не вышло: $e')));
      }
    }
  }

  /// Двойная защита от случайного сброса: диалог + чекбокс
  /// «понимаю, что необратимо», кнопка активна только с галочкой.
  Future<bool> _confirmDestructive({
    required String title,
    required String body,
    required String actionLabel,
  }) async {
    var checked = false;
    return await showDialog<bool>(
          context: context,
          builder: (c) => StatefulBuilder(
            builder: (c, setD) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppTheme.brand),
                  const SizedBox(width: 8),
                  Expanded(child: Text(title)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(body),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: () => setD(() => checked = !checked),
                    child: Row(
                      children: [
                        Checkbox(
                          value: checked,
                          activeColor: AppTheme.brand,
                          onChanged: (v) =>
                              setD(() => checked = v ?? false),
                        ),
                        const Expanded(
                          child: Text(
                              'Понимаю, действие необратимо'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Отмена')),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brand),
                  onPressed: checked
                      ? () => Navigator.pop(c, true)
                      : null,
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ) ==
        true;
  }

  @override
  void dispose() {
    // Не гасим сервер при уходе с экрана — им пользуются с другого устройства.
    _host.dispose();
    _tgBot.dispose();
    _tgChat.dispose();
    super.dispose();
  }

  Future<void> _detectAddress() async {
    final ips = await lan.localAddresses();
    if (mounted && ips.isNotEmpty) {
      setState(() => _myAddress = '${ips.first}:${LanSync.port}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: AppBackground(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const _SectionTitle('Оформление'),
            const SizedBox(height: 8),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                ButtonSegment(value: ThemeMode.system, label: Text('Системная')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
              ],
              selected: {theme.mode},
              onSelectionChanged: (s) => context.read<ThemeProvider>().set(s.first),
            ),
            const SizedBox(height: 16),
            const _SectionTitle('Масштаб интерфейса'),
            const SizedBox(height: 4),
            Text(
              '«Мелко» — больше карточек в ряд (планшет/ПК), '
              '«Крупно» — меньше и крупнее (телефон).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Мелко')),
                ButtonSegment(value: 1, label: Text('Обычно')),
                ButtonSegment(value: 2, label: Text('Крупно')),
              ],
              selected: {theme.scale},
              onSelectionChanged: (s) =>
                  context.read<ThemeProvider>().setScale(s.first),
            ),
            const Divider(height: 32),
            const _SectionTitle('Синхронизация ПК ⇄ телефон'),
            const SizedBox(height: 4),
            Text(
              'Оба устройства в одной Wi-Fi сети. На компьютере включите '
              '«Сервер», на телефоне введите его адрес и нажмите «Обменять» '
              '(или наоборот). Передаются товары, остатки, цены, популярность '
              'и заказы.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.dns_outlined),
                title: const Text('Сервер синхронизации'),
                subtitle: Text(_myAddress != null
                    ? 'Мой адрес: $_myAddress'
                    : 'Определяю адрес...'),
                value: lan.isServer,
                onChanged: (v) async {
                  if (v) {
                    await lan.startServer(context.read<AppDb>());
                  } else {
                    await lan.stopServer();
                  }
                  setState(() {});
                },
              ),
            ),
            ValueListenableBuilder<String>(
              valueListenable: lan.status,
              builder: (_, s, __) => s.isEmpty
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(s, style: Theme.of(context).textTheme.bodySmall),
                    ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _host,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText:
                    'Адрес другой стороны, например 192.168.1.50:${LanSync.port}',
                prefixIcon: Icon(Icons.smartphone),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                final db = context.read<AppDb>();
                final msg = await lan.syncWith(db, _host.text);
                setState(() => _syncResult = msg);
              },
              icon: const Icon(Icons.sync),
              label: const Text('Обменять данные'),
            ),
            if (_syncResult.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(_syncResult, textAlign: TextAlign.center),
              ),
            const Divider(height: 32),
            const _SectionTitle('Магазин и данные'),
            const SizedBox(height: 4),
            Text(
              'Сколько товара в базе, копия базы перед важным днём, '
              'очистка тестовых продаж перед живой работой.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _stats == null
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceAround,
                        children: [
                          _StatNum('${_stats!.products}', 'позиций'),
                          _StatNum('${_stats!.pieces}', 'штук'),
                          _StatNum('${_stats!.orders}', 'заказов'),
                          _StatNum(
                              '${_stats!.dbMb.toStringAsFixed(1)} МБ',
                              'база'),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _backup,
              icon: const Icon(Icons.backup_outlined),
              label: const Text('Резервная копия базы'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _restore,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('Восстановить из копии'),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.telegram_outlined),
                        const SizedBox(width: 8),
                        Text('Копия в Telegram',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Бот из BotFather, добавить в группу админом. '
                      'chat_id — через @getmyid_bot.',
                      style:
                          Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tgBot,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'Токен бота',
                          prefixIcon: Icon(Icons.key_outlined)),
                      onChanged: (_) => _saveTg(),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tgChat,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'chat_id группы',
                          prefixIcon:
                              Icon(Icons.group_outlined)),
                      onChanged: (_) => _saveTg(),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Автокопия раз в сутки'),
                      subtitle: Text(_tgLast == 0
                          ? 'ещё не отправлялось'
                          : 'последняя: ${_tgDate()}'),
                      value: _tgAuto,
                      onChanged: (v) async {
                        final p =
                            await SharedPreferences.getInstance();
                        await p.setBool(_tgAutoKey, v);
                        setState(() => _tgAuto = v);
                      },
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.tonalIcon(
                        onPressed:
                            _tgBusy ? null : _sendTgNow,
                        icon: _tgBusy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(
                                        strokeWidth: 2))
                            : const Icon(Icons.send_outlined),
                        label: Text(_tgBusy
                            ? 'Отправляю…'
                            : 'Отправить копию сейчас'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PriceListsScreen())),
              icon: const Icon(Icons.discount_outlined),
              label: const Text('Прайсы и скидки'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ReceiptsScreen())),
              icon:
                  const Icon(Icons.receipt_long_outlined),
              label: const Text('Накладные поставщиков'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final db = context.read<AppDb>();
                      final ok = await _confirmDestructive(
                        title: 'Обнулить «Часто берут»?',
                        body: 'Счётчики популярности всех товаров станут '
                            'нулевыми. Сами товары, остатки и цены не тронуты.',
                        actionLabel: 'Сбросить',
                      );
                      if (!ok) return;
                      await db.resetPopularity();
                      await _loadStats();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Популярность обнулена')));
                      }
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Сбросить топ'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.brand),
                    onPressed: () async {
                      final db = context.read<AppDb>();
                      final ok = await _confirmDestructive(
                        title: 'Удалить все заказы?',
                        body: 'Заказы, их строки и оплаты будут удалены '
                            'безвозвратно. Товары и остатки не тронуты.',
                        actionLabel: 'Удалить',
                      );
                      if (!ok) return;
                      await db.clearOrders();
                      await _loadStats();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('Заказы удалены')));
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Очистить заказы'),
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Выйти'),
              onTap: () {
                context.read<Session>().logout();
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 12),
            Center(
              child: Text(
                _appVersion.isEmpty
                    ? 'ТелеПорт'
                    : 'ТелеПорт • v$_appVersion',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Крупная цифра сводки («позиций / штук / заказов / база»).
class _StatNum extends StatelessWidget {
  final String value;
  final String label;
  const _StatNum(this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// Заголовок раздела с фирменной красной плашкой слева.
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: AppTheme.brand,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            )),
      ],
    );
  }
}
