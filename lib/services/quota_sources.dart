import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/quota.dart';
import 'app_paths.dart';

class QuotaSources {
  QuotaSources({
    AppPaths? paths,
    Map<String, String>? environment,
    this.timeout = const Duration(seconds: 12),
  })  : environment = environment ?? Platform.environment,
        paths = paths ?? AppPaths(environment: environment);

  final AppPaths paths;
  final Map<String, String> environment;
  final Duration timeout;

  Future<QuotaSnapshot> fetch(ProviderKind provider) => switch (provider) {
        ProviderKind.codex => fetchCodex(),
        ProviderKind.claude => fetchClaude(),
        ProviderKind.antigravity => fetchAntigravity(),
      };

  QuotaSnapshot _failure(
    ProviderKind provider,
    String message, {
    QuotaStatus status = QuotaStatus.error,
  }) =>
      QuotaSnapshot(
        provider: provider,
        windows: const [],
        observedAt: DateTime.now(),
        source: 'Local integration',
        status: status,
        message: message,
      );

  Future<QuotaSnapshot> fetchCodex() async {
    Process? process;
    StreamSubscription<String>? output;
    StreamSubscription<List<int>>? errors;
    final pending = <int, Completer<Map<String, dynamic>>>{};
    try {
      final executable = await resolveCodexExecutable(environment: environment);
      if (executable == null) {
        return _failure(
          ProviderKind.codex,
          'Install Codex CLI or set LLMQUETA_CODEX_EXECUTABLE to its executable. On Windows, use codex.exe.',
          status: QuotaStatus.unavailable,
        );
      }
      process = await Process.start(
        executable,
        ['app-server'],
        environment: environment,
      );
      final running = process;
      errors = running.stderr.listen((_) {});
      output = running.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
              try {
                final message = jsonDecode(line);
                if (message is Map<String, dynamic> && message['id'] is int) {
                  final waiter = pending.remove(message['id']);
                  if (waiter != null && !waiter.isCompleted)
                    waiter.complete(message);
                }
              } on FormatException {
                // Unrelated process output cannot establish a quota measurement.
              }
            },
            onError: (Object _) {},
            onDone: () {
              for (final waiter in pending.values) {
                if (!waiter.isCompleted)
                  waiter.completeError(StateError('Codex stopped.'));
              }
              pending.clear();
            },
          );
      Future<Map<String, dynamic>> request(
        int id,
        String method, [
        Map<String, dynamic>? parameters,
      ]) {
        final waiter = Completer<Map<String, dynamic>>();
        pending[id] = waiter;
        running.stdin.writeln(
          jsonEncode({
            'id': id,
            'method': method,
            if (parameters != null) 'params': parameters,
          }),
        );
        return waiter.future.timeout(timeout);
      }

      final initialization = await request(0, 'initialize', {
        'clientInfo': {
          'name': 'llmqueta',
          'title': 'LLM Queta',
          'version': '0.1.0',
        },
      });
      if (initialization.containsKey('error'))
        throw StateError('Initialization failed.');
      running.stdin.writeln(
        jsonEncode({'method': 'initialized', 'params': <String, dynamic>{}}),
      );
      final response = await request(1, 'account/rateLimits/read');
      if (response.containsKey('error')) {
        return _failure(
          ProviderKind.codex,
          'Sign in with ChatGPT in Codex, then refresh.',
        );
      }
      final result = response['result'];
      if (result is! Map<String, dynamic>) throw const FormatException();
      return parseCodexQuota(result, source: 'Codex app-server');
    } on ProcessException {
      return _failure(
        ProviderKind.codex,
        'Install Codex CLI and sign in with ChatGPT.',
        status: QuotaStatus.unavailable,
      );
    } on TimeoutException {
      return _failure(
        ProviderKind.codex,
        'Codex did not respond in time. Refresh to retry.',
      );
    } catch (_) {
      return _failure(
        ProviderKind.codex,
        'Codex quota could not be read. Check the CLI sign-in and refresh.',
      );
    } finally {
      await output?.cancel();
      await errors?.cancel();
      process?.kill();
      if (process != null) {
        try {
          await process.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          process.kill(ProcessSignal.sigkill);
          try {
            await process.exitCode.timeout(const Duration(seconds: 1));
          } on TimeoutException {
            // The fetch remains bounded if the operating system delays reaping.
          }
        }
      }
    }
  }

  Future<QuotaSnapshot> fetchClaude() async {
    try {
      final file = paths.claudeSnapshotFile;
      if (!await file.exists()) {
        return _failure(
          ProviderKind.claude,
          'Connect the Claude Code status-line bridge to display usage.',
          status: QuotaStatus.unavailable,
        );
      }
      if (await file.length() > 65536) throw const FormatException();
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      final observed = DateTime.tryParse(
        decoded['observed_at'] is String
            ? decoded['observed_at'] as String
            : '',
      );
      if (observed == null ||
          observed.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
        throw const FormatException();
      }
      final snapshot = parseClaudeQuota(
        decoded,
        observedAt: observed,
        source: 'Claude Code status line',
      );
      if (snapshot.windows.isEmpty ||
          DateTime.now().difference(observed) <= const Duration(minutes: 10))
        return snapshot;
      return QuotaSnapshot(
        provider: snapshot.provider,
        windows: snapshot.windows,
        observedAt: snapshot.observedAt,
        source: snapshot.source,
        status: QuotaStatus.stale,
        message:
            'Last observation is over 10 minutes old. Use Claude Code to update it.',
      );
    } catch (_) {
      return _failure(
        ProviderKind.claude,
        'The Claude snapshot is unreadable. Run the status-line bridge again.',
      );
    }
  }

  Future<QuotaSnapshot> fetchAntigravity() async {
    try {
      final configured = environment['LLMQUETA_ANTIGRAVITY_URL'];
      final endpoints = configured != null && configured.isNotEmpty
          ? [
              AntigravityEndpoint(
                validateAntigravityEndpoint(configured),
                environment['LLMQUETA_ANTIGRAVITY_CSRF_TOKEN'],
              ),
            ]
          : await _discoverAntigravity();
      if (endpoints.isEmpty) {
        return _failure(
          ProviderKind.antigravity,
          'Open Antigravity and sign in, then refresh. A local endpoint can also be configured.',
          status: QuotaStatus.unavailable,
        );
      }
      final deadline = DateTime.now().add(timeout);
      for (final endpoint in endpoints.take(12)) {
        if (DateTime.now().isAfter(deadline)) break;
        try {
          final remaining = deadline.difference(DateTime.now());
          final snapshot = await _fetchAntigravityEndpoint(
            endpoint,
            remaining < const Duration(seconds: 3)
                ? remaining
                : const Duration(seconds: 3),
          );
          if (snapshot.windows.isNotEmpty) return snapshot;
        } catch (_) {
          // A stale local process must not prevent probing another candidate.
        }
      }
      return _failure(
        ProviderKind.antigravity,
        'Antigravity quota is unavailable. Check the running app or local endpoint configuration.',
      );
    } catch (_) {
      return _failure(
        ProviderKind.antigravity,
        'Antigravity connection failed. Use an HTTP(S) loopback address with an explicit port.',
      );
    }
  }

  Future<List<AntigravityEndpoint>> _discoverAntigravity() async {
    final candidates = <AntigravityProcess>[];
    final portsByProcess = <int, List<int>>{};
    if (Platform.isWindows) {
      final output = await _runDiscovery('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding; $items = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -match 'language[_-]server' -and $_.CommandLine -match 'antigravity' } | ForEach-Object { $processId = $_.ProcessId; @{ processId = $processId; commandLine = $_.CommandLine; ports = @(Get-NetTCPConnection -State Listen -OwningProcess $processId -ErrorAction SilentlyContinue | Select-Object -ExpandProperty LocalPort) } }); ConvertTo-Json -InputObject $items -Compress -Depth 4",
      ]);
      final decoded = jsonDecode(output);
      if (decoded is! List) return [];
      for (final value in decoded.take(12)) {
        if (value is! Map ||
            value['processId'] is! int ||
            value['commandLine'] is! String) continue;
        final candidate = parseAntigravityProcess(
          value['processId'] as int,
          value['commandLine'] as String,
        );
        if (candidate == null) continue;
        candidates.add(candidate);
        portsByProcess[candidate.processId] = [
          for (final port
              in value['ports'] is List ? value['ports'] as List : const [])
            if (port is int && port > 0 && port <= 65535) port,
        ];
      }
    } else {
      final output = await _runDiscovery('ps', ['-xww', '-o', 'pid=,command=']);
      for (final line in const LineSplitter().convert(output)) {
        final match = RegExp(r'^\s*(\d+)\s+(.+)$').firstMatch(line);
        if (match == null) continue;
        final candidate = parseAntigravityProcess(
          int.parse(match.group(1)!),
          match.group(2)!,
        );
        if (candidate != null) candidates.add(candidate);
        if (candidates.length >= 12) break;
      }
      for (final candidate in candidates) {
        try {
          final output = await _runDiscovery('lsof', [
            '-nP',
            '-a',
            '-p',
            '${candidate.processId}',
            '-iTCP',
            '-sTCP:LISTEN',
            '-Fn',
          ]);
          portsByProcess[candidate.processId] = [
            for (final line in const LineSplitter().convert(output))
              if (line.startsWith('n') && RegExp(r':(\d+)$').hasMatch(line))
                int.parse(RegExp(r':(\d+)$').firstMatch(line)!.group(1)!),
          ];
        } catch (_) {
          // The process-provided extension port remains usable without lsof.
        }
      }
    }
    return [
      for (final candidate in candidates) ...[
        for (final port
            in (portsByProcess[candidate.processId] ?? <int>[]).toSet().take(8))
          AntigravityEndpoint(
            Uri.parse('https://127.0.0.1:$port'),
            candidate.csrfToken,
          ),
        if (candidate.extensionPort != null)
          AntigravityEndpoint(
            Uri.parse('http://127.0.0.1:${candidate.extensionPort}'),
            candidate.extensionCsrfToken ?? candidate.csrfToken,
          ),
      ],
    ];
  }

  Future<String> _runDiscovery(
    String executable,
    List<String> arguments,
  ) async {
    final process = await Process.start(
      executable,
      arguments,
      environment: environment,
    );
    final errors = process.stderr.listen((_) {});
    final bytes = <int>[];
    final outputFinished = Completer<void>();
    final output = process.stdout.listen(
      (chunk) {
        if (outputFinished.isCompleted) return;
        if (bytes.length + chunk.length > 2097152) {
          outputFinished.completeError(const FormatException());
          return;
        }
        bytes.addAll(chunk);
      },
      onError: (Object error, StackTrace stack) {
        if (!outputFinished.isCompleted)
          outputFinished.completeError(error, stack);
      },
      onDone: () {
        if (!outputFinished.isCompleted) outputFinished.complete();
      },
    );
    try {
      await (() async {
        await outputFinished.future;
        if (await process.exitCode != 0)
          throw StateError('Discovery unavailable.');
      })()
          .timeout(const Duration(seconds: 3));
      return utf8.decode(bytes);
    } finally {
      process.kill();
      await output.cancel();
      if (!outputFinished.isCompleted) outputFinished.complete();
      await errors.cancel();
      try {
        await process.exitCode.timeout(const Duration(seconds: 1));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(const Duration(seconds: 1));
      }
    }
  }

  Future<QuotaSnapshot> _fetchAntigravityEndpoint(
    AntigravityEndpoint connection,
    Duration requestTimeout,
  ) async {
    final endpoint = connection.uri;
    final client = HttpClient()..connectionTimeout = requestTimeout;
    var expired = false;
    try {
      client.badCertificateCallback =
          (_, host, port) => host == endpoint.host && port == endpoint.port;
      Future<Map<String, dynamic>> request(
        String method,
        Map<String, dynamic> body,
      ) async {
        if (expired)
          throw TimeoutException('The local quota deadline expired.');
        final request = await client.postUrl(
          endpoint.replace(
            path: '/exa.language_server_pb.LanguageServerService/$method',
          ),
        );
        request.followRedirects = false;
        request.headers.contentType = ContentType.json;
        request.headers.set('Connect-Protocol-Version', '1');
        final token = connection.csrfToken;
        if (token != null && token.isNotEmpty)
          request.headers.set('X-Codeium-Csrf-Token', token);
        request.write(jsonEncode(body));
        final response = await request.close();
        if (response.statusCode != HttpStatus.ok)
          throw const HttpException('Local quota request failed.');
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 1048576)
            throw const FormatException();
          bytes.addAll(chunk);
        }
        final decoded = jsonDecode(utf8.decode(bytes));
        if (decoded is! Map<String, dynamic>) throw const FormatException();
        return decoded;
      }

      return await (() async {
        try {
          final response = await request('RetrieveUserQuotaSummary', {
            'forceRefresh': true,
          });
          final snapshot = parseAntigravityQuota(response);
          if (snapshot.windows.isNotEmpty) return snapshot;
        } catch (_) {
          // Older local servers expose model quotas through GetUserStatus.
          if (expired) rethrow;
        }
        return parseAntigravityQuota(
          await request('GetUserStatus', {
            'metadata': {
              'ideName': 'antigravity',
              'extensionName': 'antigravity',
              'ideVersion': 'unknown',
              'locale': 'en',
            },
          }),
        );
      })()
          .timeout(
        requestTimeout,
        onTimeout: () {
          expired = true;
          client.close(force: true);
          throw TimeoutException('The local quota deadline expired.');
        },
      );
    } finally {
      client.close(force: true);
    }
  }
}

List<String> codexExecutableCandidates({
  required Map<String, String> environment,
  String? operatingSystem,
}) {
  final system = operatingSystem ?? Platform.operatingSystem;
  final windows = system == 'windows';
  final pathDirectories = (environment['PATH'] ?? '')
      .split(windows ? ';' : ':')
      .where((directory) => directory.isNotEmpty);
  final override = environment['LLMQUETA_CODEX_EXECUTABLE'];
  if (override != null) {
    if (override.trim().isEmpty ||
        (windows &&
            RegExp(r'\.(cmd|bat|ps1)$', caseSensitive: false)
                .hasMatch(override))) {
      return [];
    }
    if (override.contains('/') || override.contains('\\')) return [override];
    final name = windows && !override.toLowerCase().endsWith('.exe')
        ? '$override.exe'
        : override;
    return [for (final directory in pathDirectories) '$directory/$name'];
  }
  final name = windows ? 'codex.exe' : 'codex';
  final home = environment[windows ? 'USERPROFILE' : 'HOME'];
  final local = environment['LOCALAPPDATA'];
  return <String>{
    for (final directory in pathDirectories) '$directory/$name',
    if (home != null && home.isNotEmpty) ...[
      '$home/.local/bin/$name',
      '$home/.cargo/bin/$name',
      if (windows) '$home/scoop/shims/$name',
    ],
    if (windows && local != null && local.isNotEmpty)
      '$local/Microsoft/WinGet/Links/$name',
    if (!windows) ...[
      if (system == 'macos') '/opt/homebrew/bin/codex',
      '/usr/local/bin/codex',
      '/usr/bin/codex',
    ],
  }.toList();
}

Future<String?> resolveCodexExecutable({
  required Map<String, String> environment,
  String? operatingSystem,
}) async {
  final system = operatingSystem ?? Platform.operatingSystem;
  for (final path in codexExecutableCandidates(
    environment: environment,
    operatingSystem: system,
  )) {
    try {
      final status = await File(path).stat();
      if (status.type == FileSystemEntityType.file &&
          (system == 'windows' || (status.mode & 0x49) != 0)) {
        return path;
      }
    } on FileSystemException {
      // An inaccessible candidate cannot establish an executable installation.
    }
  }
  return null;
}

class AntigravityEndpoint {
  AntigravityEndpoint(this.uri, this.csrfToken);
  final Uri uri;
  final String? csrfToken;
}

Uri validateAntigravityEndpoint(String configured) {
  final endpoint = Uri.parse(configured);
  if (!['http', 'https'].contains(endpoint.scheme) ||
      !['127.0.0.1', '::1', '[::1]'].contains(endpoint.host) ||
      !endpoint.hasPort ||
      endpoint.port < 1 ||
      endpoint.port > 65535 ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment ||
      (endpoint.path.isNotEmpty && endpoint.path != '/')) {
    throw const FormatException(
      'A loopback HTTP(S) origin with an explicit port is required.',
    );
  }
  return endpoint;
}

class AntigravityProcess {
  AntigravityProcess(
    this.processId,
    this.csrfToken,
    this.extensionPort,
    this.extensionCsrfToken,
  );
  final int processId;
  final String csrfToken;
  final int? extensionPort;
  final String? extensionCsrfToken;
}

AntigravityProcess? parseAntigravityProcess(int processId, String commandLine) {
  final executable = commandLine.split(RegExp(r'\s+--')).first.trim();
  if (processId <= 0 ||
      !RegExp(
        r'(?:^|[/\\])language[_-]server[\w.-]*["\x27]?$',
        caseSensitive: false,
      ).hasMatch(executable) ||
      !commandLine.toLowerCase().contains('antigravity')) return null;
  String? argument(String name) {
    final match = RegExp(
      '(?:^|\\s)--$name(?:=|\\s+)(?:"([^"\\r\\n]+)"|\'([^\'\\r\\n]+)\'|([^\\s]+))',
    ).firstMatch(commandLine);
    return match?.group(1) ?? match?.group(2) ?? match?.group(3);
  }

  final token = argument('csrf_token');
  if (token == null || token.isEmpty) return null;
  final port = int.tryParse(argument('extension_server_port') ?? '');
  return AntigravityProcess(
    processId,
    token,
    port != null && port > 0 && port <= 65535 ? port : null,
    argument('extension_server_csrf_token'),
  );
}
