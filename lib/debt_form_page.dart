import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_service.dart';
import 'debts_models.dart';
import 'lookups.dart';
import 'models.dart';
import 'ui.dart';

/// Nova dívida ([debt] null) ou edição, com parcelamento e faixas de valor.
class DebtFormPage extends StatefulWidget {
  final Debt? debt;
  final List<InstallmentPlan> plans;
  const DebtFormPage({super.key, this.debt, this.plans = const []});

  @override
  State<DebtFormPage> createState() => _DebtFormPageState();
}

class _PlanRow {
  final start = TextEditingController();
  final end = TextEditingController();
  final amount = TextEditingController();

  void dispose() {
    start.dispose();
    end.dispose();
    amount.dispose();
  }
}

class _DebtFormPageState extends State<DebtFormPage> {
  final _api = ApiService.instance;
  final _lk = Lookups.instance;
  final _form = GlobalKey<FormState>();
  final _creditor = TextEditingController();
  final _description = TextEditingController();
  final _document = TextEditingController();
  final _original = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _interest = TextEditingController();
  final _fine = TextEditingController();
  final _discount = TextEditingController();
  final _notes = TextEditingController();
  String? _type;
  DateTime _issue = DateTime.now();
  DateTime _firstDue = DateTime.now();
  CashCategory? _category;
  Subcategory? _sub;
  final _planRows = <_PlanRow>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.debt != null;

  @override
  void initState() {
    super.initState();
    final d = widget.debt;
    if (d != null) {
      _creditor.text = d.creditor;
      _description.text = d.description;
      _document.text = d.documentNumber;
      _original.text = moneyInput(d.original);
      _count.text = '${d.installmentTotal}';
      _interest.text = d.interest > 0 ? moneyInput(d.interest) : '';
      _fine.text = d.fine > 0 ? moneyInput(d.fine) : '';
      _discount.text = d.discount > 0 ? moneyInput(d.discount) : '';
      _notes.text = d.notes;
      _type = d.type.isEmpty ? null : d.type;
      _issue = d.issueDate ?? DateTime.now();
      _firstDue = d.firstDueDate ?? d.dueDate ?? _issue;
      for (final p in widget.plans) {
        final r = _PlanRow();
        r.start.text = '${p.start}';
        r.end.text = '${p.end}';
        r.amount.text = moneyInput(p.amount);
        _planRows.add(r);
      }
    } else {
      final n = DateTime.now();
      _firstDue = DateTime(n.year, n.month + 1, n.day);
    }
    for (final c in [_original, _count]) {
      c.addListener(() => setState(() {}));
    }
    _init();
  }

  Future<void> _init() async {
    try {
      await _lk.load();
      final d = widget.debt;
      if (d != null && d.cashCategoryId > 0) {
        _category = _lk.findCategory('${d.cashCategoryId}');
        if (_category != null && d.cashSubcategoryId > 0) {
          _sub = _lk.findSubcategory(_category!.id, '${d.cashSubcategoryId}');
        }
      }
      if (_type == null && _lk.debtTypes.length == 1) {
        _type = _lk.debtTypes.first.code;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _creditor,
      _description,
      _document,
      _original,
      _count,
      _interest,
      _fine,
      _discount,
      _notes
    ]) {
      c.dispose();
    }
    for (final r in _planRows) {
      r.dispose();
    }
    super.dispose();
  }

  double _v(TextEditingController c) => parseMoney(c.text) ?? 0;
  int get _n {
    final n = int.tryParse(_count.text.trim()) ?? 1;
    return n < 1 ? 1 : n;
  }

  List<InstallmentPlan> get _plans => [
        for (final r in _planRows)
          if ((int.tryParse(r.start.text) ?? 0) > 0 &&
              (int.tryParse(r.end.text) ?? 0) > 0 &&
              _v(r.amount) > 0)
            InstallmentPlan(int.parse(r.start.text), int.parse(r.end.text),
                _v(r.amount)),
      ];

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(DateTime.now().year + 30),
      );

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'description': _description.text.trim(),
        'creditor_name': _creditor.text.trim(),
        'debt_type': _type,
        'document_number':
            _document.text.trim().isEmpty ? null : _document.text.trim(),
        'issue_date': isoDate(_issue),
        'first_installment_due_at': isoDate(_firstDue),
        'due_date': isoDate(_firstDue),
        'due_day': _firstDue.day,
        'installment_total': _n,
        'original_amount': _v(_original),
        'interest_amount': _v(_interest),
        'fine_amount': _v(_fine),
        'discount_amount': _v(_discount),
        if (_category != null) ...{
          'cash_category_id': _category!.id,
          'cash_subcategory_id': _sub?.id,
          'category': _category!.name,
        },
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      };
      final id = await _api.saveDebt(body, id: widget.debt?.id);
      final plans = _plans;
      if (id > 0 && (plans.isNotEmpty || widget.plans.isNotEmpty)) {
        await _api.saveInstallmentPlans(id, plans);
      }
      notifyDataChanged();
      if (!mounted) return;
      showSnack(context, _isEdit ? 'Dívida atualizada.' : 'Dívida criada.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = _n;
    final per = n > 0 ? _v(_original) / n : 0.0;
    final lastDue = installmentDueDate(_firstDue, n - 1, _firstDue.day);
    final types = [
      ..._lk.debtTypes,
      if (_type != null && !_lk.debtTypes.any((t) => t.code == _type))
        DebtType(_type!, _type!),
    ];
    final subs = _category == null
        ? const <Subcategory>[]
        : _lk.subsOf(_category!.id);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
        title: Text(_isEdit ? 'Editar dívida' : 'Nova dívida'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  TextFormField(
                    controller: _creditor,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(labelText: 'Credor *'),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Informe o credor'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    textCapitalization: TextCapitalization.sentences,
                    decoration:
                        const InputDecoration(labelText: 'Descrição *'),
                    validator: (v) => (v ?? '').trim().isEmpty
                        ? 'Informe a descrição'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _type,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Tipo *'),
                        items: [
                          for (final t in types)
                            DropdownMenuItem(
                                value: t.code,
                                child: Text(t.name,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setState(() => _type = v),
                        validator: (v) => v == null ? 'Escolha o tipo' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _document,
                        decoration:
                            const InputDecoration(labelText: 'Nº documento'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: _moneyField(_original, 'Valor original *',
                          validator: (v) => (parseMoney(v ?? '') ?? 0) <= 0
                              ? 'Informe o valor'
                              : null),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateField('Data emissão', _issue, () async {
                        final d = await _pick(_issue);
                        if (d != null) setState(() => _issue = d);
                      }),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  Text('Parcelamento',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: theme.colorScheme.primary)),
                  const SizedBox(height: 10),
                  Row(children: [
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _count,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Parcelas'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _dateField(
                          n == 1 ? 'Vencimento' : '1º vencimento', _firstDue,
                          () async {
                        final d = await _pick(_firstDue);
                        if (d != null) setState(() => _firstDue = d);
                      }),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(n == 1
                                    ? 'Pagamento único'
                                    : '$n × ${money(per)}')),
                            Text(money(_v(_original)),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                          ]),
                          if (n > 1)
                            Text(
                                '${formatDate(_firstDue)} → ${formatDate(lastDue)}'
                                ' · todo dia ${_firstDue.day}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color:
                                        theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
                  if (n > 1) ..._planFields(theme),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _moneyField(_interest, 'Juros')),
                    const SizedBox(width: 8),
                    Expanded(child: _moneyField(_fine, 'Multa')),
                    const SizedBox(width: 8),
                    Expanded(child: _moneyField(_discount, 'Desconto')),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<CashCategory>(
                        initialValue: _category,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            labelText: 'Categoria'),
                        items: [
                          for (final c in _lk.categories)
                            DropdownMenuItem(
                                value: c,
                                child: Text(c.name,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (c) => setState(() {
                          _category = c;
                          _sub = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<Subcategory>(
                        key: ValueKey('sub-${_category?.id}'),
                        initialValue: _sub,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Subcategoria'),
                        items: [
                          for (final s in subs)
                            DropdownMenuItem(
                                value: s,
                                child: Text(s.name,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: subs.isEmpty
                            ? null
                            : (s) => setState(() => _sub = s),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notes,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Observação'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50)),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(n == 1
                      ? 'Salvar dívida'
                      : 'Salvar dívida · $n parcelas'),
                ),
              ),
            ),
    );
  }

  List<Widget> _planFields(ThemeData theme) => [
        for (final r in _planRows)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(children: [
              SizedBox(
                width: 64,
                child: TextFormField(
                  controller: r.start,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'De'),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 64,
                child: TextFormField(
                  controller: r.end,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(labelText: 'Até'),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: _moneyField(r.amount, 'Valor parcela')),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => setState(() {
                  _planRows.remove(r);
                  r.dispose();
                }),
              ),
            ]),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() {
              final r = _PlanRow();
              final lastEnd = _planRows.isEmpty
                  ? 0
                  : (int.tryParse(_planRows.last.end.text) ?? 0);
              r.start.text = '${lastEnd + 1}';
              r.end.text = '$_n';
              _planRows.add(r);
            }),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Faixa de parcelas com valor diferente'),
          ),
        ),
      ];

  Widget _dateField(String label, DateTime value, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label,
              suffixIcon: const Icon(Icons.calendar_today, size: 18)),
          child: Text(formatDate(value)),
        ),
      );

  Widget _moneyField(TextEditingController c, String label,
          {FormFieldValidator<String>? validator}) =>
      TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: label, hintText: '0,00'),
        validator: validator,
      );
}
