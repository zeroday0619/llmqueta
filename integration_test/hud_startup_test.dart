import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:llmqueta/hud_overlay.dart';
import 'package:llmqueta/main.dart' as application;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('HUD startup renders without a native button overlap',
      (tester) async {
    await application.main(['--demo', '--hud']);
    await tester.pumpAndSettle();
    expect(find.byType(HudOverlay), findsOneWidget);
    expect(find.text('QUETA / DEMO'), findsOneWidget);
    expect(
        find.byTooltip('Return to window (Esc)').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
    expect(await windowManager.isAlwaysOnTop(), isTrue);
    expect(await windowManager.getOpacity(), lessThanOrEqualTo(0.91));
    expect((await windowManager.getSize()).width, closeTo(320, 2));
    expect(tester.takeException(), isNull);
  });
}
