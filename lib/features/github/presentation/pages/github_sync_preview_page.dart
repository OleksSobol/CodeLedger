import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/github_provider.dart';

class GitHubSyncPreviewPage extends ConsumerStatefulWidget {
  final DateTime start;
  final DateTime end;

  const GitHubSyncPreviewPage({
    super.key,
    required this.start,
    required this.end,
  });

  @override
  ConsumerState<GitHubSyncPreviewPage> createState() =>
      _GitHubSyncPreviewPageState();
}

class _GitHubSyncPreviewPageState
    extends ConsumerState<GitHubSyncPreviewPage> {
  GitHubSyncPreview? _preview;
  bool _loading = true;
  final List<SyncLog> _liveLog = [];
  final Set<int> _selected = {};
  bool _applying = false;
  final _logScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _runScan();
  }

  @override
  void dispose() {
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _runScan() async {
    final notifier = ref.read(githubSyncNotifierProvider.notifier);
    final result = await notifier.previewSync(
      widget.start,
      widget.end,
      onLog: (log) {
        if (mounted) {
          setState(() => _liveLog.add(log));
          // Auto-scroll to bottom
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_logScrollCtrl.hasClients) {
              _logScrollCtrl.animateTo(
                _logScrollCtrl.position.maxScrollExtent,
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
    );
    if (!mounted) return;
    setState(() {
      _preview = result;
      _loading = false;
      _selected.addAll(List.generate(result.matches.length, (i) => i));
    });
  }

  Future<void> _apply() async {
    final preview = _preview;
    if (preview == null || _selected.isEmpty) return;

    setState(() => _applying = true);
    final selected = _selected.map((i) => preview.matches[i]).toList();

    final count = await ref
        .read(githubSyncNotifierProvider.notifier)
        .applyMatches(selected);

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? 'Nothing to update.'
              : 'Applied $count issue ref${count == 1 ? '' : 's'} to time entries.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub Issue Sync'),
        bottom: _loading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
        actions: [
          if (!_loading && preview != null && preview.matches.isNotEmpty)
            TextButton(
              onPressed: _applying
                  ? null
                  : () {
                      setState(() {
                        if (_selected.length == preview.matches.length) {
                          _selected.clear();
                        } else {
                          _selected.addAll(List.generate(
                              preview.matches.length, (i) => i));
                        }
                      });
                    },
              child: Text(
                _selected.length == preview.matches.length
                    ? 'Deselect All'
                    : 'Select All',
              ),
            ),
        ],
      ),
      body: _loading
          ? _buildLiveLog(theme)
          : preview == null
              ? const SizedBox.shrink()
              : _buildResults(theme, preview),
      bottomNavigationBar: _buildBottom(theme),
    );
  }

  // ── Loading state: live log ──────────────────────────────────────────────

  Widget _buildLiveLog(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
          child: Text(
            'Scanning for issue references…',
            style: theme.textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Text(
            'Checking linked repos for branches and commits '
            'that match Issue-XXXX in the selected date range.',
            style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: _logScrollCtrl,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _liveLog.length,
            itemBuilder: (_, i) => _LogLine(log: _liveLog[i]),
          ),
        ),
      ],
    );
  }

  // ── Results ──────────────────────────────────────────────────────────────

  Widget _buildResults(ThemeData theme, GitHubSyncPreview preview) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        _buildLogSummary(theme, preview.logs),
        if (preview.hasError)
          _buildError(theme, preview.error!)
        else if (preview.matches.isEmpty)
          _buildEmpty(theme)
        else
          _buildMatchList(theme, preview),
      ],
    );
  }

  Widget _buildLogSummary(ThemeData theme, List<SyncLog> logs) {
    if (logs.isEmpty) return const SizedBox.shrink();

    final errors = logs.where((l) => l.level == SyncLogLevel.error).toList();
    final warns = logs.where((l) => l.level == SyncLogLevel.warning).toList();

    // Show a compact banner only when there are errors or warnings
    if (errors.isEmpty && warns.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (errors.isNotEmpty)
          _LogBanner(
            icon: Icons.error_outline,
            color: theme.colorScheme.error,
            background: theme.colorScheme.errorContainer.withValues(alpha: 0.4),
            logs: errors,
          ),
        if (warns.isNotEmpty)
          _LogBanner(
            icon: Icons.warning_amber_outlined,
            color: Colors.orange.shade700,
            background: Colors.orange.withValues(alpha: 0.1),
            logs: warns,
          ),
        const Divider(height: 1),
      ],
    );
  }

  Widget _buildError(ThemeData theme, String error) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 12),
          Text(error,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error)),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
      child: Column(
        children: [
          Icon(Icons.search_off, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            'No issue refs found for this date range.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure your branches are named Issue-XXXX and that '
            'you committed within the selected date range.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchList(ThemeData theme, GitHubSyncPreview preview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '${preview.matches.length} match${preview.matches.length == 1 ? '' : 'es'} found - select which to apply',
            style: theme.textTheme.titleSmall,
          ),
        ),
        ...preview.matches.asMap().entries.map((e) =>
            _MatchTile(
              idx: e.key,
              match: e.value,
              selected: _selected.contains(e.key),
              enabled: !_applying,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.add(e.key);
                } else {
                  _selected.remove(e.key);
                }
              }),
            )),
      ],
    );
  }

  Widget? _buildBottom(ThemeData theme) {
    if (_loading || _preview == null) return null;
    final preview = _preview!;
    if (preview.hasError || preview.matches.isEmpty) return null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: FilledButton.icon(
          onPressed: (_selected.isEmpty || _applying) ? null : _apply,
          icon: _applying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: Text(
            _selected.isEmpty
                ? 'Select entries to apply'
                : 'Apply ${_selected.length} of ${preview.matches.length}',
          ),
        ),
      ),
    );
  }
}

// ── Log line (live loading) ──────────────────────────────────────────────────

class _LogLine extends StatelessWidget {
  final SyncLog log;
  const _LogLine({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color color;
    switch (log.level) {
      case SyncLogLevel.error:
        color = theme.colorScheme.error;
      case SyncLogLevel.warning:
        color = Colors.orange.shade700;
      case SyncLogLevel.info:
        color = theme.colorScheme.onSurface;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      child: Text(
        log.message,
        style: theme.textTheme.bodySmall?.copyWith(color: color),
      ),
    );
  }
}

// ── Log banner (errors/warnings in results) ──────────────────────────────────

class _LogBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;
  final List<SyncLog> logs;
  const _LogBanner({
    required this.icon,
    required this.color,
    required this.background,
    required this.logs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: background,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: logs.map((log) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    log.message,
                    style: theme.textTheme.bodySmall?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Match tile ───────────────────────────────────────────────────────────────

class _MatchTile extends StatelessWidget {
  final int idx;
  final SyncMatch match;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  const _MatchTile({
    required this.idx,
    required this.match,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = match.entry;
    final dateFmt = DateFormat('EEE, MMM d');
    final timeFmt = DateFormat('h:mm a');
    final duration = entry.durationMinutes;
    final durationLabel = duration != null
        ? '${duration ~/ 60}h ${(duration % 60).toString().padLeft(2, '0')}m'
        : null;

    final description = entry.description ?? '';

    return CheckboxListTile(
      value: selected,
      onChanged: enabled ? onChanged : null,
      contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      title: Row(
        children: [
          _IssueChip(label: match.issueRef),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              match.projectName,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (durationLabel != null) ...[
            const SizedBox(width: 8),
            Text(
              durationLabel,
              style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Client · Date · Time
            Text(
              [
                if (match.clientName.isNotEmpty) match.clientName,
                dateFmt.format(entry.startTime),
                if (entry.endTime != null)
                  '${timeFmt.format(entry.startTime)} - ${timeFmt.format(entry.endTime!)}',
              ].join('  ·  '),
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (match.existingRef != null &&
                match.existingRef!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Appending to: ${match.existingRef}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.orange.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 2),
            Text(
              match.repo,
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _IssueChip extends StatelessWidget {
  final String label;
  const _IssueChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
