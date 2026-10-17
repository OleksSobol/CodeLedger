import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/time_entry_dao.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../../core/utils/tag_utils.dart';
import '../providers/time_entry_providers.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../../domain/manual_entry_mode.dart';

class EditTimeEntryPage extends ConsumerStatefulWidget {
  final TimeEntry entry;

  const EditTimeEntryPage({super.key, required this.entry});

  @override
  ConsumerState<EditTimeEntryPage> createState() => _EditTimeEntryPageState();
}

class _EditTimeEntryPageState extends ConsumerState<EditTimeEntryPage> {
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _issueRefCtrl;
  late final TextEditingController _repoCtrl;
  late final TextEditingController _tagsCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _hoursCtrl;
  late final TextEditingController _minutesCtrl;
  late ManualEntryMode _entryMode;
  late DateTime _date;
  late DateTime _endDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String? _selectedProjectId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _descriptionCtrl = TextEditingController(text: e.description ?? '');
    _issueRefCtrl = TextEditingController(text: e.issueReference ?? '');
    _repoCtrl = TextEditingController(text: e.repository ?? '');
    _tagsCtrl = TextEditingController(text: tagsToDisplay(e.tags));
    _rateCtrl = TextEditingController(
      text: e.hourlyRateSnapshot.toStringAsFixed(2),
    );
    _entryMode =
        e.isManual ? ManualEntryMode.duration : ManualEntryMode.exactTime;
    final totalMins = e.durationMinutes ??
        (e.endTime != null ? e.endTime!.difference(e.startTime).inMinutes : 0);
    _hoursCtrl = TextEditingController(
      text: (totalMins / 60.0).toStringAsFixed(totalMins % 60 == 0 ? 0 : 2),
    );
    _minutesCtrl = TextEditingController(
      text: (totalMins % 60).toString(),
    );
    _date = DateTime(e.startTime.year, e.startTime.month, e.startTime.day);
    _startTime = TimeOfDay.fromDateTime(e.startTime);
    _endTime = e.endTime != null
        ? TimeOfDay.fromDateTime(e.endTime!)
        : TimeOfDay.fromDateTime(DateTime.now());
    _endDate = e.endTime != null
        ? DateTime(e.endTime!.year, e.endTime!.month, e.endTime!.day)
        : _date;
    _selectedProjectId = e.projectId;
  }

  @override
  void dispose() {
    _descriptionCtrl.dispose();
    _issueRefCtrl.dispose();
    _repoCtrl.dispose();
    _tagsCtrl.dispose();
    _rateCtrl.dispose();
    _hoursCtrl.dispose();
    _minutesCtrl.dispose();
    super.dispose();
  }

  int get _parsedDurationMinutes {
    final hText = _hoursCtrl.text.trim();
    final mText = _minutesCtrl.text.trim();
    final hours = double.tryParse(hText) ?? 0.0;
    final minutes = int.tryParse(mText) ?? 0;
    final total = (hours * 60).round() + minutes;
    return total > 0 ? total : 0;
  }

  void _setDuration(double hours, int minutes) {
    setState(() {
      _hoursCtrl.text = hours == hours.truncateToDouble()
          ? hours.toInt().toString()
          : hours.toString();
      _minutesCtrl.text = minutes.toString();
    });
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
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        final diff = picked.difference(_date);
        _endDate = _endDate.add(diff);
        _date = picked;
      });
    }
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
    setState(() => _saving = true);

    final isRunning = widget.entry.endTime == null;

    final tagsJson = serializeTags(_tagsCtrl.text);
    final parsedRate = double.tryParse(_rateCtrl.text);
    final notifier = ref.read(timerNotifierProvider.notifier);

    try {
      if (isRunning) {
        // Only update metadata — never write end time on a running timer
        await notifier.updateEntryMeta(
          entryId: widget.entry.id,
          projectId: _selectedProjectId,
          clearProject: _selectedProjectId == null,
          description: _trimOrNull(_descriptionCtrl.text),
          issueReference: _trimOrNull(_issueRefCtrl.text),
          repository: _trimOrNull(_repoCtrl.text),
          tags: tagsJson,
          hourlyRateSnapshot: parsedRate,
        );
      } else {
        DateTime start;
        DateTime end;

        if (_entryMode == ManualEntryMode.duration) {
          final mins = _parsedDurationMinutes;
          if (mins <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please enter a duration greater than 0 minutes'),
              ),
            );
            setState(() => _saving = false);
            return;
          }
          start = _buildDateTime(_date, _startTime);
          end = start.add(Duration(minutes: mins));
        } else {
          start = _buildDateTime(_date, _startTime);
          end = _buildDateTime(_endDate, _endTime);

          if (!end.isAfter(start)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('End time must be after start time')),
            );
            setState(() => _saving = false);
            return;
          }
        }

        await notifier.updateEntryTimes(
          entryId: widget.entry.id,
          startTime: start,
          endTime: end,
          projectId: _selectedProjectId,
          clearProject: _selectedProjectId == null,
          description: _trimOrNull(_descriptionCtrl.text),
          issueReference: _trimOrNull(_issueRefCtrl.text),
          repository: _trimOrNull(_repoCtrl.text),
          tags: tagsJson,
          hourlyRateSnapshot: parsedRate,
        );
      }
      ref.invalidate(allTagsProvider);
      if (mounted) context.pop(true);
    } on OverlappingTimeEntryException catch (e) {
      if (mounted) {
        final overlapping = e.existing;
        final timeFmt = DateFormat.jm();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Overlaps with entry: '
              '${timeFmt.format(overlapping.startTime)} - '
              '${timeFmt.format(overlapping.endTime!)}',
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat.yMMMEd();
    final duration = _buildDateTime(
      _endDate,
      _endTime,
    ).difference(_buildDateTime(_date, _startTime));
    final isOvernight = _endDate != _date;
    final isCompleted = widget.entry.endTime != null;
    final projectsAsync = ref.watch(
      projectsForClientProvider(widget.entry.clientId),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Time Entry'),
        actions: [
          if (!widget.entry.isInvoiced)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final nav = Navigator.of(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Entry'),
                    content: const Text(
                      'Are you sure you want to delete this entry?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await ref
                      .read(timerNotifierProvider.notifier)
                      .deleteEntry(widget.entry.id);
                  ref.invalidate(allTagsProvider);
                  if (mounted) nav.pop(true);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Invoiced warning
          if (widget.entry.isInvoiced) ...[
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This entry is invoiced. Only description and metadata can be edited.',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Time and Duration controls — only for completed entries
          if (isCompleted) ...[
            if (!widget.entry.isInvoiced) ...[
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<ManualEntryMode>(
                  segments: const [
                    ButtonSegment(
                      value: ManualEntryMode.duration,
                      label: Text('Duration'),
                      icon: Icon(Icons.timer_outlined),
                    ),
                    ButtonSegment(
                      value: ManualEntryMode.exactTime,
                      label: Text('Exact Time'),
                      icon: Icon(Icons.schedule),
                    ),
                  ],
                  selected: {_entryMode},
                  onSelectionChanged: (set) {
                    setState(() {
                      _entryMode = set.first;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Date picker
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: Text(dateFmt.format(_date)),
              trailing: const Icon(Icons.chevron_right),
              onTap: widget.entry.isInvoiced ? null : _pickDate,
            ),

            if (_entryMode == ManualEntryMode.duration &&
                !widget.entry.isInvoiced) ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _hoursCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Hours *',
                        hintText: 'e.g. 4 or 4.5',
                        suffixText: 'hrs',
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _minutesCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Minutes',
                        hintText: 'e.g. 30',
                        suffixText: 'min',
                        isDense: true,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    Text(
                      'Presets:',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(width: 8),
                    ActionChip(
                      label: const Text('30m'),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _setDuration(0, 30),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('1h'),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _setDuration(1, 0),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('2h'),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _setDuration(2, 0),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('4h'),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _setDuration(4, 0),
                    ),
                    const SizedBox(width: 6),
                    ActionChip(
                      label: const Text('8h'),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _setDuration(8, 0),
                    ),
                  ],
                ),
              ),
              if (_parsedDurationMinutes > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Text(
                    'Total Duration: ${formatDuration(_parsedDurationMinutes)} (${(_parsedDurationMinutes / 60.0).toStringAsFixed(2)} hrs)',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.login),
                      title: Text(_startTime.format(context)),
                      subtitle: const Text('Start'),
                      onTap: widget.entry.isInvoiced ? null : _pickStartTime,
                    ),
                  ),
                  Expanded(
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.logout),
                      title: Text(_endTime.format(context)),
                      subtitle: Text(
                        isOvernight
                            ? '${DateFormat('MMM d').format(_endDate)} · End'
                            : 'End',
                      ),
                      onTap: widget.entry.isInvoiced ? null : _pickEndTime,
                    ),
                  ),
                ],
              ),
              if (duration.inMinutes > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Duration: ${formatDuration(duration.inMinutes)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ],

          const SizedBox(height: 8),
          projectsAsync.when(
            data: (projects) {
              if (projects.isEmpty) return const SizedBox.shrink();
              return DropdownButtonFormField<String?>(
                // ignore: deprecated_member_use
                value: projects.any((p) => p.id == _selectedProjectId)
                    ? _selectedProjectId
                    : null,
                decoration: const InputDecoration(labelText: 'Project'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None'),
                  ),
                  ...projects.map(
                    (p) => DropdownMenuItem<String?>(
                      value: p.id,
                      child: Text(p.name),
                    ),
                  ),
                ],
                onChanged: widget.entry.isInvoiced
                    ? null
                    : (v) => setState(() => _selectedProjectId = v),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _rateCtrl,
            decoration: const InputDecoration(
              labelText: 'Hourly Rate (\$)',
              hintText: 'e.g. 30.00',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 18,
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            enabled: !widget.entry.isInvoiced,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _descriptionCtrl,
            decoration: const InputDecoration(
              labelText: 'Description',
              hintText: 'What did you work on?',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 18,
              ),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _repoCtrl,
            decoration: const InputDecoration(
              labelText: 'Repository',
              hintText: 'e.g. org/repo',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 18,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _issueRefCtrl,
            decoration: const InputDecoration(
              labelText: 'Issue Reference',
              hintText: 'e.g. org/repo#42',
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 18,
              ),
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
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 18,
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}
