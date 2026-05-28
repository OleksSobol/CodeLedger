import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/expense_dao.dart';
import '../../../../core/database/tables/expenses_table.dart';
import '../../../../core/providers/dao_providers.dart';

class ExpenseFormPage extends ConsumerStatefulWidget {
  final Expense? expense; // null = add, non-null = edit

  const ExpenseFormPage({super.key, this.expense});

  @override
  ConsumerState<ExpenseFormPage> createState() => _ExpenseFormPageState();
}

class _ExpenseFormPageState extends ConsumerState<ExpenseFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _manualPctCtrl = TextEditingController();
  final _workHoursCtrl = TextEditingController();
  final _totalHoursCtrl = TextEditingController();
  final _workSqftCtrl = TextEditingController();
  final _totalSqftCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _category = 'other';
  String _frequency = 'monthly';
  String _method = 'manual';
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    if (e != null) {
      _nameCtrl.text = e.name;
      _amountCtrl.text = e.amount.toStringAsFixed(2);
      _category = e.category;
      _frequency = e.frequency;
      _method = e.deductionMethod;
      _manualPctCtrl.text =
          e.manualPercentage?.toStringAsFixed(1) ?? '';
      _workHoursCtrl.text =
          e.workHoursPerDay?.toStringAsFixed(1) ?? '';
      _totalHoursCtrl.text =
          e.totalHoursPerDay?.toStringAsFixed(1) ?? '24';
      _workSqftCtrl.text =
          e.workSpaceSqft?.toStringAsFixed(0) ?? '';
      _totalSqftCtrl.text =
          e.totalSpaceSqft?.toStringAsFixed(0) ?? '';
      _notesCtrl.text = e.notes ?? '';
      _startDate = e.startDate;
      _endDate = e.endDate;
    } else {
      _totalHoursCtrl.text = '24';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _manualPctCtrl.dispose();
    _workHoursCtrl.dispose();
    _totalHoursCtrl.dispose();
    _workSqftCtrl.dispose();
    _totalSqftCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Calculated preview ────────────────────────────────────────────────────

  double get _amount => double.tryParse(_amountCtrl.text) ?? 0;
  double get _monthlyAmount =>
      _frequency == 'annual' ? _amount / 12 : _amount;

  double get _fraction {
    switch (_method) {
      case 'hours':
        final work = double.tryParse(_workHoursCtrl.text) ?? 0;
        final total =
            double.tryParse(_totalHoursCtrl.text) ?? 24;
        return total > 0 ? work / total : 0;
      case 'space':
        final work = double.tryParse(_workSqftCtrl.text) ?? 0;
        final total = double.tryParse(_totalSqftCtrl.text) ?? 0;
        return total > 0 ? work / total : 0;
      case 'manual':
      default:
        return (double.tryParse(_manualPctCtrl.text) ?? 0) / 100;
    }
  }

  double get _monthlyDeductible => _monthlyAmount * _fraction;

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final dao = ref.read(expenseDaoProvider);
      final companion = ExpensesCompanion(
        id: Value(widget.expense?.id ?? const Uuid().v4()),
        name: Value(_nameCtrl.text.trim()),
        category: Value(_category),
        amount: Value(_amount),
        frequency: Value(_frequency),
        deductionMethod: Value(_method),
        manualPercentage: _method == 'manual'
            ? Value(double.tryParse(_manualPctCtrl.text))
            : const Value(null),
        workHoursPerDay: _method == 'hours'
            ? Value(double.tryParse(_workHoursCtrl.text))
            : const Value(null),
        totalHoursPerDay: _method == 'hours'
            ? Value(double.tryParse(_totalHoursCtrl.text) ?? 24)
            : const Value(null),
        workSpaceSqft: _method == 'space'
            ? Value(double.tryParse(_workSqftCtrl.text))
            : const Value(null),
        totalSpaceSqft: _method == 'space'
            ? Value(double.tryParse(_totalSqftCtrl.text))
            : const Value(null),
        startDate: Value(_startDate),
        endDate: Value(_endDate),
        notes: Value(
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim()),
      );

      if (widget.expense == null) {
        await dao.insertExpense(companion);
      } else {
        await dao.updateExpense(companion);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.expense != null;
    final fmt = NumberFormat.currency(symbol: '\$');

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Expense' : 'Add Expense'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Preview card ──────────────────────────────────────────────
            _PreviewCard(
              monthlyDeductible: _monthlyDeductible,
              fraction: _fraction,
              fmt: fmt,
            ),
            const SizedBox(height: 20),

            // ── Name ──────────────────────────────────────────────────────
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Expense Name',
                hintText: 'e.g. Home Internet, ChatGPT, Apartment',
                prefixIcon: Icon(Icons.label_outline),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // ── Category ──────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: kExpenseCategories
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(kExpenseCategoryLabels[c] ?? c),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 16),

            // ── Amount + Frequency ────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amountCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Amount',
                      prefixText: '\$ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d*'))
                    ],
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if ((double.tryParse(v) ?? 0) <= 0) {
                        return 'Must be > 0';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Frequency',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                              value: 'monthly', label: Text('Monthly')),
                          ButtonSegment(
                              value: 'annual', label: Text('Annual')),
                        ],
                        selected: {_frequency},
                        onSelectionChanged: (s) =>
                            setState(() => _frequency = s.first),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // ── Deduction Method ──────────────────────────────────────────
            Text('Tax Deduction Method',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'manual', label: Text('Manual %')),
                ButtonSegment(
                    value: 'hours', label: Text('By Hours')),
                ButtonSegment(
                    value: 'space', label: Text('By Space')),
              ],
              selected: {_method},
              onSelectionChanged: (s) =>
                  setState(() => _method = s.first),
            ),
            const SizedBox(height: 12),

            if (_method == 'manual') ...[
              TextFormField(
                controller: _manualPctCtrl,
                decoration: const InputDecoration(
                  labelText: 'Deductible Percentage',
                  suffixText: '%',
                  hintText: '100 for fully deductible',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))
                ],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  final n = double.tryParse(v) ?? -1;
                  if (n < 0 || n > 100) return '0–100';
                  return null;
                },
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter 100% for software subscriptions used only for work. '
                'Enter a partial % for mixed-use expenses.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],

            if (_method == 'hours') ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _workHoursCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Work hours/day',
                        hintText: 'e.g. 8',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'))
                      ],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final n = double.tryParse(v);
                        if (n == null || n <= 0) return 'Must be > 0';
                        if (n > 24) return 'Max 24 h/day';
                        final total =
                            double.tryParse(_totalHoursCtrl.text) ?? 24;
                        if (n > total) return 'Cannot exceed total hours';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _totalHoursCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Total hours/day',
                        hintText: '24',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'))
                      ],
                      validator: (v) {
                        if (v == null || v.isEmpty) return null;
                        final n = double.tryParse(v);
                        if (n == null || n <= 0) return 'Must be > 0';
                        if (n > 24) return 'Max 24 h/day';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'For internet: if you use it 10 hours/day for work out of 24, '
                'deductible = 10/24 ≈ 42%.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],

            if (_method == 'space') ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _workSqftCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Office area (sq ft)',
                        hintText: 'e.g. 120',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'))
                      ],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final n = double.tryParse(v);
                        if (n == null || n <= 0) return 'Must be > 0';
                        final total =
                            double.tryParse(_totalSqftCtrl.text) ?? 0;
                        if (total > 0 && n > total) {
                          return 'Cannot exceed total area';
                        }
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _totalSqftCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Total area (sq ft)',
                        hintText: 'e.g. 900',
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'))
                      ],
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'For rent: if your home office is 120 sq ft of a 900 sq ft '
                'apartment, deductible = 120/900 ≈ 13%.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],

            const SizedBox(height: 20),

            // ── Active Period ─────────────────────────────────────────────
            Text('Active Period',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.calendar_today_outlined, size: 18),
                    label: Text(
                        'Start: \${DateFormat('MMM d, yyyy').format(_startDate)}'),
                    onPressed: () => _pickDate(isStart: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_endDate == null
                        ? 'End: Ongoing'
                        : 'End: \${DateFormat('MMM d, yyyy').format(_endDate!)}'),
                    onPressed: () => _pickDate(isStart: false),
                  ),
                ),
              ],
            ),
            if (_endDate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _endDate = null),
                  child: const Text('Clear end date (mark ongoing)'),
                ),
              ),
            const SizedBox(height: 16),

            // ── Notes ─────────────────────────────────────────────────────
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. Comcast business plan, shared with family',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  final double monthlyDeductible;
  final double fraction;
  final NumberFormat fmt;

  const _PreviewCard({
    required this.monthlyDeductible,
    required this.fraction,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = (fraction * 100).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.calculate_outlined,
              color: theme.colorScheme.primary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Monthly deductible',
                    style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant)),
                Text(
                  fmt.format(monthlyDeductible),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Deduction',
                  style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
              Text(
                '$pct%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
