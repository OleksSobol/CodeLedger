import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../providers/invoice_providers.dart';

class EditDraftInvoicePage extends ConsumerStatefulWidget {
  final Invoice invoice;

  const EditDraftInvoicePage({super.key, required this.invoice});

  @override
  ConsumerState<EditDraftInvoicePage> createState() =>
      _EditDraftInvoicePageState();
}

class _EditDraftInvoicePageState extends ConsumerState<EditDraftInvoicePage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _invoiceNumberCtrl;
  late final TextEditingController _subtotalCtrl;
  late final TextEditingController _taxRateCtrl;
  late final TextEditingController _taxLabelCtrl;
  late final TextEditingController _notesCtrl;

  late int _selectedClientId;
  late DateTime _issueDate;
  late DateTime _dueDate;
  late String _currency;
  bool _isSaving = false;

  static const _currencies = ['USD', 'EUR', 'GBP', 'CAD', 'AUD'];

  @override
  void initState() {
    super.initState();
    final inv = widget.invoice;
    _invoiceNumberCtrl = TextEditingController(text: inv.invoiceNumber);
    _subtotalCtrl =
        TextEditingController(text: inv.subtotal.toStringAsFixed(2));
    _taxRateCtrl =
        TextEditingController(text: inv.taxRate.toStringAsFixed(2));
    _taxLabelCtrl = TextEditingController(text: inv.taxLabel);
    _notesCtrl = TextEditingController(text: inv.notes ?? '');
    _selectedClientId = inv.clientId;
    _issueDate = inv.issueDate;
    _dueDate = inv.dueDate;
    _currency = inv.currency;
  }

  @override
  void dispose() {
    _invoiceNumberCtrl.dispose();
    _subtotalCtrl.dispose();
    _taxRateCtrl.dispose();
    _taxLabelCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _subtotal =>
      double.tryParse(_subtotalCtrl.text.replaceAll(',', '')) ?? 0.0;
  double get _taxRate => double.tryParse(_taxRateCtrl.text) ?? 0.0;
  double get _taxAmount => _subtotal * (_taxRate / 100.0);
  double get _total =>
      _subtotal + _taxAmount + widget.invoice.lateFeeAmount;

  Future<void> _pickDate(bool isIssue) async {
    final initial = isIssue ? _issueDate : _dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2010),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isIssue) {
        _issueDate = picked;
      } else {
        _dueDate = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final taxLabel = _taxLabelCtrl.text.trim().isEmpty
          ? 'Tax'
          : _taxLabelCtrl.text.trim();

      await ref.read(invoiceNotifierProvider.notifier).updateDraftInvoice(
            invoiceId: widget.invoice.id,
            clientId: _selectedClientId,
            invoiceNumber: _invoiceNumberCtrl.text.trim(),
            issueDate: _issueDate,
            dueDate: _dueDate,
            subtotal: _subtotal,
            taxRate: _taxRate,
            taxLabel: taxLabel,
            currency: _currency,
            notes: _notesCtrl.text.trim().isEmpty
                ? null
                : _notesCtrl.text.trim(),
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft updated.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final clientsAsync = ref.watch(activeClientsProvider);
    final dateFmt = DateFormat('MMM d, yyyy');
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Ensure the current client is in the list even if archived
    final clientList = clientsAsync.whenOrNull(data: (c) => c) ?? const [];
    final clientInList =
        clientList.any((c) => c.id == _selectedClientId);

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Draft')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              Spacing.md, Spacing.md, Spacing.md, Spacing.md + bottomInset),
          children: [
            // ── Client ──────────────────────────────────────────────
            clientsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (clients) {
                // If the current client is not active, add a fallback entry
                final items = [
                  ...clients.map((c) =>
                      DropdownMenuItem(value: c.id, child: Text(c.name))),
                  if (!clientInList)
                    DropdownMenuItem(
                      value: _selectedClientId,
                      child: ref
                              .watch(clientByIdProvider(_selectedClientId))
                              .whenOrNull(
                                data: (c) => Text(c.name),
                              ) ??
                          Text('Client #$_selectedClientId'),
                    ),
                ];
                return DropdownButtonFormField<int>(
                  // ignore: deprecated_member_use
                  value: _selectedClientId,
                  decoration: const InputDecoration(
                    labelText: 'Client *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.people_outline),
                  ),
                  items: items,
                  onChanged: (v) => setState(() => _selectedClientId = v!),
                  validator: (v) => v == null ? 'Select a client' : null,
                );
              },
            ),
            const SizedBox(height: Spacing.md),

            // ── Invoice Number ───────────────────────────────────────
            TextFormField(
              controller: _invoiceNumberCtrl,
              decoration: const InputDecoration(
                labelText: 'Invoice Number *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.tag),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: Spacing.md),

            // ── Dates row ────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Issue Date',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today_outlined),
                      ),
                      child: Text(dateFmt.format(_issueDate)),
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Due Date',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.event_outlined),
                      ),
                      child: Text(dateFmt.format(_dueDate)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),

            // ── Currency ─────────────────────────────────────────────
            DropdownButtonFormField<String>(
              // ignore: deprecated_member_use
              value: _currencies.contains(_currency)
                  ? _currency
                  : _currencies.first,
              decoration: const InputDecoration(
                labelText: 'Currency',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.currency_exchange_outlined),
              ),
              items: _currencies
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v!),
            ),
            const SizedBox(height: Spacing.md),

            // ── Net Amount ───────────────────────────────────────────
            TextFormField(
              controller: _subtotalCtrl,
              decoration: const InputDecoration(
                labelText: 'Net Amount (Subtotal) *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.,]')),
              ],
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Required';
                if (double.tryParse(v.replaceAll(',', '')) == null) {
                  return 'Enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.md),

            // ── Tax row ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _taxLabelCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tax Label',
                      border: OutlineInputBorder(),
                      hintText: 'Tax',
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _taxRateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Tax Rate %',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.percent),
                      helperText: '0 = no tax',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                    ],
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v != null &&
                          v.isNotEmpty &&
                          double.tryParse(v) == null) {
                        return 'Invalid';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),

            // ── Computed totals card ─────────────────────────────────
            if (_subtotalCtrl.text.isNotEmpty) ...[
              Card(
                color: theme.colorScheme.surfaceContainerHighest,
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    children: [
                      _TotalRow(
                          label: 'Subtotal',
                          amount: _subtotal,
                          currency: _currency),
                      if (_taxRate > 0) ...[
                        const SizedBox(height: Spacing.xs),
                        _TotalRow(
                            label:
                                '${_taxLabelCtrl.text.trim().isEmpty ? 'Tax' : _taxLabelCtrl.text.trim()} '
                                '(${_taxRate.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}%)',
                            amount: _taxAmount,
                            currency: _currency),
                      ],
                      if (widget.invoice.lateFeeAmount > 0) ...[
                        const SizedBox(height: Spacing.xs),
                        _TotalRow(
                          label: 'Late Fee',
                          amount: widget.invoice.lateFeeAmount,
                          currency: _currency,
                        ),
                      ],
                      const Divider(),
                      _TotalRow(
                        label: 'Total',
                        amount: _total,
                        currency: _currency,
                        bold: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Spacing.md),
            ],

            // ── Notes ────────────────────────────────────────────────
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes_outlined),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: Spacing.xl),

            // ── Save button ──────────────────────────────────────────
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isSaving ? 'Saving...' : 'Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final double amount;
  final String currency;
  final bool bold;

  const _TotalRow({
    required this.label,
    required this.amount,
    required this.currency,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)
        : theme.textTheme.bodyMedium;

    final fmt = NumberFormat.currency(
      symbol: currency == 'USD'
          ? '\$'
          : currency == 'EUR'
              ? '€'
              : currency == 'GBP'
                  ? '£'
                  : '$currency ',
      decimalDigits: 2,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(fmt.format(amount), style: style),
      ],
    );
  }
}
