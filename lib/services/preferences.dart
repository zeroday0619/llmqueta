import 'dart:convert';
import 'dart:io';

import 'app_paths.dart';

class OverlayPreferences {
  const OverlayPreferences({
    this.alwaysOnTop = true,
    this.compact = false,
    this.hud = false,
    this.opacity = 1,
  });

  final bool alwaysOnTop;
  final bool compact;
  final bool hud;
  final double opacity;

  OverlayPreferences copyWith({
    bool? alwaysOnTop,
    bool? compact,
    bool? hud,
    double? opacity,
  }) =>
      OverlayPreferences(
        alwaysOnTop: alwaysOnTop ?? this.alwaysOnTop,
        compact: compact ?? this.compact,
        hud: hud ?? this.hud,
        opacity: opacity ?? this.opacity,
      );

  static File get file => File(
        '${AppPaths().configurationDirectory}${Platform.pathSeparator}preferences.json',
      );

  static Future<OverlayPreferences> load() async {
    try {
      final value =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return OverlayPreferences(
        alwaysOnTop:
            value['alwaysOnTop'] is bool ? value['alwaysOnTop'] as bool : true,
        compact: value['compact'] == true,
        hud: value['hud'] == true,
        opacity: value['opacity'] is num
            ? (value['opacity'] as num).toDouble().clamp(0.45, 1).toDouble()
            : 1,
      );
    } on Object {
      return const OverlayPreferences();
    }
  }

  Future<void> save() async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'alwaysOnTop': alwaysOnTop,
        'compact': compact,
        'hud': hud,
        'opacity': opacity,
      }),
    );
  }
}
