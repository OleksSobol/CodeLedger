import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/tag_utils.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../providers/time_entry_providers.dart';

class ClockInPage extends ConsumerStatefulWidget {
  const ClockInPage({super.key});

  @override
  ConsumerState<ClockInPage> createState() => _ClockInPageState();
}

class _ClockInPageState extends ConsumerState<ClockInPage> {
  final _descriptionCtrl = TextEditingController();
  final _issueRefCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  Client? _selectedClient;
  Project? _selectedProject;
  bool _saving = false;

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
      if (mounted) context.pop();
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
    final clientsAsync = ref.watch(activeClientsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Clock In')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Client selector
          clientsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error loading clients: $e'),
            data: (clients) {
              if (clients.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No clients yet. Add one first.',
                        style: Theme.of(context).textTheme.bodyMedium),
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
          const SizedBox(height: 12),

          // Project selector (filtered by client)
          if (_selectedClient != null)
            Consumer(builder: (context, ref, _) {
              final projectsAsync = ref
                  .watch(projectsForClientProvider(_selectedClient!.id));
              return projectsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (projects) {
                  if (projects.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return DropdownButtonFormField<Project?>(
                    decoration: const InputDecoration(
                        labelText: 'Project (optional)'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('No project')),
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
                  );
                },
              );
            }),
          const SizedBox(height: 12),

          TextFormField(
            controller: _descriptionCtrl,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              hintText: 'What are you working on?',
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _repoCtrl,
            decoration: const InputDecoration(
              labelText: 'Repository (optional)',
              hintText: 'e.g. org/repo',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _issueRefCtrl,
            decoration: const InputDecoration(
              labelText: 'Issue Reference (optional)',
              hintText: 'e.g. org/repo#42',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: 'Tags (optional)',
              hintText: 'e.g. bugfix, frontend',
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _clockIn,
            icon: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: const Text('Start Timer'),
          ),
        ],
      ),
    );
  }
}
