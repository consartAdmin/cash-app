import 'package:flutter/material.dart';

import 'api_service.dart';
import 'lookups.dart';
import 'models.dart';
import 'movement_detail_page.dart';
import 'ui.dart';

/// Início: saldo do mês, saldo por conta e últimos lançamentos.
class DashboardPage extends StatefulWidget {
  final VoidCallback onSeeAll;
  const DashboardPage({super.key, required this.onSeeAll});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Period _period = Period.currentMonth();
  List<Movement> _moves = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    dataChanged.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    dataChanged.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = MoveFilter(period: _period);
      final r = await Future.wait([
        ApiService.instance.movements(f),
        Lookups.instance.load(),
      ]);
      if (!mounted) return;
      setState(() => _moves = (r[0] as (List<Movement>, int)).$1);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setPeriod(Period p) {
    _period = p;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _moves.isEmpty) {
      return Center(child: ErrorView(_error!, onRetry: _load));
    }
    final theme = Theme.of(context);
    final real = _moves.where((m) => !m.isTransfer);
    final entradas = real
        .where((m) => m.type == MoveType.entrada)
        .fold<double>(0, (a, m) => a + m.total);
    final saidas = real
        .where((m) => m.type == MoveType.saida)
        .fold<double>(0, (a, m) => a + m.total);
    final byAccount = balanceByAccount(_moves);
    final accounts = Lookups.instance.accounts;
    // Contas com movimento que não estão no cadastro também aparecem.
    final names = <String>[
      ...accounts.map((a) => a.name),
      ...byAccount.keys.where((k) =>
          k.isNotEmpty && !accounts.any((a) => a.matches(k))),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          PeriodBar(period: _period, onChanged: _setPeriod),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Card(
            color: theme.colorScheme.primary,
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle(
                style: TextStyle(color: theme.colorScheme.onPrimary),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Saldo do período (todas as contas)',
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onPrimary
                                .withValues(alpha: 0.8))),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(money(entradas - saidas),
                          style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onPrimary)),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(child: _heroStat('Entradas', entradas)),
                      Expanded(child: _heroStat('Saídas', saidas)),
                    ]),
                  ],
                ),
              ),
            ),
          ),
          if (names.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 2.6,
                children: [
                  for (final n in names)
                    _AccountTile(n, byAccount[n.trim().toUpperCase()] ?? 0),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
            child: Row(children: [
              Text('Últimos lançamentos',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                  onPressed: widget.onSeeAll, child: const Text('Ver todos')),
            ]),
          ),
          if (!_loading && _moves.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Nenhum lançamento no período.',
                  textAlign: TextAlign.center),
            ),
          for (final m in _moves.take(10))
            MovementTile(m,
                showDate: true,
                onTap: () => openMovement(context, m)),
        ],
      ),
    );
  }

  Widget _heroStat(String label, double v) {
    final c = Theme.of(context).colorScheme.onPrimary;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, color: c)),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(money(v),
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: c)),
      ),
    ]);
  }
}

class _AccountTile extends StatelessWidget {
  final String name;
  final double value;
  const _AccountTile(this.name, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              Icon(accountIcon(name),
                  size: 15, color: theme.colorScheme.primary),
              const SizedBox(width: 5),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
              ),
            ]),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(value),
                  style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: value < 0 ? outColor : null)),
            ),
          ],
        ),
      ),
    );
  }
}

IconData accountIcon(String name) {
  final n = name.toUpperCase();
  if (n.contains('ESP') || n.contains('DINHEIRO') || n.contains('CAIXA')) {
    return Icons.payments_outlined;
  }
  return Icons.account_balance_outlined;
}

Future<void> openMovement(BuildContext context, Movement m) {
  return Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => MovementDetailPage(movement: m),
  ));
}
