import 'package:consart_caixa/debts_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vencimento mantém o dia e usa o último dia do mês curto', () {
    final first = DateTime(2026, 1, 31);
    expect(installmentDueDate(first, 0, 31), DateTime(2026, 1, 31));
    expect(installmentDueDate(first, 1, 31), DateTime(2026, 2, 28));
    expect(installmentDueDate(first, 2, 31), DateTime(2026, 3, 31));
    expect(installmentDueDate(DateTime(2026, 11, 10), 2, 10),
        DateTime(2027, 1, 10));
  });

  test('data DATE do ERP ignora o fuso', () {
    expect(parseDateOnly('2026-11-02T00:00:00.000Z'), DateTime(2026, 11, 2));
    expect(parseDateOnly('2026-11-02'), DateTime(2026, 11, 2));
    expect(parseDateOnly(null), isNull);
  });

  test('parcelas: faixas de valor, pagas e vencidas', () {
    final debt = Debt.fromJson({
      'id': 7,
      'description': 'Empréstimo',
      'original_amount': '1200.00',
      'paid_amount': '100.00',
      'open_amount': '1100.00',
      'installment_total': 12,
      'first_installment_due_at': '2026-10-02T00:00:00.000Z',
      'due_day': 2,
      'status': 'PARCIAL',
      'installments_paid': 1,
    });
    final payments = [
      DebtPayment.fromJson({
        'id': 1,
        'installment_number': 1,
        'payment_date': '2026-10-01',
        'amount': '100.00',
        'interest_amount': '0',
        'fine_amount': '0',
        'discount_amount': '0',
      }),
    ];
    const plans = [InstallmentPlan(7, 12, 150)];
    final list = buildInstallments(debt, payments, plans,
        today: DateTime(2026, 11, 12));

    expect(list.length, 12);
    expect(list[0].status, InstallmentStatus.paga);
    expect(list[0].payment!.id, 1);
    expect(list[1].due, DateTime(2026, 11, 2));
    expect(list[1].status, InstallmentStatus.vencida);
    expect(list[2].status, InstallmentStatus.aberta);
    expect(list[1].expected, 100);
    expect(list[6].expected, 150);
    expect(list[11].label, '012/012');
    expect(debt.nextInstallment, DateTime(2026, 11, 2));
  });

  test('dívida sem parcelamento tem uma parcela', () {
    final debt = Debt.fromJson({
      'id': 1,
      'original_amount': 500,
      'open_amount': 500,
      'installment_total': 0,
      'due_date': '2026-12-01',
    });
    final list = buildInstallments(debt, const [], const [],
        today: DateTime(2026, 11, 12));
    expect(list.length, 1);
    expect(list.first.expected, 500);
    expect(list.first.due, DateTime(2026, 12, 1));
  });

  test('pagamento: valor efetivo e envio do caixa', () {
    final p = DebtPayment.fromJson({
      'id': 3,
      'amount': '100',
      'interest_amount': '5',
      'fine_amount': '2',
      'discount_amount': '1',
    });
    expect(p.effective, 106);
    expect(p.installment, isNull);
    const cash = PaymentCash(accountId: 2, categoryId: 9);
    expect(cash.toJson()['bank_account_id'], 2);
    expect(cash.toJson().containsKey('document_type'), isFalse);
  });
}
