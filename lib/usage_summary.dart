import 'package:flutter/material.dart';

import 'models/quota.dart';
import 'models/usage.dart';

class UsageSummary extends StatelessWidget {
  const UsageSummary({super.key, required this.snapshot, this.hud = false});

  final QuotaSnapshot snapshot;
  final bool hud;

  static double estimatedHeight(QuotaSnapshot snapshot, {bool hud = false}) =>
      8 +
      (3 +
              (snapshot.creditBalance != null ? 1 : 0) +
              (snapshot.resetCredits != null ? 1 : 0)) *
          (hud ? 19 : 22);

  Widget _row(String label, String value, String tooltip) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Tooltip(
          message: tooltip,
          child: Row(children: [
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: hud ? 10 : 11, color: const Color(0xffa5b3c4))),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: hud ? 11 : 12)),
            ),
          ]),
        ),
      );

  Widget _tokens(String label, TokenCount? count) {
    final details = count == null
        ? 'Token count unavailable.'
        : [
            '${count.total} tokens',
            if (count.input != null) 'Input: ${count.input}',
            if (count.output != null) 'Output: ${count.output}',
            if (count.cachedInput != null)
              'Cached input: ${count.cachedInput} (included in input)',
          ].join('\n');
    return _row(
        '$label tokens',
        count == null ? 'Unavailable' : _format(count.total),
        '$details${snapshot.tokenUsage.note == null ? '' : '\n${snapshot.tokenUsage.note}'}');
  }

  static String _format(int count) {
    for (final unit in [(1000000000, 'B'), (1000000, 'M'), (1000, 'K')]) {
      if (count >= unit.$1) {
        final value = (count / unit.$1).toStringAsFixed(1);
        return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}${unit.$2}';
      }
    }
    return '$count';
  }

  static String _wholeCredits(String balance) {
    final parts = balance.toLowerCase().split('e');
    final decimal = parts.first.split('.');
    final digits = decimal.join();
    final exponent = parts.length == 1 ? 0 : int.tryParse(parts.last);
    if (exponent == null) return '0';
    final point = decimal.first.length + exponent;
    if (point <= 0) return '0';
    final whole = point < digits.length
        ? digits.substring(0, point)
        : digits.padRight(point, '0');
    return BigInt.parse(whole).toString();
  }

  @override
  Widget build(BuildContext context) {
    final usage = snapshot.tokenUsage;
    final credits = snapshot.creditBalance;
    final balance = credits == null
        ? ''
        : credits.unlimited
            ? 'Unlimited'
            : credits.balance != null
                ? '${_wholeCredits(credits.balance!)} credits'
                : credits.hasCredits == true
                    ? 'Available'
                    : 'Balance unavailable';
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(children: [
        _tokens(usage.todayLabel, usage.today),
        _tokens(usage.sessionLabel, usage.session),
        _tokens(usage.lifetimeLabel, usage.lifetime),
        if (credits != null)
          _row('Credits', balance,
              'Provider-reported credit balance: ${credits.unlimited || credits.balance == null ? balance : '${credits.balance} credits'}'),
        if (snapshot.resetCredits != null)
          _row('Reset credits', '${snapshot.resetCredits}',
              'Provider-reported reset credits: ${snapshot.resetCredits}'),
      ]),
    );
  }
}
