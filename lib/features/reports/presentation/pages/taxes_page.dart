import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../export/presentation/providers/export_providers.dart';
import '../../../invoices/presentation/providers/invoice_providers.dart';
import '../../../profile/presentation/providers/profile_provider.dart';
import '../../data/models/tax_report_data.dart';
import '../../data/templates/tax_report_template.dart';

// ── Receipts model (stored as JSON via AppSettingsDao) ─────────────────────────

class _Receipt {
  final String id;
  final String date;
  final String description;
  final String category;
  final double amount;

  const _Receipt({
    required this.id,
    required this.date,
    required this.description,
    required this.category,
    required this.amount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'desc': description,
        'cat': category,
        'amount': amount,
      };

  factory _Receipt.fromJson(Map<String, dynamic> j) => _Receipt(
        id: j['id'] as String,
        date: j['date'] as String,
        description: j['desc'] as String,
        category: j['cat'] as String,
        amount: (j['amount'] as num).toDouble(),
      );
}

const _kReceiptsKey = 'tax_receipts';

const _receiptCategories = [
  'Office Supplies',
  'Software / Subscriptions',
  'Hardware / Equipment',
  'Home Office',
  'Professional Services',
  'Travel',
  'Education / Training',
  'Marketing',
  'Other',
];

// ── Page ───────────────────────────────────────────────────────────────────────

class TaxesPage extends ConsumerStatefulWidget {
  const TaxesPage({super.key});

  @override
  ConsumerState<TaxesPage> createState() => _TaxesPageState();
}

class _TaxesPageState extends ConsumerState<TaxesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Shared date/client filter
  DateTimeRange? _dateRange;
  int? _selectedClientId;
  bool _includeArchived = false;
  bool _isLoading = false;

  // Receipts
  List<_Receipt> _receipts = [];

  // Quarterly tax estimation
  bool _showTaxRateSettings = false;
  double _federalRate = 0.22;
  double _seRate = 0.153;
  final _federalRateCtrl = TextEditingController(text: '22.0');
  final _seRateCtrl = TextEditingController(text: '15.3');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, 1, 1),
      end: DateTime(now.year, 12, 31),
    );
    _loadReceipts();
    _loadTaxRates();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _federalRateCtrl.dispose();
    _seRateCtrl.dispose();
    super.dispose();
  }

  // ── Receipts persistence ─────────────────────────────────────────────────────

  Future<void> _loadReceipts() async {
    final dao = ref.read(appSettingsDaoProvider);
    final raw = await dao.getValue(_kReceiptsKey);
    if (raw != null && mounted) {
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .map((e) => _Receipt.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() => _receipts = list);
      } catch (_) {}
    }
  }

  Future<void> _saveReceipts() async {
    final dao = ref.read(appSettingsDaoProvider);
    await dao.setValue(
        _kReceiptsKey, jsonEncode(_receipts.map((r) => r.toJson()).toList()));
  }

  // ── Tax rate settings ─────────────────────────────────────────────────────────

  Future<void> _loadTaxRates() async {
    final dao = ref.read(appSettingsDaoProvider);
    final fed = await dao.getValue('tax.federal_rate');
    final se = await dao.getValue('tax.se_rate');
    if (!mounted) return;
    setState(() {
      if (fed != null) {
        _federalRate = double.tryParse(fed) ?? 0.22;
        _federalRateCtrl.text = (_federalRate * 100).toStringAsFixed(1);
      }
      if (se != null) {
        _seRate = double.tryParse(se) ?? 0.153;
        _seRateCtrl.text = (_seRate * 100).toStringAsFixed(1);
      }
    });
  }

  Future<void> _saveTaxRates() async {
    final fed = (double.tryParse(_federalRateCtrl.text) ?? 22.0) / 100;
    final se = (double.tryParse(_seRateCtrl.text) ?? 15.3) / 100;
    final dao = ref.read(appSettingsDaoProvider);
    await dao.setValue('tax.federal_rate', fed.toString());
    await dao.setValue('tax.se_rate', se.toString());
  }

  double _incomeForRange(List<Invoice> invoices, DateTime start, DateTime end) {
    double total = 0;
    for (final inv in invoices) {
      final validStatus = inv.status == 'paid' ||
          (_includeArchived && inv.status == 'archived');
      if (!validStatus) continue;
      final reportDate = inv.paidDate ?? inv.issueDate;
      if (reportDate.isBefore(start)) continue;
      if (!reportDate.isBefore(end)) continue;
      if (_selectedClientId != null && inv.clientId != _selectedClientId) {
        continue;
      }
      total += inv.subtotal;
    }
    return total;
  }

  // ── Filters ──────────────────────────────────────────────────────────────────

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  // ── Tax report helpers ────────────────────────────────────────────────────────

  Future<TaxReportData?> _fetchTaxData() async {
    if (_dateRange == null) return null;

    final profileDao = ref.read(userProfileDaoProvider);
    final clientDao = ref.read(clientDaoProvider);
    final profile = await profileDao.getProfile();

    final allInvoices = ref.read(allInvoicesProvider).value ?? [];
    final endOfDay = DateTime(
      _dateRange!.end.year,
      _dateRange!.end.month,
      _dateRange!.end.day,
      23, 59, 59,
    );

    final filtered = allInvoices.where((inv) {
      final validStatus = inv.status == 'paid' ||
          (_includeArchived && inv.status == 'archived');
      if (!validStatus) return false;
      final reportDate = inv.paidDate ?? inv.issueDate;
      if (reportDate.isBefore(_dateRange!.start)) return false;
      if (reportDate.isAfter(endOfDay)) return false;
      if (_selectedClientId != null && inv.clientId != _selectedClientId) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.issueDate.compareTo(b.issueDate));

    final names = <int, String>{};
    for (final inv in filtered) {
      if (!names.containsKey(inv.clientId)) {
        try {
          names[inv.clientId] =
              (await clientDao.getClient(inv.clientId)).name;
        } catch (_) {
          names[inv.clientId] = 'Unknown Client';
        }
      }
    }

    return TaxReportData(
      profile: profile,
      startDate: _dateRange!.start,
      endDate: _dateRange!.end,
      rows: filtered
          .map((inv) =>
              TaxReportRow(invoice: inv, clientName: names[inv.clientId]!))
          .toList(),
      clientFilterName:
          _selectedClientId != null ? names[_selectedClientId] : null,
    );
  }

  Future<void> _generatePdf() async {
    setState(() => _isLoading = true);
    try {
      final data = await _fetchTaxData();
      if (data == null || !mounted) return;
      if (data.rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_includeArchived
                ? 'No paid or archived invoices in the selected period.'
                : 'No paid invoices in the selected period.')));
        return;
      }
      final bytes = await (await const TaxReportTemplate().build(data)).save();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _PdfPreviewPage(pdfBytes: bytes),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _isLoading = true);
    try {
      final data = await _fetchTaxData();
      if (data == null || !mounted) return;
      if (data.rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_includeArchived
                ? 'No paid or archived invoices in the selected period.'
                : 'No paid invoices in the selected period.')));
        return;
      }
      final exportService = ref.read(exportServiceProvider);
      final file =
          await exportService.generateTaxReportCsv(rows: data.rows);
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Federal Tax Report',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Taxes'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Federal'),
            Tab(text: 'State / Local'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildFederalTab(),
          _buildStateTab(),
        ],
      ),
    );
  }

  // ── Federal tab ──────────────────────────────────────────────────────────────

  Widget _buildFederalTab() {
    final clientsAsync = ref.watch(activeClientsProvider);
    final theme = Theme.of(context);

    // Live income/tax totals from allInvoicesProvider
    final allInvoices = ref.watch(allInvoicesProvider).value ?? [];
    final endOfDay = _dateRange == null
        ? DateTime.now()
        : DateTime(
            _dateRange!.end.year,
            _dateRange!.end.month,
            _dateRange!.end.day,
            23, 59, 59);
    double totalNet = 0;
    double totalTax = 0;
    double totalPaid = 0;
    for (final inv in allInvoices) {
      final validStatus = inv.status == 'paid' ||
          (_includeArchived && inv.status == 'archived');
      if (!validStatus) continue;
      if (_dateRange != null) {
        final reportDate = inv.paidDate ?? inv.issueDate;
        if (reportDate.isBefore(_dateRange!.start)) continue;
        if (reportDate.isAfter(endOfDay)) continue;
      }
      if (_selectedClientId != null && inv.clientId != _selectedClientId) {
        continue;
      }
      totalNet += inv.subtotal;
      totalTax += inv.taxAmount ?? 0;
      totalPaid += inv.total;
    }

    final cur = NumberFormat.currency(symbol: '\$');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Filters ────────────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filters', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDateRange,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tax Year / Period',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.date_range),
                    ),
                    child: Text(
                      _dateRange == null
                          ? 'Select dates'
                          : '${_fmt(_dateRange!.start)} - ${_fmt(_dateRange!.end)}',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                clientsAsync.when(
                  data: (clients) => InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Client (optional)',
                      border: OutlineInputBorder(),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: _selectedClientId,
                        isDense: true,
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('All Clients')),
                          ...clients.map((c) => DropdownMenuItem(
                                value: c.id,
                                child: Text(c.name),
                              )),
                        ],
                        onChanged: (val) =>
                            setState(() => _selectedClientId = val),
                      ),
                    ),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, __) => const Text('Error loading clients'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _includeArchived,
                  onChanged: (v) =>
                      setState(() => _includeArchived = v ?? false),
                  title: const Text('Include archived invoices'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Live income summary ────────────────────────────────────────────
        Card(
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Income Summary',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _SummaryRow('Net (pre-tax)',
                    cur.format(totalNet), theme),
                _SummaryRow('Tax collected',
                    cur.format(totalTax), theme),
                const Divider(height: 16),
                _SummaryRow('Total received',
                    cur.format(totalPaid), theme, bold: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Quarterly estimated taxes ──────────────────────────────────────
        _buildQuarterlyCards(theme, allInvoices, cur),
        const SizedBox(height: 12),

        // ── Tax rate settings ──────────────────────────────────────────────
        _buildTaxRateSettings(theme),
        const SizedBox(height: 12),

        // ── Report actions ─────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Income Tax Report',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Net income, tax collected, and total paid '
                  'for all paid invoices in the selected period.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isLoading ? null : _generatePdf,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Generate PDF'),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _exportCsv,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Export CSV'),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Deductible expenses ────────────────────────────────────────────
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Deductible Expenses',
                              style: theme.textTheme.titleSmall),
                          const SizedBox(height: 2),
                          Text(
                            'Track business expenses for Schedule C / deductions.',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add expense',
                      onPressed: () => _showAddReceiptDialog(),
                    ),
                  ],
                ),
                if (_receipts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No expenses recorded yet.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: 8),
                  ..._receipts.map((r) => _buildReceiptTile(r, theme, cur)),
                  const Divider(height: 16),
                  _SummaryRow(
                    'Total expenses',
                    cur.format(
                        _receipts.fold(0.0, (sum, r) => sum + r.amount)),
                    theme,
                    bold: true,
                  ),
                ],
              ],
            ),
          ),
        ),

        if (_isLoading) ...[
          const SizedBox(height: 16),
          const Center(child: CircularProgressIndicator()),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildReceiptTile(_Receipt r, ThemeData theme, NumberFormat cur) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.receipt_outlined),
      title: Text(r.description),
      subtitle: Text('${r.category} - ${r.date}',
          style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(cur.format(r.amount),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () async {
              setState(
                  () => _receipts.removeWhere((x) => x.id == r.id));
              await _saveReceipts();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _showAddReceiptDialog() async {
    String description = '';
    String category = _receiptCategories.first;
    String amount = '';
    final dateCtrl = TextEditingController(
        text: DateFormat('yyyy-MM-dd').format(DateTime.now()));

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Expense'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: dateCtrl,
                decoration: const InputDecoration(
                  labelText: 'Date (YYYY-MM-DD)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.datetime,
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Description',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => description = v,
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (ctx, setSt) => DropdownButtonFormField<String>(
                  value: category,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: _receiptCategories
                      .map((c) =>
                          DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setSt(() => category = v!),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  prefixText: '\$ ',
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => amount = v,
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
              final amt = double.tryParse(amount) ?? 0;
              if (description.trim().isEmpty || amt <= 0) return;
              final receipt = _Receipt(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                date: dateCtrl.text.trim(),
                description: description.trim(),
                category: category,
                amount: amt,
              );
              setState(() => _receipts.insert(0, receipt));
              _saveReceipts();
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // ── Quarterly cards ───────────────────────────────────────────────────────────

  Widget _buildQuarterlyCards(
      ThemeData theme, List<Invoice> allInvoices, NumberFormat cur) {
    final year = _dateRange?.start.year ?? DateTime.now().year;
    final totalExpenses = _receipts.fold(0.0, (sum, r) => sum + r.amount);
    final now = DateTime.now();

    // IRS estimated quarterly payment schedule
    final quarters = <({String label, String dates, DateTime start, DateTime end, DateTime due})>[
      (label: 'Q1', dates: 'Jan 1 – Mar 31',
        start: DateTime(year, 1, 1), end: DateTime(year, 4, 1),
        due: DateTime(year, 4, 15)),
      (label: 'Q2', dates: 'Apr 1 – May 31',
        start: DateTime(year, 4, 1), end: DateTime(year, 6, 1),
        due: DateTime(year, 6, 15)),
      (label: 'Q3', dates: 'Jun 1 – Aug 31',
        start: DateTime(year, 6, 1), end: DateTime(year, 9, 1),
        due: DateTime(year, 9, 15)),
      (label: 'Q4', dates: 'Sep 1 – Dec 31',
        start: DateTime(year, 9, 1), end: DateTime(year + 1, 1, 1),
        due: DateTime(year + 1, 1, 15)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Estimated Quarterly Taxes ($year)',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        ...quarters.map((q) {
          final gross = _incomeForRange(allInvoices, q.start, q.end);
          // Prorate annual expenses evenly across 4 quarters
          final expAlloc = totalExpenses / 4;
          final net = (gross - expAlloc).clamp(0.0, double.infinity);

          // IRS SE tax: net × 92.35% × seRate
          final seBase = net * 0.9235;
          final seTax = seBase * _seRate;
          // Federal: (net − half SE tax deduction) × federalRate
          final fedBase = (net - seTax / 2).clamp(0.0, double.infinity);
          final fedTax = fedBase * _federalRate;
          final totalEst = seTax + fedTax;

          final isPast = q.due.isBefore(now);
          final isNear = !isPast &&
              q.due.isBefore(now.add(const Duration(days: 14)));
          final dueColor = gross == 0
              ? theme.colorScheme.onSurfaceVariant
              : isPast
                  ? theme.colorScheme.error
                  : isNear
                      ? const Color(0xFFE65100)
                      : const Color(0xFF2E7D32);

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(
                        '${q.label} — ${q.dates}',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Text(
                      'Due ${DateFormat.MMMd().format(q.due)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: dueColor, fontWeight: FontWeight.w600),
                    ),
                  ]),
                  if (gross == 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'No income in this period',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  else ...[
                    const SizedBox(height: 8),
                    _SummaryRow('Gross income', cur.format(gross), theme),
                    if (expAlloc > 0)
                      _SummaryRow('Expenses (÷4)',
                          '− ${cur.format(expAlloc)}', theme),
                    _SummaryRow('Net income', cur.format(net), theme,
                        bold: true),
                    const Divider(height: 12),
                    _SummaryRow(
                        'SE tax (${(_seRate * 100).toStringAsFixed(1)}%)',
                        cur.format(seTax),
                        theme),
                    _SummaryRow(
                        'Federal (${(_federalRate * 100).toStringAsFixed(1)}%)',
                        cur.format(fedTax),
                        theme),
                    const SizedBox(height: 2),
                    _SummaryRow(
                        'Est. payment', cur.format(totalEst), theme,
                        bold: true),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTaxRateSettings(ThemeData theme) {
    return Card(
      child: Column(
        children: [
          ListTile(
            title: const Text('Tax Rate Settings'),
            subtitle: Text(
              'Federal ${_federalRateCtrl.text}%  ·  '
              'SE ${_seRateCtrl.text}%',
              style: theme.textTheme.bodySmall,
            ),
            trailing: Icon(_showTaxRateSettings
                ? Icons.expand_less
                : Icons.expand_more),
            onTap: () {
              if (_showTaxRateSettings) _saveTaxRates();
              setState(
                  () => _showTaxRateSettings = !_showTaxRateSettings);
            },
          ),
          if (_showTaxRateSettings)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: TextFormField(
                        controller: _federalRateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Federal Effective Rate (%)',
                          hintText: '22.0',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {
                          _federalRate =
                              (double.tryParse(_federalRateCtrl.text) ??
                                      22.0) /
                                  100;
                        }),
                        onEditingComplete: () {
                          _saveTaxRates();
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _seRateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'SE Tax Rate (%)',
                          hintText: '15.3',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) => setState(() {
                          _seRate =
                              (double.tryParse(_seRateCtrl.text) ?? 15.3) /
                                  100;
                        }),
                        onEditingComplete: () {
                          _saveTaxRates();
                          FocusScope.of(context).unfocus();
                        },
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'SE tax = net income × 92.35% × rate. '
                    'Federal base = net income − (SE tax ÷ 2). '
                    'WA has no state income tax.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── State tab ────────────────────────────────────────────────────────────────

  Widget _buildStateTab() {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── WA B&O ────────────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('WA Excise Tax (B&O)',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Quarterly Business & Occupation return for Washington '
                  'state. Generates a DOR-format CSV ready to upload at '
                  'MyDOR. Tracks which quarters have been submitted.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => context.push('/reports/wa-excise'),
                    icon: const Icon(Icons.account_balance_outlined),
                    label: const Text('Open WA Excise Tax'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Other states placeholder ───────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Other State / Local Taxes',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'State income tax and local tax filing support for '
                  'additional jurisdictions is planned for a future release.',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Use the Federal tab income summary and your '
                        'state\'s tax portal to prepare your return.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  String _fmt(DateTime dt) => DateFormat('MMM d, yyyy').format(dt);
}

// ── PDF preview ─────────────────────────────────────────────────────────────────

class _PdfPreviewPage extends StatelessWidget {
  final Uint8List pdfBytes;
  const _PdfPreviewPage({required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tax Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share PDF',
            onPressed: _share,
          ),
        ],
      ),
      body: PdfPreview(
        build: (_) async => pdfBytes,
        canChangeOrientation: false,
        canDebug: false,
      ),
    );
  }

  Future<void> _share() async {
    final dir = await Directory.systemTemp.createTemp('taxreport_');
    final file = File('${dir.path}/Tax_Report.pdf');
    await file.writeAsBytes(pdfBytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Tax Report',
      ),
    );
  }
}

// ── Helper widget ──────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;
  final bool bold;

  const _SummaryRow(this.label, this.value, this.theme,
      {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = theme.textTheme.bodySmall?.copyWith(
      fontWeight: bold ? FontWeight.bold : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }
}
