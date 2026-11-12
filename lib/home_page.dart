import 'package:flutter/material.dart';

import 'api_service.dart';
import 'categories_page.dart';
import 'dashboard_page.dart';
import 'login_page.dart';
import 'movement_form_page.dart';
import 'movements_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;
  final _opened = <int>{0};

  void _open(int i) => setState(() {
        _tab = i;
        _opened.add(i);
      });

  static const _titles = ['Caixa', 'Movimentos', 'Categorias'];

  Future<void> _logout() async {
    await ApiService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
  }

  void _newEntry() {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const MovementFormPage(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final api = ApiService.instance;
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(api.userName ?? '',
                    style: Theme.of(context).textTheme.bodySmall),
              ),
              const PopupMenuItem(value: 'logout', child: Text('Sair')),
            ],
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          DashboardPage(onSeeAll: () => _open(1)),
          _opened.contains(1) ? const MovementsPage() : const SizedBox(),
          _opened.contains(2) ? const CategoriesPage() : const SizedBox(),
        ],
      ),
      floatingActionButton: _tab == 2
          ? null
          : FloatingActionButton.extended(
              onPressed: _newEntry,
              icon: const Icon(Icons.add),
              label: const Text('Lançar'),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _open,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined), label: 'Início'),
          NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined), label: 'Movimentos'),
          NavigationDestination(
              icon: Icon(Icons.pie_chart_outline), label: 'Categorias'),
        ],
      ),
    );
  }
}
