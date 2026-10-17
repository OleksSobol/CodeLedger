import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../shared/widgets/responsive_layout.dart';
import '../providers/invoice_providers.dart';
import '../widgets/invoice_status_badge.dart';
import '../widgets/record_payment_dialog.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../pdf_generation/presentation/pages/pdf_preview_page.dart';

class InvoicesListPage extends ConsumerStatefulWidget {
  const InvoicesListPage({super.key});

  @override
  ConsumerState<InvoicesListPage> createState() => _InvoicesListPageState();
}

class _InvoicesListPageState extends ConsumerState<InvoicesListPage> {
  final TextEditingController _searchCtrl = TextEditingController();

  static const _statusKeys = [
    null,
    'draft',
    'sent',
    'paid',
    'overdue',
    'archived',
  ];
  static const _statusLabels = [
    'All',
    'Draft',
    'Sent',
    'Paid',
    'Overdue',
    'Archived',
  ];

  @override
  void initState() {
    super.initState();
    _searchCtrl.text = ref.read(invoiceSearchQueryProvider);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    ref.read(invoiceSearchQueryProvider.notifier).set(query);
  }

  void _clearSearch() {
    _searchCtrl.clear();
    ref.read(invoiceSearchQueryProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(filteredInvoicesProvider);
    final currentFilter = ref.watch(invoiceStatusFilterProvider);
    final statusCounts = ref.watch(invoiceStatusCountsProvider);
    final metrics = ref.watch(invoiceMetricsSummaryProvider);
    final currentSort = ref.watch(invoiceSortOrderProvider);
    final searchQuery = ref.watch(invoiceSearchQueryProvider);
    final theme = Theme.of(context);

    final draftCount = metrics.draftCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices'),
        actions: [
          // Sort Menu
          PopupMenuButton<InvoiceSortOrder>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: 'Sort Invoices',
            onSelected: (order) {
              ref.read(invoiceSortOrderProvider.notifier).set(order);
            },
            itemBuilder: (context) {
              return InvoiceSortOrder.values.map((order) {
                final isSelected = order == currentSort;
                return PopupMenuItem<InvoiceSortOrder>(
                  value: order,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check : Icons.circle_outlined,
                        size: 18,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        order.label,
                        style: TextStyle(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? theme.colorScheme.primary : null,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
          ),
          // Send Invoices shortcut
          IconButton(
            tooltip: draftCount > 0
                ? '$draftCount draft${draftCount == 1 ? '' : 's'} ready to send'
                : 'Send Invoices',
            icon: Badge(
              isLabelVisible: draftCount > 0,
              label: Text('$draftCount'),
              child: const Icon(Icons.outgoing_mail),
            ),
            onPressed: () => context.push('/invoices/send'),
          ),
        ],
      ),
      floatingActionButton: _NewInvoiceFab(),
      body: ResponsiveAlign(
        child: Column(
          children: [
            // ── Financial Metrics Overview Strip ───────────────────
            _MetricsHeader(
              metrics: metrics,
              currentFilter: currentFilter,
              onFilterSelect: (filter) {
                ref
                    .read(invoiceStatusFilterProvider.notifier)
                    .set(currentFilter == filter ? null : filter);
              },
            ),

            // ── Search Bar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Search invoices or clients...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: _clearSearch,
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),

            // ── Status Filter Chips with Live Counts ───────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: List.generate(_statusKeys.length, (i) {
                  final key = _statusKeys[i];
                  final label = _statusLabels[i];
                  final count = statusCounts[key] ?? 0;
                  final isSelected = currentFilter == key;
                  final isOverdue = key == 'overdue' && count > 0;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text('$label ($count)'),
                      selected: isSelected,
                      avatar: isOverdue && !isSelected
                          ? Icon(
                              Icons.warning_amber_rounded,
                              size: 16,
                              color: theme.colorScheme.error,
                            )
                          : null,
                      side: isOverdue && !isSelected
                          ? BorderSide(
                              color: theme.colorScheme.error.withValues(alpha: 0.5),
                            )
                          : null,
                      onSelected: (_) {
                        ref
                            .read(invoiceStatusFilterProvider.notifier)
                            .set(key);
                      },
                    ),
                  );
                }),
              ),
            ),

            const SizedBox(height: 4),

            // ── Invoices List ──────────────────────────────────────
            Expanded(
              child: invoicesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (invoices) {
                  if (invoices.isEmpty) {
                    return _EmptyInvoicesView(
                      hasSearch: searchQuery.isNotEmpty,
                      searchQuery: searchQuery,
                      currentFilter: currentFilter,
                      onClearSearch: _clearSearch,
                      onClearFilter: () {
                        ref
                            .read(invoiceStatusFilterProvider.notifier)
                            .set(null);
                      },
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                    itemCount: invoices.length,
                    itemBuilder: (context, index) {
                      return _InvoiceCard(invoice: invoices[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Financial Metrics Header ──────────────────────────────────────────
class _MetricsHeader extends StatelessWidget {
  final InvoiceMetricsSummary metrics;
  final String? currentFilter;
  final ValueChanged<String> onFilterSelect;

  const _MetricsHeader({
    required this.metrics,
    required this.currentFilter,
    required this.onFilterSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          // Outstanding
          Expanded(
            child: _MetricCard(
              title: 'Outstanding',
              amount: formatCurrency(metrics.totalOutstanding),
              subtitle: '${metrics.outstandingCount} unpaid',
              icon: Icons.pending_actions_rounded,
              color: theme.colorScheme.primary,
              isSelected: currentFilter == 'sent',
              onTap: () => onFilterSelect('sent'),
            ),
          ),
          const SizedBox(width: 8),
          // Overdue
          Expanded(
            child: _MetricCard(
              title: 'Overdue',
              amount: metrics.overdueCount > 0
                  ? formatCurrency(metrics.totalOverdue)
                  : 'None',
              subtitle: '${metrics.overdueCount} overdue',
              icon: Icons.warning_amber_rounded,
              color: metrics.overdueCount > 0
                  ? theme.colorScheme.error
                  : theme.colorScheme.outline,
              isSelected: currentFilter == 'overdue',
              onTap: () => onFilterSelect('overdue'),
            ),
          ),
          const SizedBox(width: 8),
          // Paid
          Expanded(
            child: _MetricCard(
              title: 'Paid',
              amount: formatCurrency(metrics.totalPaid),
              subtitle: '${metrics.paidCount} paid',
              icon: Icons.check_circle_outline_rounded,
              color: Colors.green,
              isSelected: currentFilter == 'paid',
              onTap: () => onFilterSelect('paid'),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String amount;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _MetricCard({
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.15)
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              amount,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected ? color : null,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 10,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overhauled Invoice Card ───────────────────────────────────────────
class _InvoiceCard extends ConsumerWidget {
  final Invoice invoice;

  const _InvoiceCard({required this.invoice});

  void _openPdf(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PdfPreviewPage(
          invoiceId: invoice.id,
          invoiceNumber: invoice.invoiceNumber,
        ),
      ),
    );
  }

  Future<void> _recordPayment(BuildContext context, double balanceDue) async {
    await showDialog<bool>(
      context: context,
      builder: (ctx) => RecordPaymentDialog(
        invoiceId: invoice.id,
        balanceDue: balanceDue,
        currency: invoice.currency,
        invoice: invoice,
      ),
    );
  }

  Future<void> _markSent(BuildContext context, WidgetRef ref) async {
    await ref
        .read(invoiceNotifierProvider.notifier)
        .updateStatus(invoice.id, 'sent');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Invoice ${invoice.invoiceNumber} marked sent')),
      );
    }
  }

  Future<void> _deleteInvoice(
    BuildContext context,
    WidgetRef ref,
    bool isDraft,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDraft ? 'Delete Draft' : 'Delete Invoice'),
        content: Text(
          isDraft
              ? 'Permanently delete draft ${invoice.invoiceNumber}? Linked time entries will be unmarked.'
              : 'Permanently delete ${invoice.invoiceNumber}? Linked time entries will be unmarked.',
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

    if (confirmed == true && context.mounted) {
      if (isDraft) {
        await ref
            .read(invoiceNotifierProvider.notifier)
            .deleteDraft(invoice.id);
      } else {
        await ref
            .read(invoiceNotifierProvider.notifier)
            .deleteInvoice(invoice.id);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd();
    final clientAsync = ref.watch(clientByIdProvider(invoice.clientId));
    final clientName = clientAsync.whenOrNull(data: (c) => c.name) ?? 'Loading...';

    final balanceDue = invoice.total - invoice.amountPaid;
    final isDraft = invoice.status == 'draft';
    final isPaid = invoice.status == 'paid';
    final isArchived = invoice.status == 'archived';

    // Due date calculation
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dueDay = DateTime(
      invoice.dueDate.year,
      invoice.dueDate.month,
      invoice.dueDate.day,
    );
    final diffDays = dueDay.difference(today).inDays;
    final isOverdue =
        invoice.status == 'overdue' ||
        (invoice.status == 'sent' && diffDays < 0);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/invoices/${invoice.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Client Name and Status Badge
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      clientName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  InvoiceStatusBadge(
                    status: isOverdue ? 'overdue' : invoice.status,
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Middle Row: Invoice # and Timing status
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      invoice.invoiceNumber,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('·', style: TextStyle(color: Colors.grey)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildTimingText(
                      theme,
                      dateFmt,
                      isOverdue,
                      diffDays,
                      isDraft,
                      isPaid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Amounts Row: Total & Balance Due
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    formatCurrency(invoice.total, currency: invoice.currency),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (balanceDue > 0 && !isDraft) ...[
                    const SizedBox(width: 12),
                    Text(
                      'Due: ${formatCurrency(balanceDue, currency: invoice.currency)}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isOverdue
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 6),

              // Quick Actions Row
              Row(
                children: [
                  // Primary contextual action button
                  if (isDraft)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Mark Sent'),
                      onPressed: () => _markSent(context, ref),
                    )
                  else if (!isPaid && !isArchived && balanceDue > 0)
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.payment_rounded, size: 16),
                      label: const Text('Record Payment'),
                      onPressed: () => _recordPayment(context, balanceDue),
                    )
                  else if (isPaid)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('View PDF'),
                      onPressed: () => _openPdf(context),
                    )
                  else if (isArchived)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.unarchive_outlined, size: 16),
                      label: const Text('Unarchive'),
                      onPressed: () async {
                        await ref
                            .read(invoiceNotifierProvider.notifier)
                            .unarchiveInvoice(invoice.id);
                      },
                    ),

                  const Spacer(),

                  // Quick PDF icon button
                  IconButton(
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                    tooltip: 'View PDF Preview',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openPdf(context),
                  ),

                  // 3-dots Context Menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    tooltip: 'More actions',
                    onSelected: (value) async {
                      switch (value) {
                        case 'details':
                          context.push('/invoices/${invoice.id}');
                          break;
                        case 'pdf':
                          _openPdf(context);
                          break;
                        case 'payment':
                          await _recordPayment(context, balanceDue);
                          break;
                        case 'edit':
                          context.push(
                            '/invoices/${invoice.id}/edit',
                            extra: invoice,
                          );
                          break;
                        case 'add_time':
                          context.push(
                            '/invoices/${invoice.id}/add-time',
                            extra: invoice,
                          );
                          break;
                        case 'reopen':
                          await ref
                              .read(invoiceNotifierProvider.notifier)
                              .revertToDraft(invoice.id);
                          break;
                        case 'archive':
                          await ref
                              .read(invoiceNotifierProvider.notifier)
                              .archiveInvoice(invoice.id);
                          break;
                        case 'unarchive':
                          await ref
                              .read(invoiceNotifierProvider.notifier)
                              .unarchiveInvoice(invoice.id);
                          break;
                        case 'delete':
                          await _deleteInvoice(context, ref, isDraft);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'details',
                        child: Row(
                          children: [
                            Icon(Icons.visibility_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('View Details'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'pdf',
                        child: Row(
                          children: [
                            Icon(Icons.picture_as_pdf_outlined, size: 18),
                            SizedBox(width: 8),
                            Text('View PDF'),
                          ],
                        ),
                      ),
                      if (isDraft) ...[
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Edit Draft'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'add_time',
                          child: Row(
                            children: [
                              Icon(Icons.add_circle_outline, size: 18),
                              SizedBox(width: 8),
                              Text('Add Time Entries'),
                            ],
                          ),
                        ),
                      ],
                      if (!isDraft && !isPaid && !isArchived) ...[
                        const PopupMenuItem(
                          value: 'payment',
                          child: Row(
                            children: [
                              Icon(Icons.payment, size: 18),
                              SizedBox(width: 8),
                              Text('Record Payment'),
                            ],
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'reopen',
                          child: Row(
                            children: [
                              Icon(Icons.replay, size: 18),
                              SizedBox(width: 8),
                              Text('Reopen as Draft'),
                            ],
                          ),
                        ),
                      ],
                      if (isPaid)
                        const PopupMenuItem(
                          value: 'archive',
                          child: Row(
                            children: [
                              Icon(Icons.archive_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Archive Invoice'),
                            ],
                          ),
                        ),
                      if (isArchived)
                        const PopupMenuItem(
                          value: 'unarchive',
                          child: Row(
                            children: [
                              Icon(Icons.unarchive_outlined, size: 18),
                              SizedBox(width: 8),
                              Text('Unarchive Invoice'),
                            ],
                          ),
                        ),
                      const PopupMenuDivider(),
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Delete',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimingText(
    ThemeData theme,
    DateFormat dateFmt,
    bool isOverdue,
    int diffDays,
    bool isDraft,
    bool isPaid,
  ) {
    if (isOverdue) {
      final days = diffDays.abs();
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, size: 14, color: theme.colorScheme.error),
          const SizedBox(width: 4),
          Text(
            'Overdue by $days day${days == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    }

    if (isPaid) {
      return Text(
        'Paid on ${dateFmt.format(invoice.paidDate ?? invoice.updatedAt)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.green,
          fontWeight: FontWeight.w500,
        ),
      );
    }

    if (isDraft) {
      return Text(
        'Created ${dateFmt.format(invoice.issueDate)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    if (diffDays == 0) {
      return Text(
        'Due today',
        style: theme.textTheme.bodySmall?.copyWith(
          color: Colors.orange.shade800,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Text(
      'Due in $diffDays day${diffDays == 1 ? '' : 's'} (${dateFmt.format(invoice.dueDate)})',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ── Empty Invoices State ──────────────────────────────────────────────
class _EmptyInvoicesView extends StatelessWidget {
  final bool hasSearch;
  final String searchQuery;
  final String? currentFilter;
  final VoidCallback onClearSearch;
  final VoidCallback onClearFilter;

  const _EmptyInvoicesView({
    required this.hasSearch,
    required this.searchQuery,
    required this.currentFilter,
    required this.onClearSearch,
    required this.onClearFilter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (hasSearch) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off_outlined,
                size: 64,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'No invoices matching "$searchQuery"',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text('Try adjusting your search terms or filters.'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onClearSearch,
                icon: const Icon(Icons.clear),
                label: const Text('Clear Search'),
              ),
            ],
          ),
        ),
      );
    }

    if (currentFilter != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.filter_list_off_outlined,
                size: 64,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                'No ${currentFilter!} invoices',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text('There are no invoices with this status.'),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onClearFilter,
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text('View All Invoices'),
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text('No invoices yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Bill your tracked client time or create a manual invoice directly.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => context.push('/invoices/create'),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('From Billable Hours'),
                ),
                OutlinedButton.icon(
                  onPressed: () => context.push('/invoices/manual'),
                  icon: const Icon(Icons.edit_note),
                  label: const Text('Manual Entry'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Floating Action Button & Menu ─────────────────────────────────────
class _NewInvoiceFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      onPressed: () => _showMenu(context),
      icon: const Icon(Icons.add),
      label: const Text('New Invoice'),
      tooltip: 'Create New Invoice',
    );
  }

  void _showMenu(BuildContext context) {
    final theme = Theme.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create Invoice',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.timer_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                title: const Text('From Billable Hours'),
                subtitle: const Text('Select tracked client time to invoice'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/invoices/create');
                },
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.edit_note_rounded,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
                title: const Text('Manual Invoice'),
                subtitle: const Text('Enter custom line items and rates'),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/invoices/manual');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
