import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/app_version_provider.dart';
import '../../../../core/providers/theme_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static IconData _themeIcon(ThemeMode mode) => switch (mode) {
        ThemeMode.system => Icons.brightness_auto,
        ThemeMode.light => Icons.light_mode,
        ThemeMode.dark => Icons.dark_mode,
      };

  static String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System',
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode =
        ref.watch(themeModeProvider).value ?? ThemeMode.system;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // --- Navigation section ---
          _SectionHeader(title: 'General'),
          _SettingsTile(
            icon: Icons.person_outline,
            title: 'Business Profile',
            subtitle: 'Company info, payment details, defaults',
            onTap: () => context.push('/profile'),
          ),
          _SettingsTile(
            icon: Icons.palette_outlined,
            title: 'Invoice Templates',
            subtitle: 'Customize invoice appearance',
            onTap: () => context.push('/settings/templates'),
          ),
          _SettingsTile(
            icon: Icons.view_list_outlined,
            title: 'Entry Layout',
            subtitle: 'Choose which fields appear and in what order',
            onTap: () => context.push('/settings/entry-layout'),
          ),
          _SettingsTile(
            icon: Icons.people_outline,
            title: 'Clients',
            subtitle: 'Manage clients & projects',
            onTap: () => context.push('/clients'),
          ),
          _SettingsTile(
            icon: Icons.summarize_outlined,
            title: 'Reports',
            subtitle: 'Work reports & summaries',
            onTap: () => context.push('/reports'),
          ),
          _SettingsTile(
            icon: Icons.cloud_outlined,
            title: 'Backup & Restore',
            subtitle: 'Encrypted local & Drive backups',
            onTap: () => context.push('/backup'),
          ),
          const Divider(height: 1),

          // --- Accounts section ---
          _SectionHeader(title: 'Accounts'),
          _SettingsTile(
            icon: Icons.code,
            title: 'GitHub',
            subtitle: 'Link GitHub to auto-fill issue references',
            onTap: () => context.push('/settings/accounts'),
          ),
          const Divider(height: 1),

          // --- Appearance section ---
          _SectionHeader(title: 'Appearance'),
          ListTile(
            leading: Icon(_themeIcon(themeMode),
                color: theme.colorScheme.primary),
            title: const Text('Theme'),
            subtitle: Text(_themeLabel(themeMode)),
            trailing: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode, size: 18),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode, size: 18),
                ),
              ],
              selected: {themeMode},
              onSelectionChanged: (modes) {
                ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(modes.first);
              },
              showSelectedIcon: false,
              style: ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const Divider(height: 1),

          // --- About section ---
          _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('CodeLedger'),
            subtitle: Text(
              ref.watch(appVersionProvider).value ?? '...',
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(title),
      subtitle: Text(subtitle,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right,
          size: 20, color: theme.colorScheme.outline),
      onTap: onTap,
    );
  }
}
