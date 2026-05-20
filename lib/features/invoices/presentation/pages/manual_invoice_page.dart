import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/invoice_dao.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../providers/invoice_providers.dart';

class ManualInvoicePage extends ConsumerStatefulWidget {
  const ManualInvoicePage({super.key});

  @override
  ConsumerState<ManualInvoicePage> createState() => _ManualInvoicePageState();
}

class _ManualInvoicePageState extends ConsumerState<ManualInvoicePage> {
  final _formKey = GlobalKey<FormState>();

  final _invoiceNumberCtrl = TextEditingController();
  final _subtotalCtrl = TextEditingController();
  final _taxRateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _selectedClientId;
  DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));
  String _status = 'paid';
  String _currency = 'USD';
  bool _isSaving = false;

  static const _statuses = ['draft', 'sent', 'paid', 'overdue', 'cancelled'];
  static const _currencies = ['USD', 'EUR', 'GBP', 'CAD', 'AUD'];

  @override
  void initState() {
    super.initState();
    _prefillFromProfile();
  }

  Future<void> _prefillFromProfile() async {
    final profileDao = ref.read(userProfileRepositoryProvider);
    final profile = await profileDao.getProfile();
    final invoiceNumber = await profileDao.getNextInvoiceNumber();
    if (!mounted) return;
    setState(() {
      _invoiceNumberCtrl.text = invoiceNumber;
      _taxRateCtrl.text = profile.defaultTaxRate.toStringAsFixed(2);
      _currency = profile.defaultCurrency;
    });
  }

  @override
  void dispose() {
    _invoiceNumberCtrl.dispose();
    _subtotalCtrl.dispose();
    _taxRateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _subtotal =>
      double.tryParse(_subtotalCtrl.text.replaceAll(',', '')) ?? 0.0;
  double get _taxRate => double.tryParse(_taxRateCtrl.text) ?? 0.0;
  double get _taxAmount => _subtotal * (_taxRate / 100.0);
  double get _total => _subtotal + _taxAmount;

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
    if (_selectedClientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a client.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final profileDao = ref.read(userProfileRepositoryProvider);
      final profile = await profileDao.getProfile();
      final invoiceDao = InvoiceDao(ref.read(databaseProvider));

      final subtotal = _subtotal;
      final taxRate = _taxRate;
      final taxAmount = _taxAmount;
      final total = _total;

      final amountPaid = _status == 'paid' ? total : 0.0;
      final paidDate = _status == 'paid' ? _issueDate : null;

      await invoiceDao.createInvoice(
        invoice: InvoicesCompanion(
          clientId: Value(_selectedClientId!),
          invoiceNumber: Value(_invoiceNumberCtrl.text.trim()),
          status: Value(_status),
          issueDate: Value(_issueDate),
          dueDate: Value(_dueDate),
          subtotal: Value(subtotal),
          taxRate: Value(taxRate),
          taxLabel: Value(profile.defaultTaxLabel),
          taxAmount: Value(taxAmount),
          total: Value(total),
          amountPaid: Value(amountPaid),
          currency: Value(_currency),
          notes: Value(_notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim()),
          paidDate: Value(paidDate),
        ),
        lineItems: [],
        timeEntryIds: [],
      );

      // Bump the invoice counter only if the number starts with the prefix
      // (user may have typed a custom number)
      final prefix = profile.invoiceNumberPrefix;
      if (_invoiceNumberCtrl.text.trim().startsWith(prefix)) {
        await profileDao.getNextInvoiceNumber(); // already incremented in _prefillFromProfile
      }

      ref.invalidate(allInvoicesProvider);

      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invoice saved.')),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Manual Invoice')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              Spacing.md, Spacing.md, Spacing.md, Spacing.md + bottomInset),
          children: [
            // ── Client ───────────────────────────────────────────────
            clientsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (clients) => DropdownButtonFormField<String>(
                initialValue: _selectedClientId,
                decoration: const InputDecoration(
                  labelText: 'Client *',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.people_outline),
                ),
                items: clients
                    .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedClientId = v),
                validator: (v) => v == null ? 'Select a client' : null,
              ),
            ),
            const SizedBox(height: Spacing.md),

            // ── Invoice number ────────────────────────────────────────
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

            // ── Dates row ─────────────────────────────────────────────
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

            // ── Status + Currency row ─────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: _statuses
                        .map((s) => DropdownMenuItem(
                              value: s,
                              child: Text(
                                  '${s[0].toUpperCase()}${s.substring(1)}'),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _currencies.contains(_currency)
                        ? _currency
                        : _currencies.first,
                    decoration: const InputDecoration(
                      labelText: 'Currency',
                      border: OutlineInputBorder(),
                    ),
                    items: _currencies
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => setState(() => _currency = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Spacing.md),

            // ── Subtotal ──────────────────────────────────────────────
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

            // ── Tax rate ──────────────────────────────────────────────
            TextFormField(
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
                if (v != null && v.isNotEmpty &&
                    double.tryParse(v) == null) {
                  return 'Enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: Spacing.md),

            // ── Computed totals card ──────────────────────────────────
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
                                'Tax (${_taxRate.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '')}%)',
                            amount: _taxAmount,
                            currency: _currency),
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

            // ── Notes ─────────────────────────────────────────────────
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

            // ── Save button ───────────────────────────────────────────
            FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_isSaving ? 'Saving...' : 'Save Invoice'),
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
