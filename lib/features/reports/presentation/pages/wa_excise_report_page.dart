import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../../../../core/constants/us_states.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../invoices/presentation/providers/invoice_providers.dart';
import '../../../profile/presentation/providers/profile_provider.dart';

// ── Submission model ───────────────────────────────────────────────────────────

class _WaSubmission {
  final String period;
  final String submittedAt;
  final double grossAmount;
  final double deductions;
  final double taxableAmount;
  final double boTax;
  final double stateSalesTax;
  final double localTax;
  final double credits;
  final double totalDue;
  final String fileContent;
  final String? notes;

  const _WaSubmission({
    required this.period,
    required this.submittedAt,
    required this.grossAmount,
    required this.deductions,
    required this.taxableAmount,
    required this.boTax,
    required this.stateSalesTax,
    required this.localTax,
    required this.credits,
    required this.totalDue,
    required this.fileContent,
    this.notes,
  });

  Map<String, dynamic> toJson() => {
    'period': period,
    'submittedAt': submittedAt,
    'grossAmount': grossAmount,
    'deductions': deductions,
    'taxableAmount': taxableAmount,
    'boTax': boTax,
    'stateSalesTax': stateSalesTax,
    'localTax': localTax,
    'credits': credits,
    'totalDue': totalDue,
    'fileContent': fileContent,
    if (notes != null) 'notes': notes,
  };

  factory _WaSubmission.fromJson(Map<String, dynamic> json) => _WaSubmission(
    period: json['period'] as String,
    submittedAt: json['submittedAt'] as String,
    grossAmount: (json['grossAmount'] as num).toDouble(),
    deductions: (json['deductions'] as num?)?.toDouble() ?? 0,
    taxableAmount: (json['taxableAmount'] as num?)?.toDouble() ?? 0,
    boTax: (json['boTax'] as num?)?.toDouble() ?? 0,
    stateSalesTax: (json['stateSalesTax'] as num?)?.toDouble() ?? 0,
    localTax: (json['localTax'] as num?)?.toDouble() ?? 0,
    credits: (json['credits'] as num?)?.toDouble() ?? 0,
    totalDue: (json['totalDue'] as num).toDouble(),
    fileContent: json['fileContent'] as String,
    notes: json['notes'] as String?,
  );
}

class _QuarterInvoiceItem {
  final String invoiceNumber;
  final String clientName;
  final String? clientState;
  final bool isOutOfState;
  final double subtotal;

  const _QuarterInvoiceItem({
    required this.invoiceNumber,
    required this.clientName,
    required this.clientState,
    required this.isOutOfState,
    required this.subtotal,
  });
}

// ── Quarter helpers ────────────────────────────────────────────────────────────

int _quarterOf(DateTime d) => ((d.month - 1) ~/ 3) + 1;

DateTimeRange _quarterRange(int year, int quarter) {
  final startMonth = (quarter - 1) * 3 + 1;
  final start = DateTime(year, startMonth, 1);
  final end = quarter == 4
      ? DateTime(year + 1, 1, 1)
      : DateTime(year, startMonth + 3, 1);
  return DateTimeRange(start: start, end: end);
}

String _periodCode(int year, int quarter) => 'Q$quarter$year';

String _periodLabel(int year, int quarter) {
  const labels = ['Jan-Mar', 'Apr-Jun', 'Jul-Sep', 'Oct-Dec'];
  return 'Q$quarter $year (${labels[quarter - 1]})';
}

// ── Settings keys ──────────────────────────────────────────────────────────────

const _kTra = 'wa_tra';
const _kBoRate = 'wa_bo_rate';
const _kStateSalesRate = 'wa_state_sales_rate';
const _kLocalCode = 'wa_local_location_code';
const _kLocalName = 'wa_local_location_name';
const _kLocalRate = 'wa_local_tax_rate';
const _kDeductBo = 'wa_deduct_bo';
const _kAutoSbc = 'wa_auto_sbc';
const _kSubmissions = 'wa_submissions';

double _round2(double v) => (v * 100).roundToDouble() / 100;

// ── Page ───────────────────────────────────────────────────────────────────────

class WaExciseReportPage extends ConsumerStatefulWidget {
  const WaExciseReportPage({super.key});

  @override
  ConsumerState<WaExciseReportPage> createState() => _WaExciseReportPageState();
}

class _WaExciseReportPageState extends ConsumerState<WaExciseReportPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Quarter
  int _year = DateTime.now().year;
  int _quarter = _quarterOf(DateTime.now());

  // Inputs
  final _traCtrl = TextEditingController();
  final _grossCtrl = TextEditingController();
  final _deductionsCtrl = TextEditingController(text: '0.00');
  final _creditsCtrl = TextEditingController(text: '0.00');
  final _notesCtrl = TextEditingController();

  // Tax rate settings
  final _boRateCtrl = TextEditingController(text: '0.004710');
  final _stateSalesRateCtrl = TextEditingController(text: '0.065000');
  final _localCodeCtrl = TextEditingController();
  final _localNameCtrl = TextEditingController();
  final _localRateCtrl = TextEditingController(text: '0.000000');

  bool _showRateSettings = false;
  bool _deductFromBo = false;
  bool _autoSmallBusinessCredit = true;
  bool _loading = false;
  double _autoGross = 0;
  double _autoDeductions = 0;
  String _ourState = 'WA';
  List<_QuarterInvoiceItem> _quarterItems = [];
  List<_WaSubmission> _submissions = [];

  // ── Computed values ──────────────────────────────────────────────────────────

  double get _gross => double.tryParse(_grossCtrl.text) ?? 0;
  double get _deductions => double.tryParse(_deductionsCtrl.text) ?? 0;
  double get _taxable => (_gross - _deductions).clamp(0, double.infinity);
  double get _boDeductions => _deductFromBo ? _deductions : 0.0;
  double get _boTaxable => (_gross - _boDeductions).clamp(0, double.infinity);
  double get _boRate => double.tryParse(_boRateCtrl.text) ?? 0;
  double get _stateSalesRate => double.tryParse(_stateSalesRateCtrl.text) ?? 0;
  double get _localRate => double.tryParse(_localRateCtrl.text) ?? 0;
  double get _boTax => _round2(_boTaxable * _boRate);
  double get _stateSalesTax => _round2(_taxable * _stateSalesRate);
  double get _localTax => _round2(_taxable * _localRate);
  double get _totalTax => _round2(_boTax + _stateSalesTax + _localTax);
  double get _credits => double.tryParse(_creditsCtrl.text) ?? 0;
  double get _totalDue =>
      _round2((_totalTax - _credits).clamp(0, double.infinity));

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _loadSettings();
    _loadSubmissions();
  }

  @override
  void dispose() {
    _tabs.dispose();
    for (final c in [
      _traCtrl,
      _grossCtrl,
      _deductionsCtrl,
      _creditsCtrl,
      _notesCtrl,
      _boRateCtrl,
      _stateSalesRateCtrl,
      _localCodeCtrl,
      _localNameCtrl,
      _localRateCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final dao = ref.read(appSettingsDaoProvider);
    final tra = await dao.getValue(_kTra);
    final boRate = await dao.getValue(_kBoRate);
    final stateRate = await dao.getValue(_kStateSalesRate);
    final localCode = await dao.getValue(_kLocalCode);
    final localName = await dao.getValue(_kLocalName);
    final localRate = await dao.getValue(_kLocalRate);
    final deductBo = await dao.getValue(_kDeductBo);
    final autoSbc = await dao.getValue(_kAutoSbc);

    final profile = await ref.read(userProfileRepositoryProvider).getProfile();
    final ourState = UsStates.normalizeCode(profile.stateProvince) ?? 'WA';

    // Fall back to profile taxId for TRA
    if ((tra == null || tra.isEmpty)) {
      if (profile.taxId != null && mounted) {
        _traCtrl.text = profile.taxId!;
      }
    }

    if (mounted) {
      setState(() {
        _ourState = ourState;
        if (tra != null) _traCtrl.text = tra;
        if (boRate != null) _boRateCtrl.text = boRate;
        if (stateRate != null) _stateSalesRateCtrl.text = stateRate;
        if (localCode != null) _localCodeCtrl.text = localCode;
        if (localName != null) _localNameCtrl.text = localName;
        if (localRate != null) _localRateCtrl.text = localRate;
        if (deductBo != null) _deductFromBo = deductBo == 'true';
        if (autoSbc != null) _autoSmallBusinessCredit = autoSbc == 'true';
      });
    }
    _refreshGross();
  }

  Future<void> _saveSettings() async {
    final dao = ref.read(appSettingsDaoProvider);
    await dao.setValue(_kTra, _traCtrl.text.trim());
    await dao.setValue(_kBoRate, _boRateCtrl.text.trim());
    await dao.setValue(_kStateSalesRate, _stateSalesRateCtrl.text.trim());
    await dao.setValue(_kLocalCode, _localCodeCtrl.text.trim());
    await dao.setValue(_kLocalName, _localNameCtrl.text.trim());
    await dao.setValue(_kLocalRate, _localRateCtrl.text.trim());
    await dao.setValue(_kDeductBo, _deductFromBo.toString());
    await dao.setValue(_kAutoSbc, _autoSmallBusinessCredit.toString());
  }

  Future<void> _loadSubmissions() async {
    final dao = ref.read(appSettingsDaoProvider);
    final json = await dao.getValue(_kSubmissions);
    if (json != null && mounted) {
      try {
        final list = jsonDecode(json) as List<dynamic>;
        setState(() {
          _submissions =
              list
                  .map((e) => _WaSubmission.fromJson(e as Map<String, dynamic>))
                  .toList()
                ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));
        });
      } catch (_) {}
    }
  }

  Future<void> _saveSubmissions() async {
    final dao = ref.read(appSettingsDaoProvider);
    await dao.setValue(
      _kSubmissions,
      jsonEncode(_submissions.map((s) => s.toJson()).toList()),
    );
  }

  void _syncSbcCredit() {
    if (_autoSmallBusinessCredit) {
      _creditsCtrl.text = _boTax.toStringAsFixed(2);
    }
  }

  void _refreshGross() {
    final invoices = ref.read(allInvoicesProvider).value ?? [];
    final clients = ref.read(allClientsProvider).value ?? [];
    final profile = ref.read(profileProvider).value;
    final ourState =
        UsStates.normalizeCode(profile?.stateProvince) ?? _ourState;
    final clientMap = {for (final c in clients) c.id: c};

    final range = _quarterRange(_year, _quarter);
    double total = 0;
    double outOfStateTotal = 0;
    final items = <_QuarterInvoiceItem>[];

    for (final inv in invoices) {
      if (inv.status != 'paid' && inv.status != 'archived') continue;
      final reportDate = inv.paidDate ?? inv.issueDate;
      if (reportDate.isBefore(range.start)) continue;
      if (!reportDate.isBefore(range.end)) continue;

      final client = clientMap[inv.clientId];
      final clientState = UsStates.normalizeCode(client?.stateProvince);
      final isOutOfState = UsStates.isOutOfState(
        clientState,
        businessState: ourState,
      );

      total += inv.subtotal;
      if (isOutOfState) {
        outOfStateTotal += inv.subtotal;
      }

      items.add(
        _QuarterInvoiceItem(
          invoiceNumber: inv.invoiceNumber,
          clientName: client?.name ?? 'Unknown Client',
          clientState: clientState,
          isOutOfState: isOutOfState,
          subtotal: inv.subtotal,
        ),
      );
    }

    if (mounted) {
      setState(() {
        _ourState = ourState;
        _autoGross = total;
        _autoDeductions = outOfStateTotal;
        _quarterItems = items;
        _grossCtrl.text = total.toStringAsFixed(2);
        _deductionsCtrl.text = outOfStateTotal.toStringAsFixed(2);
        _syncSbcCredit();
      });
    }
  }

  // ── DOR CSV generation ───────────────────────────────────────────────────────

  Future<String> _buildDorCsv() async {
    final profile = await ref.read(userProfileRepositoryProvider).getProfile();
    final tra = _traCtrl.text.trim();
    final period = _periodCode(_year, _quarter);
    final preparer = profile.ownerName.isNotEmpty ? profile.ownerName : '';
    final email = profile.email ?? '';
    final phone = profile.phone ?? '';
    final localCode = _localCodeCtrl.text.trim();
    final hasLocal = localCode.isNotEmpty && _localRate > 0;
    final hasDeductions = _deductions > 0;

    final buf = StringBuffer();
    buf.writeln('# WA Combined Excise Tax Return - $period');
    buf.writeln(
      '# Generated ${DateFormat.yMMMd().format(DateTime.now())} by CodeLedger',
    );
    buf.writeln();
    // Account line
    buf.writeln('ACCOUNT,$tra,$period,$preparer,$email,$phone');
    // B&O Retailing (line 2)
    buf.writeln('TAX,2,0,${_gross.toStringAsFixed(2)}');
    // State Retail Sales (line 1)
    buf.writeln('TAX,1,0,${_gross.toStringAsFixed(2)}');
    // Local sales tax (line 45) — uses taxable in-state sales
    if (hasLocal) {
      buf.writeln('TAX,45,$localCode,${_taxable.toStringAsFixed(2)}');
    }
    // Deductions - Interstate/Foreign Sales (deduction code 01)
    if (hasDeductions) {
      if (_deductFromBo) {
        buf.writeln('DED,2,01,${_deductions.toStringAsFixed(2)}');
      }
      buf.writeln('DED,1,01,${_deductions.toStringAsFixed(2)}');
    }
    return buf.toString();
  }

  // ── Actions ──────────────────────────────────────────────────────────────────

  Future<void> _exportCsv() async {
    setState(() => _loading = true);
    try {
      await _saveSettings();
      final content = await _buildDorCsv();
      final dir = await getTemporaryDirectory();
      final period = _periodCode(_year, _quarter);
      final file = File('${dir.path}/WA_Excise_$period.csv');
      await file.writeAsString(content);
      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: 'text/csv')],
            subject: 'WA Excise Tax $period',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markSubmitted() async {
    setState(() => _loading = true);
    try {
      await _saveSettings();
      final content = await _buildDorCsv();
      final period = _periodCode(_year, _quarter);

      final submission = _WaSubmission(
        period: period,
        submittedAt: DateTime.now().toIso8601String().substring(0, 10),
        grossAmount: _gross,
        deductions: _deductions,
        taxableAmount: _taxable,
        boTax: _boTax,
        stateSalesTax: _stateSalesTax,
        localTax: _localTax,
        credits: _credits,
        totalDue: _totalDue,
        fileContent: content,
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      );

      setState(() {
        _submissions.removeWhere((s) => s.period == period);
        _submissions.insert(0, submission);
      });
      await _saveSubmissions();
      _notesCtrl.clear();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$period marked as submitted')));
        _tabs.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _deleteSubmission(_WaSubmission s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Submission'),
        content: Text('Remove the record for ${s.period}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      setState(() => _submissions.removeWhere((x) => x.period == s.period));
      await _saveSubmissions();
    }
  }

  Future<void> _reexportSubmission(_WaSubmission s) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/WA_Excise_${s.period}.csv');
      await file.writeAsString(s.fileContent);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'WA Excise Tax ${s.period}',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Keep gross & out-of-state deductions in sync when invoices/clients load
    ref.listen(allInvoicesProvider, (_, _) => _refreshGross());
    ref.listen(allClientsProvider, (_, _) => _refreshGross());
    ref.listen(profileProvider, (_, _) => _refreshGross());

    return Scaffold(
      appBar: AppBar(
        title: const Text('WA Excise Tax'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Generate'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_buildGenerateTab(), _buildHistoryTab()],
      ),
    );
  }

  Widget _buildGenerateTab() {
    final theme = Theme.of(context);
    final cur = NumberFormat.currency(symbol: '\$');
    final pct = NumberFormat.percentPattern()..maximumFractionDigits = 4;
    final isSubmitted = _submissions.any(
      (s) => s.period == _periodCode(_year, _quarter),
    );
    final outOfStateItems = _quarterItems
        .where((i) => i.isOutOfState)
        .toList();
    final missingStateItems = _quarterItems
        .where((i) => i.clientState == null)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Quarter ────────────────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Filing Period', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        // ignore: deprecated_member_use
                        value: _year,
                        decoration: const InputDecoration(labelText: 'Year'),
                        items: List.generate(5, (i) {
                          final y = DateTime.now().year - i;
                          return DropdownMenuItem(value: y, child: Text('$y'));
                        }),
                        onChanged: (v) {
                          setState(() => _year = v!);
                          _refreshGross();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        // ignore: deprecated_member_use
                        value: _quarter,
                        decoration: const InputDecoration(labelText: 'Quarter'),
                        items: const [
                          DropdownMenuItem(
                            value: 1,
                            child: Text('Q1 (Jan-Mar)'),
                          ),
                          DropdownMenuItem(
                            value: 2,
                            child: Text('Q2 (Apr-Jun)'),
                          ),
                          DropdownMenuItem(
                            value: 3,
                            child: Text('Q3 (Jul-Sep)'),
                          ),
                          DropdownMenuItem(
                            value: 4,
                            child: Text('Q4 (Oct-Dec)'),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _quarter = v!);
                          _refreshGross();
                        },
                      ),
                    ),
                  ],
                ),
                if (isSubmitted) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Already submitted',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── TRA ───────────────────────────────────────────────────
        TextFormField(
          controller: _traCtrl,
          decoration: const InputDecoration(
            labelText: 'UBI / TRA Number',
            hintText: 'e.g. 606-043-803',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),

        // ── State Breakdown Banner ─────────────────────────────────
        if (_quarterItems.isNotEmpty) ...[
          Card(
            color: theme.colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.public_outlined,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'State Check (${_quarterItems.length} paid/archived invoices in Q$_quarter)',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _TaxRow(
                    'In-State ($_ourState) Taxable Sales',
                    cur.format(_autoGross - _autoDeductions),
                    bold: true,
                  ),
                  _TaxRow(
                    'Out-of-State Excluded (Interstate/Foreign)',
                    cur.format(_autoDeductions),
                    color: _autoDeductions > 0
                        ? theme.colorScheme.tertiary
                        : null,
                  ),
                  if (outOfStateItems.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    ...outOfStateItems.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '• ${item.invoiceNumber} — ${item.clientName} (${item.clientState})',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              cur.format(item.subtotal),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (missingStateItems.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 16,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${missingStateItems.length} invoice(s) belong to client(s) with no state set '
                              '(${missingStateItems.map((e) => e.clientName).toSet().join(', ')}). '
                              'Edit client profile to set their state.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // ── Gross & Deductions ────────────────────────────────────
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Amounts', style: theme.textTheme.titleSmall),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _grossCtrl,
                  decoration: InputDecoration(
                    labelText: 'Gross Sales',
                    helperText: _autoGross > 0
                        ? 'Auto-filled from ${cur.format(_autoGross)} total paid invoices'
                        : null,
                    border: const OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(_syncSbcCredit),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _deductionsCtrl,
                  decoration: InputDecoration(
                    labelText:
                        'Deductions (Interstate & Foreign Sales / Apportionment)',
                    helperText: _autoDeductions > 0
                        ? 'Auto-excluded ${cur.format(_autoDeductions)} from out-of-state clients'
                        : 'Revenue from clients outside $_ourState excluded from WA sales tax',
                    border: const OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(_syncSbcCredit),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _deductFromBo,
                  onChanged: (v) {
                    setState(() {
                      _deductFromBo = v ?? false;
                      _syncSbcCredit();
                    });
                    _saveSettings();
                  },
                  title: const Text(
                    'Also deduct out-of-state sales from B&O (Retailing)',
                  ),
                  subtitle: const Text(
                    'Leave unchecked when claiming Small Business Credit on gross B&O',
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _creditsCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Credits (Small Business Credit)',
                    border: OutlineInputBorder(),
                    prefixText: '\$ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {
                    _autoSmallBusinessCredit = false;
                  }),
                ),
                CheckboxListTile(
                  value: _autoSmallBusinessCredit,
                  onChanged: (v) {
                    setState(() {
                      _autoSmallBusinessCredit = v ?? false;
                      _syncSbcCredit();
                    });
                    _saveSettings();
                  },
                  title: const Text(
                    'Auto-apply Small Business Credit (offsets B&O tax)',
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // ── Rate settings (collapsible) ───────────────────────────
        Card(
          child: Column(
            children: [
              ListTile(
                title: const Text('Tax Rates & Location'),
                subtitle: Text(
                  'B&O ${(_boRate * 100).toStringAsFixed(4)}%  ·  '
                  'State Sales ${(_stateSalesRate * 100).toStringAsFixed(2)}%'
                  '${_localCodeCtrl.text.isNotEmpty ? '  ·  Local ${(_localRate * 100).toStringAsFixed(2)}%' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
                trailing: Icon(
                  _showRateSettings ? Icons.expand_less : Icons.expand_more,
                ),
                onTap: () =>
                    setState(() => _showRateSettings = !_showRateSettings),
              ),
              if (_showRateSettings)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _boRateCtrl,
                              decoration: const InputDecoration(
                                labelText: 'B&O Rate (Retailing)',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setState(_syncSbcCredit),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _stateSalesRateCtrl,
                              decoration: const InputDecoration(
                                labelText: 'State Sales Rate',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _localCodeCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Local Location Code',
                                hintText: 'e.g. 3913',
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 3,
                            child: TextFormField(
                              controller: _localNameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Location Name',
                                hintText: 'e.g. Yakima City',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _localRateCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Local Rate',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ── Tax breakdown summary ─────────────────────────────────
        Card(
          color: theme.colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filing Category Summary',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _SummarySection(
                  label: 'Business & Occupation - Retailing',
                  rows: [
                    _TaxRow('Gross Amount', cur.format(_gross)),
                    _TaxRow('Deductions', cur.format(_boDeductions)),
                    _TaxRow(
                      'Taxable Amount',
                      cur.format(_boTaxable),
                      bold: true,
                    ),
                    _TaxRow('Rate', pct.format(_boRate)),
                    _TaxRow(
                      'B&O Tax Due',
                      cur.format(_boTax),
                      bold: true,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
                if (_localRate > 0 && _localCodeCtrl.text.isNotEmpty) ...[
                  const Divider(height: 24),
                  _SummarySection(
                    label:
                        'Local Taxes - Local City and/or County Sales Tax '
                        '(${_localNameCtrl.text.isNotEmpty ? _localNameCtrl.text : _localCodeCtrl.text})',
                    rows: [
                      _TaxRow('Gross Amount', cur.format(_taxable)),
                      _TaxRow('Deductions', cur.format(0)),
                      _TaxRow(
                        'Taxable Amount',
                        cur.format(_taxable),
                        bold: true,
                      ),
                      _TaxRow('Rate', pct.format(_localRate)),
                      _TaxRow(
                        'Local Tax Due',
                        cur.format(_localTax),
                        bold: true,
                        color: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ],
                const Divider(height: 24),
                _SummarySection(
                  label: 'State Sales and Use - Retail Sales',
                  rows: [
                    _TaxRow('Gross Amount', cur.format(_gross)),
                    _TaxRow(
                      'Deductions (Interstate & Foreign Sales)',
                      cur.format(_deductions),
                    ),
                    _TaxRow('Taxable Amount', cur.format(_taxable), bold: true),
                    _TaxRow('Rate', pct.format(_stateSalesRate)),
                    _TaxRow(
                      'State Sales Tax Due',
                      cur.format(_stateSalesTax),
                      bold: true,
                      color: theme.colorScheme.primary,
                    ),
                  ],
                ),
                const Divider(height: 24),
                _TaxRow('Total Tax', cur.format(_totalTax), bold: true),
                if (_credits > 0)
                  _TaxRow(
                    'Less Credits (Small Business Credit)',
                    '- ${cur.format(_credits)}',
                    color: Colors.green,
                  ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Total Tax Due',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      Text(
                        cur.format(_totalDue),
                        style: theme.textTheme.titleMedium?.copyWith(
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
        const SizedBox(height: 12),

        // ── Notes ────────────────────────────────────────────────
        TextFormField(
          controller: _notesCtrl,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'e.g. Submitted via MyDOR - Confirmation #...',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 20),

        // ── Actions ──────────────────────────────────────────────
        FilledButton.icon(
          onPressed: _loading ? null : _exportCsv,
          icon: const Icon(Icons.download_outlined),
          label: const Text('Export DOR Upload File (.csv)'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _loading ? null : _markSubmitted,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Mark as Submitted & Save to History'),
        ),
        const SizedBox(height: 8),
        Text(
          'CSV uses WA DOR data upload format: ACCOUNT + TAX lines (B&O Retailing line 2, '
          'State Sales line 1, Local line 45) + DED lines for Interstate/Foreign Sales (code 01). '
          'Upload at MyDOR to Excise Tax Return to Upload a file.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildHistoryTab() {
    final theme = Theme.of(context);
    final cur = NumberFormat.currency(symbol: '\$');

    if (_submissions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No submissions yet.', style: TextStyle(color: Colors.grey)),
            SizedBox(height: 4),
            Text(
              'Tap "Mark as Submitted" after filing.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _submissions.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = _submissions[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _periodLabel(
                          int.parse(s.period.substring(2)),
                          int.parse(s.period.substring(1, 2)),
                        ),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'reexport') _reexportSubmission(s);
                        if (v == 'delete') _deleteSubmission(s);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'reexport',
                          child: ListTile(
                            leading: Icon(Icons.download_outlined),
                            title: Text('Re-export CSV'),
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline),
                            title: Text('Delete record'),
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Text(
                  'Submitted: ${s.submittedAt}',
                  style: theme.textTheme.bodySmall,
                ),
                if (s.notes != null)
                  Text(s.notes!, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                _TaxRow('Gross', cur.format(s.grossAmount)),
                if (s.deductions > 0)
                  _TaxRow('Deductions', '- ${cur.format(s.deductions)}'),
                _TaxRow('Taxable', cur.format(s.taxableAmount), bold: true),
                _TaxRow('B&O Tax', cur.format(s.boTax)),
                _TaxRow('State Sales Tax', cur.format(s.stateSalesTax)),
                if (s.localTax > 0)
                  _TaxRow('Local Tax', cur.format(s.localTax)),
                if (s.credits > 0)
                  _TaxRow(
                    'Credits',
                    '- ${cur.format(s.credits)}',
                    color: Colors.green,
                  ),
                const Divider(height: 12),
                _TaxRow(
                  'Total Paid',
                  cur.format(s.totalDue),
                  bold: true,
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Helper widgets ─────────────────────────────────────────────────────────────

class _SummarySection extends StatelessWidget {
  final String label;
  final List<_TaxRow> rows;

  const _SummarySection({required this.label, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        ...rows,
      ],
    );
  }
}

class _TaxRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  const _TaxRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: bold ? FontWeight.bold : null,
      color: color,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
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
