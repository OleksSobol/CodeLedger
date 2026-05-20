import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../providers/invoice_providers.dart';

class AddTimeToInvoicePage extends ConsumerStatefulWidget {
  final Invoice invoice;
  const AddTimeToInvoicePage({super.key, required this.invoice});

  @override
  ConsumerState<AddTimeToInvoicePage> createState() =>
      _AddTimeToInvoicePageState();
}

class _AddTimeToInvoicePageState extends ConsumerState<AddTimeToInvoicePage> {
  final Set<String> _selectedIds = {};
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final entriesAsync =
        ref.watch(uninvoicedEntriesProvider(widget.invoice.clientId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Add Time to ${widget.invoice.invoiceNumber}'),
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (entries) {
          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No uninvoiced time entries for this client.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return _EntryList(
            entries: entries,
            selectedIds: _selectedIds,
            onToggle: (id) {
              setState(() {
                if (!_selectedIds.add(id)) _selectedIds.remove(id);
              });
            },
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: _selectedIds.isEmpty || _saving
                ? null
                : () => _append(entriesAsync.value ?? []),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label: Text(
              _selectedIds.isEmpty
                  ? 'Select entries to add'
                  : 'Add ${_selectedIds.length} entries',
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _append(List<TimeEntry> available) async {
    final picked =
        available.where((e) => _selectedIds.contains(e.id)).toList();
    if (picked.isEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(invoiceNotifierProvider.notifier).addEntriesToInvoice(
            invoiceId: widget.invoice.id,
            entries: picked,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${picked.length} entries')),
        );
        Navigator.of(context).pop(true);
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
}

class _EntryList extends StatelessWidget {
  final List<TimeEntry> entries;
  final Set<String> selectedIds;
  final ValueChanged<String> onToggle;

  const _EntryList({
    required this.entries,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd();

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (context, i) {
        final entry = entries[i];
        final hours = (entry.durationMinutes ?? 0) / 60.0;
        final amount = hours * entry.hourlyRateSnapshot;
        final selected = selectedIds.contains(entry.id);

        return CheckboxListTile(
          value: selected,
          onChanged: (_) => onToggle(entry.id),
          title: Text(
            entry.description ?? 'Work session',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            '${dateFmt.format(entry.startTime)} - '
            '${formatDuration(entry.durationMinutes ?? 0)} - '
            '${formatCurrency(amount)}',
            style: theme.textTheme.bodySmall,
          ),
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
        );
      },
    );
  }
}
