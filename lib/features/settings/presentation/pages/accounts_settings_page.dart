import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/auth_provider.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../github/presentation/providers/github_provider.dart';

class AccountsSettingsPage extends ConsumerStatefulWidget {
  const AccountsSettingsPage({super.key});

  @override
  ConsumerState<AccountsSettingsPage> createState() =>
      _AccountsSettingsPageState();
}

class _AccountsSettingsPageState extends ConsumerState<AccountsSettingsPage> {
  late final TextEditingController _patCtrl;
  late final TextEditingController _usernameCtrl;
  bool _obscurePat = true;
  bool _saving = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _patCtrl = TextEditingController();
    _usernameCtrl = TextEditingController();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final dao = ref.read(appSettingsDaoProvider);
    final pat = await dao.getValue('github_pat');
    final username = await dao.getValue('github_username');
    if (mounted) {
      _patCtrl.text = pat ?? '';
      _usernameCtrl.text = username ?? '';
    }
  }

  @override
  void dispose() {
    _patCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final dao = ref.read(appSettingsDaoProvider);
      final pat = _patCtrl.text.trim();
      final username = _usernameCtrl.text.trim();

      if (pat.isEmpty) {
        await dao.deleteKey('github_pat');
      } else {
        await dao.setValue('github_pat', pat);
      }

      if (username.isEmpty) {
        await dao.deleteKey('github_username');
      } else {
        await dao.setValue('github_username', username);
      }

      ref.invalidate(githubPatProvider);
      ref.invalidate(githubUsernameProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _testing = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.onInverseSurface,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Testing GitHub connection…'),
          ],
        ),
        duration: const Duration(minutes: 1),
      ),
    );
    try {
      final result = await ref
          .read(githubSyncNotifierProvider.notifier)
          .testConnection(
            _patCtrl.text.trim(),
            _usernameCtrl.text.trim(),
          )
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => throw 'Connection timed out — check your network or token.',
          );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      await showDialog<void>(
        context: context,
        builder: (ctx) => _ConnectionResultDialog(result: result),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _saving || _testing;

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!kIsWeb) ...[
            Text(
              'Cloud Sync',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 8),
            const _SupabaseAccountTile(),
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
          ],
          Text(
            'GitHub',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Connect your GitHub account to automatically pull issue references '
            'from your commit history into time entries.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _usernameCtrl,
            decoration: const InputDecoration(
              labelText: 'GitHub Username',
              hintText: 'e.g. octocat',
              prefixIcon: Icon(Icons.person_outline),
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _patCtrl,
            obscureText: _obscurePat,
            decoration: InputDecoration(
              labelText: 'Personal Access Token',
              hintText: 'ghp_...',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePat ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () =>
                    setState(() => _obscurePat = !_obscurePat),
              ),
            ),
            autocorrect: false,
          ),
          const SizedBox(height: 8),
          Text(
            'Generate at GitHub → Settings → Developer Settings → '
            'Personal access tokens. Required scope: repo.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _testConnection,
                  icon: _testing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Test Connection'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('How it works', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          _HowItWorksStep(
            number: '1',
            text:
                'Link a GitHub repo to each project (Client → Project → Edit). '
                'Paste the full URL or just owner/repo.',
          ),
          _HowItWorksStep(
            number: '2',
            text:
                'Tap the sync button on the Time Tracking screen to scan the '
                'current date range.',
          ),
          _HowItWorksStep(
            number: '3',
            text:
                'Any branch named Issue-XXXX that had commits on that day will '
                'appear in the preview - select which ones to apply.',
          ),
        ],
      ),
    );
  }
}

class _ConnectionResultDialog extends StatelessWidget {
  final GitHubConnectionTest result;
  const _ConnectionResultDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Connection Test'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // PAT auth result
          _ResultRow(
            ok: result.patOk,
            label: result.patOk
                ? 'Authenticated as ${result.authedAs}'
                : (result.patError ?? 'Authentication failed'),
          ),
          if (result.repoResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Repo access:', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            ...result.repoResults.entries.map(
              (e) => _ResultRow(ok: e.value, label: e.key),
            ),
          ] else if (result.patOk) ...[
            const SizedBox(height: 12),
            Text(
              'No repos linked yet. Edit a project to add a GitHub repo.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          if (!result.patOk) ...[
            const SizedBox(height: 12),
            Text(
              'Make sure the token has the "repo" scope and matches this account.',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _ResultRow extends StatelessWidget {
  final bool ok;
  final String label;
  const _ResultRow({required this.ok, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            ok ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 18,
            color: ok ? Colors.green : theme.colorScheme.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _SupabaseAccountTile extends ConsumerStatefulWidget {
  const _SupabaseAccountTile();

  @override
  ConsumerState<_SupabaseAccountTile> createState() =>
      _SupabaseAccountTileState();
}

class _SupabaseAccountTileState extends ConsumerState<_SupabaseAccountTile> {
  bool _loading = false;

  Future<void> _signIn() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.osobol.code_ledger://login-callback',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign in failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signOut() async {
    setState(() => _loading = true);
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sign out failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authProvider).value;
    final email = session?.user.email;

    if (email != null) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.cloud_done_outlined),
        title: Text(email),
        subtitle: const Text('Syncing enabled'),
        trailing: _loading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(
                onPressed: _signOut,
                child: const Text('Sign out'),
              ),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.cloud_off_outlined),
      title: const Text('Not signed in'),
      subtitle: const Text('Sign in with Google to enable cloud sync'),
      trailing: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(
              onPressed: _signIn,
              child: const Text('Sign in'),
            ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final String number;
  final String text;
  const _HowItWorksStep({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              number,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
