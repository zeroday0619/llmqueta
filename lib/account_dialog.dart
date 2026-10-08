import 'package:flutter/material.dart';

import 'models/quota.dart';
import 'models/quota_account.dart';
import 'services/quota_controller.dart';

String _providerName(ProviderKind provider) =>
    ['Codex', 'Claude', 'Antigravity'][provider.index];

class AccountManagerDialog extends StatefulWidget {
  const AccountManagerDialog(
      {super.key, required this.controller, this.configurationError});
  final QuotaController controller;
  final String? configurationError;

  @override
  State<AccountManagerDialog> createState() => _AccountManagerDialogState();
}

class _AccountManagerDialogState extends State<AccountManagerDialog> {
  bool saving = false;
  String? error;

  Future<void> save(List<QuotaAccount> accounts) async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.controller.setAccounts(accounts);
    } on Object {
      if (mounted)
        setState(() => error =
            'Could not save accounts. Your previous settings are unchanged.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> edit([QuotaAccount? account]) async {
    final result = await showDialog<QuotaAccount>(
      context: context,
      builder: (_) => _AccountEditor(account: account),
    );
    if (result == null || !mounted) return;
    await save([
      for (final current in widget.controller.accounts)
        if (current.id == result.id) result else current,
      if (account == null) result,
    ]);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => AlertDialog(
          title: const Text('Manage accounts'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.configurationError != null)
                      Text(widget.configurationError!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    const Text(
                        'Each profile reads an existing local sign-in. Removing a profile does not sign out or delete credentials.'),
                    if (widget.controller.demo)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                            'Demo mode is active. Sample data does not show account connection status.'),
                      ),
                    for (final account in widget.controller.accounts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(account.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${_providerName(account.provider)} · ${status(account)}'),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                              tooltip: 'Edit ${account.label}',
                              onPressed: saving ? null : () => edit(account),
                              icon: const Icon(Icons.edit_outlined)),
                          IconButton(
                              tooltip: 'Remove ${account.label}',
                              onPressed: saving
                                  ? null
                                  : () => save(widget.controller.accounts
                                      .where(
                                          (current) => current.id != account.id)
                                      .toList()),
                              icon: const Icon(Icons.delete_outline)),
                        ]),
                      ),
                    if (widget.controller.accounts.isEmpty)
                      const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text('No accounts registered.')),
                    if (error != null)
                      Text(error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                  ]),
            ),
          ),
          actions: [
            if (QuotaAccount.defaults.any((account) => !widget
                .controller.accounts
                .any((current) => current.id == account.id)))
              TextButton(
                onPressed: saving
                    ? null
                    : () => save([
                          ...widget.controller.accounts,
                          for (final account in QuotaAccount.defaults)
                            if (!widget.controller.accounts
                                .any((current) => current.id == account.id))
                              account,
                        ]),
                child: const Text('Restore default connections'),
              ),
            TextButton(
                onPressed: saving ? null : () => edit(),
                child: const Text('Add account')),
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(context),
                child: const Text('Done')),
          ],
        ),
      );

  String status(QuotaAccount account) {
    if (widget.controller.demo) return 'Not checked in demo mode';
    final snapshot = widget.controller.snapshots[account.id];
    return switch (snapshot?.status) {
      QuotaStatus.live => 'Connected',
      QuotaStatus.stale => 'Stale data',
      QuotaStatus.error => 'Connection error',
      QuotaStatus.unavailable => 'Not connected',
      QuotaStatus.demo => 'Sample data',
      null => 'Not checked',
    };
  }
}

class _AccountEditor extends StatefulWidget {
  const _AccountEditor({this.account});
  final QuotaAccount? account;
  @override
  State<_AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<_AccountEditor> {
  final form = GlobalKey<FormState>();
  String? validationError;
  late ProviderKind provider = widget.account?.provider ?? ProviderKind.codex;
  late final label = TextEditingController(text: widget.account?.label);
  late final directory =
      TextEditingController(text: widget.account?.configurationDirectory);
  late final snapshot =
      TextEditingController(text: widget.account?.snapshotPath);
  late final endpoint = TextEditingController(text: widget.account?.endpoint);
  late final csrf =
      TextEditingController(text: widget.account?.csrfTokenEnvironmentVariable);
  bool get defaultConnection =>
      widget.account != null &&
      widget.account!.configurationDirectory == null &&
      widget.account!.snapshotPath == null &&
      widget.account!.endpoint == null;

  @override
  void dispose() {
    for (final controller in [label, directory, snapshot, endpoint, csrf]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? optional(TextEditingController controller) =>
      controller.text.trim().isEmpty ? null : controller.text.trim();

  void submit() {
    if (!form.currentState!.validate()) return;
    final account = QuotaAccount(
      id: widget.account?.id ??
          'account-${DateTime.now().microsecondsSinceEpoch}',
      provider: provider,
      label: label.text.trim(),
      configurationDirectory:
          defaultConnection || provider == ProviderKind.antigravity
              ? null
              : optional(directory),
      snapshotPath: !defaultConnection && provider == ProviderKind.claude
          ? optional(snapshot)
          : null,
      endpoint: !defaultConnection && provider == ProviderKind.antigravity
          ? optional(endpoint)
          : null,
      csrfTokenEnvironmentVariable:
          !defaultConnection && provider == ProviderKind.antigravity
              ? optional(csrf)
              : null,
    );
    try {
      account.validate();
    } on FormatException catch (error) {
      setState(() => validationError = error.message);
      return;
    } on ArgumentError catch (error) {
      setState(() => validationError = error.message.toString());
      return;
    }
    Navigator.pop(context, account);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.account == null ? 'Add account' : 'Edit account'),
        content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
                child: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (validationError != null)
                        Text(validationError!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                      DropdownButtonFormField<ProviderKind>(
                        initialValue: provider,
                        decoration:
                            const InputDecoration(labelText: 'Provider'),
                        items: [
                          for (final kind in ProviderKind.values)
                            DropdownMenuItem(
                                value: kind, child: Text(_providerName(kind)))
                        ],
                        onChanged: widget.account != null
                            ? null
                            : (value) => setState(() => provider = value!),
                      ),
                      TextFormField(
                          controller: label,
                          decoration:
                              const InputDecoration(labelText: 'Account label'),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter an account label.'
                                  : null),
                      if (defaultConnection)
                        const Padding(
                            padding: EdgeInsets.only(top: 16),
                            child: Text(
                                'This profile uses the existing local connection and environment settings. Add another account to configure a separate connection.')),
                      if (!defaultConnection &&
                          provider != ProviderKind.antigravity)
                        TextFormField(
                            controller: directory,
                            decoration: InputDecoration(
                                labelText: provider == ProviderKind.codex
                                    ? 'Codex home directory'
                                    : 'Claude configuration directory'),
                            validator: (value) => value == null ||
                                    value.trim().isEmpty
                                ? 'Enter this account’s configuration directory.'
                                : null),
                      if (!defaultConnection && provider == ProviderKind.claude)
                        TextFormField(
                            controller: snapshot,
                            decoration: const InputDecoration(
                                labelText: 'Claude snapshot file',
                                helperText:
                                    'Use the output path of this account’s statusline bridge.'),
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? 'Enter this account’s snapshot file.'
                                    : null),
                      if (!defaultConnection &&
                          provider == ProviderKind.antigravity) ...[
                        TextFormField(
                            controller: endpoint,
                            decoration: const InputDecoration(
                                labelText: 'Antigravity loopback URL',
                                hintText: 'http://127.0.0.1:42100'),
                            validator: (value) {
                              final uri = Uri.tryParse(value?.trim() ?? '');
                              if (uri == null ||
                                  !['http', 'https'].contains(uri.scheme) ||
                                  !['127.0.0.1', '::1', '[::1]']
                                      .contains(uri.host) ||
                                  uri.userInfo.isNotEmpty ||
                                  uri.hasQuery ||
                                  uri.hasFragment)
                                return 'Enter a local HTTP(S) URL without credentials.';
                              return null;
                            }),
                        TextFormField(
                            controller: csrf,
                            decoration: const InputDecoration(
                                labelText:
                                    'CSRF environment variable (optional)',
                                helperText:
                                    'Variable name only. Do not enter a token.'),
                            validator: (value) => value != null &&
                                    value.trim().isNotEmpty &&
                                    !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$')
                                        .hasMatch(value.trim())
                                ? 'Enter an environment variable name.'
                                : null),
                      ],
                    ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(onPressed: submit, child: const Text('Save'))
        ],
      );
}
