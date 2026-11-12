import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'debts_models.dart';
import 'models.dart';

class ApiException implements Exception {
  final String message;
  final int? status;
  ApiException(this.message, [this.status]);

  @override
  String toString() => message;
}

/// Cliente das APIs do módulo Caixa do ERP (/api/caixa, as mesmas da tela
/// Caixa no navegador).
class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  static const defaultServer = 'https://erp.consart.com.br';
  static const _kServer = 'server_url';
  static const _kToken = 'token';
  static const _kUserName = 'user_name';

  String serverUrl = '';
  String? token;
  String? userName;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    serverUrl = p.getString(_kServer) ?? defaultServer;
    token = p.getString(_kToken);
    userName = p.getString(_kUserName);
  }

  Future<void> logout() async {
    token = null;
    userName = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUserName);
  }

  static String normalizeServer(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    if (serverUrl.isEmpty) {
      throw ApiException('Configure o endereço do servidor.');
    }
    return Uri.parse('$serverUrl$path').replace(queryParameters: query);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (isLoggedIn) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final req = http.Request(method, _uri(path, query))
      ..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    return _execute(req, timeout: timeout);
  }

  Future<http.Response> _raw(http.BaseRequest req, Duration timeout) async {
    try {
      return await http.Response.fromStream(await req.send().timeout(timeout));
    } on TimeoutException {
      throw ApiException('Servidor não respondeu. Verifique a conexão.');
    } catch (_) {
      throw ApiException('Sem conexão com o servidor ($serverUrl).');
    }
  }

  static ApiException _error(http.Response res, Map<String, dynamic> json) {
    if (res.statusCode == 401) {
      return ApiException('Sessão expirada. Saia e entre novamente.', 401);
    }
    var msg = json['message'] ?? json['error'] ?? json['erro'];
    // Algumas rotas mandam o código em "error" e o texto em "message".
    if (msg is String && RegExp(r'^[A-Z0-9_]+$').hasMatch(msg)) {
      final detail = json['detail'];
      if (detail is String && detail.isNotEmpty) msg = '$msg: $detail';
    }
    return ApiException(
      msg is String && msg.isNotEmpty
          ? msg
          : 'Erro na requisição (${res.statusCode}).',
      res.statusCode,
    );
  }

  Future<dynamic> _execute(
    http.BaseRequest req, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final res = await _raw(req, timeout);
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {}
    final json =
        decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _error(res, json);
    }
    if (json['ok'] == false || json['success'] == false) {
      throw _error(res, json);
    }
    return decoded;
  }

  // ── Login ────────────────────────────────────────────────────────────
  Future<void> login(String server, String login, String password) async {
    final url = normalizeServer(server);
    serverUrl = url;
    final json = _map(await _send('POST', '/api/login',
        body: {'login': login.trim(), 'password': password}));
    final t = json['token'];
    if (t is! String || t.isEmpty) {
      throw ApiException('Login sem token na resposta.');
    }
    token = t;
    final user = json['user'];
    userName = user is Map ? (user['name']?.toString() ?? login) : login;

    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, url);
    await p.setString(_kToken, t);
    await p.setString(_kUserName, userName!);
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map ? v.cast<String, dynamic>() : <String, dynamic>{};

  /// Aceita lista pura ou {rows|data|items|...: [...]}.
  static List<Map<String, dynamic>> _rows(dynamic json) {
    dynamic raw = json;
    if (json is Map) {
      for (final k in ['rows', 'data', 'items']) {
        final v = json[k];
        if (v is List) {
          raw = v;
          break;
        }
        if (v is Map && v['rows'] is List) {
          raw = v['rows'];
          break;
        }
      }
    }
    return (raw is List ? raw : const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  static Map<String, String> _clean(Map<String, String?> q) => {
        for (final e in q.entries)
          if (e.value != null && e.value!.trim().isNotEmpty)
            e.key: e.value!.trim(),
      };

  // ── Cadastros ────────────────────────────────────────────────────────

  /// Contas bancárias ativas (Nubank, Asaas, Espécie...), a padrão primeiro.
  Future<List<Account>> accounts() async {
    final json =
        await _send('GET', '/api/bank-accounts', query: {'active': 'true'});
    final list = _rows(json)
        .where((e) => e['is_active'] != false)
        .map(Account.fromJson)
        .where((a) => a.id > 0 && a.name.isNotEmpty)
        .toList()
      ..sort((a, b) {
        if (a.isDefault != b.isDefault) return a.isDefault ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return list;
  }

  Future<List<CashCategory>> categories() async {
    final json = await _send('GET', '/api/caixa/categorias');
    return _rows(json)
        .map(CashCategory.fromJson)
        .where((c) => c.id > 0 && c.name.isNotEmpty)
        .toList();
  }

  Future<List<Subcategory>> subcategories() async {
    final json = await _send('GET', '/api/caixa/subcategorias');
    return _rows(json)
        .map(Subcategory.fromJson)
        .where((s) => s.id > 0 && s.name.isNotEmpty)
        .toList();
  }

  Future<List<String>> documentTypes() async {
    final json = await _send('GET', '/api/cash-document-types',
        query: {'activeOnly': 'true'});
    return _rows(json)
        .map((e) => str(e['name']))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  // ── Movimentações ────────────────────────────────────────────────────

  Map<String, String> _filterQuery(MoveFilter f) => _clean({
        'date_from': isoDate(f.period.start),
        'date_to': isoDate(f.period.end),
        'tipo': f.type,
        'conta': f.accountId?.toString(),
        'categoria': f.categoryId?.toString(),
        'search': f.search,
        'anexos': f.attachments,
      });

  /// GET /api/caixa/movimentacoes — todas as páginas (até [maxRows]).
  Future<(List<Movement>, int)> movements(MoveFilter f,
      {int maxRows = 3000}) async {
    const pageSize = 500;
    final rows = <Map<String, dynamic>>[];
    var total = 0;
    for (var page = 1; page <= (maxRows / pageSize).ceil(); page++) {
      final json = await _send('GET', '/api/caixa/movimentacoes', query: {
        ..._filterQuery(f),
        'page': '$page',
        'pageSize': '$pageSize',
        'orderBy': 'data-hora DESC',
      });
      final chunk = _rows(json);
      total = json is Map ? toInt(json['total']) : chunk.length;
      rows.addAll(chunk);
      if (chunk.length < pageSize || rows.length >= total) break;
    }
    return (
      rows.map(Movement.fromJson).toList(),
      total < rows.length ? rows.length : total
    );
  }

  /// GET /api/caixa/summary — entradas/saídas sem transferências.
  Future<Summary> summary(MoveFilter f) async {
    final json = await _send('GET', '/api/caixa/summary', query: _filterQuery(f));
    return Summary.fromJson(_map(json));
  }

  Future<Movement> movement(int id) async {
    final json = await _send('GET', '/api/caixa/movimentacoes/$id');
    return Movement.fromJson(_map(json));
  }

  /// Cria ([id] null) ou altera uma entrada/saída. Devolve o id.
  Future<int> saveMovement(Map<String, dynamic> body, {int? id}) async {
    final json = await _send(
      id == null ? 'POST' : 'PUT',
      id == null ? '/api/caixa/movimentacoes' : '/api/caixa/movimentacoes/$id',
      body: body,
    );
    final m = _map(json);
    final newId = toInt(m['id'] ?? (m['movimentacao'] is Map
        ? (m['movimentacao'] as Map)['id']
        : null));
    return newId > 0 ? newId : (id ?? 0);
  }

  Future<void> deleteMovement(Movement m) async {
    if (m.isTransfer) {
      await _send('DELETE', '/api/caixa/transferencias/${m.transferId}');
    } else {
      await _send('DELETE', '/api/caixa/movimentacoes/${m.id}');
    }
  }

  /// POST /api/caixa/transferencias: saída na origem + entrada no destino.
  Future<void> createTransfer({
    required int fromAccountId,
    required int toAccountId,
    required DateTime date,
    required double amount,
    double fee = 0,
    String? notes,
  }) async {
    await _send('POST', '/api/caixa/transferencias', body: {
      'from_bank_account_id': fromAccountId,
      'to_bank_account_id': toAccountId,
      'transfer_date': isoDateTimeLocal(date),
      'amount': amount,
      if (fee > 0) 'fee_amount': fee,
      'notes': notes ?? '',
    });
  }

  // ── Anexos ───────────────────────────────────────────────────────────

  Future<List<Attachment>> attachments(int movementId) async {
    final json =
        await _send('GET', '/api/caixa/movimentacoes/$movementId/anexos');
    return _rows(json).map(Attachment.fromJson).toList();
  }

  /// POST /api/upload/anexo (multipart: movId + arquivo).
  Future<void> uploadAttachment(
      int movementId, List<int> bytes, String fileName) async {
    final req = http.MultipartRequest('POST', _uri('/api/upload/anexo'))
      ..headers.addAll({
        'Accept': 'application/json',
        if (isLoggedIn) 'Authorization': 'Bearer $token',
      })
      ..fields['movId'] = '$movementId'
      ..files.add(http.MultipartFile.fromBytes('arquivo', bytes,
          filename: fileName, contentType: _mimeOf(fileName)));
    await _execute(req, timeout: const Duration(seconds: 90));
  }

  static MediaType _mimeOf(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return MediaType('image', 'png');
    if (n.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (n.endsWith('.heic')) return MediaType('image', 'heic');
    return MediaType('image', 'jpeg');
  }

  Future<void> deleteAttachment(int movementId, int attachmentId) async {
    await _send(
        'DELETE', '/api/caixa/movimentacoes/$movementId/anexos/$attachmentId');
  }

  /// Link temporário (10 min) para abrir o anexo do bucket.
  Future<String> attachmentUrl(Attachment a) async {
    if (a.path.isEmpty) return a.url;
    try {
      final json = await _send('GET', '/api/upload/anexo/sign-read',
          query: {'object': a.path});
      final url = str(_map(json)['url']);
      return url.isNotEmpty ? url : a.url;
    } catch (_) {
      return a.url;
    }
  }

  /// Relatório PDF do Caixa com os filtros (o ERP gera o arquivo).
  Uri reportUrl(MoveFilter f) =>
      _uri('/api/caixa/relatorio/pdf', _filterQuery(f));

  // ── Dívidas (/api/debts, mesma tela Dívidas do ERP) ──────────────────

  /// GET /api/debts — todas as páginas (até [maxRows]).
  Future<List<Debt>> debts(
      {String? search, DebtStatus? status, bool onlyOpen = false,
      int maxRows = 2000}) async {
    const limit = 200;
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; page <= (maxRows / limit).ceil(); page++) {
      final json = await _send('GET', '/api/debts',
          query: _clean({
            'q': search,
            'status': status == null ? null : debtStatusQuery(status),
            'only_open': onlyOpen ? 'true' : null,
            'page': '$page',
            'limit': '$limit',
          }));
      final chunk = _rows(json);
      rows.addAll(chunk);
      final total = json is Map ? toInt(json['total']) : chunk.length;
      if (chunk.length < limit || rows.length >= total) break;
    }
    return rows.map(Debt.fromJson).toList();
  }

  Future<DebtsSummary> debtsSummary() async {
    final json = _map(await _send('GET', '/api/debts/summary'));
    return DebtsSummary.fromJson(_map(json['summary']));
  }

  Future<Debt> debt(int id) async {
    final json = _map(await _send('GET', '/api/debts/$id'));
    return Debt.fromJson(_map(json['row'] ?? json));
  }

  Future<List<DebtPayment>> debtPayments(int debtId) async {
    final json = await _send('GET', '/api/debts/$debtId/payments');
    return _rows(json).map(DebtPayment.fromJson).toList();
  }

  Future<List<InstallmentPlan>> installmentPlans(int debtId) async {
    final json = await _send('GET', '/api/debts/$debtId/installment-plans');
    return _rows(json).map(InstallmentPlan.fromJson).toList();
  }

  Future<void> saveInstallmentPlans(
      int debtId, List<InstallmentPlan> plans) async {
    await _send('POST', '/api/debts/$debtId/installment-plans',
        body: {'rows': plans.map((p) => p.toJson()).toList()});
  }

  Future<List<DebtType>> debtTypes() async {
    final json =
        await _send('GET', '/api/debts-types', query: {'active': 'true'});
    return _rows(json)
        .map(DebtType.fromJson)
        .where((t) => t.code.isNotEmpty)
        .toList();
  }

  /// Cria ([id] null) ou altera uma dívida. Devolve o id.
  Future<int> saveDebt(Map<String, dynamic> body, {int? id}) async {
    final json = _map(await _send(
      id == null ? 'POST' : 'PUT',
      id == null ? '/api/debts' : '/api/debts/$id',
      body: body,
    ));
    final newId = toInt(_map(json['row'])['id']);
    return newId > 0 ? newId : (id ?? 0);
  }

  Future<void> deleteDebt(int id) async {
    await _send('DELETE', '/api/debts/$id');
  }

  /// Conta/categoria sugeridas para a saída no Caixa (último pagamento da
  /// dívida ou última saída do mesmo credor).
  Future<PaymentCash> debtCashDefaults(int debtId) async {
    final json =
        _map(await _send('GET', '/api/debts/$debtId/payments/cash-defaults'));
    return PaymentCash.fromJson(_map(json['data']));
  }

  /// POST /api/debts/:id/payments — o ERP já lança a SAÍDA no Caixa.
  /// Devolve o id da movimentação criada (para anexar o comprovante).
  Future<int> createDebtPayment(int debtId, Map<String, dynamic> body) async {
    final json =
        _map(await _send('POST', '/api/debts/$debtId/payments', body: body));
    return toInt(json['cash_movement_id'] ??
        _map(json['payment'])['cash_movement_id']);
  }

  Future<PaymentCash> debtPaymentCash(int paymentId) async {
    final json = _map(await _send('GET', '/api/debt-payments/$paymentId/cash'));
    return PaymentCash.fromJson(_map(json['data']));
  }

  /// PUT /api/debt-payments/:id — atualiza também a saída no Caixa.
  Future<int> updateDebtPayment(
      int paymentId, Map<String, dynamic> body) async {
    final json =
        _map(await _send('PUT', '/api/debt-payments/$paymentId', body: body));
    return toInt(json['cash_movement_id'] ??
        _map(json['payment'])['cash_movement_id']);
  }

  /// Exclui o pagamento (e a saída do Caixa ligada a ele).
  Future<void> deleteDebtPayment(int paymentId) async {
    await _send('DELETE', '/api/debt-payments/$paymentId');
  }
}

/// Filtros da lista (mesmos nomes da API do Caixa).
class MoveFilter {
  final Period period;

  /// ENTRADA, SAIDA, TRANSFERENCIA ou null (todos).
  final String? type;
  final int? accountId;
  final int? categoryId;
  final String? search;

  /// "com", "sem" ou null.
  final String? attachments;

  const MoveFilter({
    required this.period,
    this.type,
    this.accountId,
    this.categoryId,
    this.search,
    this.attachments,
  });

  MoveFilter copyWith({
    Period? period,
    String? Function()? type,
    int? Function()? accountId,
    int? Function()? categoryId,
    String? Function()? search,
    String? Function()? attachments,
  }) =>
      MoveFilter(
        period: period ?? this.period,
        type: type != null ? type() : this.type,
        accountId: accountId != null ? accountId() : this.accountId,
        categoryId: categoryId != null ? categoryId() : this.categoryId,
        search: search != null ? search() : this.search,
        attachments: attachments != null ? attachments() : this.attachments,
      );
}
