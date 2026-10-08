import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/app.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/services/preferences.dart';
import 'package:llmqueta/services/quota_controller.dart';

class TestWindow implements OverlayWindow {
  @override
  Future<void> setHud(bool enabled) async {}
  @override
  Future<void> close() async {}
  @override
  Future<void> setAlwaysOnTop(bool enabled) async {}
  @override
  Future<void> setCompact(bool compact) async {}
  @override
  Future<void> setOpacity(double opacity) async {}
  @override
  Future<void> startDragging() async {}
}

void main() {
  Future<QuotaController> mountOverlay(
    WidgetTester tester, {
    List<QuotaSnapshot> snapshots = const [],
    bool compact = false,
    bool refreshing = false,
  }) async {
    await tester.binding.setSurfaceSize(Size(340, compact ? 440 : 720));
    final controller = QuotaController()..refreshing = refreshing;
    for (final provider in ProviderKind.values) {
      controller.snapshots[provider] = QuotaSnapshot(
        provider: provider,
        windows: [],
        observedAt: DateTime.now(),
        source: 'Fixture',
        status: QuotaStatus.unavailable,
        message: 'Connect ${provider.name} to display usage.',
      );
    }
    for (final snapshot in snapshots) {
      controller.snapshots[snapshot.provider] = snapshot;
    }
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
      QuetaApp(
        controller: controller,
        window: TestWindow(),
        preferences: OverlayPreferences(compact: compact),
      ),
    );
    await tester.pump();
    return controller;
  }

  test('reset countdown does not imply a quota refresh', () {
    final now = DateTime.utc(2026, 10, 8);
    expect(resetLabel(null, now), 'Reset time unavailable');
    expect(resetLabel(now, now), 'Reset due · awaiting fresh data');
    expect(
      resetLabel(now.add(const Duration(hours: 2, minutes: 3)), now),
      'Resets in 2h 3m',
    );
  });

  testWidgets('demo overlay renders at narrow desktop width without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(340, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = QuotaController()..setDemo(true);
    await tester.pumpWidget(
      QuetaApp(
        controller: controller,
        window: TestWindow(),
        preferences: const OverlayPreferences(),
      ),
    );
    await tester.pump();
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Antigravity'), findsOneWidget);
    expect(find.text('DEMO · SAMPLE DATA'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('unknown usage never renders a zero or full quota bar', (
    tester,
  ) async {
    await mountOverlay(
      tester,
      snapshots: [
        QuotaSnapshot(
          provider: ProviderKind.codex,
          windows: [
            QuotaWindow(id: 'primary', label: '5 hours', usedPercent: null),
          ],
          observedAt: DateTime.now(),
          source: 'Codex app-server',
          status: QuotaStatus.live,
        ),
      ],
    );
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Claude'), findsNothing);
    expect(find.text('Antigravity'), findsNothing);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Reset time unavailable'), findsOneWidget);
    expect(find.text('0% left'), findsNothing);
    expect(find.text('100% left'), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnected and empty error snapshots show connection guidance',
      (
    tester,
  ) async {
    await mountOverlay(
      tester,
      snapshots: [
        QuotaSnapshot(
          provider: ProviderKind.claude,
          windows: [],
          observedAt: DateTime.now(),
          source: 'Claude statusline',
          status: QuotaStatus.error,
          message:
              'The snapshot is unreadable. Run the statusline bridge again.',
        ),
      ],
    );
    expect(find.text('No connected platforms'), findsOneWidget);
    expect(find.text('Connect providers'), findsOneWidget);
    expect(find.text('Codex'), findsNothing);
    expect(find.text('Claude'), findsNothing);
    expect(find.text('Antigravity'), findsNothing);
    expect(find.text('NOT CONNECTED'), findsNothing);
    expect(find.text('ERROR'), findsNothing);
    await tester.tap(find.text('Connect providers'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'old observations and elapsed resets preserve the measured quota',
    (tester) async {
      final now = DateTime.now();
      await mountOverlay(
        tester,
        snapshots: [
          QuotaSnapshot(
            provider: ProviderKind.codex,
            windows: [
              QuotaWindow(
                id: 'primary',
                label: '5 hours',
                usedPercent: 80,
                resetsAt: now.subtract(const Duration(minutes: 1)),
              ),
            ],
            observedAt: now.subtract(const Duration(minutes: 11)),
            source: 'Codex app-server',
            status: QuotaStatus.live,
          ),
        ],
      );
      expect(find.text('STALE'), findsOneWidget);
      expect(find.text('20% left'), findsOneWidget);
      expect(find.text('Reset due · awaiting fresh data'), findsOneWidget);
      expect(find.textContaining('refresh needed'), findsOneWidget);
      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.value, 0.2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact view retains stale data and fits long model labels',
    (tester) async {
      await mountOverlay(
        tester,
        compact: true,
        snapshots: [
          QuotaSnapshot(
            provider: ProviderKind.codex,
            windows: [
              QuotaWindow(
                id: 'review',
                label:
                    'Additional code review allowance for a long named model',
                usedPercent: 90,
              ),
            ],
            observedAt: DateTime.now(),
            source: 'Private fixture source',
            status: QuotaStatus.stale,
            message: 'Connection lost. Displaying the last observation.',
          ),
        ],
      );
      expect(find.text('STALE'), findsOneWidget);
      expect(find.text('10% left'), findsOneWidget);
      expect(
        find.text('Connection lost. Displaying the last observation.'),
        findsOneWidget,
      );
      expect(find.textContaining('Private fixture source'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(find.text('Codex'), findsOneWidget);
      expect(find.text('Claude'), findsNothing);
      expect(find.text('Antigravity'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty refresh indicates connection checks', (tester) async {
    await mountOverlay(tester, refreshing: true);
    expect(find.text('Checking connections…'), findsOneWidget);
    expect(find.text('No connected platforms'), findsNothing);
    expect(find.text('Codex'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final platform in [TargetPlatform.macOS, TargetPlatform.windows]) {
    testWidgets('close control follows $platform native decoration',
        (tester) async {
      await mountOverlay(tester);
      expect(find.byTooltip('Close'),
          platform == TargetPlatform.macOS ? findsNothing : findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(platform));
  }
}
