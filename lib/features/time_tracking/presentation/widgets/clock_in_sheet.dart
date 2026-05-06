import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/tag_utils.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../providers/time_entry_providers.dart';

class ClockInSheet extends ConsumerStatefulWidget {
  const ClockInSheet({super.key});

  /// Show as modal bottom sheet, returns true if timer started.
  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ClockInSheet(),
    );
  }

  @override
  ConsumerState<ClockInSheet> createState() => _ClockInSheetState();
}

class _ClockInSheetState extends ConsumerState<ClockInSheet> {
  final _descriptionCtrl = TextEditingController();
  final _issueRefCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  Client? _selectedClient;
  Project? _selectedProject;
  bool _saving = false;
  bool _showMore = false;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _issueRefCtrl.dispose();
    _repoCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  String? _trimOrNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _clockIn() async {
    if (_selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a client')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(timerNotifierProvider.notifier).clockIn(
            clientId: _selectedClient!.id,
            projectId: _selectedProject?.id,
            description: _trimOrNull(_descriptionCtrl.text),
            issueReference: _trimOrNull(_issueRefCtrl.text),
            repository: _trimOrNull(_repoCtrl.text),
            tags: serializeTags(_tagsCtrl.text),
          );
      ref.invalidate(allTagsProvider);
      if (mounted) Navigator.pop(context, true);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clientsAsync = ref.watch(activeClientsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      maxChildSize: 0.85,
      minChildSize: 0.3,
      expand: false,
      builder: (context, scrollController) {
        return SingleChildScrollView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: Spacing.md,
            right: Spacing.md,
            bottom: MediaQuery.of(context).viewInsets.bottom + Spacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: Spacing.md),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Text(
                'Start Timer',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: Spacing.md),

              // Client dropdown
              clientsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (clients) {
                  if (clients.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(Spacing.md),
                        child: Text('No clients yet. Add one first.',
                            style: theme.textTheme.bodyMedium),
                      ),
                    );
                  }
                  return DropdownButtonFormField<Client>(
                    decoration:
                        const InputDecoration(labelText: 'Client *'),
                    items: clients
                        .map((c) => DropdownMenuItem(
                              value: c,
                              child: Text(c.name),
                            ))
                        .toList(),
                    onChanged: (c) {
                      setState(() {
                        _selectedClient = c;
                        _selectedProject = null;
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: Spacing.sm),

              // Project dropdown
              if (_selectedClient != null)
                Consumer(builder: (context, ref, _) {
                  final projectsAsync = ref.watch(
                      projectsForClientProvider(_selectedClient!.id));
                  return projectsAsync.when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text('Error: $e'),
                    data: (projects) {
                      if (projects.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: Spacing.sm),
                        child: DropdownButtonFormField<Project?>(
                          decoration: const InputDecoration(
                              labelText: 'Project (optional)'),
                          items: [
                            const DropdownMenuItem(
                                value: null,
                                child: Text('No project')),
                            ...projects.map((p) => DropdownMenuItem(
                                  value: p,
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Color(p.color),
                                        radius: 8,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(p.name),
                                    ],
                                  ),
                                )),
                          ],
                          onChanged: (p) =>
                              setState(() => _selectedProject = p),
                        ),
                      );
                    },
                  );
                }),

              // Description
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description (optional)',
                  hintText: 'What are you working on?',
                ),
              ),
              const SizedBox(height: Spacing.sm),

              // More options
              InkWell(
                onTap: () => setState(() => _showMore = !_showMore),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: Spacing.sm),
                  child: Row(
                    children: [
                      Icon(
                        _showMore
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'More options',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showMore) ...[
                TextFormField(
                  controller: _repoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Repository',
                    hintText: 'e.g. org/repo',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                TextFormField(
                  controller: _issueRefCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Issue Reference',
                    hintText: 'e.g. org/repo#42',
                  ),
                ),
                const SizedBox(height: Spacing.sm),
                TextFormField(
                  controller: _tagsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tags (comma separated)',
                    hintText: 'e.g. bugfix, frontend',
                  ),
                ),
              ],
              const SizedBox(height: Spacing.lg),

              // Start Timer button
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _clockIn,
                  icon: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : const Icon(Icons.play_arrow),
                  label: const Text('Start Timer'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
