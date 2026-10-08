import 'package:flutter_test/flutter_test.dart';

import '../lib/models/quota.dart';

void main() {
  final observedAt = DateTime.utc(2026, 10, 8, 9);

  test('Codex reads the reported account plan without using model names', () {
    expect(
        parseCodexQuota({
          'rateLimits': {'planType': 'plus'}
        }).planName,
        'Plus');
    expect(
        parseCodexQuota({
          'rate_limits': {'plan_type': 'pro'}
        }).planName,
        'Pro');
    expect(
        parseCodexQuota({
          'rateLimits': {'planType': 'free'},
          'rateLimitsByLimitId': {
            'codex': {'planType': 'business'},
            'review': {'planType': 'pro'},
          },
        }).planName,
        'Business');
    expect(
        parseCodexQuota({
          'rateLimitsByLimitId': {
            'review': {'planType': 'pro'}
          },
        }).planName,
        isNull);
    expect(parseCodexQuota({'limitName': 'Pro'}).planName, isNull);
    for (final value in [null, '', '  ', 'unknown', 42, 'Plus\nPro']) {
      expect(parseCodexQuota({'planType': value}).planName, isNull);
    }
    expect(
        parseCodexQuota({'planType': 'future_plan'}).planName, 'future_plan');
  });

  test('Antigravity uses account plan names rather than model tiers', () {
    expect(
        parseAntigravityQuota({
          'userStatus': {
            'planStatus': {
              'planInfo': {'planName': 'Google AI Pro'}
            }
          },
        }).planName,
        'Google AI Pro');
    expect(
        parseAntigravityQuota({
          'models': {
            'pro': {'displayName': 'Gemini Pro'}
          },
          'userStatus': {'teamsTier': 'PRO'},
        }).planName,
        isNull);
  });

  test('Claude only uses explicitly supplied account plan metadata', () {
    expect(
        parseClaudeQuota({
          'model': {'display_name': 'Pro'}
        }).planName,
        isNull);
    expect(parseClaudeQuota({}, planName: ' Max ').planName, 'Max');
  });

  test(
    'invalid numeric reset times remain unknown without discarding usage',
    () {
      for (final reset in [
        1e300,
        -1e300,
        8640000000001,
        -8640000000001,
        double.infinity,
        double.negativeInfinity,
        double.nan,
        null,
        true,
        '1791442800',
        <String, dynamic>{},
      ]) {
        final codex = parseCodexQuota({
          'primary': {'usedPercent': 25, 'resetsAt': reset},
        });
        final claude = parseClaudeQuota({
          'rate_limits': {
            'five_hour': {'used_percentage': 25, 'resets_at': reset},
          },
        });
        for (final snapshot in [codex, claude]) {
          expect(snapshot.status, QuotaStatus.live);
          expect(snapshot.windows.single.usedPercent, 25);
          expect(snapshot.windows.single.resetsAt, isNull);
        }
      }
    },
  );

  test('epoch reset boundaries and fractional seconds are supported', () {
    for (final reset in [-8640000000000, 0, 1791442800.125, 8640000000000]) {
      final snapshot = parseCodexQuota({
        'primary': {'used_percent': 0, 'resets_at': reset},
      });
      expect(
        snapshot.windows.single.resetsAt!.millisecondsSinceEpoch,
        (reset * 1000).round(),
      );
      expect(snapshot.windows.single.resetsAt!.isUtc, isTrue);
    }
  });

  test(
    'Antigravity grouped buckets preserve identifiers and unknown resets',
    () {
      final snapshot = parseAntigravityQuota({
        'groups': [
          {
            'buckets': [
              {
                'bucketId': 'pro',
                'displayName': 'Pro',
                'remaining': {'remainingFraction': 0.5},
                'description': 'Weekly allowance',
              },
              {
                'bucketId': 'flash',
                'description': 'Flash',
                'remaining': {'remainingFraction': 1},
              },
            ],
          },
        ],
      });
      expect(snapshot.windows.map((window) => window.id), ['pro', 'flash']);
      expect(snapshot.windows.first.usedPercent, 50);
      expect(snapshot.windows.last.label, 'Flash');
      expect(
        snapshot.windows.every((window) => window.resetsAt == null),
        isTrue,
      );
    },
  );

  test('Codex app-server returns independently identified limit buckets', () {
    final snapshot = parseCodexQuota({
      'result': {
        'rateLimitsByLimitId': {
          'codex': {
            'primary': {
              'usedPercent': 12,
              'windowDurationMins': 300,
              'resetsAt': 1791442800,
            },
          },
          'review': {
            'secondary': {'usedPercent': 75, 'windowDurationMins': 10080},
          },
        },
      },
    });
    expect(snapshot.windows.map((window) => window.id), [
      'codex:primary',
      'review:secondary',
    ]);
    expect(snapshot.windows.first.usedPercent, 12);
    expect(snapshot.windows.last.usedPercent, 75);
    expect(snapshot.windows.last.label, 'review · 7 days');
  });

  test('Claude statusline reads utilization and epoch reset', () {
    final snapshot = parseClaudeQuota({
      'rate_limits': {
        'five_hour': {'used_percentage': 28, 'resets_at': 1791442800},
      },
    });
    expect(snapshot.windows.single.usedPercent, 28);
    expect(
      snapshot.windows.single.resetsAt!.millisecondsSinceEpoch,
      1791442800000,
    );
  });

  test('Antigravity user status reads model quota without invented reset', () {
    final snapshot = parseAntigravityQuota({
      'userStatus': {
        'cascadeModelConfigData': {
          'clientModelConfigs': [
            {
              'label': 'Model A',
              'quotaInfo': {'remainingFraction': 0.4},
            },
          ],
        },
      },
    });
    expect(snapshot.windows.single.label, 'Model A');
    expect(snapshot.windows.single.usedPercent, closeTo(60, 0.0001));
    expect(snapshot.windows.single.resetsAt, isNull);
  });

  test('Codex token_count preserves both windows and epoch reset times', () {
    final snapshot = parseCodexQuota({
      'type': 'event_msg',
      'payload': {
        'type': 'token_count',
        'rate_limits': {
          'primary': {
            'used_percent': 27,
            'window_minutes': 300,
            'resets_at': 1791442800,
          },
          'secondary': {
            'used_percent': 81.5,
            'window_minutes': 10080,
            'resets_at': 1791961200,
          },
        },
      },
    }, observedAt: observedAt);
    expect(snapshot.provider, ProviderKind.codex);
    expect(snapshot.status, QuotaStatus.live);
    expect(snapshot.observedAt, observedAt);
    expect(snapshot.windows, hasLength(2));
    expect(snapshot.windows.first.remainingPercent, 73);
    expect(snapshot.windows.first.durationMinutes, 300);
    expect(
      snapshot.windows.first.resetsAt!.millisecondsSinceEpoch,
      1791442800000,
    );
    expect(snapshot.windows.last.usedPercent, 81.5);
  });

  test('Claude normalizes offset timestamps and preserves real zero usage', () {
    final snapshot = parseClaudeQuota({
      'five_hour': {'utilization': 0, 'resets_at': '2026-10-08T21:00:00+09:00'},
      'seven_day': null,
      'seven_day_sonnet': {'utilization': 42.25, 'resets_at': null},
    });
    expect(snapshot.windows, hasLength(2));
    expect(snapshot.windows.first.usedPercent, 0);
    expect(snapshot.windows.first.resetsAt, DateTime.utc(2026, 10, 8, 12));
    expect(snapshot.windows.last.id, 'seven_day_sonnet');
    expect(snapshot.windows.last.resetsAt, isNull);
  });

  test('Antigravity converts remaining fraction to used percentage', () {
    final snapshot = parseAntigravityQuota({
      'models': {
        'model-a': {
          'displayName': 'Model A',
          'quotaInfo': {
            'remainingFraction': 0.75,
            'resetTime': '2026-10-09T00:00:00Z',
          },
        },
        'model-b': {
          'quotaInfo': {'remainingFraction': 0},
        },
        'model-c': {
          'quotaInfo': {'remainingFraction': 1},
        },
      },
    });
    expect(snapshot.provider, ProviderKind.antigravity);
    expect(snapshot.windows.map((window) => window.usedPercent), [25, 100, 0]);
    expect(snapshot.windows.first.label, 'Model A');
    expect(snapshot.windows.first.resetsAt, DateTime.utc(2026, 10, 9));
  });

  test(
    'missing or malformed percentages remain unknown when reset is valid',
    () {
      for (final percent in [
        null,
        '20',
        -1,
        101,
        double.nan,
        double.infinity,
      ]) {
        final snapshot = parseClaudeQuota({
          'five_hour': {
            'utilization': percent,
            'resets_at': '2026-10-08T12:00:00Z',
          },
        });
        expect(snapshot.windows.single.usedPercent, isNull);
        expect(snapshot.windows.single.remainingPercent, isNull);
      }
    },
  );

  test('invalid and absent windows produce unavailable snapshots', () {
    final snapshots = [
      parseCodexQuota({}),
      parseCodexQuota({
        'rate_limits': {'primary': false},
      }),
      parseCodexQuota({
        'primary': {'used_percent': -1, 'resets_at': 'bad'},
      }),
      parseCodexQuota({
        'primary': {'resets_at': 1e300},
      }),
      parseClaudeQuota({
        'five_hour': {'utilization': 200, 'resets_at': 'bad'},
      }),
      parseAntigravityQuota({'models': []}),
      parseAntigravityQuota({
        'models': {
          'x': {
            'quotaInfo': {'remainingFraction': 2},
          },
        },
      }),
    ];
    for (final snapshot in snapshots) {
      expect(snapshot.status, QuotaStatus.unavailable);
      expect(snapshot.windows, isEmpty);
      expect(snapshot.message, isNotEmpty);
    }
  });

  test('window constructor rejects invalid percentages', () {
    for (final percent in [-1.0, 100.01, double.nan, double.infinity]) {
      expect(
        () => QuotaWindow(id: 'x', label: 'X', usedPercent: percent),
        throwsArgumentError,
      );
    }
  });

  test('snapshot windows cannot change after construction', () {
    final windows = <QuotaWindow>[];
    final snapshot = QuotaSnapshot(
      provider: ProviderKind.codex,
      windows: windows,
      observedAt: observedAt,
      source: 'test fixture',
      status: QuotaStatus.unavailable,
    );
    windows.add(QuotaWindow(id: 'x', label: 'X', usedPercent: null));
    expect(snapshot.windows, isEmpty);
    expect(() => snapshot.windows.add(windows.single), throwsUnsupportedError);
  });
}
