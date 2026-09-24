import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../data/db/app_db.dart';

/// Экран входа: выбор пользователя + PIN, режим работы, склад, организация.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  List<Map<String, Object?>> _users = [];
  String? _selected;
  final _pinCtrl = TextEditingController();
  WorkMode _mode = WorkMode.preSelling;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = context.read<AppDb>();
    final users = await db.database.query('users');
    final warehouses = await db.database.query('warehouses');
    if (!mounted) return;
    setState(() {
      _users = users;
      if (warehouses.isNotEmpty) {
        // Склад по умолчанию для van-selling — «мобильный склад».
        final van = warehouses.firstWhere(
          (w) => (w['id'] as String).contains('van'),
          orElse: () => warehouses.first,
        );
        _vanWarehouse = van['id'] as String;
      }
    });
  }

  String? _vanWarehouse;

  void _login() async {
    final user = _users.firstWhere((u) => u['id'] == _selected);
    if ((user['pin'] as String?) != _pinCtrl.text.trim()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный PIN')));
      return;
    }
    final db = context.read<AppDb>();
    final orgs = await db.database.query('organizations', limit: 1);
    if (!mounted) return;
    context.read<Session>().login(
          userId: user['id'] as String,
          userName: user['name'] as String,
          role: Role.values.firstWhere(
              (r) => r.name == (user['role'] as String?),
              orElse: () => Role.agent),
          mode: _mode,
          warehouseId: _mode == WorkMode.vanSelling
              ? (_vanWarehouse ?? 'wh-van')
              : 'wh-main',
          organizationId: orgs.isNotEmpty ? orgs.first['id'] as String : null,
        );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.memory, size: 64,
                      color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text('ТелеПорт',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const Text('Мобильная торговля радиокомпонентами',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Пользователь'),
                    items: _users
                        .map((u) => DropdownMenuItem(
                            value: u['id'] as String,
                            child: Text('${u['name']} (${u['role']})')))
                        .toList(),
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<WorkMode>(
                    segments: const [
                      ButtonSegment(
                          value: WorkMode.preSelling,
                          label: Text('Pre-selling'),
                          icon: Icon(Icons.edit_note)),
                      ButtonSegment(
                          value: WorkMode.vanSelling,
                          label: Text('Van-selling'),
                          icon: Icon(Icons.local_shipping)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) =>
                        setState(() => _mode = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'PIN', prefixIcon: Icon(Icons.lock_outline)),
                    onSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: _selected != null ? _login : null,
                    icon: const Icon(Icons.login),
                    label: const Text('Войти'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
