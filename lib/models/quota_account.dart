import 'dart:io';

import 'quota.dart';

/// Stores connection locations without copying provider credentials.
class QuotaAccount {
  const QuotaAccount({
    required this.id,
    required this.provider,
    required this.label,
    this.configurationDirectory,
    this.snapshotPath,
    this.endpoint,
    this.csrfTokenEnvironmentVariable,
  });

  final String id;
  final ProviderKind provider;
  final String label;
  final String? configurationDirectory;
  final String? snapshotPath;
  final String? endpoint;
  final String? csrfTokenEnvironmentVariable;

  static const defaults = [
    QuotaAccount(id: 'codex', provider: ProviderKind.codex, label: 'Default'),
    QuotaAccount(id: 'claude', provider: ProviderKind.claude, label: 'Default'),
    QuotaAccount(
        id: 'antigravity',
        provider: ProviderKind.antigravity,
        label: 'Default'),
  ];

  bool get isDefault => id == provider.name;

  void validate() {
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$').hasMatch(id)) {
      throw const FormatException(
          'Account ID must contain 1–80 letters, digits, hyphens, or underscores.');
    }
    if (label.trim().isEmpty ||
        label.length > 80 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(label)) {
      throw const FormatException(
          'Account label must contain 1–80 printable characters.');
    }
    for (final value in [
      configurationDirectory,
      snapshotPath,
      endpoint,
      csrfTokenEnvironmentVariable
    ]) {
      if (value != null && (value.trim().isEmpty || value.contains('\u0000'))) {
        throw const FormatException(
            'Connection values must not be empty or contain null characters.');
      }
    }
    if (ProviderKind.values
        .any((kind) => kind.name == id && kind != provider)) {
      throw const FormatException(
          'Default account IDs must match their provider.');
    }
    for (final path in [configurationDirectory, snapshotPath]) {
      if (path != null &&
          (path.length > 4096 ||
              !(Platform.isWindows
                  ? RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+)')
                      .hasMatch(path)
                  : path.startsWith('/')))) {
        throw const FormatException(
            'Account paths must be absolute and at most 4096 characters.');
      }
    }
    if ((provider != ProviderKind.antigravity &&
            (endpoint != null || csrfTokenEnvironmentVariable != null)) ||
        (provider == ProviderKind.antigravity &&
            (configurationDirectory != null || snapshotPath != null)) ||
        (provider == ProviderKind.codex && snapshotPath != null)) {
      throw const FormatException(
          'Connection fields do not match the account provider.');
    }
    final configured = configurationDirectory != null ||
        snapshotPath != null ||
        endpoint != null ||
        csrfTokenEnvironmentVariable != null;
    if (!isDefault || configured) {
      if (provider == ProviderKind.codex && configurationDirectory == null) {
        throw const FormatException(
            'Codex accounts require a configuration directory.');
      }
      if (provider == ProviderKind.claude &&
          (configurationDirectory == null || snapshotPath == null)) {
        throw const FormatException(
            'Claude accounts require a configuration directory and snapshot path.');
      }
      if (provider == ProviderKind.antigravity && endpoint == null) {
        throw const FormatException(
            'Antigravity accounts require an explicit endpoint.');
      }
    }
    if (endpoint != null) {
      final uri = Uri.tryParse(endpoint!);
      if (uri == null ||
          !['http', 'https'].contains(uri.scheme) ||
          !['127.0.0.1', '::1', '[::1]'].contains(uri.host) ||
          !uri.hasPort ||
          uri.port < 1 ||
          uri.port > 65535 ||
          (uri.path.isNotEmpty && uri.path != '/') ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment) {
        throw const FormatException(
            'Endpoint must be a loopback HTTP(S) origin with an explicit port and no credentials.');
      }
    }
    if (csrfTokenEnvironmentVariable != null &&
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$')
            .hasMatch(csrfTokenEnvironmentVariable!)) {
      throw const FormatException(
          'CSRF token environment variable name is invalid.');
    }
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'provider': provider.name,
        'label': label,
        if (configurationDirectory != null)
          'configurationDirectory': configurationDirectory,
        if (snapshotPath != null) 'snapshotPath': snapshotPath,
        if (endpoint != null) 'endpoint': endpoint,
        if (csrfTokenEnvironmentVariable != null)
          'csrfTokenEnvironmentVariable': csrfTokenEnvironmentVariable,
      };

  factory QuotaAccount.fromJson(Map<String, dynamic> json) {
    String? field(String name, {bool required = false}) {
      final value = json[name];
      if (value is String) return value;
      if (value == null && !required) return null;
      throw FormatException('Invalid account field: $name.');
    }

    final providerName = field('provider', required: true);
    final matches =
        ProviderKind.values.where((provider) => provider.name == providerName);
    if (matches.isEmpty)
      throw const FormatException('Unknown account provider.');
    final account = QuotaAccount(
      id: field('id', required: true)!,
      provider: matches.single,
      label: field('label', required: true)!,
      configurationDirectory: field('configurationDirectory'),
      snapshotPath: field('snapshotPath'),
      endpoint: field('endpoint'),
      csrfTokenEnvironmentVariable: field('csrfTokenEnvironmentVariable'),
    );
    account.validate();
    return account;
  }

  bool hasSameConnection(QuotaAccount other) =>
      provider == other.provider &&
      configurationDirectory == other.configurationDirectory &&
      snapshotPath == other.snapshotPath &&
      endpoint == other.endpoint &&
      csrfTokenEnvironmentVariable == other.csrfTokenEnvironmentVariable;
}

void validateAccounts(List<QuotaAccount> accounts) {
  final ids = <String>{};
  for (final account in accounts) {
    account.validate();
    if (!ids.add(account.id))
      throw const FormatException('Account IDs must be unique.');
  }
}
