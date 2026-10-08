import 'dart:io';

class AppPaths {
  AppPaths({Map<String, String>? environment, String? operatingSystem})
      : environment = environment ?? Platform.environment,
        operatingSystem = operatingSystem ?? Platform.operatingSystem;

  final Map<String, String> environment;
  final String operatingSystem;

  String get configurationDirectory {
    final home = environment['HOME'] ?? environment['USERPROFILE'];
    if (operatingSystem == 'windows') {
      final roaming = environment['APPDATA'];
      if (roaming != null && roaming.isNotEmpty) return '$roaming/llmqueta';
      if (home != null && home.isNotEmpty) {
        return '$home/AppData/Roaming/llmqueta';
      }
    } else if (operatingSystem == 'macos' && home != null && home.isNotEmpty) {
      return '$home/Library/Application Support/llmqueta';
    } else {
      final configuration = environment['XDG_CONFIG_HOME'];
      if (configuration != null && configuration.startsWith('/')) {
        return '$configuration/llmqueta';
      }
      if (home != null && home.isNotEmpty) return '$home/.config/llmqueta';
    }
    throw StateError('The user configuration directory is unavailable.');
  }

  File get claudeSnapshotFile => File('$configurationDirectory/claude.json');
}
