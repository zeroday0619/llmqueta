import 'dart:convert';
import 'dart:io';

import '../lib/models/quota.dart';
import '../lib/services/quota_sources.dart';

Future<void> main() async {
  final sources = QuotaSources();
  final results = await Future.wait(ProviderKind.values.map(sources.fetch));
  for (final snapshot in results) {
    stdout.writeln(jsonEncode({
      'provider': snapshot.provider.name,
      'status': snapshot.status.name,
      'window_count': snapshot.windows.length,
      'reset_time_count':
          snapshot.windows.where((window) => window.resetsAt != null).length,
      'message': snapshot.message,
    }));
  }
}
