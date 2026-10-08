import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:llmqueta/account_dialog.dart';
import 'package:llmqueta/app.dart';
import 'package:llmqueta/models/quota.dart';
import 'package:llmqueta/models/quota_account.dart';
import 'package:llmqueta/services/preferences.dart';
import 'package:llmqueta/services/quota_controller.dart';

class AccountTestWindow implements OverlayWindow {
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

final personal = QuotaAccount(
    id: 'personal',
    provider: ProviderKind.codex,
    label: 'Personal',
    configurationDirectory:
        '${Directory.systemTemp.absolute.path}/profiles/personal');
final work = QuotaAccount(
    id: 'work',
    provider: ProviderKind.codex,
    label: 'Work subscription with a very long account label',
    configurationDirectory:
        '${Directory.systemTemp.absolute.path}/profiles/work');

void main() {
  Future<void> mount(WidgetTester tester, QuotaController controller,
      {bool hud = false}) async {
    await tester.binding.setSurfaceSize(Size(hud ? 280 : 340, 720));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(QuetaApp(
        controller: controller,
        window: AccountTestWindow(),
        preferences: OverlayPreferences(hud: hud)));
    await tester.pump();
  }

  for (final hud in [false, true]) {
    testWidgets('same-provider accounts remain distinct with hud=$hud',
        (tester) async {
      final controller = QuotaController(
          accounts: [personal, work],
          accountFetcher: (account) async => QuotaSnapshot(
              provider: account.provider,
              windows: [
                QuotaWindow(
                    id: 'primary',
                    label: '5 hours',
                    usedPercent: account.id == 'personal' ? 20 : 70)
              ],
              observedAt: DateTime.now(),
              source: 'Fixture',
              status: QuotaStatus.live));
      await controller.refresh();
      await mount(tester, controller, hud: hud);
      expect(find.text('Codex'), findsNWidgets(2));
      expect(find.text(personal.label), findsOneWidget);
      expect(find.text(work.label), findsOneWidget);
      expect(find.text('80% left'), findsOneWidget);
      expect(find.text('30% left'), findsOneWidget);
      expect(tester.widget<Text>(find.text(work.label)).overflow,
          TextOverflow.ellipsis);
      expect(find.byTooltip(work.label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account manager adds edits and removes a scoped profile',
      (tester) async {
    final saved = <List<QuotaAccount>>[];
    final controller = QuotaController(
        accounts: [],
        saveAccounts: (accounts) async {
          saved.add(accounts);
        },
        accountFetcher: (account) async => QuotaSnapshot(
            provider: account.provider,
            windows: [],
            observedAt: DateTime.now(),
            source: 'Fixture',
            status: QuotaStatus.unavailable));
    await mount(tester, controller);
    await tester.tap(find.text('Manage accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add account'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Account label'), 'Personal');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Codex home directory'),
        '${Directory.systemTemp.absolute.path}/profiles/personal');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.accounts.single.label, 'Personal');
    expect(find.text('Codex · Not connected'), findsOneWidget);
    final id = controller.accounts.single.id;
    await tester.tap(find.byTooltip('Edit Personal'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Account label'), 'Work');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.accounts.single.id, id);
    expect(controller.accounts.single.label, 'Work');
    await tester.tap(find.byTooltip('Remove Work'));
    await tester.pumpAndSettle();
    expect(controller.accounts, isEmpty);
    expect(saved, hasLength(3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed persistence preserves account and reports failure',
      (tester) async {
    final controller = QuotaController(
        accounts: [personal],
        saveAccounts: (_) async => throw StateError('fixture save failure'));
    await mount(tester, controller);
    await tester.tap(find.text('Manage accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remove Personal'));
    await tester.pumpAndSettle();
    expect(controller.accounts.single.id, personal.id);
    expect(find.textContaining('Could not save accounts.'), findsOneWidget);
    expect(find.byType(AccountManagerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('defaults can be restored after removing every account',
      (tester) async {
    final controller = QuotaController(
        accounts: [],
        saveAccounts: (_) async {},
        accountFetcher: (account) async => QuotaSnapshot(
            provider: account.provider,
            windows: [],
            observedAt: DateTime.now(),
            source: 'Fixture',
            status: QuotaStatus.unavailable));
    await mount(tester, controller);
    await tester.tap(find.text('Manage accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore default connections'));
    await tester.pumpAndSettle();
    expect(controller.accounts.map((account) => account.id),
        ['codex', 'claude', 'antigravity']);
    expect(find.text('Restore default connections'), findsNothing);
    await tester.tap(find.byTooltip('Edit Default').first);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Codex home directory'),
        findsNothing);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Account label'), 'Local Codex');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.accounts.first.configurationDirectory, isNull);
    expect(controller.accounts.first.id, 'codex');
    expect(controller.accounts.first.label, 'Local Codex');
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid labels keep the editor open with an actionable error',
      (tester) async {
    final controller =
        QuotaController(accounts: [], saveAccounts: (_) async {});
    await mount(tester, controller);
    await tester.tap(find.text('Manage accounts'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add account'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Account label'), 'a' * 81);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Codex home directory'),
        '${Directory.systemTemp.absolute.path}/profiles/personal');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.accounts, isEmpty);
    expect(find.textContaining('Account label must'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
