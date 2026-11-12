import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api_service.dart';
import 'dashboard_page.dart';
import 'lookups.dart';
import 'models.dart';
import 'ui.dart';

/// Lista de movimentações com filtros, agrupada por dia.
class MovementsPage extends StatefulWidget {
  const MovementsPage({super.key});

  @override
  State<MovementsPage> createState() => _MovementsPageState();
}

class _MovementsPageState extends State<MovementsPage> {
  MoveFilter _f = MoveFilter(period: Period.currentMonth());
  List<Movement> _moves = const [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  int _req = 0;

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
    final req = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Lookups.instance.load();
      final (list, total) = await ApiService.instance.movements(_f);
      if (!mounted || req != _req) return;
      setState(() {
        _moves = list;
        _total = total;
      });
    } catch (e) {
      if (mounted && req == _req) setState(() => _error = e.toString());
    } finally {
      if (mounted && req == _req) setState(() => _loading = false);
    }
  }

  void _apply(MoveFilter f) {
    _f = f;
    _load();
  }

  Future<T?> _choose<T>(String title, List<(T?, String)> options) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(shrinkWrap: true, children: [
            ListTile(
                title: Text(title,
                    style: Theme.of(ctx).textTheme.titleMedium)),
            for (final (value, label) in options)
              ListTile(
                title: Text(label),
                onTap: () => Navigator.pop(ctx, value),
              ),
          ]),
        ),
      ),
    ).then((v) => v);
  }

  // Sentinela para "Todos" (null fecha o menu sem mudar nada).
  static const _all = -1;

  Future<void> _pickType() async {
    final v = await _choose<String>('Tipo', const [
      ('', 'Todos'),
      ('ENTRADA', 'Entradas'),
      ('SAIDA', 'Saídas'),
      ('TRANSFERENCIA', 'Transferências'),
    ]);
    if (v != null) _apply(_f.copyWith(type: () => v.isEmpty ? null : v));
  }

  Future<void> _pickAccount() async {
    final v = await _choose<int>('Conta', [
      (_all, 'Todas as contas'),
      for (final a in Lookups.instance.accounts) (a.id, a.name),
    ]);
    if (v != null) _apply(_f.copyWith(accountId: () => v == _all ? null : v));
  }

  Future<void> _pickCategory() async {
    final v = await _choose<int>('Categoria', [
      (_all, 'Todas as categorias'),
      for (final c in Lookups.instance.categories.where((c) => c.active))
        (c.id, c.name),
    ]);
    if (v != null) {
      _apply(_f.copyWith(categoryId: () => v == _all ? null : v));
    }
  }

  Future<void> _pickAttachment() async {
    final v = await _choose<String>('Anexo', const [
      ('', 'Com ou sem anexo'),
      ('com', 'Com anexo'),
      ('sem', 'Sem anexo'),
    ]);
    if (v != null) {
      _apply(_f.copyWith(attachments: () => v.isEmpty ? null : v));
    }
  }

  Future<void> _openPdf() async {
    final ok = await launchUrl(ApiService.instance.reportUrl(_f),
        mode: LaunchMode.externalApplication);
    if (!ok && mounted) showSnack(context, 'Não foi possível abrir o PDF.');
  }

  String _label<T>(T? value, String empty, Map<T, String> names) =>
      value == null ? empty : (names[value] ?? empty);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lk = Lookups.instance;
    final real = _moves.where((m) => !m.isTransfer);
    final entradas = real
        .where((m) => m.type == MoveType.entrada)
        .fold<double>(0, (a, m) => a + m.total);
    final saidas = real
        .where((m) => m.type == MoveType.saida)
        .fold<double>(0, (a, m) => a + m.total);
    final saldo = _moves.fold<double>(0, (a, m) => a + m.signed);

    // Agrupa por dia (a lista já vem da mais nova para a mais antiga).
    final items = <Widget>[];
    DateTime? lastDay;
    for (var i = 0; i < _moves.length; i++) {
      final m = _moves[i];
      final d = m.date;
      final day = d == null ? null : DateTime(d.year, d.month, d.day);
      if (i == 0 || day != lastDay) {
        lastDay = day;
        final dayTotal = _moves
            .where((x) =>
                x.date != null &&
                day != null &&
                DateTime(x.date!.year, x.date!.month, x.date!.day) == day)
            .fold<double>(0, (a, x) => a + x.signed);
        items.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(children: [
            Text(day == null ? 'Sem data' : dayLabel(day),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const Spacer(),
            Text('${dayTotal > 0 ? '+' : ''}${money(dayTotal)}',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ]),
        ));
      }
      items.add(MovementTile(m, onTap: () => openMovement(context, m)));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(children: [
              Expanded(
                child: SearchField(
                  hint: 'Buscar descrição, fornecedor, nº doc…',
                  onSubmit: (s) => _apply(_f.copyWith(
                      search: () => s.trim().isEmpty ? null : s.trim())),
                ),
              ),
              IconButton(
                tooltip: 'Relatório PDF',
                onPressed: _openPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _Chip(_f.period.label, true, () async {
                  // Reaproveita o seletor de período do PeriodBar.
                  final p = await showModalBottomSheet<Period>(
                    context: context,
                    builder: (ctx) => SafeArea(
                      child: PeriodBar(
                        period: _f.period,
                        onChanged: (p) => Navigator.pop(ctx, p),
                      ),
                    ),
                  );
                  if (p != null) _apply(_f.copyWith(period: p));
                }),
                _Chip(
                    _label(_f.type, 'Tipo', const {
                      'ENTRADA': 'Entradas',
                      'SAIDA': 'Saídas',
                      'TRANSFERENCIA': 'Transferências',
                    }),
                    _f.type != null,
                    _pickType),
                _Chip(
                    _label(_f.accountId, 'Conta',
                        {for (final a in lk.accounts) a.id: a.name}),
                    _f.accountId != null,
                    _pickAccount),
                _Chip(
                    _label(_f.categoryId, 'Categoria',
                        {for (final c in lk.categories) c.id: c.name}),
                    _f.categoryId != null,
                    _pickCategory),
                _Chip(
                    _label(_f.attachments, 'Anexo',
                        const {'com': 'Com anexo', 'sem': 'Sem anexo'}),
                    _f.attachments != null,
                    _pickAttachment),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
            child: Row(children: [
              MiniStat('Entradas', entradas, color: inColor),
              const SizedBox(width: 6),
              MiniStat('Saídas', saidas, color: outColor),
              const SizedBox(width: 6),
              MiniStat('Saldo', saldo),
            ]),
          ),
        ),
        if (_loading)
          const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2)),
        if (_error != null)
          SliverToBoxAdapter(child: ErrorView(_error!, onRetry: _load))
        else if (!_loading && _moves.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text('Nenhuma movimentação com estes filtros.',
                  textAlign: TextAlign.center),
            ),
          ),
        SliverList.list(children: items),
        if (_total > _moves.length)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                  'Mostrando ${_moves.length} de $_total. Use os filtros para ver as demais.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 96)),
      ]),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Chip(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          const Icon(Icons.arrow_drop_down, size: 18),
        ]),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
      ),
    );
  }
}
