import 'usage.dart';
import 'quota_account.dart';

enum ProviderKind { codex, claude, antigravity }

enum QuotaStatus { live, stale, unavailable, error, demo }

class QuotaWindow {
  QuotaWindow({
    required this.id,
    required this.label,
    required this.usedPercent,
    DateTime? resetsAt,
    this.durationMinutes,
  }) : resetsAt = resetsAt?.toUtc() {
    final percent = usedPercent;
    if (percent != null &&
        (!percent.isFinite || percent < 0 || percent > 100)) {
      throw ArgumentError.value(percent, 'usedPercent', 'Must be 0–100.');
    }
  }

  final String id;
  final String label;
  final double? usedPercent;
  final DateTime? resetsAt;
  final int? durationMinutes;

  double? get remainingPercent =>
      usedPercent == null ? null : 100 - usedPercent!;
}

class QuotaSnapshot {
  QuotaSnapshot({
    required this.provider,
    required List<QuotaWindow> windows,
    required DateTime observedAt,
    required this.source,
    required this.status,
    this.accountId,
    this.accountLabel,
    this.message,
    this.planName,
    this.tokenUsage = const TokenUsage(),
    this.creditBalance,
    this.resetCredits,
  })  : windows = List.unmodifiable(windows),
        observedAt = observedAt.toUtc();

  final ProviderKind provider;
  final String? accountId;
  final String? accountLabel;
  final List<QuotaWindow> windows;
  final DateTime observedAt;
  final String source;
  final QuotaStatus status;
  final String? message;
  final String? planName;
  final TokenUsage tokenUsage;
  final CreditBalance? creditBalance;
  final int? resetCredits;

  bool get hasUsage =>
      windows.isNotEmpty ||
      tokenUsage.hasData ||
      creditBalance != null ||
      resetCredits != null;

  QuotaSnapshot withAccount(QuotaAccount account) => QuotaSnapshot(
        provider: provider,
        accountId: account.id,
        accountLabel: account.label,
        windows: windows,
        observedAt: observedAt,
        source: source,
        status: status,
        message: message,
        planName: planName,
        tokenUsage: tokenUsage,
        creditBalance: creditBalance,
        resetCredits: resetCredits,
      );

  QuotaSnapshot withUsage({TokenUsage? tokenUsage}) {
    final usage = tokenUsage ?? this.tokenUsage;
    final available = windows.isNotEmpty ||
        usage.hasData ||
        creditBalance != null ||
        resetCredits != null;
    return QuotaSnapshot(
      provider: provider,
      accountId: accountId,
      accountLabel: accountLabel,
      windows: windows,
      observedAt: observedAt,
      source: source,
      status: available &&
              (status == QuotaStatus.unavailable ||
                  (status == QuotaStatus.error && usage.hasData))
          ? QuotaStatus.live
          : status,
      message: status == QuotaStatus.error && usage.hasData
          ? 'Quota windows are unavailable; showing token usage.'
          : available && status == QuotaStatus.unavailable
              ? null
              : message,
      planName: planName,
      tokenUsage: usage,
      creditBalance: creditBalance,
      resetCredits: resetCredits,
    );
  }
}

Map<String, dynamic>? _object(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : null;

double? _percent(Object? value) {
  if (value is! num) return null;
  final percent = value.toDouble();
  return percent.isFinite && percent >= 0 && percent <= 100 ? percent : null;
}

DateTime? _isoTime(Object? value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
        caseSensitive: false,
      ).hasMatch(value)) {
    return null;
  }
  return DateTime.tryParse(value)?.toUtc();
}

DateTime? _epochTime(Object? value) {
  // DateTime supports at most 100 million days on either side of the epoch.
  if (value is! num || !value.isFinite || value.abs() > 8640000000000) {
    return null;
  }
  try {
    return DateTime.fromMillisecondsSinceEpoch(
      (value * 1000).round(),
      isUtc: true,
    );
  } on ArgumentError {
    return null;
  }
}

QuotaSnapshot _snapshot(
  ProviderKind provider,
  List<QuotaWindow> windows,
  DateTime? observedAt,
  String source, {
  String? planName,
  CreditBalance? creditBalance,
  int? resetCredits,
}) =>
    QuotaSnapshot(
      provider: provider,
      windows: windows,
      observedAt: observedAt ?? DateTime.now(),
      source: source,
      planName: planName,
      creditBalance: creditBalance,
      resetCredits: resetCredits,
      status: windows.isEmpty ? QuotaStatus.unavailable : QuotaStatus.live,
      message: windows.isEmpty
          ? 'No recognizable quota windows were returned.'
          : null,
    );

String? normalizeReportedPlanName(Object? value) {
  if (value is! String) return null;
  final name = value.trim();
  if (name.isEmpty ||
      name.length > 120 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(name) ||
      {'unknown', 'unspecified'}.contains(name.toLowerCase())) {
    return null;
  }
  return name;
}

String? _codexPlanName(Map<String, dynamic>? limits) {
  final name =
      normalizeReportedPlanName(limits?['planType'] ?? limits?['plan_type']);
  if (name == null) return null;
  return const {
        'free': 'Free',
        'go': 'Go',
        'plus': 'Plus',
        'pro': 'Pro',
        'team': 'Team',
        'business': 'Business',
        'enterprise': 'Enterprise',
        'edu': 'Edu',
      }[name] ??
      name;
}

/// Accepts an app-server account rate-limits result or a token_count event.
QuotaSnapshot parseCodexQuota(
  Map<String, dynamic> payload, {
  DateTime? observedAt,
  String source = 'Codex app-server',
}) {
  final event =
      _object(payload['result']) ?? _object(payload['payload']) ?? payload;
  final buckets = _object(event['rateLimitsByLimitId']);
  final limits =
      _object(event['rateLimits']) ?? _object(event['rate_limits']) ?? event;
  final windows = <QuotaWindow>[];
  final entries = buckets != null && buckets.isNotEmpty
      ? buckets.entries
      : [MapEntry('', limits)];
  for (final entry in entries) {
    final bucket = _object(entry.value);
    if (bucket == null) continue;
    for (final id in ['primary', 'secondary']) {
      final window = _object(bucket[id]);
      if (window == null) continue;
      final used = _percent(window['usedPercent'] ?? window['used_percent']);
      final reset = _epochTime(window['resetsAt'] ?? window['resets_at']);
      if (used == null && reset == null) continue;
      final duration = window['windowDurationMins'] ?? window['window_minutes'];
      final minutes = duration is int && duration > 0 ? duration : null;
      final windowLabel = minutes == 300
          ? '5 hours'
          : minutes == 10080
              ? '7 days'
              : id == 'primary'
                  ? 'Primary'
                  : 'Secondary';
      final bucketName = bucket['limitName'];
      final bucketLabel = bucketName is String && bucketName.isNotEmpty
          ? bucketName
          : entry.key;
      windows.add(
        QuotaWindow(
          id: entry.key.isEmpty ? id : '${entry.key}:$id',
          label: entry.key.isEmpty || entry.key == 'codex'
              ? windowLabel
              : '$bucketLabel · $windowLabel',
          usedPercent: used,
          resetsAt: reset,
          durationMinutes: minutes,
        ),
      );
    }
  }
  return _snapshot(
    ProviderKind.codex,
    windows,
    observedAt,
    source,
    planName:
        _codexPlanName(_object(buckets?['codex'])) ?? _codexPlanName(limits),
    creditBalance: parseCreditBalance(_object(buckets?['codex'])?['credits']) ??
        parseCreditBalance(limits['credits']),
    resetCredits: nonnegativeTokenCount(
        _object(event['rateLimitResetCredits'])?['availableCount']),
  ).withUsage();
}

/// Accepts a Claude statusline event or a usage response with named windows.
QuotaSnapshot parseClaudeQuota(
  Map<String, dynamic> payload, {
  DateTime? observedAt,
  String source = 'Claude statusline',
  String? planName,
}) {
  final limits = _object(payload['rate_limits']) ?? payload;
  const labels = {
    'five_hour': '5 hours',
    'seven_day': '7 days',
    'seven_day_opus': 'Opus · 7 days',
    'seven_day_sonnet': 'Sonnet · 7 days',
    'seven_day_oauth_apps': 'OAuth apps · 7 days',
    'seven_day_cowork': 'Cowork · 7 days',
  };
  final windows = <QuotaWindow>[];
  for (final entry in labels.entries) {
    final window = _object(limits[entry.key]);
    if (window == null) continue;
    final used = _percent(window['used_percentage'] ?? window['utilization']);
    final reset =
        _epochTime(window['resets_at']) ?? _isoTime(window['resets_at']);
    if (used == null && reset == null) continue;
    windows.add(
      QuotaWindow(
        id: entry.key,
        label: entry.value,
        usedPercent: used,
        resetsAt: reset,
        durationMinutes: entry.key == 'five_hour' ? 300 : 10080,
      ),
    );
  }
  return _snapshot(ProviderKind.claude, windows, observedAt, source,
      planName: normalizeReportedPlanName(planName));
}

/// Accepts grouped quota buckets, a user status response, or a models map.
QuotaSnapshot parseAntigravityQuota(
  Map<String, dynamic> payload, {
  DateTime? observedAt,
  String source = 'Antigravity language server',
}) {
  final models = _object(payload['models']);
  final windows = <QuotaWindow>[];
  final userStatus = _object(payload['userStatus']);
  final config = _object(userStatus?['cascadeModelConfigData']);
  final clients = config?['clientModelConfigs'];
  final groups = payload['groups'];
  final modelEntries = <MapEntry<String, dynamic>>[
    ...?models?.entries,
    if (clients is List)
      for (var index = 0; index < clients.length; index++)
        MapEntry('model-$index', clients[index]),
  ];
  if (groups is List) {
    for (var groupIndex = 0; groupIndex < groups.length; groupIndex++) {
      final buckets = _object(groups[groupIndex])?['buckets'];
      if (buckets is! List) continue;
      for (var bucketIndex = 0; bucketIndex < buckets.length; bucketIndex++) {
        final bucket = _object(buckets[bucketIndex]);
        final id = bucket?['bucketId'];
        modelEntries.add(
          MapEntry(
            id is String ? id : 'group-$groupIndex-bucket-$bucketIndex',
            bucket,
          ),
        );
      }
    }
  }
  for (final entry in modelEntries) {
    final model = _object(entry.value);
    final quota = _object(model?['quotaInfo']) ?? _object(model?['remaining']);
    if (quota == null) continue;
    final fraction = quota['remainingFraction'];
    final remaining = fraction is num && fraction >= 0 && fraction <= 1
        ? _percent(fraction * 100)
        : null;
    final reset = _isoTime(quota['resetTime']);
    if (remaining == null && reset == null) continue;
    final label =
        model?['displayName'] ?? model?['label'] ?? model?['description'];
    windows.add(
      QuotaWindow(
        id: entry.key,
        label: label is String && label.isNotEmpty ? label : entry.key,
        usedPercent: remaining == null ? null : 100 - remaining,
        resetsAt: reset,
      ),
    );
  }
  final planStatus = _object(userStatus?['planStatus']);
  final planInfo = _object(planStatus?['planInfo']);
  return _snapshot(ProviderKind.antigravity, windows, observedAt, source,
      planName: normalizeReportedPlanName(planInfo?['planName']));
}
