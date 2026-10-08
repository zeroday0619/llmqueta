import 'dart:convert';
import 'dart:io';

import '../models/quota_account.dart';
import 'app_paths.dart';

class AccountStore {
  AccountStore({File? file}) : file = file ?? _defaultFile();

  final File file;

  static File _defaultFile() =>
      File('${AppPaths().configurationDirectory}/accounts.json');

  Future<List<QuotaAccount>> load() async {
    if (!await file.exists()) return List.of(QuotaAccount.defaults);
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map ||
        decoded['version'] != 1 ||
        decoded['accounts'] is! List) {
      throw const FormatException('Unsupported account configuration.');
    }
    final accounts = <QuotaAccount>[];
    for (final value in decoded['accounts'] as List) {
      if (value is! Map<String, dynamic>)
        throw const FormatException('Invalid account entry.');
      accounts.add(QuotaAccount.fromJson(value));
    }
    validateAccounts(accounts);
    return accounts;
  }

  Future<void> save(List<QuotaAccount> accounts) async {
    validateAccounts(accounts);
    // Existing invalid configuration requires explicit repair before replacement.
    await load();
    await file.parent.create(recursive: true);
    final directory = await file.parent.createTemp('.accounts-');
    final temporary = File('${directory.path}/accounts.json');
    try {
      await temporary.writeAsString(
          '${const JsonEncoder.withIndent('  ').convert({
                'version': 1,
                'accounts': accounts.map((account) => account.toJson()).toList()
              })}\n',
          flush: true);
      await temporary.rename(file.path);
    } finally {
      await directory.delete(recursive: true);
    }
  }
}
