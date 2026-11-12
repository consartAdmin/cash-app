# CONSART Caixa

App Flutter (Android e iOS) para lançar e consultar as movimentações do
**Caixa** do ERP Infinity (https://erp.consart.com.br), usando as mesmas APIs
da tela Caixa do ERP (`/api/caixa`).

## Telas

- **Início**: saldo do mês (entradas − saídas, sem transferências), saldo do
  período por conta (Nubank, Asaas, Espécie, Banco do Brasil... vindas de
  `/api/bank-accounts`) e os últimos lançamentos.
- **Movimentos**: lista agrupada por dia, com busca e filtros de período,
  tipo (entrada, saída, transferência), conta, categoria e anexo; totais do
  filtro e o relatório PDF do ERP.
- **Detalhe**: todos os campos, anexos (abrir, adicionar foto pela câmera ou
  galeria, excluir), editar e excluir.
- **Novo lançamento**: entrada ou saída com valor, data/hora, conta,
  categoria/subcategoria, fornecedor, tipo e número do documento, multa,
  juros, encargos, observação e foto do comprovante.
- **Transferência** entre contas (`/api/caixa/transferencias`): cria a saída
  na origem e a entrada no destino juntas, com tarifa opcional.
- **Categorias**: entradas, saídas e resultado do período por categoria e
  subcategoria, com filtro por conta.

## APK

Cada push na `main` gera um APK pelo GitHub Actions. Último APK:
https://github.com/consartAdmin/cash-app/releases/latest/download/consart-caixa.apk

## iPhone

O workflow `ios-testflight.yml` envia para o TestFlight (bundle
`br.com.consart.caixa`) quando os 4 secrets da App Store Connect estiverem
configurados no repositório; sem eles, só compila.
