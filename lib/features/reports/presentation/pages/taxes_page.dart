import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
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
  final bool isTaxDeductible;
  final String? imagePath;

  const _Receipt({
    required this.id,
    required this.date,
    required this.description,
    required this.category,
    required this.amount,
    this.isTaxDeductible = true,
    this.imagePath,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'desc': description,
        'cat': category,
        'amount': amount,
        'taxded': isTaxDeductible,
        if (imagePath != null) 'img': imagePath,
      };

  factory _Receipt.fromJson(Map<String, dynamic> j) => _Receipt(
        id: j['id'] as String,
        date: j['date'] as String,
        description: j['desc'] as String,
        category: j['cat'] as String,
        amount: (j['amount'] as num).toDouble(),
        isTaxDeductible: j['taxded'] as bool? ?? true,
        imagePath: j['img'] as String?,
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

  // Guide tab estimator
  final _guideIncomeCtrl = TextEditingController();
  final _guideExpensesCtrl = TextEditingController(text: '0');

  // Home office calculator
  final _homeRentCtrl = TextEditingController();
  int _homeOfficeTotalRooms = 4;
  int _homeOfficeWorkRooms = 1;
  bool _showHomeOffice = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final now = DateTime.now();
    _dateRange = DateTimeRange(
      start: DateTime(now.year, 1, 1),
      end: DateTime(now.year, 12, 31),
    );
    _loadReceipts();
    _loadTaxRates();
    _loadHomeOffice();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _federalRateCtrl.dispose();
    _seRateCtrl.dispose();
    _guideIncomeCtrl.dispose();
    _guideExpensesCtrl.dispose();
    _homeRentCtrl.dispose();
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

  Future<void> _loadHomeOffice() async {
    final dao = ref.read(appSettingsDaoProvider);
    final rent = await dao.getValue('deduct.home_rent');
    final total = await dao.getValue('deduct.home_total_rooms');
    final work = await dao.getValue('deduct.home_work_rooms');
    if (!mounted) return;
    setState(() {
      if (rent != null) _homeRentCtrl.text = rent;
      if (total != null) _homeOfficeTotalRooms = int.tryParse(total) ?? 4;
      if (work != null) _homeOfficeWorkRooms = int.tryParse(work) ?? 1;
    });
  }

  Future<void> _saveHomeOffice() async {
    final dao = ref.read(appSettingsDaoProvider);
    await dao.setValue('deduct.home_rent', _homeRentCtrl.text);
    await dao.setValue(
        'deduct.home_total_rooms', _homeOfficeTotalRooms.toString());
    await dao.setValue(
        'deduct.home_work_rooms', _homeOfficeWorkRooms.toString());
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
            Tab(text: 'Guide'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildFederalTab(),
          _buildStateTab(),
          _buildGuideTab(),
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
      totalTax += inv.taxAmount;
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
                  error: (e, _) => const Text('Error loading clients'),
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

        // ── Home Office Calculator ─────────────────────────────────────────
        const SizedBox(height: 12),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.home_work_outlined),
                title: const Text('Home Office Deduction'),
                subtitle: Builder(builder: (ctx) {
                  final rent =
                      double.tryParse(_homeRentCtrl.text) ?? 0;
                  final monthly = _homeOfficeTotalRooms > 0
                      ? rent *
                          _homeOfficeWorkRooms /
                          _homeOfficeTotalRooms
                      : 0.0;
                  return Text(
                    monthly > 0
                        ? '${cur.format(monthly)}/mo · ${cur.format(monthly * 12)}/yr'
                        : 'Enter rent to calculate',
                    style: theme.textTheme.bodySmall,
                  );
                }),
                trailing: Icon(_showHomeOffice
                    ? Icons.expand_less
                    : Icons.expand_more),
                onTap: () =>
                    setState(() => _showHomeOffice = !_showHomeOffice),
              ),
              if (_showHomeOffice)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _homeRentCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Monthly rent / mortgage',
                          prefixText: '\$',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) {
                          setState(() {});
                          _saveHomeOffice();
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: _RoomStepper(
                            label: 'Total rooms',
                            value: _homeOfficeTotalRooms,
                            min: 1,
                            max: 20,
                            onChanged: (v) {
                              setState(() => _homeOfficeTotalRooms = v);
                              _saveHomeOffice();
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RoomStepper(
                            label: 'Office rooms',
                            value: _homeOfficeWorkRooms,
                            min: 1,
                            max: _homeOfficeTotalRooms,
                            onChanged: (v) {
                              setState(() => _homeOfficeWorkRooms = v);
                              _saveHomeOffice();
                            },
                          ),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      Builder(builder: (ctx) {
                        final rent =
                            double.tryParse(_homeRentCtrl.text) ?? 0;
                        final frac = _homeOfficeTotalRooms > 0
                            ? _homeOfficeWorkRooms /
                                _homeOfficeTotalRooms
                            : 0.0;
                        final monthly = rent * frac;
                        final annual = monthly * 12;
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _SummaryRow(
                                  'Office fraction',
                                  '${(frac * 100).toStringAsFixed(0)}%'
                                  ' ($_homeOfficeWorkRooms/$_homeOfficeTotalRooms)',
                                  theme),
                              _SummaryRow('Monthly deduction',
                                  cur.format(monthly), theme),
                              _SummaryRow('Annual deduction',
                                  cur.format(annual), theme,
                                  bold: true),
                              if (annual > 0) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Est. tax savings: '
                                  '${cur.format(annual * (_federalRate + _seRate * 0.9235 * 0.5))}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF2E7D32),
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      Text(
                        'IRS rule: room must be used regularly and '
                        'exclusively for business. Add monthly amount '
                        'as "Home Office" expense below to track it.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
            ],
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
                            'Business expenses for Schedule C.',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _showAddExpense,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),
                  ],
                ),
                if (_receipts.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        'No expenses yet. Tap Add to record one.',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else ...[
                  const SizedBox(height: 8),
                  ..._receipts.map((r) => _buildReceiptTile(r, theme, cur)),
                  const Divider(height: 16),
                  () {
                    final totalAll = _receipts.fold(
                        0.0, (sum, r) => sum + r.amount);
                    final totalDed = _receipts
                        .where((r) => r.isTaxDeductible)
                        .fold(0.0, (sum, r) => sum + r.amount);
                    final savings = totalDed *
                        (_federalRate + _seRate * 0.9235 * 0.5);
                    return Column(
                      children: [
                        if (totalAll != totalDed)
                          _SummaryRow('Total expenses',
                              cur.format(totalAll), theme),
                        _SummaryRow('Deductible total',
                            cur.format(totalDed), theme,
                            bold: true),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Est. tax savings',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF2E7D32))),
                            Text(cur.format(savings),
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: const Color(0xFF2E7D32),
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    );
                  }(),
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
    final hasPhoto =
        r.imagePath != null && File(r.imagePath!).existsSync();

    Widget leading = hasPhoto
        ? GestureDetector(
            onTap: () => _viewPhoto(r.imagePath!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(r.imagePath!),
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            ),
          )
        : Icon(
            Icons.receipt_outlined,
            color: r.isTaxDeductible
                ? null
                : theme.colorScheme.onSurfaceVariant,
          );

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: leading,
      title: Text(r.description),
      subtitle: Text(
        r.isTaxDeductible
            ? '${r.category} · ${r.date}'
            : '${r.category} · ${r.date} · Non-deductible',
        style: theme.textTheme.bodySmall,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            cur.format(r.amount),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          PopupMenuButton<String>(
            tooltip: 'Options',
            onSelected: (value) async {
              if (value == 'edit') {
                if (!mounted) return;
                final updated = await _showExpenseSheet(existing: r);
                if (updated == null || !mounted) return;
                setState(() {
                  final idx = _receipts.indexWhere((x) => x.id == r.id);
                  if (idx != -1) _receipts[idx] = updated;
                });
                await _saveReceipts();
              } else if (value == 'view_photo') {
                _viewPhoto(r.imagePath!);
              } else if (value == 'delete') {
                if (r.imagePath != null) {
                  try {
                    await File(r.imagePath!).delete();
                  } catch (_) {}
                }
                setState(() => _receipts.removeWhere((x) => x.id == r.id));
                await _saveReceipts();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Edit'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (hasPhoto)
                const PopupMenuItem(
                  value: 'view_photo',
                  child: ListTile(
                    leading: Icon(Icons.photo_outlined),
                    title: Text('View photo'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _viewPhoto(String path) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.file(File(path)),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.black45),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddExpense() async {
    final result = await _showExpenseSheet();
    if (result == null || !mounted) return;
    setState(() => _receipts.insert(0, result));
    await _saveReceipts();
  }

  Future<_Receipt?> _showExpenseSheet({_Receipt? existing}) {
    return showModalBottomSheet<_Receipt>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ExpenseSheet(existing: existing),
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

  // ── Guide tab ─────────────────────────────────────────────────────────────────

  Widget _buildGuideTab() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cur = NumberFormat.currency(symbol: '\$');
    final allInvoices = ref.watch(allInvoicesProvider).value ?? [];

    // YTD income from paid/archived invoices
    final now = DateTime.now();
    final ytdStart = DateTime(now.year, 1, 1);
    double ytdIncome = 0;
    for (final inv in allInvoices) {
      if (inv.status != 'paid' && inv.status != 'archived') continue;
      final d = inv.paidDate ?? inv.issueDate;
      if (d.isBefore(ytdStart) || d.isAfter(now)) continue;
      ytdIncome += inv.subtotal;
    }
    final saveMin = ytdIncome * 0.25;
    final saveMax = ytdIncome * 0.30;

    // Estimator calc
    final annualIncome =
        double.tryParse(_guideIncomeCtrl.text.replaceAll(',', '')) ?? 0;
    final annualExpenses =
        double.tryParse(_guideExpensesCtrl.text.replaceAll(',', '')) ?? 0;
    final taxableProfit =
        (annualIncome - annualExpenses).clamp(0.0, double.infinity);
    final seBase = taxableProfit * 0.9235;
    final seTax = seBase * _seRate;
    final fedBase =
        (taxableProfit - seTax / 2).clamp(0.0, double.infinity);
    final fedTax = fedBase * _federalRate;
    final totalEst = seTax + fedTax;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 25-30% Savings Banner ──────────────────────────────────────────
        if (ytdIncome > 0) ...[
          Card(
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.savings_outlined,
                        color: cs.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text('Set Aside Now',
                        style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onPrimaryContainer,
                            fontWeight: FontWeight.bold)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'Based on your ${now.year} income so far '
                    '(${cur.format(ytdIncome)}):',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onPrimaryContainer),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _GuideStat(
                        label: '25% minimum',
                        value: cur.format(saveMin),
                        color: cs.onPrimaryContainer,
                        theme: theme,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GuideStat(
                        label: '30% safe buffer',
                        value: cur.format(saveMax),
                        color: cs.onPrimaryContainer,
                        theme: theme,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Text(
                    'Keep in a separate savings account. '
                    'Do not touch until quarterly due dates.',
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onPrimaryContainer.withAlpha(200)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Annual Tax Estimator ───────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.calculate_outlined),
                  const SizedBox(width: 8),
                  Text('Annual Tax Estimator',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Estimate your full-year tax bill. '
                  'Uses your current rate settings.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _guideIncomeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Expected annual income',
                    prefixText: '\$',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _guideExpensesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Business expenses (software, hardware…)',
                    prefixText: '\$',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
                if (annualIncome > 0) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 4),
                  _SummaryRow(
                      'Annual income', cur.format(annualIncome), theme),
                  _SummaryRow('Business expenses',
                      '− ${cur.format(annualExpenses)}', theme),
                  _SummaryRow('Taxable profit',
                      cur.format(taxableProfit), theme,
                      bold: true),
                  const Divider(height: 16),
                  _SummaryRow(
                      'SE tax (${(_seRate * 100).toStringAsFixed(1)}%)',
                      cur.format(seTax),
                      theme),
                  _SummaryRow(
                      'Federal income tax '
                      '(${(_federalRate * 100).toStringAsFixed(1)}%)',
                      cur.format(fedTax),
                      theme),
                  const SizedBox(height: 4),
                  _SummaryRow('Total estimated tax',
                      cur.format(totalEst), theme,
                      bold: true),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Set aside ~${cur.format(totalEst / 4)} per quarter'
                          ' (${annualIncome > 0 ? (totalEst / annualIncome * 100).toStringAsFixed(0) : 0}%'
                          ' of income).',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Quarterly Due Dates ────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.calendar_today_outlined),
                  const SizedBox(width: 8),
                  Text('${now.year} Payment Schedule',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 12),
                _DueDateRow('Q1 — Jan 1 to Mar 31',
                    DateTime(now.year, 4, 15), theme),
                _DueDateRow('Q2 — Apr 1 to May 31',
                    DateTime(now.year, 6, 15), theme),
                _DueDateRow('Q3 — Jun 1 to Aug 31',
                    DateTime(now.year, 9, 15), theme),
                _DueDateRow('Q4 — Sep 1 to Dec 31',
                    DateTime(now.year + 1, 1, 15), theme),
                const SizedBox(height: 8),
                Text(
                  'Pay online via IRS Direct Pay — no account required, '
                  'straight from your bank.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── IRS Links ──────────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.link),
                  const SizedBox(width: 8),
                  Text('Official Resources',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                _LinkTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'IRS Estimated Taxes Guide',
                  subtitle: 'When and how to pay quarterly (Form 1040-ES)',
                  url:
                      'https://www.irs.gov/businesses/small-businesses-self-employed/estimated-taxes',
                ),
                _LinkTile(
                  icon: Icons.payment_outlined,
                  title: 'IRS Direct Pay',
                  subtitle: 'Pay from your bank — free, no login needed',
                  url: 'https://www.irs.gov/payments/direct-pay',
                ),
                _LinkTile(
                  icon: Icons.description_outlined,
                  title: 'Form 1040-ES',
                  subtitle: 'Quarterly payment vouchers and worksheet',
                  url:
                      'https://www.irs.gov/forms-pubs/about-form-1040-es',
                ),
                _LinkTile(
                  icon: Icons.store_outlined,
                  title: 'WA Dept of Revenue',
                  subtitle: 'B&O and sales tax filing (no WA income tax)',
                  url: 'https://dor.wa.gov/',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── WA State Note ──────────────────────────────────────────────────
        Card(
          color: cs.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.location_on_outlined, color: cs.primary),
                  const SizedBox(width: 8),
                  Text('Washington State Notes',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 10),
                _GuideCheckRow(
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF2E7D32),
                    text: 'No state income tax — only federal',
                    theme: theme),
                _GuideCheckRow(
                    icon: Icons.info_outline,
                    color: cs.primary,
                    text:
                        'B&O tax applies to gross business receipts',
                    theme: theme),
                _GuideCheckRow(
                    icon: Icons.info_outline,
                    color: cs.primary,
                    text:
                        'Sales tax may apply to some digital services / SaaS',
                    theme: theme),
                _GuideCheckRow(
                    icon: Icons.info_outline,
                    color: cs.primary,
                    text: 'File quarterly at MyDOR (dor.wa.gov)',
                    theme: theme),
                const SizedBox(height: 8),
                Text(
                  'Custom web development is typically B&O taxable. '
                  'Hosting, SaaS, or digital products may also trigger '
                  'sales tax — verify with a WA tax professional.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Record Keeping ─────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.folder_outlined),
                  const SizedBox(width: 8),
                  Text('Keep Records Now',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 4),
                Text(
                  'Everything you need for Schedule C (self-employment).',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                _GuideCheckRow(
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF2E7D32),
                    text: 'All invoices sent',
                    theme: theme),
                _GuideCheckRow(
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF2E7D32),
                    text: 'Business expense receipts',
                    theme: theme),
                _GuideCheckRow(
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF2E7D32),
                    text: 'Software / subscription invoices',
                    theme: theme),
                _GuideCheckRow(
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF2E7D32),
                    text: 'Hardware and equipment purchases',
                    theme: theme),
                _GuideCheckRow(
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF2E7D32),
                    text: 'Bank statements',
                    theme: theme),
                _GuideCheckRow(
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF2E7D32),
                    text: 'Home office costs (if applicable)',
                    theme: theme),
                _GuideCheckRow(
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF2E7D32),
                    text: 'Mileage log (if any business travel)',
                    theme: theme),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── First Year Note ────────────────────────────────────────────────
        Card(
          color: cs.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.lightbulb_outline,
                      color: cs.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Text('First Year Self-Employed',
                      style: theme.textTheme.titleSmall?.copyWith(
                          color: cs.onSecondaryContainer,
                          fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 8),
                Text(
                  'The IRS is generally forgiving in your first year. '
                  'The biggest mistake is ignoring taxes completely.\n\n'
                  'You do not need to panic or immediately form an LLC. '
                  'Sole proprietor + Schedule C is the normal starting '
                  'point for freelance web developers. Consider a CPA '
                  'review for your first annual return if your income is '
                  'significant.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSecondaryContainer),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
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

// ── Expense entry bottom sheet ─────────────────────────────────────────────────

class _ExpenseSheet extends StatefulWidget {
  final _Receipt? existing;
  const _ExpenseSheet({this.existing});

  @override
  State<_ExpenseSheet> createState() => _ExpenseSheetState();
}

class _ExpenseSheetState extends State<_ExpenseSheet> {
  late DateTime _date;
  late final TextEditingController _descCtrl;
  late final TextEditingController _amountCtrl;
  late String _category;
  late bool _isTaxDeductible;
  String? _imagePath;
  bool _pickingImage = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _date = e != null
        ? (DateTime.tryParse(e.date) ?? DateTime.now())
        : DateTime.now();
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _amountCtrl = TextEditingController(
      text: e != null ? e.amount.toStringAsFixed(2) : '',
    );
    _category = e?.category ?? _receiptCategories.first;
    _isTaxDeductible = e?.isTaxDeductible ?? true;
    _imagePath = e?.imagePath;
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickImage(ImageSource source) async {
    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (file == null || !mounted) return;

      // Copy to app documents so it persists
      final dir = await getApplicationDocumentsDirectory();
      final receiptsDir =
          Directory(p.join(dir.path, 'receipt_photos'));
      await receiptsDir.create(recursive: true);
      final ext = p.extension(file.path).isNotEmpty
          ? p.extension(file.path)
          : '.jpg';
      final dest = p.join(receiptsDir.path,
          '${DateTime.now().millisecondsSinceEpoch}$ext');
      await File(file.path).copy(dest);

      setState(() => _imagePath = dest);
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _removeImage() => setState(() => _imagePath = null);

  void _save() {
    final description = _descCtrl.text.trim();
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (description.isEmpty || amount <= 0) return;
    Navigator.pop(
      context,
      _Receipt(
        id: widget.existing?.id ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        date: DateFormat('yyyy-MM-dd').format(_date),
        description: description,
        category: _category,
        amount: amount,
        isTaxDeductible: _isTaxDeductible,
        imagePath: _imagePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;
    final hasImage = _imagePath != null && File(_imagePath!).existsSync();

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        24,
        24,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isEditing ? 'Edit Expense' : 'Add Expense',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pickDate,
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Date',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today_outlined),
              ),
              child: Text(DateFormat('MMM d, yyyy').format(_date)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            autofocus: widget.existing == null,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              border: OutlineInputBorder(),
            ),
            items: _receiptCategories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v!),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountCtrl,
            decoration: const InputDecoration(
              labelText: 'Amount',
              border: OutlineInputBorder(),
              prefixText: '\$ ',
            ),
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),

          // ── Receipt photo ──────────────────────────────────────────────
          if (hasImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(_imagePath!),
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _removeImage,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remove photo'),
            ),
          ] else ...[
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickingImage
                      ? null
                      : () => _pickImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined, size: 18),
                  label: const Text('Camera'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickingImage
                      ? null
                      : () => _pickImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('Gallery'),
                ),
              ),
            ]),
          ],

          const SizedBox(height: 4),
          SwitchListTile(
            value: _isTaxDeductible,
            onChanged: (v) => setState(() => _isTaxDeductible = v),
            title: const Text('Tax deductible'),
            subtitle: const Text('Count toward Schedule C deductions'),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _save,
            child: Text(isEditing ? 'Save Changes' : 'Add Expense'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ── Room stepper widget ────────────────────────────────────────────────────────

class _RoomStepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _RoomStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed:
                    value > min ? () => onChanged(value - 1) : null,
              ),
              Text('$value',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add),
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed:
                    value < max ? () => onChanged(value + 1) : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Guide helper widgets ────────────────────────────────────────────────────────

class _GuideStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final ThemeData theme;

  const _GuideStat({
    required this.label,
    required this.value,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style: theme.textTheme.bodySmall?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _DueDateRow extends StatelessWidget {
  final String label;
  final DateTime due;
  final ThemeData theme;

  const _DueDateRow(this.label, this.due, this.theme);

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isPast = due.isBefore(now);
    final isNear =
        !isPast && due.isBefore(now.add(const Duration(days: 21)));
    final color = isPast
        ? theme.colorScheme.onSurfaceVariant
        : isNear
            ? const Color(0xFFE65100)
            : const Color(0xFF2E7D32);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(
          isPast ? Icons.check_circle_outline : Icons.radio_button_unchecked,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: isPast ? theme.colorScheme.onSurfaceVariant : null)),
        ),
        Text(
          'Due ${DateFormat.MMMd().format(due)}',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: color, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

class _LinkTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String url;

  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: cs.primary),
      title: Text(title,
          style: TextStyle(color: cs.primary, fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: Icon(Icons.open_in_new, size: 16, color: cs.primary),
      onTap: () => launchUrl(Uri.parse(url),
          mode: LaunchMode.externalApplication),
    );
  }
}

class _GuideCheckRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  final ThemeData theme;

  const _GuideCheckRow({
    required this.icon,
    required this.color,
    required this.text,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
      ]),
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
