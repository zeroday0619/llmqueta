import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/models/usage.dart';
import 'package:llmqueta/main.dart' show overlayHeight;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/app.dart';
import 'package:llmqueta/services/preferences.dart';
import 'package:llmqueta/services/quota_controller.dart';

class PreviewWindow implements OverlayWindow {
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
  for (final mode in ['connected', 'empty', 'demo', 'hud']) {
    testWidgets('render $mode preview', (tester) async {
      final font = Platform.environment['LLMQUETA_PREVIEW_FONT'];
      final icons = Platform.environment['LLMQUETA_ICON_FONT'];
      if (font == null || icons == null) {
        fail(
            'Set LLMQUETA_PREVIEW_FONT and LLMQUETA_ICON_FONT to local font files.');
      }
      await tester.runAsync(() async {
        for (final entry
            in {'.AppleSystemUIFont': font, 'MaterialIcons': icons}.entries) {
          final loader = FontLoader(entry.key);
          loader.addFont(File(entry.value)
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes)));
          await loader.load();
        }
      });
      final controller = QuotaController();
      if (mode == 'demo') controller.setDemo(true);
      if (mode == 'connected' || mode == 'hud') {
        controller.snapshots[ProviderKind.codex] = QuotaSnapshot(
          provider: ProviderKind.codex,
          status: QuotaStatus.live,
          source: 'Preview data',
          planName: 'Pro',
          tokenUsage: const TokenUsage(
            today: TokenCount(total: 125000),
            session: TokenCount(total: 32000, input: 27000, output: 5000),
            lifetime: TokenCount(total: 4200000),
            note: 'Preview data.',
          ),
          creditBalance:
              const CreditBalance(balance: '120.50', hasCredits: true),
          resetCredits: 2,
          observedAt: DateTime.now(),
          windows: [
            QuotaWindow(
                id: 'primary',
                label: '5 hours',
                usedPercent: 28,
                resetsAt:
                    DateTime.now().add(const Duration(hours: 2, minutes: 18))),
            QuotaWindow(
                id: 'secondary',
                label: '7 days',
                usedPercent: 43,
                resetsAt:
                    DateTime.now().add(const Duration(days: 3, hours: 7))),
          ],
        );
      }
      await tester.binding.setSurfaceSize(Size(
          mode == 'hud' ? 320 : 380,
          overlayHeight(controller, false, hud: mode == 'hud') -
              (mode == 'hud' ? 0 : 28)));
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundaryKey,
          child: QuetaApp(
            controller: controller,
            window: PreviewWindow(),
            preferences: OverlayPreferences(hud: mode == 'hud'),
          )));
      await tester.pump();
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/overlay-$mode-preview.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}
