import 'dart:io';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/expense_transaction_dao.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../shared/widgets/app_page_scaffold.dart';
import '../providers/expense_providers.dart';

class QuickCaptureExpensePage extends ConsumerStatefulWidget {
  final ExpenseTransactionWithCategory? initialTransaction;

  const QuickCaptureExpensePage({
    super.key,
    this.initialTransaction,
  });

  @override
  ConsumerState<QuickCaptureExpensePage> createState() =>
      _QuickCaptureExpensePageState();
}

class _QuickCaptureExpensePageState
    extends ConsumerState<QuickCaptureExpensePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _vendorCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _customPctCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  DateTime _date = DateTime.now();
  String? _selectedCategoryId;
  int _businessUsePct = 100;
  bool _isCustomPct = false;
  String? _receiptPath;
  bool _saving = false;

  final _currencyFmt = NumberFormat.currency(symbol: '\$');

  @override
  void initState() {
    super.initState();
    final item = widget.initialTransaction;
    if (item != null) {
      final t = item.transaction;
      _titleCtrl.text = t.title;
      _vendorCtrl.text = t.vendor ?? '';
      _amountCtrl.text = t.amount.toStringAsFixed(2);
      _date = t.date;
      _selectedCategoryId = t.categoryId;
      _businessUsePct = t.businessUsePct;
      _isCustomPct = ![100, 80, 50].contains(_businessUsePct);
      if (_isCustomPct) {
        _customPctCtrl.text = _businessUsePct.toString();
      }
      _receiptPath = t.receiptPath;
      _notesCtrl.text = t.notes ?? '';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _vendorCtrl.dispose();
    _amountCtrl.dispose();
    _customPctCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  double get _currentAmount {
    return double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0.0;
  }

  double get _calculatedDeductible {
    return (_currentAmount * (_businessUsePct / 100.0));
  }

  Future<void> _pickReceipt(ImageSource source) async {
    try {
      final service = ref.read(receiptStorageServiceProvider);
      final path = await service.pickAndStoreReceipt(source);
      if (path != null && mounted) {
        setState(() {
          _receiptPath = path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to capture receipt: $e')),
        );
      }
    }
  }

  void _removeReceipt() {
    setState(() {
      _receiptPath = null;
    });
  }

  void _showReceiptFullscreen() {
    if (_receiptPath == null || _receiptPath!.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(
              _titleCtrl.text.trim().isNotEmpty
                  ? _titleCtrl.text.trim()
                  : 'Receipt Preview',
            ),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.8,
              maxScale: 5.0,
              child: kIsWeb
                  ? Image.network(
                      _receiptPath!,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    )
                  : Image.file(
                      File(_receiptPath!),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Center(
                        child: Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
      });
    }
  }

  void _onPresetTapped(int pct) {
    setState(() {
      _businessUsePct = pct;
      _isCustomPct = false;
      _customPctCtrl.clear();
    });
  }

  void _onCustomTapped() {
    setState(() {
      _isCustomPct = true;
      if (_customPctCtrl.text.isEmpty) {
        _customPctCtrl.text = _businessUsePct.toString();
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an expense category')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final repo = ref.read(expenseTransactionRepositoryProvider);
      final id = widget.initialTransaction?.transaction.id ?? const Uuid().v4();
      final totalAmount = _currentAmount;
      final pct = _businessUsePct.clamp(0, 100);
      final deductible = double.parse(
        (totalAmount * (pct / 100.0)).toStringAsFixed(2),
      );

      final companion = ExpenseTransactionsCompanion.insert(
        id: id,
        title: _titleCtrl.text.trim(),
        vendor: Value(
          _vendorCtrl.text.trim().isEmpty ? null : _vendorCtrl.text.trim(),
        ),
        amount: totalAmount,
        date: _date,
        categoryId: _selectedCategoryId!,
        businessUsePct: Value(pct),
        deductibleAmount: Value(deductible),
        receiptPath: Value(_receiptPath),
        notes: Value(
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        ),
      );

      if (widget.initialTransaction == null) {
        await repo.insertTransaction(companion);
      } else {
        await repo.updateTransaction(companion);
      }

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.initialTransaction == null
                  ? 'Expense recorded successfully'
                  : 'Expense updated',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving expense: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(expenseCategoriesProvider);
    final theme = Theme.of(context);

    return AppPageScaffold(
      title: widget.initialTransaction == null
          ? 'Quick Capture Expense'
          : 'Edit Expense',
      actions: [
        if (_saving)
          const Padding(
            padding: EdgeInsets.all(16),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          TextButton(
            onPressed: _save,
            child: const Text('Save'),
          ),
      ],
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading categories: $e')),
        data: (categories) {
          if (categories.isNotEmpty && _selectedCategoryId == null) {
            _selectedCategoryId = categories.first.id;
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                // ── Receipt Capture Preview ──
                _buildReceiptPreview(theme),
                const SizedBox(height: 16),

                // ── Total Amount & Dynamic Deductible Card ──
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Expense Amount',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                          decoration: InputDecoration(
                            prefixText: '\$ ',
                            prefixStyle: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.primary,
                            ),
                            hintText: '0.00',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: theme.colorScheme.surface,
                          ),
                          onChanged: (_) => setState(() {}),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Enter expense amount';
                            }
                            final val = double.tryParse(v);
                            if (val == null || val <= 0) {
                              return 'Enter a valid amount';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),

                        // Calculated Basis Badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Deductible Tax Basis',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      color:
                                          theme.colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '$_businessUsePct% of ${_currencyFmt.format(_currentAmount)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onPrimaryContainer
                                          .withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                _currencyFmt.format(_calculatedDeductible),
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Deductible Percentage Presets ──
                Text(
                  'Business Use Percentage',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildPresetPill(100, '100% Work'),
                    _buildPresetPill(80, '80%'),
                    _buildPresetPill(50, '50%'),
                    _buildCustomPill(),
                  ],
                ),
                if (_isCustomPct) ...[
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _customPctCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(3),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Custom Percentage (0 - 100%)',
                      suffixText: '%',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      isDense: true,
                    ),
                    onChanged: (v) {
                      final val = int.tryParse(v);
                      if (val != null) {
                        setState(() {
                          _businessUsePct = val.clamp(0, 100);
                        });
                      }
                    },
                  ),
                ],
                const SizedBox(height: 20),

                // ── Category & Schedule C Mapping ──
                Text(
                  'Tax Category (Schedule C)',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategoryId,
                  isExpanded: true,
                  itemHeight: null,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.account_balance_outlined),
                    helperText:
                        'Mapped to IRS Schedule C line item for reporting',
                  ),
                  selectedItemBuilder: (context) {
                    return categories.map((c) {
                      return Text(
                        '${c.name} (${c.irsScheduleCLine})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      );
                    }).toList();
                  },
                  items: categories.map((c) {
                    return DropdownMenuItem(
                      value: c.id,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              c.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              c.irsScheduleCLine,
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCategoryId = val;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),

                // ── Title & Vendor ──
                TextFormField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    labelText: 'Expense Description *',
                    hintText: 'e.g., Mechanical Keyboard, Cloud Hosting',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.shopping_bag_outlined),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Please enter a description'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vendorCtrl,
                  decoration: InputDecoration(
                    labelText: 'Vendor / Merchant',
                    hintText: 'e.g., Apple, Best Buy, AWS',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    prefixIcon: const Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Date Picker ──
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  leading: const Icon(Icons.calendar_today_outlined),
                  title: const Text('Transaction Date'),
                  subtitle: Text(DateFormat.yMMMd().format(_date)),
                  trailing: const Icon(Icons.arrow_drop_down),
                  onTap: _selectDate,
                ),
                const SizedBox(height: 12),

                // ── Notes ──
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Notes / Audit Justification (Optional)',
                    hintText: 'e.g. Needed for Client X backend integration',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPresetPill(int pct, String label) {
    final isSelected = !_isCustomPct && _businessUsePct == pct;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _onPresetTapped(pct),
    );
  }

  Widget _buildCustomPill() {
    return ChoiceChip(
      label: Text(_isCustomPct ? '$_businessUsePct%' : 'Custom'),
      selected: _isCustomPct,
      onSelected: (_) => _onCustomTapped(),
    );
  }

  Widget _buildReceiptPreview(ThemeData theme) {
    final hasReceipt = _receiptPath != null && _receiptPath!.isNotEmpty;

    if (!hasReceipt) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            style: BorderStyle.solid,
          ),
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.2,
          ),
        ),
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 44,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              'Attach Receipt for Audit Defense',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Compressed automatically for offline storage',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pickReceipt(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Camera'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () => _pickReceipt(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Gallery'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              GestureDetector(
                onTap: _showReceiptFullscreen,
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: kIsWeb
                          ? Image.network(
                              _receiptPath!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Center(
                                child: Icon(Icons.broken_image, size: 48),
                              ),
                            )
                          : Image.file(
                              File(_receiptPath!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  const Center(
                                child: Icon(Icons.broken_image, size: 48),
                              ),
                            ),
                    ),
                    Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in, color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text(
                            'Tap to preview',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon:
                        const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: _removeReceipt,
                    tooltip: 'Remove Receipt',
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Receipt Attached',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton.icon(
                  onPressed: _showReceiptFullscreen,
                  icon: const Icon(Icons.fullscreen, size: 18),
                  label: const Text('View Full'),
                ),
                TextButton.icon(
                  onPressed: () => _pickReceipt(ImageSource.camera),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Replace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

