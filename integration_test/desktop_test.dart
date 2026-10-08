import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';

import 'package:llmqueta/main.dart' as application;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native overlay renders and applies window controls',
      (tester) async {
    await application.main(['--demo']);
    await tester.pumpAndSettle();
    expect(find.text('Codex'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    expect(find.text('Antigravity'), findsOneWidget);
    expect(find.text('DEMO · SAMPLE DATA'), findsOneWidget);
    if (Platform.isMacOS) {
      expect(await windowManager.getTitleBarHeight(), greaterThan(0));
      expect(find.byTooltip('Close'), findsNothing);
    } else {
      expect(find.byTooltip('Close'), findsOneWidget);
    }
    final window = application.DesktopOverlayWindow();
    await window.setAlwaysOnTop(true);
    expect(await windowManager.isAlwaysOnTop(), isTrue);
    await window.setAlwaysOnTop(false);
    expect(await windowManager.isAlwaysOnTop(), isFalse);
    await window.setOpacity(0.75);
    expect(await windowManager.getOpacity(), closeTo(0.75, 0.01));
    await window.setOpacity(1);
    await window.setCompact(true);
    await tester.pumpAndSettle();
    expect((await windowManager.getSize()).height, closeTo(540, 2));
    await window.setHud(true);
    expect(await windowManager.isAlwaysOnTop(), isTrue);
    expect(await windowManager.getOpacity(), closeTo(0.90, 0.01));
    expect((await windowManager.getSize()).width, closeTo(320, 2));
    await window.setAlwaysOnTop(false);
    await window.setOpacity(1);
    expect(await windowManager.isAlwaysOnTop(), isTrue);
    expect(await windowManager.getOpacity(), closeTo(0.90, 0.01));
    await window.setHud(false);
    expect(await windowManager.isAlwaysOnTop(), isFalse);
    expect(await windowManager.getOpacity(), closeTo(1, 0.01));
    expect((await windowManager.getSize()).width, closeTo(380, 2));
    expect((await windowManager.getSize()).height, closeTo(540, 2));
    if (Platform.isMacOS) {
      expect(await windowManager.getTitleBarHeight(), greaterThan(0));
    }
    await window.setCompact(false);
    await window.setAlwaysOnTop(true);
    expect(tester.takeException(), isNull);
  });
}
