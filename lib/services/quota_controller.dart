import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/quota.dart';
import 'quota_sources.dart';

typedef QuotaFetcher = Future<QuotaSnapshot> Function(ProviderKind provider);

class QuotaController extends ChangeNotifier {
  QuotaController({QuotaFetcher? fetcher})
      : _fetcher = fetcher ?? QuotaSources().fetch;

  final QuotaFetcher _fetcher;
  final Map<ProviderKind, QuotaSnapshot> snapshots = {};
  List<QuotaSnapshot> get visibleSnapshots => [
        for (final provider in ProviderKind.values)
          if (snapshots[provider] case final snapshot?)
            if (snapshot.windows.isNotEmpty &&
                {QuotaStatus.live, QuotaStatus.stale, QuotaStatus.demo}
                    .contains(snapshot.status))
              snapshot,
      ];
  Timer? _timer;
  bool refreshing = false;
  bool demo = false;
  bool _disposed = false;
  int _generation = 0;

  void start() {
    unawaited(refresh());
    _timer ??= Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(refresh()),
    );
  }

  void setDemo(bool enabled) {
    demo = enabled;
    _generation++;
    refreshing = false;
    snapshots.clear();
    unawaited(refresh());
  }

  Future<void> refresh() async {
    if (refreshing || _disposed) return;
    final generation = _generation;
    refreshing = true;
    notifyListeners();
    await Future.wait(
      ProviderKind.values.map((provider) async {
        QuotaSnapshot snapshot;
        try {
          snapshot = demo ? _demo(provider) : await _fetcher(provider);
        } on Object {
          snapshot = QuotaSnapshot(
            provider: provider,
            windows: [],
            observedAt: DateTime.now(),
            source: 'Provider',
            status: QuotaStatus.error,
            message: 'Could not refresh. Check the connection and retry.',
          );
        }
        if (_disposed || generation != _generation) return;
        final previous = snapshots[provider];
        if (snapshot.status == QuotaStatus.error &&
            previous != null &&
            previous.windows.isNotEmpty) {
          snapshot = QuotaSnapshot(
            provider: provider,
            windows: previous.windows,
            observedAt: previous.observedAt,
            source: previous.source,
            status: QuotaStatus.stale,
            message: snapshot.message,
          );
        }
        snapshots[provider] = snapshot;
        notifyListeners();
      }),
    );
    if (_disposed || generation != _generation) return;
    refreshing = false;
    notifyListeners();
  }

  QuotaSnapshot _demo(ProviderKind provider) {
    final now = DateTime.now().toUtc();
    return QuotaSnapshot(
      provider: provider,
      observedAt: now,
      source: 'Sample data',
      status: QuotaStatus.demo,
      windows: [
        QuotaWindow(
          id: 'primary',
          label:
              provider == ProviderKind.antigravity ? 'Gemini Pro' : '5 hours',
          usedPercent: [28.0, 64.0, 12.0][provider.index],
          resetsAt: now.add(const Duration(hours: 2, minutes: 18)),
        ),
        QuotaWindow(
          id: 'secondary',
          label:
              provider == ProviderKind.antigravity ? 'Claude Sonnet' : '7 days',
          usedPercent: [43.0, 21.0, 36.0][provider.index],
          resetsAt: now.add(const Duration(days: 3, hours: 7)),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
