import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/models/quota_account.dart';
import 'package:llmqueta/services/quota_sources.dart';

void main() {
  test('Claude accounts use distinct snapshots and configuration directories',
      () async {
    final temporary = await Directory.systemTemp.createTemp('quota-accounts-');
    addTearDown(() => temporary.delete(recursive: true));
    final sources = QuotaSources(environment: {
      'HOME': temporary.path,
      'LLMQUETA_CLAUDE_EXECUTABLE': '${temporary.path}/missing',
    });
    final accounts = <QuotaAccount>[];
    for (var index = 1; index <= 2; index++) {
      final directory = Directory('${temporary.path}/profile$index');
      await directory.create();
      final snapshot = File('${directory.path}/quota.json');
      await snapshot.writeAsString(jsonEncode({
        'observed_at': DateTime.now().toUtc().toIso8601String(),
        'rate_limits': {
          'five_hour': {'used_percentage': index * 20}
        },
      }));
      final transcript =
          File('${directory.path}/projects/example/session.jsonl');
      await transcript.parent.create(recursive: true);
      await transcript.writeAsString('${jsonEncode({
            'type': 'assistant',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'message': {
              'id': 'message',
              'usage': {'input_tokens': index * 100, 'output_tokens': 0}
            },
          })}\n');
      accounts.add(QuotaAccount(
          id: 'claude$index',
          provider: ProviderKind.claude,
          label: 'Claude $index',
          configurationDirectory: directory.path,
          snapshotPath: snapshot.path));
    }
    final snapshots = await Future.wait(accounts.map(sources.fetchAccount));
    expect(snapshots.map((snapshot) => snapshot.windows.single.usedPercent),
        [20, 40]);
    expect(snapshots.map((snapshot) => snapshot.tokenUsage.lifetime?.total),
        [100, 200]);
    expect(snapshots.map((snapshot) => snapshot.accountId),
        ['claude1', 'claude2']);
    final invalid = await sources.fetchAccount(QuotaAccount(
        id: 'bad',
        provider: ProviderKind.claude,
        label: 'Bad',
        snapshotPath: accounts.first.snapshotPath));
    expect(invalid.status, QuotaStatus.error);
    expect(invalid.windows, isEmpty);
    expect(invalid.tokenUsage.lifetime, isNull);
  });

  test('Codex account processes isolate homes and inherited authentication',
      () async {
    final temporary = await Directory.systemTemp.createTemp('quota-codex-');
    addTearDown(() => temporary.delete(recursive: true));
    final executable = File('${temporary.path}/codex');
    await executable.writeAsString(r'''#!/bin/sh
[ -z "$OPENAI_API_KEY$CODEX_API_KEY$CODEX_THREAD_ID$LLMQUETA_CODEX_THREAD_ID" ] || exit 1
IFS= read -r initialization
printf '%s\n' '{"id":0,"result":{}}'
IFS= read -r initialized
IFS= read -r quota
case "$CODEX_HOME" in
  */first) used=20 ;;
  */second) used=40 ;;
  *) exit 1 ;;
esac
printf '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":%s,"windowDurationMins":300}}}}\n' "$used"
IFS= read -r usage
printf '%s\n' '{"id":2,"result":{}}'
while :; do :; done
''');
    expect((await Process.run('chmod', ['+x', executable.path])).exitCode, 0);
    final sources = QuotaSources(environment: {
      'LLMQUETA_CODEX_EXECUTABLE': executable.path,
      'CODEX_HOME': '/wrong',
      'OPENAI_API_KEY': 'wrong',
      'CODEX_API_KEY': 'wrong',
      'CODEX_THREAD_ID': 'wrong',
      'LLMQUETA_CODEX_THREAD_ID': 'wrong',
    });
    final accounts = <QuotaAccount>[];
    for (final name in ['first', 'second']) {
      final directory = await Directory('${temporary.path}/$name').create();
      accounts.add(QuotaAccount(
          id: name,
          provider: ProviderKind.codex,
          label: name,
          configurationDirectory: directory.path));
    }
    final snapshots = await Future.wait(accounts.map(sources.fetchAccount));
    expect(snapshots.map((snapshot) => snapshot.windows.single.usedPercent),
        [20, 40]);
    expect(
        snapshots.map((snapshot) => snapshot.accountId), ['first', 'second']);
  }, skip: Platform.isWindows);

  test('Claude plan lookup receives only its profile credentials', () async {
    final temporary =
        await Directory.systemTemp.createTemp('quota-claude-plan-');
    addTearDown(() => temporary.delete(recursive: true));
    final executable = File('${temporary.path}/claude');
    await executable.writeAsString(r'''#!/bin/sh
[ -z "$ANTHROPIC_API_KEY$ANTHROPIC_AUTH_TOKEN$CLAUDE_CODE_OAUTH_TOKEN" ] || exit 1
case "$CLAUDE_CONFIG_DIR" in
  */work) plan=max ;;
  */personal) plan=pro ;;
  *) exit 1 ;;
esac
printf '{"loggedIn":true,"authMethod":"claude.ai","subscriptionType":"%s"}\n' "$plan"
''');
    expect((await Process.run('chmod', ['+x', executable.path])).exitCode, 0);
    final sources = QuotaSources(environment: {
      'LLMQUETA_CLAUDE_EXECUTABLE': executable.path,
      'CLAUDE_CONFIG_DIR': '/wrong',
      'ANTHROPIC_API_KEY': 'wrong',
      'ANTHROPIC_AUTH_TOKEN': 'wrong',
      'CLAUDE_CODE_OAUTH_TOKEN': 'wrong',
    });
    final accounts = <QuotaAccount>[];
    for (final name in ['work', 'personal']) {
      final directory = await Directory('${temporary.path}/$name').create();
      final file = File('${directory.path}/quota.json');
      await file.writeAsString(jsonEncode({
        'observed_at': DateTime.now().toUtc().toIso8601String(),
        'rate_limits': {
          'five_hour': {'used_percentage': 20}
        },
      }));
      accounts.add(QuotaAccount(
          id: name,
          provider: ProviderKind.claude,
          label: name,
          configurationDirectory: directory.path,
          snapshotPath: file.path));
    }
    final snapshots = await Future.wait(accounts.map(sources.fetchAccount));
    expect(snapshots.map((snapshot) => snapshot.planName), ['Max', 'Pro']);
  }, skip: Platform.isWindows);

  test('Antigravity profile uses its named token and rejects missing variables',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var requests = 0;
    server.listen((request) async {
      requests++;
      expect(request.headers.value('X-Codeium-Csrf-Token'), 'profile-token');
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'userStatus': {
          'planStatus': {
            'planInfo': {'planName': 'Pro'}
          },
          'cascadeModelConfigData': {
            'clientModelConfigs': [
              {
                'label': 'Gemini',
                'modelOrAlias': {'model': 'gemini'},
                'quotaInfo': {'remainingFraction': 0.7}
              }
            ]
          }
        }
      }));
      await request.response.close();
    });
    final sources = QuotaSources(environment: {
      'WORK_CSRF': 'profile-token',
      'LLMQUETA_ANTIGRAVITY_CSRF_TOKEN': 'wrong',
      'LLMQUETA_ANTIGRAVITY_URL': 'http://127.0.0.1:1',
    });
    final snapshot = await sources.fetchAccount(QuotaAccount(
        id: 'work',
        provider: ProviderKind.antigravity,
        label: 'Work',
        endpoint: 'http://127.0.0.1:${server.port}',
        csrfTokenEnvironmentVariable: 'WORK_CSRF'));
    expect(snapshot.status, QuotaStatus.live);
    expect(snapshot.accountId, 'work');
    final lowercase = await sources.fetchAccount(QuotaAccount(
        id: 'lowercase',
        provider: ProviderKind.antigravity,
        label: 'Lowercase',
        endpoint: 'http://127.0.0.1:${server.port}',
        csrfTokenEnvironmentVariable: 'work_csrf'));
    expect(lowercase.status,
        Platform.isWindows ? QuotaStatus.live : QuotaStatus.error);
    final before = requests;
    final invalid = await sources.fetchAccount(QuotaAccount(
        id: 'missing',
        provider: ProviderKind.antigravity,
        label: 'Missing',
        endpoint: 'http://127.0.0.1:${server.port}',
        csrfTokenEnvironmentVariable: 'MISSING_CSRF'));
    expect(invalid.status, QuotaStatus.error);
    expect(requests, before);
    expect(invalid.message, isNot(contains('profile-token')));
  });
}
