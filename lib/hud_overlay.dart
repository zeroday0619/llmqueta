import 'dart:async';

import 'package:flutter/material.dart';

import 'models/quota.dart';
import 'services/quota_controller.dart';

class HudOverlay extends StatelessWidget {
  const HudOverlay(
      {super.key,
      required this.controller,
      required this.resetLabel,
      required this.onDrag,
      required this.onClose,
      required this.onExit});

  final QuotaController controller;
  final String Function(DateTime?, DateTime) resetLabel;
  final Future<void> Function() onDrag;
  final Future<void> Function() onClose;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff131b24),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xff3b4957)),
          ),
          child: Column(children: [
            SizedBox(
                height: 44,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 4),
                  child: Row(children: [
                    Expanded(
                        child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (_) => unawaited(onDrag()),
                      child: SizedBox(
                          height: 44,
                          child: Row(children: [
                            Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                    color: controller.demo
                                        ? Colors.amber
                                        : const Color(0xffa6e6ce),
                                    shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Text(
                                controller.demo
                                    ? 'QUETA / DEMO'
                                    : 'QUETA / HUD',
                                style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.3,
                                    color: Color(0xffa5b3c4))),
                          ])),
                    )),
                    IconButton(
                        tooltip: 'Return to window (Esc)',
                        onPressed: onExit,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.open_in_full, size: 15)),
                    IconButton(
                        tooltip: 'Close',
                        onPressed: onClose,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16)),
                  ]),
                )),
            Expanded(
                child: controller.visibleSnapshots.isEmpty
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                                controller.refreshing
                                    ? 'Checking connections…'
                                    : 'No connected platforms',
                                style: const TextStyle(
                                    fontSize: 12, color: Color(0xffa5b3c4)))))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                        children: [
                            for (final snapshot in controller.visibleSnapshots)
                              _HudAccount(
                                  snapshot: snapshot, resetLabel: resetLabel),
                          ])),
            SizedBox(
                height: 28,
                child: Padding(
                    padding: const EdgeInsets.only(left: 14, right: 6),
                    child: Row(children: [
                      Expanded(
                          child: Text(
                              controller.refreshing
                                  ? 'Updating…'
                                  : 'Refreshes every 60s',
                              style: const TextStyle(
                                  fontSize: 9, color: Color(0xff7f90a5)))),
                      IconButton(
                          tooltip: 'Refresh now',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 28, height: 28),
                          icon: const Icon(Icons.refresh, size: 14),
                          onPressed: controller.refreshing
                              ? null
                              : controller.refresh),
                    ]))),
          ]),
        ),
      );
}

class _HudAccount extends StatelessWidget {
  const _HudAccount({required this.snapshot, required this.resetLabel});
  final QuotaSnapshot snapshot;
  final String Function(DateTime?, DateTime) resetLabel;

  @override
  Widget build(BuildContext context) {
    final color = [
      const Color(0xffa6e6ce),
      const Color(0xffe7b397),
      const Color(0xff9abaff)
    ][snapshot.provider.index];
    final stale = snapshot.status == QuotaStatus.stale ||
        (snapshot.status == QuotaStatus.live &&
            DateTime.now().difference(snapshot.observedAt).inMinutes >= 10);
    return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                height: 22,
                child: Row(children: [
                  Expanded(
                      child: Text(
                          [
                            'Codex',
                            'Claude',
                            'Antigravity'
                          ][snapshot.provider.index],
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color))),
                  if (stale)
                    const Text('STALE',
                        style: TextStyle(fontSize: 8, color: Colors.amber)),
                ])),
            for (final window in snapshot.windows)
              Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                          child: Text(window.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xffa5b3c4)))),
                      Text(
                          window.remainingPercent == null
                              ? 'Unknown'
                              : '${window.remainingPercent!.round()}% left',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 4),
                    if (window.remainingPercent != null)
                      LinearProgressIndicator(
                          value: window.remainingPercent! / 100,
                          minHeight: 2,
                          color: color,
                          backgroundColor: const Color(0xff2c3845),
                          semanticsLabel:
                              '${window.label}: ${window.remainingPercent!.round()} percent remaining'),
                    const SizedBox(height: 4),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Tooltip(
                            message: window.resetsAt?.toLocal().toString() ??
                                'Reset time unavailable',
                            child: Text(
                                resetLabel(window.resetsAt, DateTime.now()),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 9, color: Color(0xff7f90a5))))),
                  ])),
          ],
        ));
  }
}
