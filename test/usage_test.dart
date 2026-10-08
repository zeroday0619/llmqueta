import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/models/usage.dart';

void main() {
  final now = DateTime(2026, 10, 8, 14);

  test('account usage reads today and lifetime independently', () {
    final usage = parseCodexTokenUsage({
      'result': {
        'summary': {'lifetimeTokens': 16808063757},
        'dailyUsageBuckets': [
          {'startDate': '2026-10-07', 'tokens': 200},
          {'startDate': '2026-10-08', 'tokens': 0},
        ],
      },
    }, now: now);
    expect(usage.today!.total, 0);
    expect(usage.lifetime!.total, 16808063757);
    expect(usage.session, isNull);
    expect(usage.note, contains('2026-10-08'));
  });

  test('missing or ambiguous daily bucket never becomes zero', () {
    for (final buckets in [
      null,
      [],
      [
        {'startDate': '2026-10-07', 'tokens': 400},
      ],
      [
        {'startDate': '2026-10-08', 'tokens': 100},
        {'startDate': '2026-10-08', 'tokens': 200},
      ]
    ]) {
      final usage = parseCodexTokenUsage({
        'summary': {'lifetimeTokens': 500},
        'dailyUsageBuckets': buckets,
      }, now: now);
      expect(usage.today, isNull);
      expect(usage.lifetime!.total, 500);
    }
  });

  test('invalid counts remain unknown instead of losing valid siblings', () {
    for (final invalid in [-1, 1.5, '25', true, double.infinity, null]) {
      final usage = parseCodexTokenUsage({
        'summary': {'lifetimeTokens': invalid},
        'dailyUsageBuckets': [
          {'startDate': '2026-10-08', 'tokens': 30}
        ],
      }, now: now);
      expect(usage.today!.total, 30);
      expect(usage.lifetime, isNull);
    }
  });

  test('thread groups sum explicit totals without double-counting cache', () {
    final usage = parseCodexTokenUsage(
        {
          'summary': {'lifetimeTokens': 10000},
        },
        now: now,
        sessionPayload: {
          'threadUsage': {
            'groups': [
              {
                'totalTokens': 120,
                'inputTokens': 100,
                'outputTokens': 20,
                'cachedInputTokens': 80
              },
              {
                'totalTokens': 60,
                'inputTokens': 50,
                'outputTokens': 10,
                'cachedInputTokens': 40
              },
            ]
          },
        });
    expect(usage.session!.total, 180);
    expect(usage.session!.input, 150);
    expect(usage.session!.output, 30);
    expect(usage.session!.cachedInput, 120);
    expect(usage.lifetime!.total, 10000);
  });

  test('partial session groups cannot be presented as a complete total', () {
    final usage = parseCodexTokenUsage({}, sessionPayload: {
      'threadUsage': {
        'groups': [
          {'totalTokens': 100},
          {'totalTokens': null}
        ]
      },
    });
    expect(usage.session, isNull);
    expect(usage.hasData, isFalse);
  });

  test('credit parsing preserves zero, decimal precision, and unlimited', () {
    expect(parseCreditBalance({'balance': '0'})!.balance, '0');
    expect(parseCreditBalance({'balance': '120.50'})!.balance, '120.50');
    expect(parseCreditBalance({'balance': 4.5})!.balance, '4.5');
    expect(parseCreditBalance({'unlimited': true})!.unlimited, isTrue);
    final available = parseCreditBalance({'hasCredits': true});
    expect(available!.hasCredits, isTrue);
    expect(available.balance, isNull);
  });

  test('invalid credit values are not converted into a balance', () {
    for (final value in [
      '-1',
      'NaN',
      'Infinity',
      '1e999',
      'USD 20',
      true,
      {},
      []
    ]) {
      expect(parseCreditBalance({'balance': value}), isNull);
    }
    expect(parseCreditBalance(null), isNull);
  });

  test('Codex credits are account data and reset credits stay separate', () {
    final snapshot = parseCodexQuota({
      'rateLimits': {
        'credits': {'balance': '5.25', 'hasCredits': true}
      },
      'rateLimitsByLimitId': {
        'review': {
          'credits': {'balance': '999'}
        },
      },
      'rateLimitResetCredits': {'availableCount': 2},
    });
    expect(snapshot.creditBalance!.balance, '5.25');
    expect(snapshot.resetCredits, 2);
    expect(snapshot.windows, isEmpty);
    expect(snapshot.hasUsage, isTrue);
    expect(snapshot.status, QuotaStatus.live);
  });

  test('token-only observations become visible without inventing quota', () {
    final snapshot = parseCodexQuota({}).withUsage(
      tokenUsage: const TokenUsage(lifetime: TokenCount(total: 123)),
    );
    expect(snapshot.windows, isEmpty);
    expect(snapshot.hasUsage, isTrue);
    expect(snapshot.status, QuotaStatus.live);
    expect(snapshot.message, isNull);
  });
}
