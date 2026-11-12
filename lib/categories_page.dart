import 'package:flutter/material.dart';

import 'api_service.dart';
import 'lookups.dart';
import 'models.dart';
import 'ui.dart';

/// Totais do período por categoria (sem transferências).
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  Period _period = Period.currentMonth();
  int? _accountId;
  List<CategoryTotal> _totals = const [];
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
      await Lookups.instance.load();
      final (list, _) = await ApiService.instance
          .movements(MoveFilter(period: _period, accountId: _accountId));
      if (!mounted) return;
      setState(() => _totals = totalsByCategory(list));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entradas = _totals.fold<double>(0, (a, t) => a + t.entradas);
    final saidas = _totals.fold<double>(0, (a, t) => a + t.saidas);
    final accounts = Lookups.instance.accounts;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          PeriodBar(
              period: _period,
              onChanged: (p) {
                _period = p;
                _load();
              }),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: const Text('Todas as contas'),
                    selected: _accountId == null,
                    onSelected: (_) {
                      _accountId = null;
                      _load();
                    },
                  ),
                ),
                for (final a in accounts)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(a.name),
                      selected: _accountId == a.id,
                      onSelected: (_) {
                        _accountId = a.id;
                        _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(children: [
              MiniStat('Entradas', entradas, color: inColor),
              const SizedBox(width: 6),
              MiniStat('Saídas', saidas, color: outColor),
              const SizedBox(width: 6),
              MiniStat('Resultado', entradas - saidas),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            ErrorView(_error!, onRetry: _load)
          else if (!_loading && _totals.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nenhum lançamento no período.',
                  textAlign: TextAlign.center),
            ),
          for (final t in _totals)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              clipBehavior: Clip.antiAlias,
              child: ExpansionTile(
                shape: const Border(),
                title: Text(t.name,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w500)),
                subtitle: _Bar(
                    value: t.entradas + t.saidas,
                    max: _totals.isEmpty
                        ? 1
                        : _totals.first.entradas + _totals.first.saidas,
                    color: t.saldo >= 0 ? inColor : outColor,
                    caption:
                        '${t.count} lançamento${t.count == 1 ? '' : 's'}'),
                trailing: Text(
                    '${t.saldo > 0 ? '+' : ''}${money(t.saldo)}',
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: t.saldo >= 0 ? inColor : outColor)),
                children: [
                  for (final e in (t.subs.entries.toList()
                    ..sort((a, b) => a.value.abs() > b.value.abs() ? -1 : 1)))
                    ListTile(
                      dense: true,
                      title: Text(e.key),
                      trailing: Text(money(e.value),
                          style: TextStyle(
                              color: e.value >= 0 ? inColor : outColor)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double value;
  final double max;
  final Color color;
  final String caption;
  const _Bar(
      {required this.value,
      required this.max,
      required this.color,
      required this.caption});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: max <= 0 ? 0 : (value / max).clamp(0, 1),
            minHeight: 5,
            color: color,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        const SizedBox(height: 3),
        Text(caption, style: theme.textTheme.bodySmall),
      ]),
    );
  }
}
