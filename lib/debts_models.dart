// Modelos do módulo Dívidas do ERP (/api/debts), as mesmas regras da tela
// Dívidas no navegador.

import 'models.dart';

/// Datas DATE do ERP chegam como "2026-11-02" ou "2026-11-02T00:00:00.000Z".
/// Como a tela web, usa só os 10 primeiros caracteres (sem fuso).
DateTime? parseDateOnly(dynamic v) {
  final s = str(v);
  if (s.length < 10) return null;
  return DateTime.tryParse(s.substring(0, 10));
}

DateTime _today() {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// Status da dívida no ERP.
enum DebtStatus { emAberto, parcial, pago, vencido }

DebtStatus debtStatusOf(String s) => switch (s.toUpperCase()) {
      'PAGO' => DebtStatus.pago,
      'PARCIAL' => DebtStatus.parcial,
      'VENCIDO' => DebtStatus.vencido,
      _ => DebtStatus.emAberto,
    };

String debtStatusLabel(DebtStatus s) => switch (s) {
      DebtStatus.emAberto => 'EM ABERTO',
      DebtStatus.parcial => 'PARCIAL',
      DebtStatus.pago => 'PAGA',
      DebtStatus.vencido => 'VENCIDA',
    };

/// Valor do filtro "status" da API.
String debtStatusQuery(DebtStatus s) => switch (s) {
      DebtStatus.emAberto => 'EM_ABERTO',
      DebtStatus.parcial => 'PARCIAL',
      DebtStatus.pago => 'PAGO',
      DebtStatus.vencido => 'VENCIDO',
    };

class Debt {
  final int id;
  final String code;
  final String description;
  final String creditor;
  final String creditorDocument;
  final String type;
  final String documentNumber;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final DateTime? firstDueDate;
  final int dueDay;
  final double original;
  final double interest;
  final double fine;
  final double discount;
  final double updated;
  final double paid;
  final double open;
  final DebtStatus status;
  final String notes;
  final int installmentTotal;
  final int installmentsPaid;
  final int cashCategoryId;
  final int cashSubcategoryId;

  const Debt({
    required this.id,
    this.code = '',
    this.description = '',
    this.creditor = '',
    this.creditorDocument = '',
    this.type = '',
    this.documentNumber = '',
    this.issueDate,
    this.dueDate,
    this.firstDueDate,
    this.dueDay = 0,
    this.original = 0,
    this.interest = 0,
    this.fine = 0,
    this.discount = 0,
    this.updated = 0,
    this.paid = 0,
    this.open = 0,
    this.status = DebtStatus.emAberto,
    this.notes = '',
    this.installmentTotal = 1,
    this.installmentsPaid = 0,
    this.cashCategoryId = 0,
    this.cashSubcategoryId = 0,
  });

  factory Debt.fromJson(Map<String, dynamic> j) {
    final total = toInt(j['installment_total']);
    return Debt(
      id: toInt(j['id']),
      code: str(j['code']),
      description: str(j['description']),
      creditor: str(j['creditor_name']),
      creditorDocument: str(j['creditor_document']),
      type: str(j['debt_type']),
      documentNumber: str(j['document_number']),
      issueDate: parseDateOnly(j['issue_date']),
      dueDate: parseDateOnly(j['due_date']),
      firstDueDate: parseDateOnly(j['first_installment_due_at']),
      dueDay: toInt(j['due_day']),
      original: toDouble(j['original_amount']),
      interest: toDouble(j['interest_amount']),
      fine: toDouble(j['fine_amount']),
      discount: toDouble(j['discount_amount']),
      updated: toDouble(j['updated_amount']),
      paid: toDouble(j['paid_amount']),
      open: toDouble(j['open_amount']),
      status: debtStatusOf(str(j['status'])),
      notes: str(j['notes']),
      installmentTotal: total > 0 ? total : 1,
      installmentsPaid: toInt(j['installments_paid']),
      cashCategoryId: toInt(j['cash_category_id']),
      cashSubcategoryId: toInt(j['cash_subcategory_id']),
    );
  }

  String get title => description.isNotEmpty
      ? description
      : (creditor.isNotEmpty ? creditor : 'Dívida #$id');

  /// Total a pagar (original + juros + multa - desconto).
  double get total => updated > 0 ? updated : original;

  double get progress => total <= 0 ? 0 : (paid / total).clamp(0, 1).toDouble();

  bool get isOverdue =>
      status == DebtStatus.vencido ||
      (open > 0 && dueDate != null && dueDate!.isBefore(_today()));

  /// Vencido pela próxima parcela em aberto, mesmo se o ERP diz PARCIAL.
  DebtStatus get displayStatus {
    if (open <= 0) return DebtStatus.pago;
    final next = nextInstallment;
    if (next != null && next.isBefore(_today())) return DebtStatus.vencido;
    return status;
  }

  /// Vencimento estimado da próxima parcela (parcelas pagas em ordem).
  DateTime? get nextInstallment {
    if (open <= 0) return null;
    final first = firstDueDate ?? dueDate ?? issueDate;
    if (first == null) return null;
    final n = installmentsPaid.clamp(0, installmentTotal - 1);
    return installmentDueDate(first, n, dueDay > 0 ? dueDay : first.day);
  }
}

class DebtPayment {
  final int id;
  final int debtId;
  final int? installment;
  final DateTime? installmentDue;
  final DateTime? date;
  final double amount;
  final double interest;
  final double fine;
  final double discount;
  final double effective;
  final String method;
  final String receipt;
  final String notes;

  const DebtPayment({
    required this.id,
    this.debtId = 0,
    this.installment,
    this.installmentDue,
    this.date,
    this.amount = 0,
    this.interest = 0,
    this.fine = 0,
    this.discount = 0,
    this.effective = 0,
    this.method = '',
    this.receipt = '',
    this.notes = '',
  });

  factory DebtPayment.fromJson(Map<String, dynamic> j) {
    final n = toInt(j['installment_number']);
    final amount = toDouble(j['amount']);
    final interest = toDouble(j['interest_amount']);
    final fine = toDouble(j['fine_amount']);
    final discount = toDouble(j['discount_amount']);
    final eff = j['effective_amount'] == null
        ? amount + interest + fine - discount
        : toDouble(j['effective_amount']);
    return DebtPayment(
      id: toInt(j['id']),
      debtId: toInt(j['debt_id']),
      installment: n > 0 ? n : null,
      installmentDue: parseDateOnly(j['installment_due_date']),
      date: parseDateOnly(j['payment_date']),
      amount: amount,
      interest: interest,
      fine: fine,
      discount: discount,
      effective: eff,
      method: str(j['payment_method']),
      receipt: str(j['receipt_number']),
      notes: str(j['notes']),
    );
  }
}

/// Faixa de parcelas com valor próprio (ex.: 1 a 6 = R$ 500, 7 a 12 = R$ 800).
class InstallmentPlan {
  final int start;
  final int end;
  final double amount;
  const InstallmentPlan(this.start, this.end, this.amount);

  factory InstallmentPlan.fromJson(Map<String, dynamic> j) => InstallmentPlan(
        toInt(j['start_installment']),
        toInt(j['end_installment']),
        toDouble(j['installment_amount']),
      );

  Map<String, dynamic> toJson() => {
        'start_installment': start,
        'end_installment': end,
        'installment_amount': amount,
      };
}

enum InstallmentStatus { aberta, vencida, paga }

class Installment {
  final int number;
  final int total;
  final DateTime? due;
  final double expected;
  final InstallmentStatus status;
  final DebtPayment? payment;

  const Installment({
    required this.number,
    required this.total,
    this.due,
    this.expected = 0,
    this.status = InstallmentStatus.aberta,
    this.payment,
  });

  bool get isPaid => status == InstallmentStatus.paga;

  String get label =>
      '${number.toString().padLeft(3, '0')}/${total.toString().padLeft(3, '0')}';
}

/// Mês [index] depois de [first], mantendo o dia de vencimento (ou o último
/// dia do mês, se for menor). Igual a addMonthsKeepingDueDay da tela web.
DateTime installmentDueDate(DateTime first, int index, int dueDay) {
  final month = first.month - 1 + index;
  final year = first.year + (month ~/ 12);
  final m = month % 12 + 1;
  final last = DateTime(year, m + 1, 0).day;
  final day = dueDay < last ? dueDay : last;
  return DateTime(year, m, day);
}

/// Parcelas da dívida (o ERP não guarda parcelas: calcula a partir do total,
/// 1º vencimento, dia de vencimento e faixas de valor).
List<Installment> buildInstallments(
  Debt debt,
  List<DebtPayment> payments,
  List<InstallmentPlan> plans, {
  DateTime? today,
}) {
  final total = debt.installmentTotal;
  final first = debt.firstDueDate ?? debt.dueDate ?? debt.issueDate;
  if (total <= 0 || first == null) return const [];
  // Sem dia de vencimento: usa o dia do 1º vencimento.
  final dueDay = debt.dueDay > 0 ? debt.dueDay : first.day;
  final fallback = debt.original / total;
  final t = today ?? _today();

  final paid = <int, DebtPayment>{};
  for (final p in payments) {
    if (p.installment != null) paid.putIfAbsent(p.installment!, () => p);
  }

  return [
    for (var n = 1; n <= total; n++)
      () {
        final due = installmentDueDate(first, n - 1, dueDay);
        final plan = plans.where((p) => n >= p.start && n <= p.end);
        final payment = paid[n];
        return Installment(
          number: n,
          total: total,
          due: due,
          expected: _round(plan.isEmpty ? fallback : plan.first.amount),
          status: payment != null
              ? InstallmentStatus.paga
              : (due.isBefore(t)
                  ? InstallmentStatus.vencida
                  : InstallmentStatus.aberta),
          payment: payment,
        );
      }(),
  ];
}

double _round(double v) => (v * 100).round() / 100;

class DebtsSummary {
  final int count;
  final int countOpen;
  final int countOverdue;
  final double totalOpen;
  final double totalOverdue;
  final double totalPaid;

  const DebtsSummary({
    this.count = 0,
    this.countOpen = 0,
    this.countOverdue = 0,
    this.totalOpen = 0,
    this.totalOverdue = 0,
    this.totalPaid = 0,
  });

  factory DebtsSummary.fromJson(Map<String, dynamic> j) => DebtsSummary(
        count: toInt(j['total_debts']),
        countOpen: toInt(j['count_open']),
        countOverdue: toInt(j['count_overdue']),
        totalOpen: toDouble(j['total_open']),
        totalOverdue: toDouble(j['total_overdue']),
        totalPaid: toDouble(j['total_paid']),
      );
}

class DebtType {
  final String code;
  final String name;
  const DebtType(this.code, this.name);

  factory DebtType.fromJson(Map<String, dynamic> j) {
    final code = str(j['code']);
    final name = str(j['name']);
    return DebtType(code.isNotEmpty ? code : name, name.isNotEmpty ? name : code);
  }
}

/// Classificação da SAÍDA no Caixa criada com o pagamento.
class PaymentCash {
  final int? accountId;
  final int? categoryId;
  final int? subcategoryId;

  /// Conta contábil: não aparece no app, mas é mantida (padrão/edição).
  final int? chartAccountId;
  final String documentType;
  const PaymentCash(
      {this.accountId,
      this.categoryId,
      this.subcategoryId,
      this.chartAccountId,
      this.documentType = ''});

  factory PaymentCash.fromJson(Map<String, dynamic> j) {
    int? id(dynamic v) => toInt(v) > 0 ? toInt(v) : null;
    return PaymentCash(
      accountId: id(j['bank_account_id']),
      categoryId: id(j['category_id']),
      subcategoryId: id(j['subcategory_id']),
      chartAccountId: id(j['chart_account_id']),
      documentType: str(j['document_type']),
    );
  }

  Map<String, dynamic> toJson() => {
        'bank_account_id': accountId,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'chart_account_id': chartAccountId,
        if (documentType.isNotEmpty) 'document_type': documentType,
      };
}
