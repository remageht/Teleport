import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/session.dart';
import '../../data/sync/sync_engine.dart';
import '../../main.dart' show pendingShortcut;
import '../clients/clients_screen.dart';
import '../home/dashboard_screen.dart';
import '../home/home_screen.dart';
import '../orders/order_edit_screen.dart';
import '../orders/orders_screen.dart';
import '../shared/app_background.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../warehouse/warehouse_screen.dart';

/// Оболочка приложения: нижняя навигация (5 разделов), синхронизация в AppBar.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    context.read<SyncEngine>().start();
    // Запуск через ярлык с рабочего стола (Новая продажа / Склад).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final a = pendingShortcut;
      pendingShortcut = null;
      if (!mounted || a == null) return;
      if (a == 'action_sale') {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) =>
                    const OrderEditScreen(client: null)));
      } else if (a == 'action_stock') {
        setState(() => _tab = 2);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final sync = context.watch<SyncState>();
    final pages = [
      HomeScreen(onOpenTab: (i) => setState(() => _tab = i)),
      const DashboardScreen(),
      const WarehouseScreen(),
      const OrdersScreen(),
      const ClientsScreen(),
      const ReportsScreen(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(session.userName ?? 'ТелеПорт'),
            Text(
              session.mode == WorkMode.vanSelling
                  ? 'Van-selling · мобильный склад'
                  : 'Pre-selling · сбор заказов',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: sync.pending > 0
                ? 'Синхронизировать (${sync.pending})'
                : 'Синхронизировать',
            onPressed: () => context.read<SyncEngine>().sync(),
            icon: Badge(
              isLabelVisible: sync.pending > 0,
              label: Text('${sync.pending}'),
              child: Icon(sync.syncing
                  ? Icons.sync
                  : sync.lastError != null
                      ? Icons.sync_problem
                      : Icons.sync),
            ),
          ),
          IconButton(
            tooltip: 'Настройки',
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: AppBackground(child: pages[_tab]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const OrderEditScreen(client: null))),
        icon: const Icon(Icons.point_of_sale),
        label: const Text('Продажа'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.storefront_outlined), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.today), label: 'День'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Склад'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'Заказы'),
          NavigationDestination(icon: Icon(Icons.groups), label: 'Клиенты'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'Отчёты'),
        ],
      ),
    );
  }
}
