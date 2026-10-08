import 'dart:convert';
import 'dart:io';

import '../lib/services/account_store.dart';
import '../lib/services/quota_sources.dart';

Future<void> main() async {
  final sources = QuotaSources();
  final accounts = await AccountStore().load();
  final results = await Future.wait(accounts.map(sources.fetchAccount));
  for (var index = 0; index < results.length; index++) {
    final snapshot = results[index];
    stdout.writeln(jsonEncode({
      'account_index': index + 1,
      'provider': snapshot.provider.name,
      'status': snapshot.status.name,
      'window_count': snapshot.windows.length,
      'reset_time_count':
          snapshot.windows.where((window) => window.resetsAt != null).length,
      'message': snapshot.message,
    }));
  }
}
