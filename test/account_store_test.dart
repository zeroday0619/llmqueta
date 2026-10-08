import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/models/quota_account.dart';
import 'package:llmqueta/services/account_store.dart';

void main() {
  late Directory directory;
  late AccountStore store;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('accounts-test-');
    store = AccountStore(file: File('${directory.path}/accounts.json'));
  });
  tearDown(() async => directory.delete(recursive: true));

  test('missing configuration preserves default providers', () async {
    expect((await store.load()).map((account) => account.id),
        ['codex', 'claude', 'antigravity']);
  });
  test('multiple accounts round trip without credentials', () async {
    final accounts = [
      QuotaAccount(
          id: 'work',
          provider: ProviderKind.codex,
          label: 'Work',
          configurationDirectory: '${Directory.systemTemp.path}/work'),
      QuotaAccount(
          id: 'personal',
          provider: ProviderKind.codex,
          label: 'Personal',
          configurationDirectory: '${Directory.systemTemp.path}/personal'),
      QuotaAccount(
          id: 'gravity',
          provider: ProviderKind.antigravity,
          label: 'Gravity',
          endpoint: 'http://127.0.0.1:1234',
          csrfTokenEnvironmentVariable: 'WORK_CSRF'),
    ];
    await store.save(accounts);
    await store.save(accounts);
    expect((await store.load()).map((account) => account.toJson()),
        accounts.map((account) => account.toJson()));
    expect(await directory.list().length, 1);
  });
  test('invalid existing configuration cannot be overwritten', () async {
    await store.file.writeAsString('broken');
    await expectLater(store.load(), throwsFormatException);
    await expectLater(store.save(QuotaAccount.defaults), throwsFormatException);
    expect(await store.file.readAsString(), 'broken');
  });
  test('duplicate identifiers and incomplete custom connections fail',
      () async {
    await expectLater(
        store.save([QuotaAccount.defaults.first, QuotaAccount.defaults.first]),
        throwsFormatException);
    for (final provider in ProviderKind.values) {
      expect(
          () => QuotaAccount(id: 'custom', provider: provider, label: 'Custom')
              .validate(),
          throwsFormatException);
    }
    expect(
        () => QuotaAccount(
                id: 'custom',
                provider: ProviderKind.antigravity,
                label: 'Custom',
                endpoint: 'http://secret@localhost')
            .validate(),
        throwsFormatException);
  });
  test(
      'connection validation rejects ambiguous and credential-bearing configuration',
      () {
    for (final account in [
      const QuotaAccount(
          id: 'custom',
          provider: ProviderKind.codex,
          label: 'Custom',
          configurationDirectory: 'relative'),
      QuotaAccount(
          id: 'claude',
          provider: ProviderKind.claude,
          label: 'Default',
          configurationDirectory: directory.path),
      QuotaAccount(
          id: 'custom',
          provider: ProviderKind.codex,
          label: 'Custom',
          configurationDirectory: directory.path,
          snapshotPath: directory.path),
      const QuotaAccount(
          id: 'antigravity',
          provider: ProviderKind.antigravity,
          label: 'Default',
          csrfTokenEnvironmentVariable: 'TOKEN'),
      const QuotaAccount(
          id: 'custom',
          provider: ProviderKind.antigravity,
          label: 'Custom',
          endpoint: 'http://example.com:1234'),
      const QuotaAccount(
          id: 'custom',
          provider: ProviderKind.antigravity,
          label: 'Custom',
          endpoint: 'http://127.0.0.1:1234/path'),
      const QuotaAccount(
          id: 'custom',
          provider: ProviderKind.antigravity,
          label: 'Custom',
          endpoint: 'http://127.0.0.1'),
    ]) {
      expect(account.validate, throwsFormatException);
    }
  });

  test('an empty list remains empty', () async {
    await store.save([]);
    expect(await store.load(), isEmpty);
  });
}
