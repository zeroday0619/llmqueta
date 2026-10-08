import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/services/quota_controller.dart';

QuotaSnapshot measurement(
  ProviderKind provider, {
  QuotaStatus status = QuotaStatus.live,
}) =>
    QuotaSnapshot(
      provider: provider,
      windows: status == QuotaStatus.error
          ? []
          : [QuotaWindow(id: 'hour', label: 'Hour', usedPercent: 30)],
      observedAt: DateTime.utc(2026, 10, 8),
      source: 'Test',
      status: status,
    );

void main() {
  test(
    'a refresh failure retains the last observation and marks it stale',
    () async {
      var failure = false;
      final controller = QuotaController(
        fetcher: (provider) async => measurement(
          provider,
          status: failure ? QuotaStatus.error : QuotaStatus.live,
        ),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      failure = true;
      await controller.refresh();
      expect(
        controller.snapshots[ProviderKind.codex]!.status,
        QuotaStatus.stale,
      );
      expect(
        controller.snapshots[ProviderKind.codex]!.windows.single.usedPercent,
        30,
      );
      expect(
        controller.snapshots[ProviderKind.codex]!.observedAt,
        DateTime.utc(2026, 10, 8),
      );
    },
  );

  test('switching to demo discards in-flight real responses', () async {
    final completers = {
      for (final provider in ProviderKind.values)
        provider: Completer<QuotaSnapshot>(),
    };
    final controller = QuotaController(
      fetcher: (provider) => completers[provider]!.future,
    );
    addTearDown(controller.dispose);
    final request = controller.refresh();
    controller.setDemo(true);
    for (final provider in ProviderKind.values) {
      completers[provider]!.complete(measurement(provider));
    }
    await request;
    await Future<void>.delayed(Duration.zero);
    expect(
      controller.snapshots.values.every(
        (snapshot) => snapshot.status == QuotaStatus.demo,
      ),
      isTrue,
    );
  });
}
