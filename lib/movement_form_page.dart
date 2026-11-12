import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';
import 'dashboard_page.dart';
import 'lookups.dart';
import 'models.dart';
import 'movement_detail_page.dart';
import 'ui.dart';

enum _Kind { entrada, saida, transfer }

/// Novo lançamento (entrada, saída ou transferência) ou edição de um
/// lançamento existente.
class MovementFormPage extends StatefulWidget {
  final Movement? editing;
  const MovementFormPage({super.key, this.editing});

  @override
  State<MovementFormPage> createState() => _MovementFormPageState();
}

class _MovementFormPageState extends State<MovementFormPage> {
  final _api = ApiService.instance;
  final _lk = Lookups.instance;
  final _form = GlobalKey<FormState>();

  _Kind _kind = _Kind.saida;
  DateTime _when = DateTime.now();
  final _amount = TextEditingController();
  final _supplier = TextEditingController();
  final _docNumber = TextEditingController();
  final _notes = TextEditingController();
  final _penalty = TextEditingController();
  final _interest = TextEditingController();
  final _fee = TextEditingController();
  Account? _account;
  Account? _from;
  Account? _to;
  CashCategory? _category;
  Subcategory? _sub;
  String? _docType;
  bool _showExtras = false;
  final _photos = <XFile>[];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
    _init();
  }

  @override
  void dispose() {
    for (final c in [
      _amount,
      _supplier,
      _docNumber,
      _notes,
      _penalty,
      _interest,
      _fee
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _init() async {
    try {
      await _lk.load();
    } catch (e) {
      _error = e.toString();
    }
    final m = widget.editing;
    if (m != null) {
      _kind = m.type == MoveType.entrada ? _Kind.entrada : _Kind.saida;
      _when = m.date ?? DateTime.now();
      _amount.text = moneyInput(m.amount);
      _supplier.text = m.supplier;
      _docNumber.text = m.documentNumber;
      _notes.text = m.notes;
      if (m.penalty > 0) _penalty.text = moneyInput(m.penalty);
      if (m.interest > 0) _interest.text = moneyInput(m.interest);
      if (m.fee > 0) _fee.text = moneyInput(m.fee);
      _showExtras = m.extras > 0;
      _account = _lk.findAccount(m.account);
      _category = _lk.findCategory(m.categoryId, m.categoryName);
      if (_category != null) {
        _sub = _lk.findSubcategory(
            _category!.id, m.subcategoryId, m.subcategoryName);
      }
      _docType = m.documentType.isEmpty ? null : m.documentType;
      if (_docType != null && !_lk.documentTypes.contains(_docType)) {
        _lk.documentTypes = [..._lk.documentTypes, _docType!];
      }
    } else if (_lk.accounts.isNotEmpty) {
      _account = _lk.accounts.first;
    }
    if (mounted) setState(() => _loading = false);
  }

  double get _value => parseMoney(_amount.text) ?? 0;

  Color get _color => switch (_kind) {
        _Kind.entrada => inColor,
        _Kind.saida => outColor,
        _Kind.transfer => transferColor,
      };

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _when,
      firstDate: DateTime(2015),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (d != null) {
      setState(() =>
          _when = DateTime(d.year, d.month, d.day, _when.hour, _when.minute));
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(_when));
    if (t != null) {
      setState(() => _when =
          DateTime(_when.year, _when.month, _when.day, t.hour, t.minute));
    }
  }

  Future<void> _addPhoto() async {
    final source = await pickPhotoSource(context);
    if (source == null) return;
    final x = await ImagePicker()
        .pickImage(source: source, maxWidth: 2000, imageQuality: 75);
    if (x != null) setState(() => _photos.add(x));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_kind == _Kind.transfer) {
        await _api.createTransfer(
          fromAccountId: _from!.id,
          toAccountId: _to!.id,
          date: _when,
          amount: _value,
          fee: parseMoney(_fee.text) ?? 0,
          notes: _notes.text.trim(),
        );
      } else {
        final body = <String, dynamic>{
          'data_hora': isoDateTimeLocal(_when),
          'tipo_movimentacao': _kind == _Kind.entrada ? 'ENTRADA' : 'SAIDA',
          'conta_caixa': _account!.name,
          'valor': _value,
          'multa': parseMoney(_penalty.text) ?? 0,
          'juros': parseMoney(_interest.text) ?? 0,
          'encargos': parseMoney(_fee.text) ?? 0,
          'tipo_documento': _docType,
          'numero_documento': _docNumber.text.trim(),
          'fornecedor': _supplier.text.trim(),
          // Igual à tela do ERP: categoria e subcategoria pelo nome.
          'categoria': _category?.name,
          'subcategoria': _sub?.name,
          'observacao': _notes.text.trim(),
          if (!_isEdit) ...{
            'is_deductible': _sub?.deductible ?? true,
            'is_pis_cofins_creditable': false,
          },
        };
        final id = await _api.saveMovement(body, id: widget.editing?.id);
        for (final p in _photos) {
          if (id <= 0) break;
          await _api.uploadAttachment(id, await p.readAsBytes(), p.name);
        }
      }
      notifyDataChanged();
      if (!mounted) return;
      Navigator.pop(context, true);
      showSnack(
          context,
          _kind == _Kind.transfer
              ? 'Transferência lançada.'
              : (_isEdit ? 'Lançamento atualizado.' : 'Lançamento salvo.'));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _required(Object? v, String msg) => v == null ? msg : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _isEdit
        ? 'Editar lançamento'
        : (_kind == _Kind.transfer ? 'Transferência' : 'Novo lançamento');
    final saveLabel = switch (_kind) {
      _Kind.entrada => 'Salvar entrada',
      _Kind.saida => 'Salvar saída',
      _Kind.transfer => 'Transferir',
    };
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context)),
        title: Text(title),
        actions: [
          TextButton(
              onPressed: _saving || _loading ? null : _save,
              child: const Text('Salvar')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  SegmentedButton<_Kind>(
                    segments: [
                      const ButtonSegment(
                          value: _Kind.entrada,
                          icon: Icon(Icons.arrow_upward),
                          label: Text('Entrada')),
                      const ButtonSegment(
                          value: _Kind.saida,
                          icon: Icon(Icons.arrow_downward),
                          label: Text('Saída')),
                      ButtonSegment(
                          value: _Kind.transfer,
                          enabled: !_isEdit,
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Transf.')),
                    ],
                    selected: {_kind},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        setState(() => _kind = s.first),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _amount,
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
                    ],
                    style: theme.textTheme.headlineMedium
                        ?.copyWith(color: _color, fontWeight: FontWeight.w600),
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      prefixText: 'R\$ ',
                      hintText: '0,00',
                    ),
                    validator: (v) => (parseMoney(v ?? '') ?? 0) <= 0
                        ? 'Informe o valor'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: _TapField(
                          label: 'Data',
                          value: formatDate(_when),
                          icon: Icons.calendar_today,
                          onTap: _pickDate),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TapField(
                          label: 'Hora',
                          value: formatTime(_when),
                          icon: Icons.schedule,
                          onTap: _pickTime),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  if (_kind == _Kind.transfer)
                    ..._transferFields(theme)
                  else
                    ..._movementFields(theme),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
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
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : Icon(_kind == _Kind.transfer
                          ? Icons.swap_horiz
                          : Icons.check),
                  label: Text(_value > 0
                      ? '$saveLabel · ${money(_value)}'
                      : saveLabel),
                ),
              ),
            ),
    );
  }

  List<Widget> _movementFields(ThemeData theme) {
    final cats = _lk.categories
        .where((c) => c.active || c.id == _category?.id)
        .toList();
    final subs = _category == null
        ? const <Subcategory>[]
        : _lk
            .subsOf(_category!.id)
            .where((s) => s.active || s.id == _sub?.id)
            .toList();
    return [
      DropdownButtonFormField<Account>(
        initialValue: _account,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Conta *'),
        items: [
          for (final a in _lk.accounts)
            DropdownMenuItem(
              value: a,
              child: Row(children: [
                Icon(accountIcon(a.name), size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text(a.name, overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ],
        onChanged: (a) => setState(() => _account = a),
        validator: (v) => _required(v, 'Escolha a conta'),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<CashCategory>(
        initialValue: _category,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Categoria *'),
        items: [
          for (final c in cats)
            DropdownMenuItem(
                value: c, child: Text(c.name, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (c) => setState(() {
          _category = c;
          _sub = null;
        }),
        validator: (v) => _required(v, 'Escolha a categoria'),
      ),
      const SizedBox(height: 14),
      DropdownButtonFormField<Subcategory>(
        key: ValueKey('sub-${_category?.id}'),
        initialValue: _sub,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Subcategoria'),
        items: [
          for (final s in subs)
            DropdownMenuItem(
                value: s, child: Text(s.name, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: subs.isEmpty ? null : (s) => setState(() => _sub = s),
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _supplier,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
            labelText: _kind == _Kind.entrada
                ? 'Cliente / descrição'
                : 'Fornecedor / descrição'),
      ),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: _docType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo doc.'),
            items: [
              const DropdownMenuItem<String>(value: null, child: Text('—')),
              for (final t in _lk.documentTypes)
                DropdownMenuItem(
                    value: t, child: Text(t, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (t) => setState(() => _docType = t),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextFormField(
            controller: _docNumber,
            decoration: const InputDecoration(labelText: 'Nº documento'),
          ),
        ),
      ]),
      const SizedBox(height: 6),
      if (!_showExtras)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => setState(() => _showExtras = true),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Multa / juros / encargos'),
          ),
        )
      else ...[
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _moneyField(_penalty, 'Multa')),
          const SizedBox(width: 8),
          Expanded(child: _moneyField(_interest, 'Juros')),
          const SizedBox(width: 8),
          Expanded(child: _moneyField(_fee, 'Encargos')),
        ]),
        const SizedBox(height: 14),
      ],
      TextFormField(
        controller: _notes,
        maxLines: 2,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Observação'),
      ),
      const SizedBox(height: 14),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in _photos)
          Chip(
            avatar: const Icon(Icons.image_outlined, size: 18),
            label: Text(p.name.length > 18
                ? '${p.name.substring(0, 15)}…'
                : p.name),
            onDeleted: () => setState(() => _photos.remove(p)),
          ),
        ActionChip(
          avatar: const Icon(Icons.add_a_photo_outlined, size: 18),
          label: Text(_isEdit ? 'Adicionar foto' : 'Foto do comprovante'),
          onPressed: _addPhoto,
        ),
      ]),
    ];
  }

  List<Widget> _transferFields(ThemeData theme) {
    return [
      Text('De', style: theme.textTheme.labelLarge),
      const SizedBox(height: 6),
      _AccountPicker(
        accounts: _lk.accounts,
        selected: _from,
        onSelect: (a) => setState(() {
          _from = a;
          if (_to?.id == a.id) _to = null;
        }),
      ),
      Center(
          child: Icon(Icons.arrow_downward, color: theme.colorScheme.primary)),
      Text('Para', style: theme.textTheme.labelLarge),
      const SizedBox(height: 6),
      _AccountPicker(
        accounts: _lk.accounts,
        selected: _to,
        disabledId: _from?.id,
        onSelect: (a) => setState(() => _to = a),
      ),
      // Validação das contas da transferência.
      FormField<void>(
        validator: (_) {
          if (_from == null) return 'Escolha a conta de origem';
          if (_to == null) return 'Escolha a conta de destino';
          return null;
        },
        builder: (state) => state.hasError
            ? Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(state.errorText!,
                    style: TextStyle(
                        color: theme.colorScheme.error, fontSize: 12)),
              )
            : const SizedBox(),
      ),
      const SizedBox(height: 14),
      _moneyField(_fee, 'Tarifa (opcional)'),
      const SizedBox(height: 14),
      TextFormField(
        controller: _notes,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(labelText: 'Observação'),
      ),
      const SizedBox(height: 8),
      Text(
        _from != null && _to != null
            ? 'Cria a saída em ${_from!.name} e a entrada em ${_to!.name} juntas.'
            : 'Cria a saída na origem e a entrada no destino juntas.',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    ];
  }

  Widget _moneyField(TextEditingController c, String label) => TextFormField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: InputDecoration(labelText: label, hintText: '0,00'),
      );
}

class _TapField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  const _TapField(
      {required this.label,
      required this.value,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration:
            InputDecoration(labelText: label, suffixIcon: Icon(icon, size: 18)),
        child: Text(value),
      ),
    );
  }
}

class _AccountPicker extends StatelessWidget {
  final List<Account> accounts;
  final Account? selected;
  final int? disabledId;
  final ValueChanged<Account> onSelect;
  const _AccountPicker(
      {required this.accounts,
      required this.selected,
      required this.onSelect,
      this.disabledId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3.2,
      children: [
        for (final a in accounts)
          Builder(builder: (_) {
            final on = selected?.id == a.id;
            final off = disabledId == a.id;
            return InkWell(
              onTap: off ? null : () => onSelect(a),
              borderRadius: BorderRadius.circular(10),
              child: Opacity(
                opacity: off ? 0.4 : 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: on ? theme.colorScheme.primaryContainer : null,
                    border: Border.all(
                        color: on
                            ? theme.colorScheme.primary
                            : theme.colorScheme.outlineVariant,
                        width: on ? 2 : 1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    Icon(accountIcon(a.name), size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(a.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium)),
                  ]),
                ),
              ),
            );
          }),
      ],
    );
  }
}
