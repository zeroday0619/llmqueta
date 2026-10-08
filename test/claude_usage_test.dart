import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/services/claude_usage.dart';

void main() {
  late Directory directory;
  late Map<String, String> environment;
  final now = DateTime(2026, 10, 8, 12);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('claude-usage-');
    environment = {'CLAUDE_CONFIG_DIR': directory.path};
    await Directory('${directory.path}/projects/example')
        .create(recursive: true);
  });
  tearDown(() => directory.delete(recursive: true));

  Map<String, Object?> record(String identifier, DateTime date,
          {int output = 7, String session = 'active'}) =>
      {
        'type': 'assistant',
        'sessionId': session,
        'timestamp': date.toIso8601String(),
        'message': {
          'id': identifier,
          'usage': {
            'input_tokens': 10,
            'output_tokens': output,
            'cache_read_input_tokens': 20,
            'cache_creation_input_tokens': 30,
          },
        },
      };

  Future<void> write(String name, List<Object> records) async {
    final file = File('${directory.path}/projects/example/$name.jsonl');
    await file.parent.create(recursive: true);
    await file.writeAsString(records.map(jsonEncode).join('\n'));
  }

  test('counts caches once and deduplicates streaming and nested records',
      () async {
    await write('active', [record('one', now, output: 2), record('one', now)]);
    await write(
        'active/subagents/agent', [record('one', now), record('two', now)]);
    final usage = await readClaudeTokenUsage(
        environment: environment, sessionId: 'active', now: now);
    expect(usage.today?.total, 134);
    expect(usage.session?.total, 134);
    expect(usage.lifetime?.input, 120);
    expect(usage.lifetime?.output, 14);
    expect(usage.lifetime?.cachedInput, 40);
    expect(usage.lifetimeLabel, 'Local total');
  });

  test('uses local midnight and keeps sessions separate', () async {
    await write('active', [record('one', DateTime(2026, 10, 8))]);
    await write(
        'old', [record('two', DateTime(2026, 10, 7, 23, 59), session: 'old')]);
    final usage = await readClaudeTokenUsage(
        environment: environment, sessionId: 'active', now: now);
    expect(usage.today?.total, 67);
    expect(usage.session?.total, 67);
    expect(usage.lifetime?.total, 134);
    final tomorrow = await readClaudeTokenUsage(
        environment: environment, now: DateTime(2026, 10, 9));
    expect(tomorrow.today?.total, 0);
    expect(tomorrow.session, isNull);
  });

  test('malformed history does not expose partial totals', () async {
    await write('active', [record('one', now)]);
    await File('${directory.path}/projects/example/broken.jsonl')
        .writeAsString('{');
    final usage =
        await readClaudeTokenUsage(environment: environment, now: now);
    expect(usage.lifetime, isNull);
    expect(usage.today, isNull);
    expect(usage.note, contains('incomplete'));
  });

  test('empty history stays unavailable instead of inventing zero', () async {
    final usage =
        await readClaudeTokenUsage(environment: environment, now: now);
    expect(usage.lifetime, isNull);
    expect(usage.today, isNull);
  });

  test('duplicate records retain previously reported cache counters', () async {
    final later = record('one', now, output: 12);
    final message = later['message'] as Map;
    (message['usage'] as Map).remove('cache_read_input_tokens');
    (message['usage'] as Map).remove('cache_creation_input_tokens');
    await write('active', [record('one', now), later]);
    final usage =
        await readClaudeTokenUsage(environment: environment, now: now);
    expect(usage.lifetime?.total, 72);
    expect(usage.lifetime?.cachedInput, 20);
  });

  test('negative usage makes totals unavailable', () async {
    await write('active', [record('one', now, output: -1)]);
    final usage =
        await readClaudeTokenUsage(environment: environment, now: now);
    expect(usage.lifetime, isNull);
  });

  test('latest timestamp wins when corrected counters decrease', () async {
    await write('active', [
      record('one', now.add(const Duration(seconds: 1)), output: 2),
      record('one', now, output: 12),
    ]);
    final usage =
        await readClaudeTokenUsage(environment: environment, now: now);
    expect(usage.lifetime?.total, 62);
  });

  test(
      'transcript path identifies active session without reading external files',
      () async {
    await write('active', [record('one', now)]);
    await write('other', [record('two', now, session: 'other')]);
    final usage = await readClaudeTokenUsage(
        environment: environment,
        transcriptPath: '${directory.path}/projects/example/active.jsonl',
        now: now);
    expect(usage.session?.total, 67);
    expect(usage.lifetime?.total, 134);
  });

  test('relative transcript paths identify the active session', () async {
    final relativeDirectory =
        await Directory('.').createTemp('.claude-relative-');
    try {
      final transcript =
          File('${relativeDirectory.path}/projects/example/active.jsonl');
      await transcript.parent.create(recursive: true);
      await transcript.writeAsString(jsonEncode(record('one', now)));
      final usage = await readClaudeTokenUsage(
          environment: {'CLAUDE_CONFIG_DIR': relativeDirectory.absolute.path},
          transcriptPath: transcript.path,
          now: now);
      expect(usage.session?.total, 67);
    } finally {
      await relativeDirectory.delete(recursive: true);
    }
  });

  test('missing transcript paths preserve totals without selecting a session',
      () async {
    await write('active', [record('one', now)]);
    final usage = await readClaudeTokenUsage(
        environment: environment,
        transcriptPath: '${directory.path}/missing.jsonl',
        now: now);
    expect(usage.session, isNull);
    expect(usage.lifetime?.total, 67);
  });

  test('Windows transcript separator variants identify the same file',
      () async {
    await write('active', [record('one', now)]);
    final transcriptPath = '${directory.path}/projects/example/active.jsonl';
    for (final path in [
      transcriptPath.replaceAll('\\', '/'),
      transcriptPath.replaceAll('/', '\\'),
    ]) {
      final usage = await readClaudeTokenUsage(
          environment: environment, transcriptPath: path, now: now);
      expect(usage.session?.total, 67);
    }
  }, skip: !Platform.isWindows);
}
