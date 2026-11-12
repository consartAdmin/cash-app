import 'package:flutter/material.dart';

import 'api_service.dart';
import 'debt_form_page.dart';
import 'debt_payment_page.dart';
import 'debts_models.dart';
import 'debts_page.dart';
import 'lookups.dart';
import 'models.dart';
import 'ui.dart';

/// Detalhe da dívida: parcelas (selecionar e pagar) e pagamentos feitos.
class DebtDetailPage extends StatefulWidget {
  final int debtId;
  const DebtDetailPage({super.key, required this.debtId});

  @override
  State<DebtDetailPage> createState() => _DebtDetailPageState();
}

class _DebtDetailPageState extends State<DebtDetailPage> {
  final _api = ApiService.instance;
  Debt? _debt;
  List<DebtPayment> _payments = const [];
  List<InstallmentPlan> _plans = const [];
  List<Installment> _installments = const [];
  final _selected = <int>{};
  bool _showPayments = false;
  bool _showPaid = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final id = widget.debtId;
      final r = await Future.wait([
        _api.debt(id),
        _api.debtPayments(id),
        _api.installmentPlans(id).catchError((_) => <InstallmentPlan>[]),
      ]);
      if (!mounted) return;
      final debt = r[0] as Debt;
      final payments = r[1] as List<DebtPayment>;
      final plans = r[2] as List<InstallmentPlan>;
      setState(() {
        _debt = debt;
        _payments = payments;
        _plans = plans;
        _installments = buildInstallments(debt, payments, plans);
        _selected.removeWhere((n) => !_installments
            .any((i) => i.number == n && !i.isPaid));
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Installment> get _chosen => _installments
      .where((i) => _selected.contains(i.number))
      .toList();

  void _toggle(Installment i) {
    if (i.isPaid) {
      _paymentActions(i.payment!);
      return;
    }
    setState(() {
      if (!_selected.remove(i.number)) _selected.add(i.number);
    });
  }

  Future<void> _pay() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DebtPaymentPage(debt: _debt!, installments: _chosen),
    ));
    if (ok == true) {
      _selected.clear();
      await _load();
    }
  }

  Future<void> _paymentActions(DebtPayment p) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(p.installment == null
                ? 'Pagamento de ${formatDate(p.date)}'
                : 'Parcela ${p.installment} · paga ${formatDate(p.date)}'),
            subtitle: Text([
              money(p.effective),
              if (p.method.isNotEmpty) p.method,
              if (p.receipt.isNotEmpty) 'Comprovante ${p.receipt}',
            ].join(' · ')),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar pagamento'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: Icon(Icons.undo, color: Theme.of(ctx).colorScheme.error),
            title: Text('Estornar (excluir pagamento)',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ]),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'edit') {
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => DebtPaymentPage(debt: _debt!, payment: p),
      ));
      if (ok == true) await _load();
    } else {
      final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Estornar pagamento?'),
          content: const Text(
              'O pagamento é excluído e a saída lançada no Caixa também. '
              'A parcela volta a ficar em aberto.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Estornar')),
          ],
        ),
      );
      if (yes != true) return;
      try {
        await _api.deleteDebtPayment(p.id);
        notifyDataChanged();
        if (mounted) showSnack(context, 'Pagamento estornado.');
        await _load();
      } catch (e) {
        if (mounted) showSnack(context, e.toString(), error: true);
      }
    }
  }

  Future<void> _edit() async {
    final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DebtFormPage(debt: _debt, plans: _plans),
    ));
    if (ok == true) await _load();
  }

  Future<void> _delete() async {
    if (_payments.isNotEmpty) {
      showSnack(context,
          'Esta dívida tem pagamentos. Estorne os pagamentos antes de excluir.',
          error: true);
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir dívida?'),
        content: Text(_debt!.title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _api.deleteDebt(_debt!.id);
      notifyDataChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _debt;
    final chosen = _chosen;
    final chosenSum = chosen.fold<double>(0, (a, i) => a + i.expected);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dívida'),
        actions: [
          if (d != null)
            TextButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Editar')),
          if (d != null)
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'delete') _delete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Excluir dívida')),
              ],
            ),
        ],
      ),
      body: d == null
          ? Center(
              child: _error != null
                  ? ErrorView(_error!, onRetry: _load)
                  : const CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 100),
                children: [
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  _header(d),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                            value: false,
                            label: Text('Parcelas (${_installments.length})')),
                        ButtonSegment(
                            value: true,
                            label: Text('Pagamentos (${_payments.length})')),
                      ],
                      selected: {_showPayments},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) =>
                          setState(() => _showPayments = s.first),
                    ),
                  ),
                  if (_showPayments) ..._paymentList() else ..._installmentList(),
                ],
              ),
            ),
      bottomNavigationBar: chosen.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50)),
                  onPressed: _pay,
                  icon: const Icon(Icons.payments_outlined),
                  label: Text(chosen.length == 1
                      ? 'Pagar parcela ${chosen.first.number} · ${money(chosenSum)}'
                      : 'Pagar ${chosen.length} parcelas · ${money(chosenSum)}'),
                ),
              ),
            ),
    );
  }

  Widget _header(Debt d) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final type = Lookups.instance.debtTypeName(d.type);
    return Card(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StatusTag.debt(d.displayStatus),
            const SizedBox(height: 4),
            Text(d.title,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text(
                [
                  if (d.creditor.isNotEmpty) 'Credor: ${d.creditor}',
                  if (type.isNotEmpty) type,
                  if (d.documentNumber.isNotEmpty) 'Doc. ${d.documentNumber}',
                ].join(' · '),
                style: muted),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: _amount('Em aberto', d.open, outColor)),
              Expanded(child: _amount('Pago', d.paid, inColor)),
              Expanded(child: _amount('Total', d.total, null)),
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
            if (d.notes.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(d.notes, style: muted),
            ],
          ],
        ),
      ),
    );
  }

  Widget _amount(String label, double v, Color? c) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text(money(v),
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: c)),
      ),
    ]);
  }

  List<Widget> _installmentList() {
    if (_installments.isEmpty) {
      return [
        const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Dívida sem data de vencimento.'))),
      ];
    }
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final paidCount = _installments.where((i) => i.isPaid).length;
    final visible = _showPaid || paidCount == _installments.length
        ? _installments
        : _installments.where((i) => !i.isPaid).toList();
    return [
      if (paidCount > 0 && paidCount < _installments.length)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton.icon(
              onPressed: () => setState(() => _showPaid = !_showPaid),
              icon: Icon(_showPaid ? Icons.expand_less : Icons.expand_more),
              label: Text(_showPaid
                  ? 'Esconder parcelas pagas'
                  : 'Mostrar $paidCount ${paidCount == 1 ? 'parcela paga' : 'parcelas pagas'}'),
            ),
          ),
        ),
      for (final i in visible)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: _selected.contains(i.number)
                ? BorderSide(color: theme.colorScheme.primary, width: 2)
                : BorderSide.none,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _toggle(i),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(children: [
                i.isPaid
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Icon(Icons.check_circle, color: inColor),
                      )
                    : Checkbox(
                        value: _selected.contains(i.number),
                        onChanged: (_) => _toggle(i),
                      ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(i.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700)),
                        Text(' · ${formatDate(i.due)}'),
                        if (i.status == InstallmentStatus.vencida) ...[
                          const SizedBox(width: 6),
                          StatusTag('VENCIDA',
                              bg: debtStatusColors(DebtStatus.vencido).$1,
                              fg: outColor),
                        ],
                      ]),
                      if (i.isPaid)
                        Text(
                            [
                              'Paga ${formatDate(i.payment!.date)}',
                              if (i.payment!.method.isNotEmpty)
                                i.payment!.method,
                            ].join(' · '),
                            style: muted),
                    ],
                  ),
                ),
                Text(
                    money(i.isPaid ? i.payment!.effective : i.expected),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: i.isPaid ? inColor : null)),
              ]),
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          'Toque nas parcelas para selecionar · toque numa paga para editar ou estornar',
          textAlign: TextAlign.center,
          style: muted,
        ),
      ),
    ];
  }

  List<Widget> _paymentList() {
    if (_payments.isEmpty) {
      return [
        const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Nenhum pagamento ainda.'))),
      ];
    }
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final total = _debt?.installmentTotal ?? 0;
    return [
      for (final p in _payments)
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          child: ListTile(
            onTap: () => _paymentActions(p),
            leading: const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0x22B3261E),
              child: Icon(Icons.arrow_downward, size: 19, color: outColor),
            ),
            title: Text(p.installment == null
                ? 'Pagamento'
                : 'Parcela ${p.installment.toString().padLeft(3, '0')}'
                    '${total > 0 ? '/${total.toString().padLeft(3, '0')}' : ''}'),
            subtitle: Text(
                [
                  formatDate(p.date),
                  if (p.method.isNotEmpty) p.method,
                  if (p.interest + p.fine > 0)
                    'juros/multa ${moneyInput(p.interest + p.fine)}',
                  if (p.discount > 0) 'desc. ${moneyInput(p.discount)}',
                ].join(' · '),
                style: muted),
            trailing: Text('-${money(p.effective)}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, color: outColor)),
          ),
        ),
    ];
  }
}
