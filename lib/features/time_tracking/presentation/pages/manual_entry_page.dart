import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/tag_utils.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../../../../core/database/daos/time_entry_dao.dart';
import '../providers/time_entry_providers.dart';

class ManualEntryPage extends ConsumerStatefulWidget {
  const ManualEntryPage({super.key});

  @override
  ConsumerState<ManualEntryPage> createState() => _ManualEntryPageState();
}

class _ManualEntryPageState extends ConsumerState<ManualEntryPage> {
  final _descriptionCtrl = TextEditingController();
  final _issueRefCtrl = TextEditingController();
  final _repoCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  Client? _selectedClient;
  Project? _selectedProject;
  DateTime _date = DateTime.now();
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  bool _saving = false;

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _issueRefCtrl.dispose();
    _repoCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  DateTime _buildDateTime(DateTime date, TimeOfDay time) {
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String? _trimOrNull(String text) {
    final trimmed = text.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) setState(() => _endTime = picked);
  }

  Future<void> _save() async {
    if (_selectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a client')),
      );
      return;
    }

    final start = _buildDateTime(_date, _startTime);
    final end = _buildDateTime(_date, _endTime);

    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref.read(timerNotifierProvider.notifier).addManualEntry(
            clientId: _selectedClient!.id,
            projectId: _selectedProject?.id,
            startTime: start,
            endTime: end,
            description: _trimOrNull(_descriptionCtrl.text),
            issueReference: _trimOrNull(_issueRefCtrl.text),
            repository: _trimOrNull(_repoCtrl.text),
            tags: serializeTags(_tagsCtrl.text),
          );
      ref.invalidate(allTagsProvider);
      if (mounted) context.pop();
    } on OverlappingTimeEntryException catch (e) {
      if (mounted) {
        final timeFmt = DateFormat.jm();
        final overlap = e.existing;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Overlaps with existing entry: '
              '${timeFmt.format(overlap.startTime)} – '
              '${timeFmt.format(overlap.endTime!)}',
            ),
            duration: const Duration(seconds: 4),
          ),
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

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(activeClientsProvider);
    final dateFmt = DateFormat.yMMMEd();
    final duration = _buildDateTime(_date, _endTime)
        .difference(_buildDateTime(_date, _startTime));

    return Scaffold(
      appBar: AppBar(title: const Text('Manual Entry')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Client selector
          clientsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => Text('Error: $e'),
            data: (clients) {
              if (clients.isEmpty) {
                return const Text('No clients. Add one first.');
              }
              return DropdownButtonFormField<Client>(
                decoration:
                    const InputDecoration(labelText: 'Client *'),
                items: clients
                    .map((c) => DropdownMenuItem(
                        value: c, child: Text(c.name)))
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

          // Project selector
          if (_selectedClient != null)
            Consumer(builder: (context, ref, _) {
              final projectsAsync = ref
                  .watch(projectsForClientProvider(_selectedClient!.id));
              return projectsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (projects) {
                  if (projects.isEmpty) return const SizedBox.shrink();
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

          const SizedBox(height: 16),
          // Date picker
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_today),
            title: Text(dateFmt.format(_date)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickDate,
          ),

          // Time pickers
          Row(
            children: [
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.login),
                  title: Text(_startTime.format(context)),
                  subtitle: const Text('Start'),
                  onTap: _pickStartTime,
                ),
              ),
              Expanded(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: Text(_endTime.format(context)),
                  subtitle: const Text('End'),
                  onTap: _pickEndTime,
                ),
              ),
            ],
          ),
          if (duration.inMinutes > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Duration: ${duration.inHours}h ${duration.inMinutes % 60}m',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),

          const SizedBox(height: 8),
          TextFormField(
            controller: _descriptionCtrl,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'What did you work on?',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _repoCtrl,
            decoration: const InputDecoration(
              labelText: 'Repository',
              hintText: 'e.g. org/repo',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _issueRefCtrl,
            decoration: const InputDecoration(
              labelText: 'Issue Reference',
              hintText: 'e.g. org/repo#42',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            ),
            minLines: 1,
            maxLines: 6,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _tagsCtrl,
            decoration: const InputDecoration(
              labelText: 'Tags (comma separated)',
              hintText: 'e.g. bugfix, frontend, review',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Add Entry'),
          ),
        ],
      ),
    );
  }
}
