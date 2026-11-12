import 'package:flutter/material.dart';

import 'api_service.dart';
import 'debt_detail_page.dart';
import 'debts_models.dart';
import 'lookups.dart';
import 'models.dart';
import 'ui.dart';

/// Aba Dívidas: resumo, busca/filtro e lista das dívidas com progresso.
class DebtsPage extends StatefulWidget {
  const DebtsPage({super.key});

  @override
  State<DebtsPage> createState() => _DebtsPageState();
}

/// Filtro rápido da lista.
enum _Show { abertas, vencidas, pagas, todas }

class _DebtsPageState extends State<DebtsPage> {
  final _api = ApiService.instance;
  List<Debt> _debts = const [];
  DebtsSummary _summary = const DebtsSummary();
  _Show _show = _Show.abertas;
  String _search = '';
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
      final r = await Future.wait([
        _api.debts(
          search: _search,
          onlyOpen: _show == _Show.abertas || _show == _Show.vencidas,
          status: _show == _Show.pagas ? DebtStatus.pago : null,
        ),
        _api.debtsSummary().catchError((_) => const DebtsSummary()),
        Lookups.instance.load().catchError((_) {}),
      ]);
      if (!mounted) return;
      var list = r[0] as List<Debt>;
      if (_show == _Show.vencidas) {
        list = list
            .where((d) => d.displayStatus == DebtStatus.vencido)
            .toList();
      }
      setState(() {
        _debts = list;
        _summary = r[1] as DebtsSummary;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Debt d) {
    Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DebtDetailPage(debtId: d.id)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openSum = _debts.fold<double>(0, (a, d) => a + d.open);
    final paidSum = _debts.fold<double>(0, (a, d) => a + d.paid);
    final totalSum = _debts.fold<double>(0, (a, d) => a + d.total);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          Card(
            color: theme.colorScheme.primary,
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _heroLabel(context, 'Saldo em aberto (todas as dívidas)'),
                  const SizedBox(height: 2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(money(_summary.totalOpen),
                        style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onPrimary)),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                        child: _heroStat(context, 'Vencido',
                            money(_summary.totalOverdue))),
                    Expanded(
                        child: _heroStat(context, 'Dívidas em aberto',
                            '${_summary.countOpen}'
                            '${_summary.countOverdue > 0 ? ' · ${_summary.countOverdue} vencidas' : ''}')),
                  ]),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SearchField(
              hint: 'Buscar credor, descrição, nº doc...',
              onSubmit: (s) {
                _search = s;
                _load();
              },
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(children: [
              for (final s in _Show.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(switch (s) {
                      _Show.abertas => 'Em aberto',
                      _Show.vencidas => 'Vencidas',
                      _Show.pagas => 'Pagas',
                      _Show.todas => 'Todas',
                    }),
                    selected: _show == s,
                    onSelected: (_) {
                      setState(() => _show = s);
                      _load();
                    },
                  ),
                ),
            ]),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_debts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              child: Row(children: [
                MiniStat('Total', totalSum),
                const SizedBox(width: 6),
                MiniStat('Pago', paidSum, color: inColor),
                const SizedBox(width: 6),
                MiniStat('Em aberto', openSum, color: outColor),
              ]),
            ),
          if (_error != null && _debts.isEmpty)
            ErrorView(_error!, onRetry: _load)
          else if (!_loading && _debts.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nenhuma dívida encontrada.')),
            ),
          for (final d in _debts) DebtTile(d, onTap: () => _open(d)),
        ],
      ),
    );
  }
}

Widget _heroLabel(BuildContext context, String text) => Text(text,
    style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.8)));

Widget _heroStat(BuildContext context, String label, String value) {
  final c = Theme.of(context).colorScheme.onPrimary;
  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    _heroLabel(context, label),
    FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(value,
          style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, color: c)),
    ),
  ]);
}

/// Cores do selo de status.
(Color, Color) debtStatusColors(DebtStatus s) => switch (s) {
      DebtStatus.vencido => (const Color(0xFFFDE3E3), outColor),
      DebtStatus.parcial => (const Color(0xFFFFF1D6), const Color(0xFFA35A00)),
      DebtStatus.pago => (const Color(0xFFDFF3E2), inColor),
      DebtStatus.emAberto => (const Color(0xFFE1F0F8), transferColor),
    };

class StatusTag extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  const StatusTag(this.text, {super.key, required this.bg, required this.fg});

  factory StatusTag.debt(DebtStatus s) {
    final (bg, fg) = debtStatusColors(s);
    return StatusTag(debtStatusLabel(s), bg: bg, fg: fg);
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: fg)),
      );
}

class DebtTile extends StatelessWidget {
  final Debt d;
  final VoidCallback? onTap;
  const DebtTile(this.d, {super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final type = Lookups.instance.debtTypeName(d.type);
    final next = d.nextInstallment;
    final info = [
      if (type.isNotEmpty) type,
      if (d.installmentTotal > 1)
        '${d.installmentsPaid} de ${d.installmentTotal} pagas'
      else
        'pagamento único',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      Text(
                          [
                            if (d.creditor.isNotEmpty &&
                                d.creditor != d.title)
                              d.creditor,
                            info
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusTag.debt(d.displayStatus),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: d.progress,
                  minHeight: 6,
                  color: const Color(0xFF2E9E5B),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(
                    child: Text('Aberto ${money(d.open)}',
                        style: muted?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: d.open > 0 ? outColor : inColor))),
                if (next != null)
                  Text('próx. ${formatDate(next).substring(0, 5)} · ',
                      style: muted),
                Text('de ${money(d.total)}', style: muted),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
