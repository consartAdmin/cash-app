// Modelos e formatação do app Caixa.

double toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0;
  return double.tryParse(s) ?? double.tryParse(s.replaceAll(',', '.')) ?? 0;
}

int toInt(dynamic v) => toDouble(v).round();

String str(dynamic v) => v == null ? '' : v.toString().trim();

/// "1.234,56", "1234,56" ou "1234.56" -> 1234.56 (null se inválido).
double? parseMoney(String text) {
  var s = text.replaceAll('R\$', '').replaceAll(' ', '').trim();
  if (s.isEmpty) return null;
  if (s.contains(',')) s = s.replaceAll('.', '').replaceAll(',', '.');
  return double.tryParse(s);
}

/// Data/hora do ERP ("2026-11-04T14:30:00.000Z"), no fuso do aparelho, como
/// a tela do Caixa no navegador mostra.
DateTime? parseDateTime(dynamic v) {
  final s = str(v);
  if (s.length < 10) return null;
  final d = DateTime.tryParse(s);
  return d?.toLocal();
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// Igual ao campo datetime-local do ERP: "2026-11-04T14:30".
String isoDateTimeLocal(DateTime d) =>
    '${isoDate(d)}T${_two(d.hour)}:${_two(d.minute)}';

String formatDate(DateTime? d) =>
    d == null ? '' : '${_two(d.day)}/${_two(d.month)}/${d.year}';

String formatTime(DateTime? d) =>
    d == null ? '' : '${_two(d.hour)}:${_two(d.minute)}';

String formatDateTime(DateTime? d) =>
    d == null ? '' : '${formatDate(d)} ${formatTime(d)}';

String _two(int n) => n.toString().padLeft(2, '0');

const monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

const weekDays = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

/// "Hoje · sex 06/11", "Ontem · qui 05/11", "Qua 04/11".
String dayLabel(DateTime d, {DateTime? today}) {
  final t = today ?? DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final t0 = DateTime(t.year, t.month, t.day);
  final short = '${weekDays[d.weekday - 1]} ${_two(d.day)}/${_two(d.month)}';
  if (day == t0) return 'Hoje · $short';
  if (day == t0.subtract(const Duration(days: 1))) return 'Ontem · $short';
  return short[0].toUpperCase() + short.substring(1);
}

/// R$ 1.234,56
String money(double v) {
  final neg = v < 0;
  final cents = (v.abs() * 100).round();
  final intPart = (cents ~/ 100).toString();
  final dec = (cents % 100).toString().padLeft(2, '0');
  final buf = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buf.write('.');
    buf.write(intPart[i]);
  }
  return '${neg ? '-' : ''}R\$ $buf,$dec';
}

/// "1.234,56" (para preencher campos de valor).
String moneyInput(double v) => money(v).replaceFirst('R\$ ', '');

// ── Período ──────────────────────────────────────────────────────────────

class Period {
  final DateTime start;
  final DateTime end;
  final bool isMonth;

  const Period(this.start, this.end, {this.isMonth = false});

  factory Period.month(int year, int month) => Period(
        DateTime(year, month, 1),
        DateTime(year, month + 1, 0),
        isMonth: true,
      );

  factory Period.currentMonth() {
    final now = DateTime.now();
    return Period.month(now.year, now.month);
  }

  Period shiftMonth(int delta) => Period.month(start.year, start.month + delta);

  String get label => isMonth
      ? '${monthNames[start.month - 1]} ${start.year}'
      : '${formatDate(start)} a ${formatDate(end)}';

  @override
  bool operator ==(Object other) =>
      other is Period && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

// ── Caixa ────────────────────────────────────────────────────────────────

enum MoveType { entrada, saida }

class Movement {
  final int id;
  final DateTime? date;
  final MoveType type;
  final String account;
  final double amount;
  final double penalty;
  final double interest;
  final double fee;
  final String documentType;
  final String documentNumber;
  final String supplier;
  final String notes;
  final String categoryId;
  final String categoryName;
  final String subcategoryId;
  final String subcategoryName;
  final int attachments;
  final int? transferId;
  final String transferFrom;
  final String transferTo;
  final String fiscalDoc;

  Movement({
    required this.id,
    required this.date,
    required this.type,
    required this.account,
    required this.amount,
    this.penalty = 0,
    this.interest = 0,
    this.fee = 0,
    this.documentType = '',
    this.documentNumber = '',
    this.supplier = '',
    this.notes = '',
    this.categoryId = '',
    this.categoryName = '',
    this.subcategoryId = '',
    this.subcategoryName = '',
    this.attachments = 0,
    this.transferId,
    this.transferFrom = '',
    this.transferTo = '',
    this.fiscalDoc = '',
  });

  /// Valor + multa + juros + encargos (igual ao total do ERP).
  double get total => amount + penalty + interest + fee;

  double get extras => penalty + interest + fee;

  /// Total com sinal: entrada positiva, saída negativa.
  double get signed => type == MoveType.entrada ? total : -total;

  bool get isTransfer => transferId != null;

  String get title {
    if (supplier.isNotEmpty) return supplier;
    if (isTransfer) {
      return type == MoveType.saida
          ? 'Transferência → $transferTo'
          : 'Transferência ← $transferFrom';
    }
    if (notes.isNotEmpty) return notes;
    if (documentType.isNotEmpty) {
      return '$documentType ${documentNumber.isEmpty ? '' : documentNumber}'
          .trim();
    }
    return type == MoveType.entrada ? 'Entrada' : 'Saída';
  }

  String get categoryLabel {
    if (isTransfer) return '$transferFrom → $transferTo';
    final c = categoryName.isNotEmpty ? categoryName : categoryId;
    final s = subcategoryName.isNotEmpty ? subcategoryName : subcategoryId;
    if (c.isEmpty) return s;
    return s.isEmpty ? c : '$c › $s';
  }

  static MoveType parseType(dynamic v) {
    final s = str(v)
        .toUpperCase()
        .replaceAll('Í', 'I')
        .replaceAll('Ã', 'A')
        .replaceAll('É', 'E');
    return s.startsWith('ENTR') || s.startsWith('CRED')
        ? MoveType.entrada
        : MoveType.saida;
  }

  factory Movement.fromJson(Map<String, dynamic> j) {
    final fdType = str(j['nota_tipo']);
    final fdNum = str(j['nota_numero']);
    final tid = toInt(j['transfer_id']);
    return Movement(
      id: toInt(j['id']),
      date: parseDateTime(j['movement_date'] ?? j['data_hora']),
      type: parseType(j['movement_type'] ?? j['tipo_movimentacao']),
      account: str(j['cash_account'] ?? j['conta_caixa']),
      amount: toDouble(j['amount'] ?? j['valor']),
      penalty: toDouble(j['penalty_amount'] ?? j['multa']),
      interest: toDouble(j['interest_amount'] ?? j['juros']),
      fee: toDouble(j['fee_amount'] ?? j['encargos']),
      documentType: str(j['document_type'] ?? j['tipo_documento']),
      documentNumber: str(j['document_number'] ?? j['numero_documento']),
      supplier: str(j['supplier_name'] ?? j['fornecedor']),
      notes: str(j['notes'] ?? j['observacao']),
      categoryId: str(j['category'] ?? j['categoria']),
      categoryName: str(j['categoria_nome']),
      subcategoryId: str(j['subcategory'] ?? j['subcategoria']),
      subcategoryName: str(j['subcategoria_nome']),
      attachments: toInt(j['anexos_count']) + toInt(j['nota_anexos_count']),
      transferId: tid > 0 ? tid : null,
      transferFrom: str(j['transf_origem']),
      transferTo: str(j['transf_destino']),
      fiscalDoc: fdNum.isEmpty ? '' : '$fdType $fdNum'.trim(),
    );
  }
}

class Summary {
  final double entradas;
  final double saidas;
  final double transfIn;
  final double transfOut;

  const Summary(this.entradas, this.saidas,
      [this.transfIn = 0, this.transfOut = 0]);

  double get saldo => entradas - saidas;

  factory Summary.fromJson(Map<String, dynamic> j) => Summary(
        toDouble(j['total_entradas']),
        toDouble(j['total_saidas']),
        toDouble(j['transf_entradas']),
        toDouble(j['transf_saidas']),
      );
}

class Account {
  final int id;
  final String name;
  final String bank;
  final bool isDefault;

  const Account(this.id, this.name, {this.bank = '', this.isDefault = false});

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        toInt(j['id']),
        str(j['name']),
        bank: str(j['bank_name']),
        isDefault: j['is_default'] == true,
      );

  bool matches(String accountName) =>
      name.trim().toUpperCase() == accountName.trim().toUpperCase();
}

class CashCategory {
  final int id;
  final String name;
  final bool active;
  const CashCategory(this.id, this.name, {this.active = true});

  factory CashCategory.fromJson(Map<String, dynamic> j) => CashCategory(
        toInt(j['id']),
        str(j['name'] ?? j['nome']),
        active: j['is_active'] != false,
      );
}

class Subcategory {
  final int id;
  final int categoryId;
  final String name;
  final bool active;
  final bool? deductible;

  const Subcategory(this.id, this.categoryId, this.name,
      {this.active = true, this.deductible});

  factory Subcategory.fromJson(Map<String, dynamic> j) => Subcategory(
        toInt(j['id']),
        toInt(j['category_id'] ?? j['categoria_id']),
        str(j['name'] ?? j['nome']),
        active: j['is_active'] != false,
        deductible: j['is_deductible'] is bool ? j['is_deductible'] : null,
      );
}

class Attachment {
  final int id;
  final String name;
  final String mime;
  final String path;
  final String url;

  const Attachment(this.id, this.name, this.mime, this.path, this.url);

  bool get isImage => mime.startsWith('image/');

  factory Attachment.fromJson(Map<String, dynamic> j) => Attachment(
        toInt(j['id']),
        str(j['file_name'] ?? j['filename'] ?? j['name']),
        str(j['mime_type']),
        str(j['storage_path'] ?? j['gcs_path']),
        str(j['url']),
      );
}

/// Totais por categoria (aba Categorias).
class CategoryTotal {
  final String name;
  double entradas = 0;
  double saidas = 0;
  int count = 0;
  final Map<String, double> subs = {};

  CategoryTotal(this.name);

  double get saldo => entradas - saidas;
}

/// Agrupa movimentos (sem transferências) por categoria.
List<CategoryTotal> totalsByCategory(Iterable<Movement> moves) {
  final map = <String, CategoryTotal>{};
  for (final m in moves) {
    if (m.isTransfer) continue;
    final cat = m.categoryName.isNotEmpty
        ? m.categoryName
        : (m.categoryId.isNotEmpty ? m.categoryId : 'Sem categoria');
    final t = map.putIfAbsent(cat, () => CategoryTotal(cat));
    t.count++;
    if (m.type == MoveType.entrada) {
      t.entradas += m.total;
    } else {
      t.saidas += m.total;
    }
    final sub = m.subcategoryName.isNotEmpty
        ? m.subcategoryName
        : (m.subcategoryId.isNotEmpty ? m.subcategoryId : '—');
    t.subs[sub] = (t.subs[sub] ?? 0) + m.signed;
  }
  final list = map.values.toList()
    ..sort((a, b) =>
        (b.entradas + b.saidas).compareTo(a.entradas + a.saidas));
  return list;
}

/// Saldo líquido do período por conta (entradas - saídas, com transferências),
/// igual ao "Saldos" do ERP.
Map<String, double> balanceByAccount(Iterable<Movement> moves) {
  final out = <String, double>{};
  for (final m in moves) {
    final k = m.account.trim().toUpperCase();
    out[k] = (out[k] ?? 0) + m.signed;
  }
  return out;
}
