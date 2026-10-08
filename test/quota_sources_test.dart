import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/services/app_paths.dart';
import 'package:llmqueta/services/quota_sources.dart';

void main() {
  test('Codex search respects PATH order and GUI installation locations', () {
    final candidates = codexExecutableCandidates(
      environment: {'PATH': '/first:/second', 'HOME': '/Users/test'},
      operatingSystem: 'macos',
    );
    expect(candidates.take(2), ['/first/codex', '/second/codex']);
    expect(
        candidates,
        containsAll(
            ['/Users/test/.local/bin/codex', '/opt/homebrew/bin/codex']));
    expect(
        codexExecutableCandidates(
          environment: {
            'LLMQUETA_CODEX_EXECUTABLE': '/explicit/codex',
            'PATH': '/other'
          },
          operatingSystem: 'linux',
        ),
        ['/explicit/codex']);
    expect(
        codexExecutableCandidates(
          environment: {'LLMQUETA_CODEX_EXECUTABLE': '', 'PATH': '/other'},
        ),
        isEmpty);
  });

  test('Windows Codex resolution accepts native executables, not shell shims',
      () {
    final candidates = codexExecutableCandidates(
      environment: {
        'PATH': r'C:\first;C:\second',
        'USERPROFILE': r'C:\Users\test'
      },
      operatingSystem: 'windows',
    );
    expect(candidates.take(2), [r'C:\first/codex.exe', r'C:\second/codex.exe']);
    for (final shim in ['codex.cmd', 'codex.bat', 'codex.ps1']) {
      expect(
          codexExecutableCandidates(
            environment: {'LLMQUETA_CODEX_EXECUTABLE': shim},
            operatingSystem: 'windows',
          ),
          isEmpty);
    }
  });

  test('Codex resolver rejects a missing explicit override without fallback',
      () async {
    final temporary =
        await Directory.systemTemp.createTemp('llmqueta-resolver-');
    addTearDown(() => temporary.delete(recursive: true));
    final executable = File('${temporary.path}/codex');
    await executable.writeAsString('#!/bin/sh\nexit 0\n');
    if (!Platform.isWindows) {
      expect((await Process.run('chmod', ['+x', executable.path])).exitCode, 0);
    }
    expect(
        await resolveCodexExecutable(environment: {
          'LLMQUETA_CODEX_EXECUTABLE': '${temporary.path}/missing',
          'PATH': temporary.path,
        }),
        isNull);
    expect(
        await resolveCodexExecutable(environment: {
          'LLMQUETA_CODEX_EXECUTABLE': executable.path,
        }),
        executable.path);
  });

  test('configuration paths follow platform conventions', () {
    expect(
      AppPaths(
        environment: {'HOME': '/home/test'},
        operatingSystem: 'linux',
      ).configurationDirectory,
      '/home/test/.config/llmqueta',
    );
    expect(
      AppPaths(
        environment: {'HOME': '/home/test', 'XDG_CONFIG_HOME': '/config'},
        operatingSystem: 'linux',
      ).configurationDirectory,
      '/config/llmqueta',
    );
    expect(
      AppPaths(
        environment: {'HOME': '/Users/test'},
        operatingSystem: 'macos',
      ).configurationDirectory,
      '/Users/test/Library/Application Support/llmqueta',
    );
    expect(
      AppPaths(
        environment: {'APPDATA': 'C:/Users/test/AppData/Roaming'},
        operatingSystem: 'windows',
      ).configurationDirectory,
      'C:/Users/test/AppData/Roaming/llmqueta',
    );
  });

  test('missing integrations are unavailable rather than fabricated', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'llmqueta-sources-',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final sources = QuotaSources(
      environment: {},
      paths: AppPaths(
        environment: {'HOME': temporary.path},
        operatingSystem: 'macos',
      ),
    );
    expect((await sources.fetchClaude()).status, QuotaStatus.unavailable);
  });

  test(
    'Claude observations preserve age and reject invalid timestamps',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'llmqueta-sources-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final paths = AppPaths(
        environment: {'HOME': temporary.path},
        operatingSystem: 'macos',
      );
      final sources = QuotaSources(paths: paths, environment: {});
      final file = paths.claudeSnapshotFile;
      await file.parent.create(recursive: true);
      final observed = DateTime.now().toUtc().subtract(
            const Duration(minutes: 20),
          );
      await file.writeAsString(
        jsonEncode({
          'observed_at': observed.toIso8601String(),
          'rate_limits': {
            'five_hour': {
              'used_percentage': 42,
              'resets_at': DateTime.now()
                      .add(const Duration(hours: 1))
                      .millisecondsSinceEpoch ~/
                  1000,
            },
          },
        }),
      );
      final snapshot = await sources.fetchClaude();
      expect(snapshot.status, QuotaStatus.stale);
      expect(snapshot.observedAt, observed);
      expect(snapshot.windows.single.usedPercent, 42);
      await file.writeAsString('{"observed_at":"invalid","rate_limits":{}}');
      expect((await sources.fetchClaude()).status, QuotaStatus.error);
    },
  );

  test('Antigravity rejects remote hosts before sending credentials', () async {
    final sources = QuotaSources(
      environment: {
        'LLMQUETA_ANTIGRAVITY_URL': 'https://example.com:443',
        'LLMQUETA_ANTIGRAVITY_CSRF_TOKEN': 'test-only-secret',
      },
    );
    final snapshot = await sources.fetchAntigravity();
    expect(snapshot.status, QuotaStatus.error);
    expect(snapshot.message, isNot(contains('test-only-secret')));
  });

  test('local endpoint validation rejects redirects and credential URLs', () {
    expect(validateAntigravityEndpoint('http://127.0.0.1:42123').port, 42123);
    expect(validateAntigravityEndpoint('https://[::1]:42123').port, 42123);
    for (final value in [
      'http://localhost:42123',
      'https://example.com:42123',
      'http://user:password@127.0.0.1:42123',
      'http://127.0.0.1:42123/path',
      'http://127.0.0.1:42123?target=remote',
      'http://127.0.0.1:42123#fragment',
    ]) {
      expect(() => validateAntigravityEndpoint(value), throwsFormatException);
    }
  });

  test('process parser requires Antigravity server identity and CSRF', () {
    final process = parseAntigravityProcess(
      123,
      '/Applications/Antigravity.app/bin/language_server_macos_arm --csrf_token="test-token" --extension_server_port 42123 --extension_server_csrf_token fallback-token',
    );
    expect(process?.csrfToken, 'test-token');
    expect(process?.extensionPort, 42123);
    expect(process?.extensionCsrfToken, 'fallback-token');
    final windows = parseAntigravityProcess(
      456,
      r'"C:\Program Files\Antigravity\bin\language_server_windows_x64.exe" --csrf_token "windows-token" --extension_server_port=42124',
    );
    expect(windows?.csrfToken, 'windows-token');
    expect(windows?.extensionPort, 42124);
    expect(
      parseAntigravityProcess(
        789,
        'language_server_linux_x64 --app_data_dir antigravity --csrf_token linux-token',
      )?.csrfToken,
      'linux-token',
    );
    expect(
      parseAntigravityProcess(123, '/bin/language_server --csrf_token test'),
      isNull,
    );
    expect(
      parseAntigravityProcess(123, '/Applications/Antigravity/language_server'),
      isNull,
    );
    expect(
      parseAntigravityProcess(
        123,
        '/Applications/Antigravity/language_server --csrf_token test --extension_server_port 99999',
      )?.extensionPort,
      isNull,
    );
  });

  test('Antigravity local HTTP request authenticates and falls back', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final methods = <String>[];
    server.listen((request) async {
      methods.add(request.uri.path.split('/').last);
      expect(request.headers.value('X-Codeium-Csrf-Token'), 'local-test-token');
      expect(request.headers.value('Connect-Protocol-Version'), '1');
      final body = jsonDecode(await utf8.decoder.bind(request).join());
      if (methods.length == 1) {
        expect(body, {'forceRefresh': true});
        request.response.statusCode = 404;
      } else {
        expect(body['metadata']['ideName'], 'antigravity');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'userStatus': {
              'cascadeModelConfigData': {
                'clientModelConfigs': [
                  {
                    'label': 'Gemini',
                    'modelOrAlias': {'model': 'gemini-test'},
                    'quotaInfo': {
                      'remainingFraction': 0.7,
                      'resetTime': '2030-01-01T00:00:00Z',
                    },
                  },
                ],
              },
            },
          }),
        );
      }
      await request.response.close();
    });
    final sources = QuotaSources(
      environment: {
        'LLMQUETA_ANTIGRAVITY_URL': 'http://127.0.0.1:${server.port}',
        'LLMQUETA_ANTIGRAVITY_CSRF_TOKEN': 'local-test-token',
      },
    );
    final snapshot = await sources.fetchAntigravity();
    expect(snapshot.status, QuotaStatus.live);
    expect(snapshot.windows.single.usedPercent, closeTo(30, 0.001));
    expect(methods, ['RetrieveUserQuotaSummary', 'GetUserStatus']);
  });

  test('Antigravity does not follow HTTP redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var redirected = false;
    server.listen((request) async {
      if (request.uri.path == '/credential-leak') redirected = true;
      await request.drain<void>();
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set('Location', '/credential-leak');
      await request.response.close();
    });
    final snapshot = await QuotaSources(
      environment: {
        'LLMQUETA_ANTIGRAVITY_URL': 'http://127.0.0.1:${server.port}',
      },
    ).fetchAntigravity();
    expect(snapshot.status, QuotaStatus.error);
    expect(redirected, isFalse);
  });

  test(
    'Antigravity deadline stops a continuously streaming response',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final timers = <Timer>[];
      addTearDown(() async {
        for (final timer in timers) {
          timer.cancel();
        }
        await server.close(force: true);
      });
      var requests = 0;
      server.listen((request) async {
        requests += 1;
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{');
        final timer = Timer.periodic(const Duration(milliseconds: 10), (timer) {
          try {
            request.response.write(' ');
            unawaited(
              request.response.flush().catchError((Object _) {
                timer.cancel();
              }),
            );
          } catch (_) {
            timer.cancel();
          }
        });
        timers.add(timer);
      });
      final stopwatch = Stopwatch()..start();
      final snapshot = await QuotaSources(
        environment: {
          'LLMQUETA_ANTIGRAVITY_URL': 'http://127.0.0.1:${server.port}',
        },
        timeout: const Duration(milliseconds: 150),
      ).fetchAntigravity();
      stopwatch.stop();
      expect(snapshot.status, QuotaStatus.error);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
      expect(requests, 1);
    },
  );

  test('Codex RPC handshake completes and child is terminated', () async {
    final temporary = await Directory.systemTemp.createTemp('llmqueta-rpc-');
    addTearDown(() => temporary.delete(recursive: true));
    final executable = File('${temporary.path}/mock-codex');
    final log = File('${temporary.path}/requests');
    final stopped = File('${temporary.path}/stopped');
    await executable.writeAsString(r'''#!/bin/sh
trap 'printf stopped > "$LLMQUETA_TEST_STOPPED"; exit 0' TERM
IFS= read -r initialization
printf '%s\n' "$initialization" >> "$LLMQUETA_TEST_LOG"
printf '%s\n' '{"id":0,"result":{}}'
IFS= read -r initialized
printf '%s\n' "$initialized" >> "$LLMQUETA_TEST_LOG"
IFS= read -r request
printf '%s\n' "$request" >> "$LLMQUETA_TEST_LOG"
printf '%s\n' '{"id":1,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1893456000}}}}'
while :; do :; done
''');
    expect((await Process.run('chmod', ['+x', executable.path])).exitCode, 0);
    final snapshot = await QuotaSources(
      environment: {
        'LLMQUETA_CODEX_EXECUTABLE': executable.path,
        'LLMQUETA_TEST_LOG': log.path,
        'LLMQUETA_TEST_STOPPED': stopped.path,
      },
    ).fetchCodex();
    expect(snapshot.status, QuotaStatus.live);
    expect(snapshot.windows.single.usedPercent, 25);
    expect(
      (await log.readAsLines())
          .map((line) => jsonDecode(line)['method'])
          .toList(),
      ['initialize', 'initialized', 'account/rateLimits/read'],
    );
    expect(await stopped.exists(), isTrue);
  }, skip: Platform.isWindows);
}
