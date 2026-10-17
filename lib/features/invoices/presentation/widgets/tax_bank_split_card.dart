import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../domain/entities/tax_bank_split.dart';
import '../providers/invoice_providers.dart';

/// Interactive card on InvoiceDetailPage showing the recommended bank account split
/// for sales tax, federal tax reserve, and operating/take-home funds. (DEV-78)
class TaxBankSplitCard extends ConsumerWidget {
  final Invoice invoice;

  const TaxBankSplitCard({
    super.key,
    required this.invoice,
  });

  void _copyToClipboard(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label copied to clipboard'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showCustomRateDialog(
    BuildContext context,
    WidgetRef ref,
    double currentRate,
  ) async {
    final controller = TextEditingController(
      text: currentRate.toStringAsFixed(1),
    );
    final formKey = GlobalKey<FormState>();

    final picked = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom Federal Tax Rate'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Tax Rate (%)',
              suffixText: '%',
              border: OutlineInputBorder(),
              helperText: 'Recommended: 15% - 30% for self-employed',
            ),
            autofocus: true,
            validator: (val) {
              final parsed = double.tryParse(val?.trim() ?? '');
              if (parsed == null || parsed < 0 || parsed > 100) {
                return 'Enter a valid percentage between 0 and 100';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                final rate = double.parse(controller.text.trim());
                Navigator.of(ctx).pop(rate);
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (picked != null) {
      ref.read(bankSplitFederalTaxRateProvider.notifier).setRate(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final split = ref.watch(invoiceBankSplitProvider(invoice));
    final fedRate = split.federalTaxRate;
    final currency = invoice.currency;

    final presetRates = [15.0, 20.0, 25.0, 30.0];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Icon(
                  Icons.account_balance,
                  size: 22,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bank Account Tax Split',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'How to divide payment into bank accounts',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Copy all transfer notes',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: () {
                    final summary = split.toClipboardSummary(
                      invoiceNumber: invoice.invoiceNumber,
                      currency: currency,
                    );
                    _copyToClipboard(context, summary, 'Bank transfer summary');
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Federal Tax Rate selector row
            Row(
              children: [
                Text(
                  'Federal Rate:',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final rate in presetRates) ...[
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text('${rate.toInt()}%'),
                              selected: (fedRate - rate).abs() < 0.1,
                              onSelected: (selected) {
                                if (selected) {
                                  ref
                                      .read(bankSplitFederalTaxRateProvider.notifier)
                                      .setRate(rate);
                                }
                              },
                              labelStyle: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: (fedRate - rate).abs() < 0.1
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                        ActionChip(
                          avatar: const Icon(Icons.tune, size: 14),
                          label: Text(
                            presetRates.any((r) => (r - fedRate).abs() < 0.1)
                                ? 'Custom'
                                : '${fedRate.toStringAsFixed(1)}%',
                          ),
                          onPressed: () => _showCustomRateDialog(
                            context,
                            ref,
                            fedRate,
                          ),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Sales Tax Account
            if (split.salesTaxAmount > 0) ...[
              _SplitItemRow(
                icon: Icons.receipt_long,
                iconColor: Colors.orange.shade700,
                iconBgColor: Colors.orange.withValues(alpha: 0.12),
                label: '${invoice.taxLabel} Account',
                rateSubtitle: '${split.taxRate.toStringAsFixed(1)}% state/local tax',
                amountText: formatCurrency(
                  split.salesTaxAmount,
                  currency: currency,
                ),
                onCopy: () => _copyToClipboard(
                  context,
                  split.salesTaxAmount.toStringAsFixed(2),
                  'Sales tax amount',
                ),
              ),
              const SizedBox(height: 10),
            ],

            // 2. Federal Tax Account
            _SplitItemRow(
              icon: Icons.shield_outlined,
              iconColor: Colors.blue.shade700,
              iconBgColor: Colors.blue.withValues(alpha: 0.12),
              label: 'Federal Tax Account',
              rateSubtitle:
                  '${split.federalTaxRate.toStringAsFixed(1)}% estimated income/SE',
              amountText: formatCurrency(
                split.federalTaxAmount,
                currency: currency,
              ),
              onCopy: () => _copyToClipboard(
                context,
                split.federalTaxAmount.toStringAsFixed(2),
                'Federal tax amount',
              ),
            ),
            const SizedBox(height: 12),

            // Total tax reserve banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_clock_outlined,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Total Tax to Move',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    formatCurrency(
                      split.totalTaxReserve,
                      currency: currency,
                    ),
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 14),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                    tooltip: 'Copy tax reserve sum',
                    onPressed: () => _copyToClipboard(
                      context,
                      split.totalTaxReserve.toStringAsFixed(2),
                      'Total tax reserve',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 3. Operating / Take-Home Account
            _SplitItemRow(
              icon: Icons.account_balance_wallet,
              iconColor: Colors.green.shade700,
              iconBgColor: Colors.green.withValues(alpha: 0.12),
              label: 'Operating / Take-Home',
              rateSubtitle: 'Safe to spend or invest in business',
              amountText: formatCurrency(
                split.takeHomeAmount,
                currency: currency,
              ),
              amountColor: Colors.green.shade800,
              isProminent: true,
              onCopy: () => _copyToClipboard(
                context,
                split.takeHomeAmount.toStringAsFixed(2),
                'Take-home amount',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SplitItemRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBgColor;
  final String label;
  final String rateSubtitle;
  final String amountText;
  final Color? amountColor;
  final bool isProminent;
  final VoidCallback onCopy;

  const _SplitItemRow({
    required this.icon,
    required this.iconColor,
    required this.iconBgColor,
    required this.label,
    required this.rateSubtitle,
    required this.amountText,
    this.amountColor,
    this.isProminent = false,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isProminent
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isProminent
              ? theme.colorScheme.primary.withValues(alpha: 0.3)
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        isProminent ? FontWeight.bold : FontWeight.w600,
                  ),
                ),
                Text(
                  rateSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountText,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: amountColor ?? theme.textTheme.titleMedium?.color,
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.copy, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            tooltip: 'Copy amount',
            onPressed: onCopy,
          ),
        ],
      ),
    );
  }
}
