import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/quota.dart';
import 'services/preferences.dart';
import 'services/quota_controller.dart';
import 'hud_overlay.dart';

abstract class OverlayWindow {
  Future<void> setHud(bool enabled);
  Future<void> setAlwaysOnTop(bool enabled);
  Future<void> setOpacity(double opacity);
  Future<void> setCompact(bool compact);
  Future<void> startDragging();
  Future<void> close();
}

class QuetaApp extends StatelessWidget {
  const QuetaApp({
    super.key,
    required this.controller,
    required this.window,
    required this.preferences,
    this.savePreferences,
  });
  final QuotaController controller;
  final OverlayWindow window;
  final OverlayPreferences preferences;
  final Future<void> Function(OverlayPreferences)? savePreferences;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'LLM Queta',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          useMaterial3: true,
          scaffoldBackgroundColor: const Color(0xff11151c),
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xffa6e6ce),
            brightness: Brightness.dark,
          ),
          tooltipTheme: const TooltipThemeData(
            waitDuration: Duration(milliseconds: 400),
          ),
        ),
        home: OverlayPage(
          controller: controller,
          window: window,
          preferences: preferences,
          savePreferences: savePreferences,
        ),
      );
}

class OverlayPage extends StatefulWidget {
  const OverlayPage({
    super.key,
    required this.controller,
    required this.window,
    required this.preferences,
    this.savePreferences,
  });
  final QuotaController controller;
  final OverlayWindow window;
  final OverlayPreferences preferences;
  final Future<void> Function(OverlayPreferences)? savePreferences;

  @override
  State<OverlayPage> createState() => _OverlayPageState();
}

class _OverlayPageState extends State<OverlayPage> {
  late OverlayPreferences preferences = widget.preferences;
  late final Timer ticker;
  bool applyingPreferences = false;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker.cancel();
    super.dispose();
  }

  Future<void> update(OverlayPreferences next) async {
    if (applyingPreferences) return;
    setState(() => applyingPreferences = true);
    var applied = false;
    try {
      await widget.window.setHud(next.hud);
      await widget.window.setAlwaysOnTop(next.alwaysOnTop);
      await widget.window.setOpacity(next.opacity);
      await widget.window.setCompact(next.compact);
      applied = true;
      if (mounted) setState(() => preferences = next);
      await (widget.savePreferences?.call(next) ?? next.save());
    } on Object {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(applied
                ? 'Window settings applied, but could not be saved.'
                : 'Could not apply window settings.'),
          ),
        );
    } finally {
      if (mounted) setState(() => applyingPreferences = false);
    }
  }

  @override
  Widget build(BuildContext context) => preferences.hud
      ? CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                unawaited(update(preferences.copyWith(hud: false))),
          },
          child: Focus(
              autofocus: true,
              child: Scaffold(
                body: HudOverlay(
                  controller: widget.controller,
                  resetLabel: resetLabel,
                  onDrag: widget.window.startDragging,
                  onClose: widget.window.close,
                  onExit: applyingPreferences
                      ? null
                      : () =>
                          unawaited(update(preferences.copyWith(hud: false))),
                ),
              )),
        )
      : Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.keyR, control: true):
                _RefreshIntent(),
            SingleActivator(LogicalKeyboardKey.keyR, meta: true):
                _RefreshIntent(),
          },
          child: Actions(
            actions: {
              _RefreshIntent: CallbackAction<_RefreshIntent>(
                onInvoke: (_) {
                  unawaited(widget.controller.refresh());
                  return null;
                },
              ),
            },
            child: Focus(
              autofocus: true,
              child: Scaffold(
                body: SafeArea(
                  child: AnimatedBuilder(
                    animation: widget.controller,
                    builder: (context, _) => Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 8, 6, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (_) =>
                                      unawaited(widget.window.startDragging()),
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.blur_on_rounded,
                                          size: 22,
                                          color: Color(0xffa6e6ce),
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'QUETA',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.8,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: preferences.alwaysOnTop
                                    ? 'Unpin overlay'
                                    : 'Keep on top',
                                icon: Icon(
                                  preferences.alwaysOnTop
                                      ? Icons.push_pin
                                      : Icons.push_pin_outlined,
                                  size: 17,
                                ),
                                onPressed: applyingPreferences
                                    ? null
                                    : () => update(
                                          preferences.copyWith(
                                            alwaysOnTop:
                                                !preferences.alwaysOnTop,
                                          ),
                                        ),
                              ),
                              PopupMenuButton<String>(
                                enabled: !applyingPreferences,
                                tooltip: 'Overlay settings',
                                icon: const Icon(Icons.tune, size: 18),
                                onSelected: (value) {
                                  switch (value) {
                                    case 'hud':
                                      unawaited(update(
                                          preferences.copyWith(hud: true)));
                                    case 'compact':
                                      unawaited(
                                        update(
                                          preferences.copyWith(
                                            compact: !preferences.compact,
                                          ),
                                        ),
                                      );
                                    case 'demo':
                                      widget.controller.setDemo(
                                        !widget.controller.demo,
                                      );
                                    case 'opacity':
                                      unawaited(
                                        update(
                                          preferences.copyWith(
                                            opacity: preferences.opacity == 1
                                                ? 0.75
                                                : 1,
                                          ),
                                        ),
                                      );
                                    case 'help':
                                      showDialog<void>(
                                        context: context,
                                        builder: (_) => const _ConnectionHelp(),
                                      );
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'hud',
                                    child: Text('HUD mode'),
                                  ),
                                  CheckedPopupMenuItem(
                                    value: 'compact',
                                    checked: preferences.compact,
                                    child: const Text('Compact view'),
                                  ),
                                  CheckedPopupMenuItem(
                                    value: 'opacity',
                                    checked: preferences.opacity < 1,
                                    child: const Text('75% opacity'),
                                  ),
                                  CheckedPopupMenuItem(
                                    value: 'demo',
                                    checked: widget.controller.demo,
                                    child: const Text('Demo data'),
                                  ),
                                  const PopupMenuItem(
                                    value: 'help',
                                    child: Text('Connect providers'),
                                  ),
                                ],
                              ),
                              if (Theme.of(context).platform !=
                                  TargetPlatform.macOS)
                                IconButton(
                                  tooltip: 'Close',
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: widget.window.close,
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                          child: Row(
                            children: [
                              Text(
                                widget.controller.demo
                                    ? 'DEMO · SAMPLE DATA'
                                    : 'CONNECTED ACCOUNTS',
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.3,
                                  color: widget.controller.demo
                                      ? Colors.amber
                                      : const Color(0xff8c98a9),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: widget.controller.visibleSnapshots.isEmpty
                              ? _EmptyConnections(
                                  refreshing: widget.controller.refreshing)
                              : ListView(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  children: [
                                    for (final snapshot
                                        in widget.controller.visibleSnapshots)
                                      _ProviderCard(
                                        provider: snapshot.provider,
                                        snapshot: snapshot,
                                        compact: preferences.compact,
                                        now: DateTime.now(),
                                      ),
                                  ],
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 3, 8, 5),
                          child: Row(
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  color: widget.controller.demo
                                      ? Colors.amber
                                      : const Color(0xff8c98a9),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  widget.controller.refreshing
                                      ? 'Refreshing…'
                                      : 'Auto-refresh · 60s',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xff8c98a9),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Refresh now (Ctrl/Cmd+R)',
                                onPressed: widget.controller.refreshing
                                    ? null
                                    : widget.controller.refresh,
                                icon: const Icon(Icons.refresh, size: 17),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
}

class _RefreshIntent extends Intent {
  const _RefreshIntent();
}

class _EmptyConnections extends StatelessWidget {
  const _EmptyConnections({required this.refreshing});
  final bool refreshing;

  @override
  Widget build(BuildContext context) => Center(
          child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(refreshing ? Icons.sync : Icons.link_off,
              size: 28, color: const Color(0xff8c98a9)),
          const SizedBox(height: 12),
          Text(refreshing ? 'Checking connections…' : 'No connected platforms',
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          if (!refreshing) ...[
            const SizedBox(height: 8),
            const Text('Connected accounts appear here automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xff8c98a9))),
            const SizedBox(height: 12),
            TextButton(
                onPressed: () => showDialog<void>(
                    context: context, builder: (_) => const _ConnectionHelp()),
                child: const Text('Connect providers')),
          ],
        ]),
      ));
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.snapshot,
    required this.compact,
    required this.now,
  });
  final ProviderKind provider;
  final QuotaSnapshot? snapshot;
  final bool compact;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final color = [
      const Color(0xffa6e6ce),
      const Color(0xffe7b397),
      const Color(0xff9abaff),
    ][provider.index];
    final title = ['Codex', 'Claude', 'Antigravity'][provider.index];
    final status = snapshot?.status;
    final age = snapshot == null
        ? Duration.zero
        : now.toUtc().difference(snapshot!.observedAt);
    final stale = status == QuotaStatus.stale ||
        (status == QuotaStatus.live && age.inMinutes >= 10);
    final badge = stale
        ? 'STALE'
        : switch (status) {
            QuotaStatus.live => 'CONNECTED',
            QuotaStatus.demo => 'DEMO',
            QuotaStatus.error => 'ERROR',
            QuotaStatus.unavailable => 'NOT CONNECTED',
            _ => 'LOADING',
          };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: const Color(0xff1a202a),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xff2b3442)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 16,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                badge,
                style: TextStyle(
                  fontSize: 8,
                  letterSpacing: 0.6,
                  color: stale || status == QuotaStatus.error
                      ? Colors.amber
                      : const Color(0xff8c98a9),
                ),
              ),
            ],
          ),
          if (snapshot == null)
            const Padding(
              padding: EdgeInsets.only(top: 14),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (snapshot != null && snapshot!.windows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                snapshot!.message ?? 'No quota data available.',
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: Color(0xffa5afbf),
                ),
              ),
            ),
          for (final window in snapshot?.windows ?? <QuotaWindow>[])
            Padding(
              padding: EdgeInsets.only(top: compact ? 9 : 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          window.label,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xffb7c1d0),
                          ),
                        ),
                      ),
                      Text(
                        window.remainingPercent == null
                            ? 'Unknown'
                            : '${window.remainingPercent!.toStringAsFixed(0)}% left',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: window.remainingPercent != null &&
                                  window.remainingPercent! < 15
                              ? Colors.amber
                              : color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  if (window.remainingPercent != null)
                    Semantics(
                      label:
                          '${window.label}: ${window.remainingPercent!.round()} percent remaining',
                      child: LinearProgressIndicator(
                        value: window.remainingPercent! / 100,
                        color: color,
                        backgroundColor: const Color(0xff303947),
                        borderRadius: BorderRadius.circular(4),
                        minHeight: 4,
                      ),
                    ),
                  const SizedBox(height: 6),
                  Tooltip(
                    message: window.resetsAt == null
                        ? 'The provider did not report a reset time.'
                        : 'Reset: ${window.resetsAt!.toLocal()}',
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        resetLabel(window.resetsAt, now),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff8c98a9),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!compact && snapshot != null && snapshot!.windows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '${snapshot!.source} · ${age.isNegative || age.inSeconds < 60 ? 'just now' : '${age.inMinutes}m ago'}${stale ? ' · refresh needed' : ''}',
                style: const TextStyle(fontSize: 9, color: Color(0xff7c889a)),
              ),
            ),
          if (snapshot?.message != null && snapshot!.windows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                snapshot!.message!,
                style: const TextStyle(fontSize: 10, color: Colors.amber),
              ),
            ),
        ],
      ),
    );
  }
}

String resetLabel(DateTime? resetsAt, DateTime now) {
  if (resetsAt == null) return 'Reset time unavailable';
  final duration = resetsAt.difference(now);
  if (duration <= Duration.zero) return 'Reset due · awaiting fresh data';
  if (duration.inDays > 0)
    return 'Resets in ${duration.inDays}d ${duration.inHours % 24}h';
  if (duration.inHours > 0)
    return 'Resets in ${duration.inHours}h ${duration.inMinutes % 60}m';
  return 'Resets in ${duration.inMinutes}m ${duration.inSeconds % 60}s';
}

class _ConnectionHelp extends StatelessWidget {
  const _ConnectionHelp();
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Connect providers'),
        content: const SingleChildScrollView(
          child: SelectableText(
            'Codex\nInstall Codex CLI and sign in with your ChatGPT account. Queta reads limits through its app server.\n\n'
            'Claude\nConnect the included statusline bridge in Claude Code settings. Usage appears after a response. See README for the command.\n\n'
            'Antigravity\nStart the Antigravity desktop app. Queta detects its local language server. See README for manual endpoint overrides.\n\n'
            'Demo data is available in the settings menu. It is never mixed with account data.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      );
}
