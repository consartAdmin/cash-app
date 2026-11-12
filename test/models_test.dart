import 'package:consart_caixa/models.dart';
import 'package:flutter_test/flutter_test.dart';

Movement mv(String type, double amount,
        {String account = 'NUBANK',
        String cat = 'Vendas',
        String sub = '',
        int? transfer,
        double interest = 0}) =>
    Movement.fromJson({
      'id': 1,
      'data_hora': '2026-11-04T14:30:00.000Z',
      'tipo_movimentacao': type,
      'conta_caixa': account,
      'valor': '$amount',
      'juros': interest,
      'categoria_nome': cat,
      'subcategoria_nome': sub,
      'transfer_id': transfer,
    });

void main() {
  test('money e parseMoney', () {
    expect(money(1234.5), 'R\$ 1.234,50');
    expect(money(-10), '-R\$ 10,00');
    expect(moneyInput(2800), '2.800,00');
    expect(parseMoney('1.234,56'), 1234.56);
    expect(parseMoney('1234,5'), 1234.5);
    expect(parseMoney('1234.56'), 1234.56);
    expect(parseMoney(''), isNull);
  });

  test('datas', () {
    expect(isoDateTimeLocal(DateTime(2026, 2, 3, 8, 5)), '2026-02-03T08:05');
    expect(dayLabel(DateTime(2026, 11, 6), today: DateTime(2026, 11, 6, 10)),
        'Hoje · sex 06/11');
    expect(dayLabel(DateTime(2026, 11, 5), today: DateTime(2026, 11, 6)),
        'Ontem · qui 05/11');
    expect(dayLabel(DateTime(2026, 11, 4), today: DateTime(2026, 11, 6)),
        'Qua 04/11');
    expect(Period.month(2026, 2).label, 'Fevereiro 2026');
  });

  test('movimento: total e sinal', () {
    final m = mv('SAÍDA', 2800, interest: 140);
    expect(m.type, MoveType.saida);
    expect(m.total, 2940);
    expect(m.signed, -2940);
    expect(mv('ENTRADA', 10).signed, 10);
    expect(mv('Entrada', 10).type, MoveType.entrada);
  });

  test('totais por categoria ignoram transferências', () {
    final list = [
      mv('ENTRADA', 100, cat: 'Vendas', sub: 'Pedidos'),
      mv('SAIDA', 30, cat: 'Veículos', sub: 'Combustível'),
      mv('SAIDA', 20, cat: 'Veículos', sub: 'Combustível'),
      mv('SAIDA', 500, transfer: 7),
    ];
    final t = totalsByCategory(list);
    expect(t.length, 2);
    expect(t.first.name, 'Vendas');
    final v = t.firstWhere((x) => x.name == 'Veículos');
    expect(v.saidas, 50);
    expect(v.subs['Combustível'], -50);
  });

  test('saldo por conta inclui transferências', () {
    final b = balanceByAccount([
      mv('ENTRADA', 100, account: 'Nubank'),
      mv('SAIDA', 40, account: 'NUBANK', transfer: 3),
      mv('ENTRADA', 40, account: 'Espécie', transfer: 3),
    ]);
    expect(b['NUBANK'], 60);
    expect(b['ESPÉCIE'], 40);
  });
}
