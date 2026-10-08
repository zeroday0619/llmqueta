import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/main.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/services/quota_controller.dart';

void main() {
  test('visible accounts determine window height and stale data stays visible',
      () {
    final controller = QuotaController();
    addTearDown(controller.dispose);
    final emptyHeight = overlayHeight(controller, false);
    controller.snapshots[ProviderKind.codex] = QuotaSnapshot(
      provider: ProviderKind.codex,
      windows: [
        QuotaWindow(id: 'primary', label: '5 hours', usedPercent: 25),
        QuotaWindow(id: 'secondary', label: '7 days', usedPercent: 50),
      ],
      observedAt: DateTime.now(),
      source: 'Fixture',
      status: QuotaStatus.stale,
    );
    controller.snapshots[ProviderKind.claude] = QuotaSnapshot(
      provider: ProviderKind.claude,
      windows: [],
      observedAt: DateTime.now(),
      source: 'Fixture',
      status: QuotaStatus.unavailable,
    );
    expect(controller.visibleSnapshots.single.provider, ProviderKind.codex);
    expect(overlayHeight(controller, false), greaterThan(emptyHeight));
    expect(overlayHeight(controller, true),
        lessThan(overlayHeight(controller, false)));
  });
}
