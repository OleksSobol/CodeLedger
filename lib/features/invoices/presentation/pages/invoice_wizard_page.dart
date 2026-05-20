import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/duration_formatter.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../providers/invoice_providers.dart';
import '../providers/template_providers.dart';

/// Single-page invoice wizard with 3 steps using PageView.
/// System back navigates to the previous step; on step 1 it exits.
class InvoiceWizardPage extends ConsumerStatefulWidget {
  const InvoiceWizardPage({super.key});

  @override
  ConsumerState<InvoiceWizardPage> createState() => _InvoiceWizardPageState();
}

class _InvoiceWizardPageState extends ConsumerState<InvoiceWizardPage> {
  final _pageController = PageController();
  int _currentStep = 0;
  bool _creating = false;

  // Review page controllers
  final _notesCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();

  static const _stepLabels = ['Client', 'Entries', 'Review'];

  @override
  void initState() {
    super.initState();
    // Reset wizard state when entering
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(invoiceWizardProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _notesCtrl.dispose();
    _taxCtrl.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  bool _handleBackPress() {
    if (_creating) return false; // Don't allow back while creating
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
      return false; // Don't pop the route
    }
    // Step 0 — confirm exit if wizard has data
    final wizard = ref.read(invoiceWizardProvider);
    if (wizard.clientId != null) {
      _showExitConfirmation();
      return false;
    }
    return true; // Pop the route (nothing to lose)
  }

  void _showExitConfirmation() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard Invoice?'),
        content: const Text(
          'Your invoice progress will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Editing'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(invoiceWizardProvider.notifier).reset();
              context.go('/invoices');
            },
            child: const Text('Discard'),
          ),
        ],
      ),
    );
  }

  Future<void> _createInvoice() async {
    setState(() => _creating = true);

    final notifier = ref.read(invoiceWizardProvider.notifier);
    final notesText = _notesCtrl.text.trim();
    if (notesText.isNotEmpty) notifier.setNotes(notesText);

    final taxText = _taxCtrl.text.trim();
    if (taxText.isNotEmpty) {
      final rate = double.tryParse(taxText);
      if (rate != null) notifier.setTaxRateOverride(rate);
    }

    try {
      await ref.read(invoiceNotifierProvider.notifier).createInvoice();
      if (mounted) {
        ref.read(invoiceWizardProvider.notifier).reset();
        context.go('/invoices');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final shouldPop = _handleBackPress();
        if (shouldPop && mounted) {
          context.go('/invoices');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              final shouldPop = _handleBackPress();
              if (shouldPop) context.go('/invoices');
            },
          ),
          title: const Text('New Invoice'),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Column(
              children: [
                // Step indicator
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: List.generate(3, (i) {
                      final isActive = i == _currentStep;
                      final isCompleted = i < _currentStep;
                      return Expanded(
                        child: Row(
                          children: [
                            if (i > 0)
                              Expanded(
                                child: Container(
                                  height: 2,
                                  color: isCompleted
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outlineVariant,
                                ),
                              ),
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isActive || isCompleted
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.surfaceContainerHighest,
                              ),
                              child: Center(
                                child: isCompleted
                                    ? Icon(Icons.check,
                                        size: 16,
                                        color: theme.colorScheme.onPrimary)
                                    : Text(
                                        '${i + 1}',
                                        style:
                                            theme.textTheme.labelSmall?.copyWith(
                                          color: isActive
                                              ? theme.colorScheme.onPrimary
                                              : theme.colorScheme.onSurfaceVariant,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ),
                            if (i < 2)
                              Expanded(
                                child: Container(
                                  height: 2,
                                  color: i < _currentStep
                                      ? theme.colorScheme.primary
                                      : theme.colorScheme.outlineVariant,
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 4),
                // Step labels
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(3, (i) {
                      final isActive = i == _currentStep;
                      return Text(
                        _stepLabels[i],
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isActive
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight:
                              isActive ? FontWeight.bold : FontWeight.normal,
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        body: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _currentStep = i),
          children: [
            _ClientStep(onClientSelected: () => _goToStep(1)),
            _EntriesStep(
              onNext: () => _goToStep(2),
              onBack: () => _goToStep(0),
            ),
            _ReviewStep(
              notesCtrl: _notesCtrl,
              taxCtrl: _taxCtrl,
              creating: _creating,
              onBack: () => _goToStep(1),
              onCreate: _createInvoice,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Step 1: Select Client
// ─────────────────────────────────────────────────────────────────────

class _ClientStep extends ConsumerWidget {
  final VoidCallback onClientSelected;
  const _ClientStep({required this.onClientSelected});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clientsAsync = ref.watch(activeClientsProvider);
    final theme = Theme.of(context);
    final wizard = ref.watch(invoiceWizardProvider);

    return clientsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (clients) {
        if (clients.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people_outline,
                    size: 64, color: theme.colorScheme.outline),
                const SizedBox(height: 16),
                Text('No clients', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text('Add a client before creating an invoice'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.push('/clients/add'),
                  icon: const Icon(Icons.add),
                  label: const Text('Add Client'),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: clients.length,
          itemBuilder: (context, index) {
            final client = clients[index];
            final isSelected = wizard.clientId == client.id;
            return _ClientTile(
              client: client,
              isSelected: isSelected,
              onTap: () {
                ref.read(invoiceWizardProvider.notifier).setClient(client.id);
                onClientSelected();
              },
            );
          },
        );
      },
    );
  }
}

class _ClientTile extends ConsumerWidget {
  final Client client;
  final bool isSelected;
  final VoidCallback onTap;

  const _ClientTile({
    required this.client,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uninvoicedAsync = ref.watch(uninvoicedEntriesProvider(client.id));
    final entryCount =
        uninvoicedAsync.whenOrNull(data: (entries) => entries.length) ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
          : null,
      child: ListTile(
        leading: CircleAvatar(child: Text(client.name[0].toUpperCase())),
        title: Text(client.name),
        subtitle: Text(
          entryCount > 0
              ? '$entryCount uninvoiced entries'
              : 'No uninvoiced entries',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Step 2: Select Entries
// ─────────────────────────────────────────────────────────────────────

class _EntriesStep extends ConsumerWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _EntriesStep({required this.onNext, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wizard = ref.watch(invoiceWizardProvider);

    if (wizard.clientId == null) {
      return const Center(child: Text('Select a client first'));
    }

    final entriesAsync =
        ref.watch(uninvoicedEntriesProvider(wizard.clientId!));

    return Column(
      children: [
        Expanded(
          child: entriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (entries) =>
                _EntriesBody(entries: entries, wizard: wizard),
          ),
        ),
        _EntriesBottomBar(wizard: wizard, onNext: onNext),
      ],
    );
  }
}

class _EntriesBottomBar extends StatelessWidget {
  final InvoiceWizardState wizard;
  final VoidCallback onNext;

  const _EntriesBottomBar({required this.wizard, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasItems =
        wizard.selectedEntries.isNotEmpty || wizard.manualLineItems.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Subtotal', style: theme.textTheme.bodySmall),
                  Text(
                    formatCurrency(wizard.subtotal),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: hasItems ? onNext : null,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Review'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntriesBody extends ConsumerWidget {
  final List<TimeEntry> entries;
  final InvoiceWizardState wizard;

  const _EntriesBody({required this.entries, required this.wizard});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final notifier = ref.read(invoiceWizardProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (entries.isNotEmpty)
          Row(
            children: [
              Text('Time Entries (${entries.length})',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              TextButton(
                onPressed: () {
                  if (wizard.selectedEntries.length == entries.length) {
                    notifier.deselectAll();
                  } else {
                    notifier.selectAll(entries);
                  }
                },
                child: Text(
                  wizard.selectedEntries.length == entries.length
                      ? 'Deselect All'
                      : 'Select All',
                ),
              ),
            ],
          ),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'No uninvoiced time entries for this client',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ),
        ...entries.map((entry) {
          final isSelected =
              wizard.selectedEntries.any((e) => e.id == entry.id);
          final dateFmt = DateFormat.yMMMd();
          final hours = (entry.durationMinutes ?? 0) / 60.0;
          final amount = hours * entry.hourlyRateSnapshot;

          return CheckboxListTile(
            value: isSelected,
            onChanged: (_) => notifier.toggleEntry(entry),
            title: Text(
              entry.description ?? 'Work session',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${dateFmt.format(entry.startTime)} · ${formatDuration(entry.durationMinutes ?? 0)} · ${formatCurrency(amount)}',
              style: theme.textTheme.bodySmall,
            ),
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
          );
        }),
        const Divider(height: 32),
        Row(
          children: [
            Text('Manual Line Items',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showAddManualItemDialog(context, ref),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (wizard.manualLineItems.isEmpty)
          Text(
            'No manual line items',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ...wizard.manualLineItems.asMap().entries.map((e) {
          final idx = e.key;
          final item = e.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(item.description),
              subtitle: Text(
                '${item.quantity} × ${formatCurrency(item.unitPrice)} = ${formatCurrency(item.total)}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => notifier.removeManualLineItem(idx),
              ),
            ),
          );
        }),
      ],
    );
  }

  void _showAddManualItemDialog(BuildContext context, WidgetRef ref) {
    final descCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Line Item'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: qtyCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Quantity',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Unit Price',
                        prefixText: '\$ ',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                ref.read(invoiceWizardProvider.notifier).addManualLineItem(
                      ManualLineItem(
                        description: descCtrl.text.trim(),
                        quantity: double.parse(qtyCtrl.text.trim()),
                        unitPrice: double.parse(priceCtrl.text.trim()),
                      ),
                    );
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────
// Step 3: Review & Create
// ─────────────────────────────────────────────────────────────────────

class _ReviewStep extends ConsumerWidget {
  final TextEditingController notesCtrl;
  final TextEditingController taxCtrl;
  final bool creating;
  final VoidCallback onBack;
  final VoidCallback onCreate;

  const _ReviewStep({
    required this.notesCtrl,
    required this.taxCtrl,
    required this.creating,
    required this.onBack,
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wizard = ref.watch(invoiceWizardProvider);
    final theme = Theme.of(context);

    if (wizard.clientId == null) {
      return const Center(child: Text('Select a client first'));
    }

    final clientAsync = ref.watch(clientByIdProvider(wizard.clientId!));
    final clientName =
        clientAsync.whenOrNull(data: (c) => c.name) ?? '...';

    final totalHours = wizard.selectedEntries.fold<int>(
        0, (sum, e) => sum + (e.durationMinutes ?? 0));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Invoice Summary',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _SummaryRow(label: 'Client', value: clientName),
                _SummaryRow(
                    label: 'Time Entries',
                    value: '${wizard.selectedEntries.length}'),
                if (wizard.selectedEntries.isNotEmpty)
                  _SummaryRow(
                      label: 'Total Hours',
                      value: formatDuration(totalHours)),
                if (wizard.manualLineItems.isNotEmpty)
                  _SummaryRow(
                      label: 'Manual Items',
                      value: '${wizard.manualLineItems.length}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Line items preview
        Text('Line Items',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        ...wizard.selectedEntries.map((entry) {
          final hours = (entry.durationMinutes ?? 0) / 60.0;
          return ListTile(
            dense: true,
            title: Text(entry.description ?? 'Work session',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing:
                Text(formatCurrency(hours * entry.hourlyRateSnapshot)),
          );
        }),
        ...wizard.manualLineItems.map((item) => ListTile(
              dense: true,
              title: Text(item.description,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(formatCurrency(item.total)),
            )),

        const Divider(height: 32),

        // Invoice template picker
        ref.watch(allTemplatesProvider).when(
              loading: () => const LinearProgressIndicator(),
              error: (_, _) => const SizedBox.shrink(),
              data: (templates) {
                return DropdownButtonFormField<String?>(
                  initialValue: wizard.templateId,
                  decoration: const InputDecoration(
                    labelText: 'Invoice Template',
                    border: OutlineInputBorder(),
                  ),
                  items: templates
                      .map((t) => DropdownMenuItem<String?>(
                            value: t.id,
                            child: Text(t.name),
                          ))
                      .toList(),
                  onChanged: (v) => ref
                      .read(invoiceWizardProvider.notifier)
                      .setTemplate(v),
                );
              },
            ),
        const SizedBox(height: 16),

        // Tax override
        TextFormField(
          controller: taxCtrl,
          decoration: const InputDecoration(
            labelText: 'Tax Rate Override (%)',
            hintText: 'Leave blank for default',
            border: OutlineInputBorder(),
            suffixText: '%',
          ),
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 16),

        // Notes
        TextFormField(
          controller: notesCtrl,
          decoration: const InputDecoration(
            labelText: 'Notes',
            hintText: 'Optional notes for the invoice',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        const SizedBox(height: 24),

        // Totals
        Card(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Subtotal',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  formatCurrency(wizard.subtotal),
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Create button
        SizedBox(
          height: 48,
          child: FilledButton.icon(
            onPressed: creating ? null : onCreate,
            icon: creating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.receipt),
            label: Text(creating ? 'Creating...' : 'Create Invoice'),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
              width: 120,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall)),
          Expanded(
              child: Text(value,
                  style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
