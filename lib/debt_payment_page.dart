import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';
import 'dashboard_page.dart' show accountIcon;
import 'debts_models.dart';
import 'lookups.dart';
import 'models.dart';
import 'movement_detail_page.dart' show pickPhotoSource;
import 'ui.dart';

const paymentMethods = [
  'Pix',
  'Boleto',
  'Transferência',
  'Débito automático',
  'Cartão',
  'Dinheiro',
];

/// Paga uma ou mais parcelas ([installments]) ou edita um pagamento
/// ([payment]). Cada pagamento vira uma SAÍDA no Caixa (o ERP lança).
class DebtPaymentPage extends StatefulWidget {
  final Debt debt;
  final List<Installment> installments;
  final DebtPayment? payment;
  const DebtPaymentPage(
      {super.key,
      required this.debt,
      this.installments = const [],
      this.payment});

  @override
  State<DebtPaymentPage> createState() => _DebtPaymentPageState();
}

class _DebtPaymentPageState extends State<DebtPaymentPage> {
  final _api = ApiService.instance;
  final _lk = Lookups.instance;
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _interest = TextEditingController();
  final _fine = TextEditingController();
  final _discount = TextEditingController();
  final _receipt = TextEditingController();
  final _notes = TextEditingController();
  String _method = 'Pix';
  DateTime _date = DateTime.now();
  Account? _account;
  CashCategory? _category;
  Subcategory? _sub;
  PaymentCash _cash = const PaymentCash();
  final _photos = <XFile>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.payment != null;
  bool get _multi => widget.installments.length > 1;

  @override
  void initState() {
    super.initState();
    final p = widget.payment;
    if (p != null) {
      _amount.text = moneyInput(p.amount);
      _interest.text = p.interest > 0 ? moneyInput(p.interest) : '';
      _fine.text = p.fine > 0 ? moneyInput(p.fine) : '';
      _discount.text = p.discount > 0 ? moneyInput(p.discount) : '';
      _receipt.text = p.receipt;
      _notes.text = p.notes;
      _method = p.method;
      _date = p.date ?? DateTime.now();
    } else {
      _amount.text = moneyInput(_expectedSum);
    }
    for (final c in [_amount, _interest, _fine, _discount]) {
      c.addListener(() => setState(() {}));
    }
    _init();
  }

  @override
  void dispose() {
    for (final c in [_amount, _interest, _fine, _discount, _receipt, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  double get _expectedSum =>
      widget.installments.fold<double>(0, (a, i) => a + i.expected);

  double _v(TextEditingController c) => parseMoney(c.text) ?? 0;

  double get _principal => _multi ? _expectedSum : _v(_amount);

  double get _total =>
      _principal + _v(_interest) + _v(_fine) - _v(_discount);

  Future<void> _init() async {
    try {
      await _lk.load();
      final cash = _isEdit
          ? await _api.debtPaymentCash(widget.payment!.id)
          : await _api
              .debtCashDefaults(widget.debt.id)
              .catchError((_) => const PaymentCash());
      final catId = cash.categoryId ??
          (widget.debt.cashCategoryId > 0 ? widget.debt.cashCategoryId : null);
      final subId = cash.subcategoryId ??
          (widget.debt.cashSubcategoryId > 0
              ? widget.debt.cashSubcategoryId
              : null);
      _cash = cash;
      _account = _lk.findAccountById(cash.accountId) ??
          (_isEdit
              ? null
              : _lk.accounts.where((a) => a.isDefault).firstOrNull);
      _category = catId == null ? null : _lk.findCategory('$catId');
      _sub = _category == null || subId == null
          ? null
          : _lk.findSubcategory(_category!.id, '$subId');
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _addPhoto() async {
    final source = await pickPhotoSource(context);
    if (source == null) return;
    final x = await ImagePicker()
        .pickImage(source: source, maxWidth: 2000, imageQuality: 75);
    if (x != null) setState(() => _photos.add(x));
  }

  Map<String, dynamic> get _cashBody => PaymentCash(
        accountId: _account?.id,
        categoryId: _category?.id,
        subcategoryId: _sub?.id,
        chartAccountId: _cash.chartAccountId,
        documentType: _cash.documentType,
      ).toJson();

  Map<String, dynamic> _body({
    required double amount,
    required bool withExtras,
    Installment? installment,
  }) =>
      {
        if (installment != null) ...{
          'installment_number': installment.number,
          'installment_due_date':
              installment.due == null ? null : isoDate(installment.due!),
        },
        'payment_date': isoDate(_date),
        'amount': amount,
        'interest_amount': withExtras ? _v(_interest) : 0,
        'fine_amount': withExtras ? _v(_fine) : 0,
        'discount_amount': withExtras ? _v(_discount) : 0,
        'payment_method': _method.trim().isEmpty ? null : _method.trim(),
        'receipt_number':
            _receipt.text.trim().isEmpty ? null : _receipt.text.trim(),
        'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        'cash': _cashBody,
      };

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final movementIds = <int>[];
    var done = 0;
    try {
      if (_isEdit) {
        final id = await _api.updateDebtPayment(
            widget.payment!.id, _body(amount: _v(_amount), withExtras: true));
        movementIds.add(id);
      } else {
        // Um pagamento por parcela (como na tela web); juros, multa e
        // desconto vão na primeira parcela selecionada.
        final list = widget.installments;
        for (var k = 0; k < list.length; k++) {
          final i = list[k];
          final id = await _api.createDebtPayment(
            widget.debt.id,
            _body(
              amount: _multi ? i.expected : _v(_amount),
              withExtras: k == 0,
              installment: i,
            ),
          );
          movementIds.add(id);
          done++;
        }
      }
      // Comprovante: anexado à saída do Caixa de cada pagamento.
      var uploadFailed = false;
      for (final movId in movementIds.where((id) => id > 0)) {
        for (final x in _photos) {
          try {
            await _api.uploadAttachment(movId, await x.readAsBytes(), x.name);
          } catch (_) {
            uploadFailed = true;
          }
        }
      }
      notifyDataChanged();
      if (!mounted) return;
      showSnack(
          context,
          uploadFailed
              ? 'Pagamento salvo, mas o comprovante não foi enviado.'
              : (_isEdit ? 'Pagamento atualizado.' : 'Pagamento registrado.'),
          error: uploadFailed);
      Navigator.pop(context, true);
    } catch (e) {
      if (done > 0) notifyDataChanged();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = done > 0
            ? '$done de ${widget.installments.length} parcelas foram pagas. '
                'Erro na seguinte: $e'
            : e.toString();
      });
    }
  }

  String get _subtitle {
    final d = widget.debt;
    if (_isEdit) {
      final n = widget.payment!.installment;
      return '${d.title}${n == null ? '' : ' · parcela $n'}';
    }
    final nums = widget.installments.map((i) => '${i.number}').toList();
    if (nums.isEmpty) return d.title;
    final label = nums.length == 1
        ? 'parcela ${nums.first}'
        : 'parcelas ${nums.sublist(0, nums.length - 1).join(', ')} e ${nums.last}';
    return '${d.title} · $label';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cats = _lk.categories
        .where((c) => c.active || c.id == _category?.id)
        .toList();
    final subs = _category == null
        ? const <Subcategory>[]
        : _lk
            .subsOf(_category!.id)
            .where((s) => s.active || s.id == _sub?.id)
            .toList();
    final methods = {
      ...paymentMethods,
      if (_method.isNotEmpty) _method,
    }.toList();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
        title: Text(_isEdit ? 'Editar pagamento' : 'Pagar parcelas'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  Text(_subtitle,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Text('Total a pagar',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(money(_total),
                        style: theme.textTheme.headlineMedium?.copyWith(
                            color: outColor, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 12),
                  if (_multi)
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(children: [
                          for (final i in widget.installments)
                            Row(children: [
                              Expanded(
                                  child: Text(
                                      'Parcela ${i.label} · ${formatDate(i.due)}')),
                              Text(money(i.expected)),
                            ]),
                        ]),
                      ),
                    )
                  else
                    _moneyField(_amount, 'Valor da parcela *',
                        validator: (v) => (parseMoney(v ?? '') ?? 0) <= 0
                            ? 'Informe o valor'
                            : null),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: InkWell(
                        onTap: _pickDate,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: 'Data pagamento',
                              suffixIcon: Icon(Icons.calendar_today, size: 18)),
                          child: Text(formatDate(_date)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _method.isEmpty ? null : _method,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Forma'),
                        items: [
                          for (final m in methods)
                            DropdownMenuItem(
                                value: m,
                                child: Text(m,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (m) => setState(() => _method = m ?? ''),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _moneyField(_interest, 'Juros')),
                    const SizedBox(width: 8),
                    Expanded(child: _moneyField(_fine, 'Multa')),
                    const SizedBox(width: 8),
                    Expanded(child: _moneyField(_discount, 'Desconto')),
                  ]),
                  if (_multi)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                          'Juros, multa e desconto entram na primeira parcela.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<Account>(
                    initialValue: _account,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Sai da conta (Caixa) *'),
                    items: [
                      for (final a in _lk.accounts)
                        DropdownMenuItem(
                          value: a,
                          child: Row(children: [
                            Icon(accountIcon(a.name), size: 18),
                            const SizedBox(width: 8),
                            Flexible(
                                child: Text(a.name,
                                    overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                    ],
                    onChanged: (a) => setState(() => _account = a),
                    validator: (v) => v == null ? 'Escolha a conta' : null,
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<CashCategory>(
                        initialValue: _category,
                        isExpanded: true,
                        decoration:
                            const InputDecoration(labelText: 'Categoria'),
                        items: [
                          for (final c in cats)
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
                    controller: _receipt,
                    decoration:
                        const InputDecoration(labelText: 'Nº comprovante'),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _notes,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Observação'),
                  ),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: _addPhoto,
                      icon: const Icon(Icons.photo_camera_outlined),
                      label: const Text('Foto do comprovante'),
                    ),
                    for (final x in _photos)
                      InputChip(
                        avatar: const Icon(Icons.image_outlined, size: 18),
                        label: Text(x.name, overflow: TextOverflow.ellipsis),
                        onDeleted: () => setState(() => _photos.remove(x)),
                      ),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    'O ERP lança a saída no Caixa automaticamente'
                    '${_isEdit ? ' (e atualiza a existente).' : '.'}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  label: Text(_isEdit
                      ? 'Salvar pagamento · ${money(_total)}'
                      : 'Confirmar pagamento · ${money(_total)}'),
                ),
              ),
            ),
    );
  }

  Widget _moneyField(TextEditingController c, String label,
          {FormFieldValidator<String>? validator}) =>
      TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration:
            InputDecoration(labelText: label, hintText: '0,00', prefixText: 'R\$ '),
        validator: validator,
      );
}
