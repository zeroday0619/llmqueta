import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/preferences.dart';
import 'services/quota_controller.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final savedPreferences = await OverlayPreferences.load();
  final preferences = arguments.contains('--hud')
      ? savedPreferences.copyWith(hud: true)
      : savedPreferences;
  final controller = QuotaController();
  if (arguments.contains('--demo')) controller.setDemo(true);
  final window = DesktopOverlayWindow(
      controller: controller,
      compact: preferences.compact,
      hud: preferences.hud,
      alwaysOnTop: preferences.alwaysOnTop,
      opacity: preferences.opacity);
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: Size(preferences.hud ? 320 : 380,
          overlayHeight(controller, preferences.compact, hud: preferences.hud)),
      minimumSize:
          preferences.hud ? const Size(280, 140) : const Size(340, 260),
      center: true,
      title: 'LLM Queta',
      titleBarStyle: Platform.isMacOS && !preferences.hud
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden,
      windowButtonVisibility: Platform.isMacOS && !preferences.hud,
      backgroundColor: const Color(0xff11151c),
    ),
    () async {
      if (Platform.isMacOS) await windowManager.setBrightness(Brightness.dark);
      await window.setAlwaysOnTop(preferences.alwaysOnTop);
      await window.setOpacity(preferences.opacity);
      await windowManager.show();
      await windowManager.focus();
    },
  );
  controller.addListener(window.updateContentSize);
  controller.start();
  runApp(
    QuetaApp(controller: controller, window: window, preferences: preferences),
  );
}

class DesktopOverlayWindow implements OverlayWindow {
  DesktopOverlayWindow({
    this.controller,
    bool compact = false,
    bool hud = false,
    bool alwaysOnTop = true,
    double opacity = 1,
  })  : _compact = compact,
        _hud = hud,
        _alwaysOnTop = alwaysOnTop,
        _opacity = opacity;
  final QuotaController? controller;
  bool _compact;
  bool _hud;
  bool _alwaysOnTop;
  double _opacity;
  Size? _requestedSize;

  Size get _contentSize => Size(
        _hud ? 320 : 380,
        controller == null
            ? (_hud ? 280 : (_compact ? 540 : 760))
            : overlayHeight(controller!, _compact, hud: _hud),
      );

  Future<void> _updateSize() async {
    final size = _contentSize;
    if (_requestedSize == size) return;
    _requestedSize = size;
    await windowManager.setSize(size);
  }

  void updateContentSize() {
    if (controller == null) return;
    unawaited(_updateSize());
  }

  @override
  Future<void> setAlwaysOnTop(bool enabled) async {
    _alwaysOnTop = enabled;
    await windowManager.setAlwaysOnTop(_hud || enabled);
  }

  @override
  Future<void> setOpacity(double opacity) async {
    _opacity = opacity;
    await windowManager.setOpacity(_hud ? opacity.clamp(0.45, 0.90) : opacity);
  }

  @override
  Future<void> setHud(bool enabled) async {
    _hud = enabled;
    await windowManager.setTitleBarStyle(
      Platform.isMacOS && !enabled
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden,
      windowButtonVisibility: Platform.isMacOS && !enabled,
    );
    await windowManager
        .setMinimumSize(enabled ? const Size(280, 140) : const Size(340, 260));
    await windowManager.setAlwaysOnTop(enabled || _alwaysOnTop);
    await windowManager
        .setOpacity(enabled ? _opacity.clamp(0.45, 0.90) : _opacity);
    await _updateSize();
  }

  @override
  Future<void> setCompact(bool compact) async {
    _compact = compact;
    await _updateSize();
  }

  @override
  Future<void> startDragging() => windowManager.startDragging();

  @override
  Future<void> close() => windowManager.close();
}

double overlayHeight(QuotaController controller, bool compact,
    {bool hud = false}) {
  final snapshots = controller.visibleSnapshots;
  if (hud) {
    final height = 88 +
        snapshots.fold<double>(
          0,
          (sum, snapshot) => sum + 32 + snapshot.windows.length * 46,
        );
    return height.clamp(140, 600).toDouble();
  }
  if (snapshots.isEmpty) return 320;
  final height = 144 +
      snapshots.fold<double>(
          0,
          (sum, snapshot) =>
              sum +
              (compact ? 62 : 90) +
              snapshot.windows.length * (compact ? 58 : 72));
  return height.clamp(320, 800).toDouble();
}
