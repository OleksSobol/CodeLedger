import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/tax_bank_split.dart';
import '../providers/invoice_providers.dart';

/// Dialog to record a payment against an invoice.
/// Returns `true` if a payment was recorded.
class RecordPaymentDialog extends ConsumerStatefulWidget {
  final String invoiceId;
  final double balanceDue;
  final String currency;
  final Invoice? invoice;

  const RecordPaymentDialog({
    super.key,
    required this.invoiceId,
    required this.balanceDue,
    this.currency = 'USD',
    this.invoice,
  });

  @override
  ConsumerState<RecordPaymentDialog> createState() =>
      _RecordPaymentDialogState();
}

class _RecordPaymentDialogState extends ConsumerState<RecordPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountCtrl;
  String _method = 'ACH';
  bool _saving = false;

  static const _methods = ['ACH', 'Stripe', 'Other'];

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
      text: widget.balanceDue.toStringAsFixed(2),
    );
    _amountCtrl.addListener(_onAmountChanged);
  }

  void _onAmountChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _amountCtrl.removeListener(_onAmountChanged);
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(invoiceNotifierProvider.notifier)
          .recordPayment(
            invoiceId: widget.invoiceId,
            amount: double.parse(_amountCtrl.text.trim()),
            method: _method,
          );
      if (mounted) Navigator.of(context).pop(true);
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
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Record Payment'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Balance due: ${formatCurrency(widget.balanceDue, currency: widget.currency)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.tertiary,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amountCtrl,
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter an amount';
                final amount = double.tryParse(v);
                if (amount == null || amount <= 0) {
                  return 'Enter a valid amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(
                labelText: 'Payment Method',
                border: OutlineInputBorder(),
              ),
              items: _methods
                  .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _method = v);
              },
            ),
            if (widget.invoice != null) ...[
              const SizedBox(height: 16),
              Builder(
                builder: (context) {
                  final enteredAmount =
                      double.tryParse(_amountCtrl.text.trim()) ??
                      widget.balanceDue;
                  final split = TaxBankSplit.calculate(
                    subtotal: widget.invoice!.subtotal,
                    taxAmount: widget.invoice!.taxAmount,
                    taxRate: widget.invoice!.taxRate,
                    taxLabel: widget.invoice!.taxLabel,
                    federalTaxRate: ref.watch(bankSplitFederalTaxRateProvider),
                    lateFeeAmount: widget.invoice!.lateFeeAmount,
                    total: widget.invoice!.total,
                    paymentAmount: enteredAmount > 0 ? enteredAmount : null,
                  );

                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.5),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.account_balance,
                              size: 15,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Bank Deposit Split (DEV-78)',
                              style: theme.textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (split.salesTaxAmount > 0)
                          _splitRow(
                            '${split.taxLabel} (${split.taxRate.toStringAsFixed(1)}%):',
                            formatCurrency(
                              split.salesTaxAmount,
                              currency: widget.currency,
                            ),
                          ),
                        _splitRow(
                          'Federal Tax (${split.federalTaxRate.toStringAsFixed(1)}%):',
                          formatCurrency(
                            split.federalTaxAmount,
                            currency: widget.currency,
                          ),
                        ),
                        const Divider(height: 12),
                        _splitRow(
                          'Operating / Take-Home:',
                          formatCurrency(
                            split.takeHomeAmount,
                            currency: widget.currency,
                          ),
                          isBold: true,
                          color: Colors.green.shade800,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Record Payment'),
        ),
      ],
    );
  }

  Widget _splitRow(
    String label,
    String value, {
    bool isBold = false,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
