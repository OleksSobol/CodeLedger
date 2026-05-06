import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../time_tracking/presentation/providers/time_entry_providers.dart';
import '../providers/quick_actions_provider.dart';

/// Horizontal scrollable row of quick clock-in buttons.
///
/// Shows persisted quick actions + an "add" chip. Long-press to remove.
class QuickActionChips extends ConsumerWidget {
  const QuickActionChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionsAsync = ref.watch(quickActionsProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Quick Actions',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            if ((actionsAsync.value ?? []).isNotEmpty)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                tooltip: 'Edit quick actions',
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    _showEditSheet(context, ref, actionsAsync.value ?? []),
              ),
          ],
        ),
        const SizedBox(height: Spacing.xs),
        SizedBox(
          height: 40,
          child: actionsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (actions) => ListView(
              scrollDirection: Axis.horizontal,
              children: [
                ...actions.map((action) {
                  return Padding(
                    padding: const EdgeInsets.only(right: Spacing.sm),
                    child: ActionChip(
                      avatar: Icon(Icons.play_arrow,
                          size: 18, color: theme.colorScheme.primary),
                      label: Text(action.label),
                      tooltip: 'Clock in: ${action.label}',
                      side: BorderSide(
                          color: theme.colorScheme.primary
                              .withValues(alpha: 0.3)),
                      onPressed: () => _clockIn(context, ref, action),
                    ),
                  );
                }),
                // "Add" chip — outlined/secondary style to differentiate
                ActionChip(
                  avatar: Icon(Icons.add, size: 18,
                      color: theme.colorScheme.outline),
                  label: Text('Add',
                      style: TextStyle(color: theme.colorScheme.outline)),
                  tooltip: 'Add quick action',
                  side: BorderSide(
                      color: theme.colorScheme.outlineVariant),
                  onPressed: () => _showAddSheet(context, ref),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _clockIn(
      BuildContext context, WidgetRef ref, QuickAction action) async {
    try {
      await ref.read(timerNotifierProvider.notifier).clockIn(
            clientId: action.clientId,
            projectId: action.projectId,
            description: action.description,
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.read(activeClientsProvider);
    final clients = clientsAsync.value ?? [];

    if (clients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a client first')),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _AddQuickActionSheet(clients: clients),
    );
  }

  void _showEditSheet(
      BuildContext context, WidgetRef ref, List<QuickAction> actions) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _EditQuickActionsSheet(actions: actions),
    );
  }
}

/// Bottom sheet to add a new quick action.
class _AddQuickActionSheet extends ConsumerStatefulWidget {
  final List<dynamic> clients;

  const _AddQuickActionSheet({required this.clients});

  @override
  ConsumerState<_AddQuickActionSheet> createState() =>
      _AddQuickActionSheetState();
}

class _AddQuickActionSheetState extends ConsumerState<_AddQuickActionSheet> {
  int? _selectedClientId;
  final _labelController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _labelController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Spacing.lg,
        Spacing.lg,
        Spacing.lg,
        Spacing.lg + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add Quick Action',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: Spacing.md),
          DropdownButtonFormField<int>(
            decoration: const InputDecoration(
              labelText: 'Client',
              border: OutlineInputBorder(),
            ),
            items: widget.clients.map<DropdownMenuItem<int>>((c) {
              return DropdownMenuItem(
                value: c.id as int,
                child: Text(c.name as String),
              );
            }).toList(),
            onChanged: (id) {
              setState(() => _selectedClientId = id);
              if (_labelController.text.isEmpty && id != null) {
                final client =
                    widget.clients.firstWhere((c) => c.id == id);
                _labelController.text = client.name as String;
              }
            },
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: 'Button label',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.sm),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: Spacing.md),
          FilledButton(
            onPressed: _selectedClientId == null ||
                    _labelController.text.trim().isEmpty
                ? null
                : () {
                    ref.read(quickActionsProvider.notifier).addAction(
                          QuickAction(
                            clientId: _selectedClientId!,
                            label: _labelController.text.trim(),
                            description:
                                _descriptionController.text.trim().isEmpty
                                    ? null
                                    : _descriptionController.text.trim(),
                          ),
                        );
                    Navigator.pop(context);
                  },
            child: const Text('Add'),
          ),
          const SizedBox(height: Spacing.sm),
        ],
      ),
    );
  }
}

/// Bottom sheet to reorder/remove quick actions.
class _EditQuickActionsSheet extends ConsumerWidget {
  final List<QuickAction> actions;

  const _EditQuickActionsSheet({required this.actions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.lg, Spacing.lg, Spacing.lg, Spacing.sm),
            child: Text('Edit Quick Actions',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ),
          const Divider(height: 1),
          ...actions.asMap().entries.map((entry) {
            final i = entry.key;
            final action = entry.value;
            return ListTile(
              title: Text(action.label),
              subtitle: action.description != null
                  ? Text(action.description!)
                  : null,
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove',
                onPressed: () {
                  ref.read(quickActionsProvider.notifier).removeAt(i);
                  Navigator.pop(context);
                },
              ),
            );
          }),
          const SizedBox(height: Spacing.sm),
        ],
      ),
    );
  }
}
