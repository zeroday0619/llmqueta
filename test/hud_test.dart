import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/hud_overlay.dart';
import 'package:llmqueta/app.dart';
import 'package:llmqueta/main.dart' show overlayHeight;
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/services/quota_controller.dart';
import 'package:llmqueta/services/preferences.dart';

class HudTestWindow implements OverlayWindow {
  final modes = <bool>[];
  @override
  Future<void> setHud(bool enabled) async {
    modes.add(enabled);
  }

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {}
  @override
  Future<void> setOpacity(double opacity) async {}
  @override
  Future<void> setCompact(bool compact) async {}
  @override
  Future<void> startDragging() async {}
  @override
  Future<void> close() async {}
}

void main() {
  testWidgets('HUD menu and Escape switch modes and persist the choice',
      (tester) async {
    final controller = QuotaController()..setDemo(true);
    final window = HudTestWindow();
    final saved = <bool>[];
    await tester.pumpWidget(QuetaApp(
        controller: controller,
        window: window,
        preferences: const OverlayPreferences(),
        savePreferences: (value) async {
          saved.add(value.hud);
        }));
    await tester.pump();
    await tester.tap(find.byTooltip('Overlay settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('HUD mode'));
    await tester.pumpAndSettle();
    expect(find.byType(HudOverlay), findsOneWidget);
    expect(saved, [true]);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(HudOverlay), findsNothing);
    expect(find.byTooltip('Overlay settings'), findsOneWidget);
    expect(window.modes, [true, false]);
    expect(saved, [true, false]);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
  testWidgets(
      'HUD fits a narrow panel and keeps return and close controls accessible',
      (tester) async {
    final controller = QuotaController();
    controller.snapshots[ProviderKind.codex] = QuotaSnapshot(
      provider: ProviderKind.codex,
      windows: [
        QuotaWindow(
            id: 'primary',
            label: '5 hours',
            usedPercent: 20,
            resetsAt: DateTime.now().add(const Duration(hours: 1)))
      ],
      observedAt: DateTime.now(),
      source: 'Fixture',
      status: QuotaStatus.live,
    );
    await tester.binding
        .setSurfaceSize(Size(280, overlayHeight(controller, false, hud: true)));
    var returned = false;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HudOverlay(
      controller: controller,
      resetLabel: resetLabel,
      onDrag: () async {},
      onExit: () => returned = true,
      onClose: () async {
        closed = true;
      },
    ))));
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Claude'), findsNothing);
    expect(find.text('80% left'), findsOneWidget);
    await tester.tap(find.byTooltip('Return to window (Esc)'));
    await tester.tap(find.byTooltip('Close'));
    expect(returned, isTrue);
    expect(closed, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('HUD marks old observations and preserves unknown quota',
      (tester) async {
    final controller = QuotaController();
    controller.snapshots[ProviderKind.claude] = QuotaSnapshot(
      provider: ProviderKind.claude,
      windows: [
        QuotaWindow(id: 'primary', label: '5 hours', usedPercent: null)
      ],
      observedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      source: 'Fixture',
      status: QuotaStatus.live,
    );
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: HudOverlay(
      controller: controller,
      resetLabel: resetLabel,
      onDrag: () async {},
      onExit: () {},
      onClose: () async {},
    ))));
    expect(find.text('STALE'), findsOneWidget);
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.text('Reset time unavailable'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
