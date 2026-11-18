import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/calendar/calendar_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/shopping/shopping_lists_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/transactions/transaction_form_screen.dart';
import '../features/transactions/transactions_screen.dart';
import 'providers.dart';

/// Estructura principal: cinco pestañas con barra inferior y botón +.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with SingleTickerProviderStateMixin {
  late final AppLifecycleListener _lifecycle;

  // Fundido suave al cambiar de pestaña. Se anima el IndexedStack entero (sin
  // reconstruirlo), así cada pestaña conserva su scroll y su estado.
  late final AnimationController _tabFade =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  late final Animation<double> _tabCurve = CurvedAnimation(parent: _tabFade, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // Genera los movimientos recurrentes al abrir la app y al volver a ella.
    _lifecycle = AppLifecycleListener(onResume: _generateRecurring);
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateRecurring());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _tabFade.dispose();
    super.dispose();
  }

  Future<void> _generateRecurring() async {
    try {
      await ref.read(recurringRepoProvider).generateDue();
    } catch (e) {
      debugPrint('Error generando recurrentes: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(selectedTabProvider);
    // En Compra el botón + vive dentro de su propia pantalla.
    final showFab = index != 4;
    ref.listen(selectedTabProvider, (previous, next) {
      if (previous != next && !MediaQuery.disableAnimationsOf(context)) _tabFade.forward(from: 0);
    });

    return Scaffold(
      body: FadeTransition(
        opacity: _tabCurve,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.012), end: Offset.zero).animate(_tabCurve),
          child: IndexedStack(
            index: index,
            children: const [
              DashboardScreen(),
              TransactionsScreen(),
              CalendarScreen(),
              StatsScreen(),
              ShoppingListsScreen(),
            ],
          ),
        ),
      ),
      floatingActionButton: showFab
          ? FloatingActionButton(
              tooltip: 'Nuevo movimiento',
              onPressed: () {
                final date = index == 2 ? ref.read(calendarDayProvider) : null;
                openTransactionForm(context, date: date);
              },
              child: const Icon(Icons.add_rounded, size: 30),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: ref.read(selectedTabProvider.notifier).select,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Inicio'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Movimientos'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Calendario'),
          NavigationDestination(icon: Icon(Icons.pie_chart_outline), selectedIcon: Icon(Icons.pie_chart), label: 'Estadísticas'),
          NavigationDestination(
              icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: 'Compra'),
        ],
      ),
    );
  }
}
