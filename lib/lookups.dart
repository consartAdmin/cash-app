import 'package:flutter/foundation.dart';

import 'api_service.dart';
import 'debts_models.dart';
import 'models.dart';

/// Contas, categorias e tipos de documento (carregados uma vez).
class Lookups {
  Lookups._();
  static final Lookups instance = Lookups._();

  List<Account> accounts = const [];
  List<CashCategory> categories = const [];
  List<Subcategory> subcategories = const [];
  List<String> documentTypes = const [];
  List<DebtType> debtTypes = const [];
  Future<void>? _loading;

  Future<void> load({bool force = false}) {
    if (force) _loading = null;
    return _loading ??= _load().catchError((Object e) {
      _loading = null;
      throw e;
    });
  }

  Future<void> _load() async {
    final api = ApiService.instance;
    final r = await Future.wait([
      api.accounts(),
      api.categories(),
      api.subcategories(),
      api.documentTypes().catchError((_) => <String>[]),
      api.debtTypes().catchError((_) => <DebtType>[]),
    ]);
    accounts = r[0] as List<Account>;
    categories = r[1] as List<CashCategory>;
    subcategories = r[2] as List<Subcategory>;
    documentTypes = r[3] as List<String>;
    debtTypes = r[4] as List<DebtType>;
  }

  List<Subcategory> subsOf(int categoryId) =>
      subcategories.where((s) => s.categoryId == categoryId).toList();

  /// A movimentação guarda o id ou o nome da categoria.
  CashCategory? findCategory(String idOrName, [String name = '']) {
    for (final c in categories) {
      if ('${c.id}' == idOrName ||
          c.name.toUpperCase() == idOrName.toUpperCase() ||
          (name.isNotEmpty && c.name.toUpperCase() == name.toUpperCase())) {
        return c;
      }
    }
    return null;
  }

  Subcategory? findSubcategory(int categoryId, String idOrName,
      [String name = '']) {
    for (final s in subsOf(categoryId)) {
      if ('${s.id}' == idOrName ||
          s.name.toUpperCase() == idOrName.toUpperCase() ||
          (name.isNotEmpty && s.name.toUpperCase() == name.toUpperCase())) {
        return s;
      }
    }
    return null;
  }

  /// Nome do tipo de dívida (a dívida guarda o código).
  String debtTypeName(String code) {
    for (final t in debtTypes) {
      if (t.code == code) return t.name;
    }
    return code;
  }

  Account? findAccountById(int? id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  Account? findAccount(String name) {
    for (final a in accounts) {
      if (a.matches(name)) return a;
    }
    return null;
  }
}

/// Avisa as telas para recarregar depois de salvar/excluir.
final dataChanged = ValueNotifier<int>(0);

void notifyDataChanged() => dataChanged.value++;
