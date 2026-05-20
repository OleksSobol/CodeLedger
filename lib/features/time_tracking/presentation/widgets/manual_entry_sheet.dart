import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/tag_utils.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../../../../core/database/daos/time_entry_dao.dart';
import '../providers/time_entry_providers.dart';

class ManualEntrySheet extends ConsumerStatefulWidget {
  const ManualEntrySheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ManualEntrySheet(),
    );
  }

  @override
  ConsumerState<ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends ConsumerState<ManualEntrySheet> {
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
  bool _showMore = false;

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
      if (mounted) Navigator.pop(context, true);
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
    final theme = Theme.of(context);
    final clientsAsync = ref.watch(activeClientsProvider);
    final dateFmt = DateFormat.yMMMEd();
    final duration = _buildDateTime(_date, _endTime)
        .difference(_buildDateTime(_date, _startTime));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.9,
      minChildSize: 0.4,
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
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Text(
                'Manual Entry',
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

              // Date + Time row
              const SizedBox(height: Spacing.sm),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _pickDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: Spacing.sm),
                      Text(dateFmt.format(_date),
                          style: theme.textTheme.bodyMedium),
                      const Spacer(),
                      Icon(Icons.chevron_right,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant),
                    ],
                  ),
                ),
              ),

              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _pickStartTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: Spacing.sm),
                        child: Row(
                          children: [
                            Icon(Icons.login,
                                size: 20,
                                color:
                                    theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: Spacing.sm),
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(_startTime.format(context),
                                    style: theme.textTheme.bodyMedium),
                                Text('Start',
                                    style: theme.textTheme.labelSmall),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _pickEndTime,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: Spacing.sm),
                        child: Row(
                          children: [
                            Icon(Icons.logout,
                                size: 20,
                                color:
                                    theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: Spacing.sm),
                            Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Text(_endTime.format(context),
                                    style: theme.textTheme.bodyMedium),
                                Text('End',
                                    style: theme.textTheme.labelSmall),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (duration.inMinutes > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: Spacing.sm),
                  child: Text(
                    'Duration: ${duration.inHours}h ${duration.inMinutes % 60}m',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600),
                  ),
                ),

              // Description
              TextFormField(
                controller: _descriptionCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'What did you work on?',
                ),
                maxLines: 2,
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
                    hintText: 'e.g. bugfix, frontend, review',
                  ),
                ),
              ],
              const SizedBox(height: Spacing.lg),

              // Add Entry button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2))
                      : const Text('Add Entry'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
