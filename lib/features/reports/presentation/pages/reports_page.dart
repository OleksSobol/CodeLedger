import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../../../../core/database/app_database.dart';
import '../../../clients/presentation/providers/client_providers.dart';
import '../../../export/presentation/providers/export_providers.dart';
import '../../../projects/presentation/providers/project_providers.dart';
import '../../../profile/presentation/providers/profile_provider.dart';
import '../../../time_tracking/presentation/providers/time_entry_providers.dart';
import '../../../invoices/presentation/providers/invoice_providers.dart';
import '../../data/models/tax_report_data.dart';
import '../../data/models/work_report_data.dart';
import '../../data/templates/tax_report_template.dart';
import '../../data/templates/timesheet_template.dart';
import 'report_preview_page.dart';

class ReportsPage extends ConsumerStatefulWidget {
  const ReportsPage({super.key});

  @override
  ConsumerState<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends ConsumerState<ReportsPage> {
  DateTimeRange? _dateRange;
  int? _selectedClientId;
  int? _selectedProjectId;
  bool _isLoading = false;

  // Timesheet column toggles
  bool _showStartEnd = true;
  bool _showDescription = true;
  bool _showProject = false;

  // Tax report options
  bool _includeArchived = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateRange =
        DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _dateRange,
    );
    if (picked != null) setState(() => _dateRange = picked);
  }

  Future<WorkReportData?> _fetchData() async {
    if (_dateRange == null) return null;

    final start = _dateRange!.start;
    final end = _dateRange!.end.add(const Duration(days: 1));

    final timeDao = ref.read(timeEntryDaoProvider);
    final profileDao = ref.read(userProfileDaoProvider);
    final clientDao = ref.read(clientDaoProvider);
    final projectDao = ref.read(projectDaoProvider);

    final profile = await profileDao.getProfile();
    final entries = await timeDao.getAllEntries(
      from: start,
      to: end,
      clientId: _selectedClientId,
      projectId: _selectedProjectId,
    );

    Client? client;
    if (_selectedClientId != null) {
      client = await clientDao.getClient(_selectedClientId!);
    }
    Project? project;
    if (_selectedProjectId != null) {
      project = await projectDao.getProject(_selectedProjectId!);
    }

    final projectIds =
        entries.map((e) => e.projectId).whereType<int>().toSet();
    final projectNames = <int, String>{};
    for (final pid in projectIds) {
      try {
        final p = await projectDao.getProject(pid);
        projectNames[pid] = p.name;
      } catch (_) {
        projectNames[pid] = 'Unknown Project';
      }
    }

    return WorkReportData(
      profile: profile,
      startDate: start,
      endDate: _dateRange!.end,
      entries: entries,
      client: client,
      project: project,
      projectNames: projectNames,
    );
  }

  Future<void> _generateWorkReport() async {
    setState(() => _isLoading = true);
    try {
      final data = await _fetchData();
      if (data == null || !mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReportPreviewPage(data: data)),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _generateTimesheet() async {
    setState(() => _isLoading = true);
    try {
      final data = await _fetchData();
      if (data == null || !mounted) return;

      final template = TimesheetTemplate(
        columns: TimesheetColumns(
          showStartEnd: _showStartEnd,
          showDescription: _showDescription,
          showProject: _showProject,
        ),
      );
      final doc = await template.build(data);
      final bytes = await doc.save();

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _TimesheetPreviewPage(
            pdfBytes: bytes,
            title: 'Timesheet',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<TaxReportData?> _fetchTaxReportData() async {
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
      if (inv.issueDate.isBefore(_dateRange!.start)) return false;
      if (inv.issueDate.isAfter(endOfDay)) return false;
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

  Future<void> _generateTaxReport() async {
    setState(() => _isLoading = true);
    try {
      final data = await _fetchTaxReportData();
      if (data == null || !mounted) return;
      if (data.rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(_includeArchived
                ? 'No paid or archived invoices in the selected period.'
                : 'No paid invoices in the selected period.')));
        return;
      }
      final bytes =
          await (await const TaxReportTemplate().build(data)).save();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            _TimesheetPreviewPage(pdfBytes: bytes, title: 'Tax Report'),
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

  Future<void> _exportTaxReportCsv() async {
    setState(() => _isLoading = true);
    try {
      final data = await _fetchTaxReportData();
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
        subject: 'Tax Report',
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
      final data = await _fetchData();
      if (data == null || !mounted) return;

      final clientDao = ref.read(clientDaoProvider);
      final clientIds = data.entries.map((e) => e.clientId).toSet();
      final clientNames = <int, String>{};
      for (final cid in clientIds) {
        try {
          final c = await clientDao.getClient(cid);
          clientNames[cid] = c.name;
        } catch (_) {
          clientNames[cid] = 'Unknown';
        }
      }

      final exportService = ref.read(exportServiceProvider);
      final file = await exportService.generateTimeEntriesCsv(
        entries: data.entries,
        projectNames: data.projectNames,
        clientNames: clientNames,
      );

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'Time entries export',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientsAsync = ref.watch(activeClientsProvider);
    final projectsAsync = ref.watch(allActiveProjectsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports & Export')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Filters ────────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Filters', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 16),

                    InkWell(
                      onTap: _pickDateRange,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Date Range',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.date_range),
                        ),
                        child: Text(
                          _dateRange == null
                              ? 'Select dates'
                              : '${_fmt(_dateRange!.start)} – ${_fmt(_dateRange!.end)}',
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
                            onChanged: (val) => setState(() {
                              _selectedClientId = val;
                              _selectedProjectId = null;
                            }),
                          ),
                        ),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Error loading clients'),
                    ),
                    const SizedBox(height: 12),

                    projectsAsync.when(
                      data: (projects) {
                        final filtered = _selectedClientId == null
                            ? projects
                            : projects
                                .where(
                                    (p) => p.clientId == _selectedClientId)
                                .toList();
                        return InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Project (optional)',
                            border: OutlineInputBorder(),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              value: _selectedProjectId,
                              isDense: true,
                              items: [
                                const DropdownMenuItem(
                                    value: null,
                                    child: Text('All Projects')),
                                ...filtered.map((p) => DropdownMenuItem(
                                      value: p.id,
                                      child: Text(p.name),
                                    )),
                              ],
                              onChanged: (val) =>
                                  setState(() => _selectedProjectId = val),
                            ),
                          ),
                        );
                      },
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) =>
                          const Text('Error loading projects'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Timesheet ──────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Timesheet', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Clean hours sheet for employers — choose which '
                      'columns to include.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Start / End'),
                          selected: _showStartEnd,
                          onSelected: (v) =>
                              setState(() => _showStartEnd = v),
                        ),
                        FilterChip(
                          label: const Text('Description'),
                          selected: _showDescription,
                          onSelected: (v) =>
                              setState(() => _showDescription = v),
                        ),
                        FilterChip(
                          label: const Text('Project'),
                          selected: _showProject,
                          onSelected: (v) =>
                              setState(() => _showProject = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _generateTimesheet,
                        icon: const Icon(Icons.table_chart_outlined),
                        label: const Text('Generate Timesheet PDF'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Work Report ────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Work Report', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Detailed PDF grouped by day with project, '
                      'description, and issue references.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _generateWorkReport,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('Generate Work Report PDF'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── CSV Export ─────────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CSV Export', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Export all fields to a spreadsheet-compatible '
                      'CSV file.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
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

            const SizedBox(height: 16),

            // ── Tax / Income Report ────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tax / Income Report',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Net income, tax collected, and total paid. '
                      'Uses the date range and client filter above.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
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
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : _generateTaxReport,
                        icon: const Icon(Icons.receipt_long_outlined),
                        label: const Text('Generate PDF'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _exportTaxReportCsv,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('Export CSV'),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── WA Excise Tax ──────────────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WA Excise Tax (B&O)',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      'Quarterly B&O return for WA state. Generates a '
                      'DOR-format CSV ready to upload at MyDOR. Tracks '
                      'which quarters have been submitted.',
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

            if (_isLoading) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime dt) => DateFormat('MMM d, yyyy').format(dt);
}

// ── Timesheet preview page ──────────────────────────────────────────

class _TimesheetPreviewPage extends StatelessWidget {
  final Uint8List pdfBytes;
  final String title;

  const _TimesheetPreviewPage(
      {required this.pdfBytes, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Share PDF',
            onPressed: () => _share(),
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
    final dir = await Directory.systemTemp.createTemp('timesheet_');
    final file =
        File('${dir.path}/${title.replaceAll(' ', '_')}.pdf');
    await file.writeAsBytes(pdfBytes);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: title,
      ),
    );
  }
}
