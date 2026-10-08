class TokenCount {
  const TokenCount({
    required this.total,
    this.input,
    this.output,
    this.cachedInput,
  });

  final int total;
  final int? input;
  final int? output;
  final int? cachedInput;
}

class TokenUsage {
  const TokenUsage({
    this.today,
    this.session,
    this.lifetime,
    this.todayLabel = 'Today',
    this.sessionLabel = 'Session',
    this.lifetimeLabel = 'Lifetime',
    this.note,
  });

  final TokenCount? today;
  final TokenCount? session;
  final TokenCount? lifetime;
  final String todayLabel;
  final String sessionLabel;
  final String lifetimeLabel;
  final String? note;

  bool get hasData => today != null || session != null || lifetime != null;
}

class CreditBalance {
  const CreditBalance({this.balance, this.unlimited = false, this.hasCredits});

  final String? balance;
  final bool unlimited;
  final bool? hasCredits;
}

Map<String, dynamic>? _object(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : null;

int? nonnegativeTokenCount(Object? value) =>
    value is int && value >= 0 ? value : null;

CreditBalance? parseCreditBalance(Object? value) {
  final object = _object(value);
  if (object == null) return null;
  final raw = object['balance'];
  final text = raw is String
      ? raw.trim()
      : raw is num
          ? raw.toString()
          : null;
  final numeric = text == null ? null : double.tryParse(text);
  final balance = numeric != null &&
          numeric.isFinite &&
          numeric >= 0 &&
          RegExp(r'^\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$').hasMatch(text!)
      ? text
      : null;
  final unlimited = object['unlimited'] == true;
  final available = object['hasCredits'];
  final hasCredits = available is bool ? available : null;
  if (balance == null && !unlimited && hasCredits == null) return null;
  return CreditBalance(
    balance: balance,
    unlimited: unlimited,
    hasCredits: hasCredits,
  );
}

/// Reads account totals without converting quota percentages or monetary data.
TokenUsage parseCodexTokenUsage(
  Map<String, dynamic> payload, {
  DateTime? now,
  Map<String, dynamic>? sessionPayload,
}) {
  final result = _object(payload['result']) ?? payload;
  final summary = _object(result['summary']);
  final lifetime = nonnegativeTokenCount(summary?['lifetimeTokens']);
  final date = now ?? DateTime.now();
  final todayKey = '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
  final buckets = result['dailyUsageBuckets'];
  final matching = buckets is List
      ? buckets
          .map(_object)
          .where((bucket) => bucket?['startDate'] == todayKey)
          .toList()
      : <Map<String, dynamic>?>[];
  final today = matching.length == 1
      ? nonnegativeTokenCount(matching.single?['tokens'])
      : null;
  final sessionResult = sessionPayload == null
      ? result
      : _object(sessionPayload['result']) ?? sessionPayload;
  final thread = _object(sessionResult['threadUsage']);
  final groups = thread?['groups'];
  TokenCount? session;
  if (groups is List && groups.isNotEmpty) {
    int? sum(String field) {
      var total = 0;
      for (final group in groups) {
        final count = nonnegativeTokenCount(_object(group)?[field]);
        if (count == null) return null;
        total += count;
        if (total < 0) return null;
      }
      return total;
    }

    final total = sum('totalTokens');
    if (total != null) {
      session = TokenCount(
        total: total,
        input: sum('inputTokens'),
        output: sum('outputTokens'),
        cachedInput: sum('cachedInputTokens'),
      );
    }
  }
  return TokenUsage(
    today: today == null ? null : TokenCount(total: today),
    session: session,
    lifetime: lifetime == null ? null : TokenCount(total: lifetime),
    todayLabel: 'Today (provider)',
    note:
        'Account token activity. Today uses the provider bucket dated $todayKey; '
        'the service does not specify its day timezone. '
        'Session usage requires a configured Codex thread and may be estimated. '
        'Cached input is included in input tokens.',
  );
}
