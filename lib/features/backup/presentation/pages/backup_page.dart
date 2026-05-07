import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../shared/widgets/app_page_body.dart';
import '../../../../shared/widgets/app_page_scaffold.dart';
import '../../../../shared/widgets/app_section_card.dart';
import '../../../../shared/widgets/confirm_destructive.dart';
import '../../../../shared/widgets/passphrase_bottom_sheet.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../application/drive_backup_service.dart';
import '../providers/backup_providers.dart';

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  @override
  void initState() {
    super.initState();
    _trySilentSignIn();
  }

  Future<void> _trySilentSignIn() async {
    final drive = ref.read(driveBackupServiceProvider);
    final email = await drive.trySilentSignIn();
    if (email != null && mounted) {
      ref.read(driveSignedInProvider.notifier).set(true);
      ref.read(driveEmailProvider.notifier).set(email);
    }
  }

  // -- Helpers --

  void _setState(BackupUiState state) {
    if (!mounted) return;
    ref.read(backupUiStateProvider.notifier).set(state);
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // -- Passphrase resolution --

  /// Returns the stored passphrase if set, otherwise prompts the user.
  Future<String?> _resolvePassphrase({bool requireConfirmation = false}) async {
    final stored = await ref.read(backupPassphraseProvider.future);
    if (stored != null && stored.isNotEmpty) return stored;
    if (!mounted) return null;
    return askPassphrase(context, requireConfirmation: requireConfirmation);
  }

  // -- Actions --

  Future<void> _createLocalBackup() async {
    final passphrase = await _resolvePassphrase(requireConfirmation: true);
    if (passphrase == null) return;

    _setState(const BackupWorking('Encrypting...'));
    try {
      final backup = ref.read(backupServiceProvider);
      final file = await backup.createBackup(passphrase);

      _setState(const BackupIdle());
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)]),
      );
      _showSnack('Backup created');
    } catch (e) {
      _setState(const BackupIdle());
      _showSnack('Backup failed: $e');
    }
  }

  Future<void> _restoreLocalBackup() async {
    // Pick file
    final result = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;

    final filePath = result.files.single.path;
    if (filePath == null) return;

    // Confirm destructive
    if (!mounted) return;
    final confirmed = await confirmDestructive(
      context,
      title: 'Restore Backup?',
      message:
          "This will replace all your current data with this backup. This can't be undone.",
      confirmLabel: 'Restore',
    );
    if (!confirmed) return;

    // Passphrase
    if (!mounted) return;
    final passphrase = await _resolvePassphrase();
    if (passphrase == null) return;

    _setState(const BackupWorking('Decrypting...'));
    try {
      final backup = ref.read(backupServiceProvider);
      await backup.restoreBackup(File(filePath), passphrase);

      _setState(const BackupIdle());
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Complete'),
            content: const Text(
                'Restore complete. Restart the app to load your data.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _setState(const BackupIdle());
      _showSnack('Restore failed: $e');
    }
  }

  Future<void> _signInToDrive() async {
    _setState(const BackupWorking('Signing in to Google...'));
    try {
      final drive = ref.read(driveBackupServiceProvider);
      final email = await drive.signIn();
      if (email != null) {
        ref.read(driveSignedInProvider.notifier).set(true);
        ref.read(driveEmailProvider.notifier).set(email);
        ref.invalidate(driveBackupsProvider);
        _setState(const BackupIdle());
        _showSnack('Signed in as $email');
      } else {
        _setState(const BackupIdle());
        _showSnack('Sign-in cancelled');
      }
    } catch (e) {
      _setState(const BackupIdle());
      final msg = e.toString();
      if (msg.contains('10') ||
          msg.contains('DEVELOPER_ERROR') ||
          msg.contains('PlatformException')) {
        _showSnack(
          'Google Sign-In not configured. Add google-services.json '
          'to android/app/ from Google Cloud Console.',
        );
      } else {
        _showSnack('Sign-in failed: $msg');
      }
    }
  }

  Future<void> _signOut() async {
    final drive = ref.read(driveBackupServiceProvider);
    await drive.signOut();
    ref.read(driveSignedInProvider.notifier).set(false);
    ref.read(driveEmailProvider.notifier).set(null);
    _setState(const BackupIdle());
  }

  Future<void> _backupToDrive() async {
    final passphrase = await _resolvePassphrase(requireConfirmation: true);
    if (passphrase == null) return;

    _setState(const BackupWorking('Encrypting...'));
    try {
      final backup = ref.read(backupServiceProvider);
      final file = await backup.createBackup(passphrase);

      _setState(const BackupWorking('Uploading to Drive...'));
      final drive = ref.read(driveBackupServiceProvider);
      await drive.uploadBackup(file);
      await file.delete();

      ref.invalidate(driveBackupsProvider);
      _setState(const BackupIdle());
      _showSnack('Backup uploaded');
    } catch (e) {
      _setState(const BackupIdle());
      _showSnack('Drive backup failed: $e');
    }
  }

  Future<void> _restoreFromDrive() async {
    final drive = ref.read(driveBackupServiceProvider);

    _setState(const BackupWorking('Loading backups...'));
    final backups = await drive.listBackups();
    _setState(const BackupIdle());

    if (backups.isEmpty) {
      _showSnack('No backups found on Google Drive');
      return;
    }

    if (!mounted) return;
    final selected = await showModalBottomSheet<DriveBackupEntry>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _BackupPickerSheet(backups: backups),
    );

    if (selected == null) return;
    await _restoreFromDriveEntry(selected);
  }

  Future<void> _restoreFromDriveEntry(DriveBackupEntry entry) async {
    if (!mounted) return;
    final confirmed = await confirmDestructive(
      context,
      title: 'Restore Backup?',
      message:
          "This will replace all your current data with this backup. This can't be undone.",
      confirmLabel: 'Restore',
    );
    if (!confirmed) return;

    if (!mounted) return;
    final passphrase = await _resolvePassphrase();
    if (passphrase == null) return;

    _setState(const BackupWorking('Downloading...'));
    try {
      final drive = ref.read(driveBackupServiceProvider);
      final file = await drive.downloadBackup(entry.id, entry.name);

      _setState(const BackupWorking('Decrypting...'));
      final backup = ref.read(backupServiceProvider);
      await backup.restoreBackup(file, passphrase);
      await file.delete();

      _setState(const BackupIdle());
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore Complete'),
            content: const Text(
                'Restore complete. Restart the app to load your data.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _setState(const BackupIdle());
      _showSnack('Restore failed: $e');
    }
  }

  Future<void> _eraseAllData() async {
    if (!mounted) return;
    final confirmed1 = await confirmDestructive(
      context,
      title: 'Erase All Data?',
      message:
          'This will permanently delete all time entries, invoices, clients, and projects. Your backup passphrase will be kept. This cannot be undone.',
      confirmLabel: 'Erase',
    );
    if (!confirmed1) return;

    if (!mounted) return;
    final confirmed2 = await confirmDestructive(
      context,
      title: 'Are you absolutely sure?',
      message: 'All your data will be gone. There is no undo.',
      confirmLabel: 'Yes, erase everything',
    );
    if (!confirmed2) return;

    _setState(const BackupWorking('Erasing data...'));
    try {
      final db = ref.read(databaseProvider);
      await db.eraseAllData();
      _setState(const BackupIdle());
      if (mounted) {
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Data Erased'),
            content: const Text(
                'All data has been erased. Restart the app to continue.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _setState(const BackupIdle());
      _showSnack('Erase failed: $e');
    }
  }

  Future<void> _deleteDriveBackup(DriveBackupEntry entry) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete Backup?',
      message: 'Delete "${entry.name}" from Google Drive?',
    );
    if (!confirmed) return;

    _setState(const BackupWorking('Deleting...'));
    try {
      final drive = ref.read(driveBackupServiceProvider);
      await drive.deleteBackup(entry.id);
      ref.invalidate(driveBackupsProvider);
      _setState(const BackupIdle());
      _showSnack('Backup deleted');
    } catch (e) {
      _setState(const BackupIdle());
      _showSnack('Delete failed: $e');
    }
  }

  // -- Build --

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(backupUiStateProvider);
    final isSignedIn = ref.watch(driveSignedInProvider);
    final isWorking = uiState is BackupWorking;

    return AppPageScaffold(
      title: 'Backup & Restore',
      body: AppPageBody(
        children: [
          // -- Local Section --
          _LocalBackupSection(
            isWorking: isWorking,
            onCreateBackup: _createLocalBackup,
            onRestoreBackup: _restoreLocalBackup,
          ),
          const SizedBox(height: Spacing.lg),

          // -- Google Drive Section --
          _GoogleDriveSection(
            isSignedIn: isSignedIn,
            isWorking: isWorking,
            email: ref.watch(driveEmailProvider),
            uiState: uiState,
            onSignIn: _signInToDrive,
            onSignOut: _signOut,
            onBackup: _backupToDrive,
            onRestore: _restoreFromDrive,
          ),

          // -- Drive Backups List --
          if (isSignedIn) ...[
            const SizedBox(height: Spacing.lg),
            _DriveBackupsList(
              isWorking: isWorking,
              onRestore: _restoreFromDriveEntry,
              onDelete: _deleteDriveBackup,
            ),
          ],

          // -- Danger Zone --
          const SizedBox(height: Spacing.lg),
          _DangerZoneSection(
            isWorking: isWorking,
            onErase: _eraseAllData,
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Section Widgets
// ============================================================

class _LocalBackupSection extends StatelessWidget {
  final bool isWorking;
  final VoidCallback onCreateBackup;
  final VoidCallback onRestoreBackup;

  const _LocalBackupSection({
    required this.isWorking,
    required this.onCreateBackup,
    required this.onRestoreBackup,
  });

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: 'Local',
      children: [
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.tonalIcon(
                onPressed: isWorking ? null : onCreateBackup,
                icon: const Icon(Icons.share_outlined),
                label: const Text('Create & Share Backup'),
              ),
              const SizedBox(height: Spacing.sm),
              OutlinedButton.icon(
                onPressed: isWorking ? null : onRestoreBackup,
                icon: const Icon(Icons.file_open_outlined),
                label: const Text('Restore from File'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GoogleDriveSection extends StatelessWidget {
  final bool isSignedIn;
  final bool isWorking;
  final String? email;
  final BackupUiState uiState;
  final VoidCallback onSignIn;
  final VoidCallback onSignOut;
  final VoidCallback onBackup;
  final VoidCallback onRestore;

  const _GoogleDriveSection({
    required this.isSignedIn,
    required this.isWorking,
    required this.email,
    required this.uiState,
    required this.onSignIn,
    required this.onSignOut,
    required this.onBackup,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppSectionCard(
      title: 'Google Drive',
      trailing: isSignedIn
          ? Chip(
              label: const Text('Connected'),
              labelStyle: theme.textTheme.labelSmall,
              visualDensity: VisualDensity.compact,
            )
          : null,
      children: [
        if (!isSignedIn) _buildSignInPrompt(theme) else _buildSignedIn(theme),
      ],
    );
  }

  Widget _buildSignInPrompt(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.lg),
      child: Column(
        children: [
          Icon(
            Icons.cloud_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: Spacing.md),
          Text(
            'Back up your data securely to Google Drive',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Spacing.md),
          FilledButton.icon(
            onPressed: isWorking ? null : onSignIn,
            icon: isWorking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: Text(isWorking ? 'Signing in...' : 'Sign in with Google'),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedIn(ThemeData theme) {
    final workingMessage =
        uiState is BackupWorking ? (uiState as BackupWorking).message : null;

    return Padding(
      padding: const EdgeInsets.all(Spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Account row
          Row(
            children: [
              Icon(Icons.account_circle,
                  color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: Spacing.sm),
              Expanded(
                child: Text(
                  email ?? 'Signed in',
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: isWorking ? null : onSignOut,
                child: const Text('Sign out'),
              ),
            ],
          ),
          const Divider(height: Spacing.lg),

          // Backup button (primary action)
          FilledButton.icon(
            onPressed: isWorking ? null : onBackup,
            icon: isWorking && workingMessage != null
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(workingMessage ?? 'Backup to Drive'),
          ),
          const SizedBox(height: Spacing.sm),

          // Restore button
          OutlinedButton.icon(
            onPressed: isWorking ? null : onRestore,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Restore from Drive'),
          ),
        ],
      ),
    );
  }
}

class _DriveBackupsList extends ConsumerWidget {
  final bool isWorking;
  final void Function(DriveBackupEntry) onRestore;
  final void Function(DriveBackupEntry) onDelete;

  const _DriveBackupsList({
    required this.isWorking,
    required this.onRestore,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupsAsync = ref.watch(driveBackupsProvider);
    final theme = Theme.of(context);

    return AppSectionCard(
      title: 'Your Backups',
      trailing: IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Refresh backups',
        onPressed: isWorking
            ? null
            : () => ref.invalidate(driveBackupsProvider),
      ),
      children: [
        backupsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Spacing.lg),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(Spacing.md),
            child: Text('Error loading backups: $e',
                style: TextStyle(color: theme.colorScheme.error)),
          ),
          data: (backups) {
            if (backups.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(Spacing.lg),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_outlined,
                        size: 48, color: theme.colorScheme.outline),
                    const SizedBox(height: Spacing.sm),
                    Text('No backups yet',
                        style: theme.textTheme.bodyMedium),
                  ],
                ),
              );
            }

            return Column(
              children: backups.map((b) {
                final dateStr = b.createdAt != null
                    ? DateFormat.yMMMd().add_jm().format(b.createdAt!)
                    : 'Unknown date';

                return ListTile(
                  leading: Icon(Icons.lock_outline,
                      color: theme.colorScheme.onSurfaceVariant),
                  title: Text(b.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text('$dateStr - ${b.formattedSize}'),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Backup options',
                    onSelected: (value) {
                      if (value == 'restore') onRestore(b);
                      if (value == 'delete') onDelete(b);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'restore',
                        child: ListTile(
                          leading: Icon(Icons.restore),
                          title: Text('Restore'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      ],
    );
  }
}

// ============================================================
// Danger Zone Section
// ============================================================

class _DangerZoneSection extends StatelessWidget {
  final bool isWorking;
  final VoidCallback onErase;

  const _DangerZoneSection({
    required this.isWorking,
    required this.onErase,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSectionCard(
      title: 'Danger Zone',
      children: [
        Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Permanently delete all time entries, invoices, clients, '
                'and projects. Your backup passphrase is kept. '
                'This cannot be undone.',
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: Spacing.md),
              OutlinedButton.icon(
                onPressed: isWorking ? null : onErase,
                icon: Icon(Icons.delete_forever_outlined,
                    color: theme.colorScheme.error),
                label: Text(
                  'Erase All Data',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// Backup Picker Bottom Sheet
// ============================================================

class _BackupPickerSheet extends StatelessWidget {
  final List<DriveBackupEntry> backups;

  const _BackupPickerSheet({required this.backups});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
            child: Text('Select Backup',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5,
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: backups.length,
              itemBuilder: (ctx, i) {
                final b = backups[i];
                final dateStr = b.createdAt != null
                    ? DateFormat.yMMMd().add_jm().format(b.createdAt!)
                    : 'Unknown date';

                return ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(b.name, overflow: TextOverflow.ellipsis),
                  subtitle: Text('$dateStr - ${b.formattedSize}'),
                  onTap: () => Navigator.pop(ctx, b),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
