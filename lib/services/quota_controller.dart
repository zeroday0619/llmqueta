import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/quota.dart';
import '../models/quota_account.dart';
import '../models/usage.dart';
import 'quota_sources.dart';

typedef QuotaFetcher = Future<QuotaSnapshot> Function(ProviderKind provider);

typedef AccountQuotaFetcher = Future<QuotaSnapshot> Function(
    QuotaAccount account);

class QuotaController extends ChangeNotifier {
  QuotaController({
    QuotaFetcher? fetcher,
    List<QuotaAccount>? accounts,
    AccountQuotaFetcher? accountFetcher,
    Future<void> Function(List<QuotaAccount>)? saveAccounts,
  })  : _accounts = List.unmodifiable(accounts ?? QuotaAccount.defaults),
        _fetcher = accountFetcher ??
            (fetcher == null
                ? QuotaSources().fetchAccount
                : (account) => fetcher(account.provider)),
        _saveAccounts = saveAccounts {
    validateAccounts(_accounts);
  }

  final AccountQuotaFetcher _fetcher;
  final Future<void> Function(List<QuotaAccount>)? _saveAccounts;
  List<QuotaAccount> _accounts;
  List<QuotaAccount> get accounts => _accounts;
  final Map<String, QuotaSnapshot> snapshots = {};
  bool _saving = false;

  Future<void> setAccounts(List<QuotaAccount> accounts) async {
    if (_disposed) return;
    if (_saving) throw StateError('An account update is already in progress.');
    final next = List<QuotaAccount>.unmodifiable(accounts);
    validateAccounts(next);
    _saving = true;
    try {
      await _saveAccounts?.call(next);
      if (_disposed) return;
      final previousAccounts = {
        for (final account in _accounts) account.id: account
      };
      _generation++;
      refreshing = false;
      snapshots.removeWhere((id, snapshot) => !next.any((account) =>
          account.id == id &&
          previousAccounts[id] != null &&
          account.hasSameConnection(previousAccounts[id]!)));
      _accounts = next;
      for (final account in next) {
        final snapshot = snapshots[account.id];
        if (snapshot != null)
          snapshots[account.id] = snapshot.withAccount(account);
      }
      notifyListeners();
      unawaited(refresh());
    } finally {
      _saving = false;
    }
  }

  List<QuotaSnapshot> get visibleSnapshots => [
        for (final account in accounts)
          if (snapshots[account.id] case final snapshot?)
            if (snapshot.hasUsage &&
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
      accounts.map((account) async {
        final provider = account.provider;
        QuotaSnapshot snapshot;
        try {
          snapshot = demo ? _demo(provider) : await _fetcher(account);
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
        final previous = snapshots[account.id];
        if (snapshot.status == QuotaStatus.error &&
            previous != null &&
            previous.hasUsage) {
          snapshot = QuotaSnapshot(
            provider: provider,
            windows: previous.windows,
            observedAt: previous.observedAt,
            source: previous.source,
            planName: previous.planName,
            tokenUsage: previous.tokenUsage,
            creditBalance: previous.creditBalance,
            resetCredits: previous.resetCredits,
            status: QuotaStatus.stale,
            message: snapshot.message,
          );
        }
        snapshots[account.id] = snapshot.withAccount(account);
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
      tokenUsage: const TokenUsage(
        today: TokenCount(total: 125000, input: 100000, output: 25000),
        session: TokenCount(
            total: 32000, input: 27000, output: 5000, cachedInput: 16000),
        lifetime: TokenCount(total: 4200000),
        note: 'Sample token counts.',
      ),
      creditBalance: provider == ProviderKind.codex
          ? const CreditBalance(balance: '120.50', hasCredits: true)
          : null,
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
