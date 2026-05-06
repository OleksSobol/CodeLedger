import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../../../../core/database/app_database.dart';
import '../../../../shared/widgets/spacing.dart';
import '../../../pdf_generation/data/models/pdf_invoice_data.dart';
import '../../../pdf_generation/data/pdf_generator.dart';
import '../../../profile/presentation/providers/profile_provider.dart';
import '../providers/template_providers.dart';

class TemplateDesignerPage extends ConsumerStatefulWidget {
  final InvoiceTemplate template;

  const TemplateDesignerPage({super.key, required this.template});

  @override
  ConsumerState<TemplateDesignerPage> createState() =>
      _TemplateDesignerPageState();
}

class _TemplateDesignerPageState extends ConsumerState<TemplateDesignerPage> {
  late TextEditingController _nameCtrl;
  late TextEditingController _descriptionCtrl;
  late TextEditingController _footerCtrl;
  late String _templateKey;
  late Color _primaryColor;
  late Color _accentColor;
  late String _fontFamily;
  late String _lineItemDisplayMode;
  late bool _showDateColumn;
  late bool _showIssueColumn;
  late bool _showLogo;
  late bool _showPaymentInfo;
  late bool _showTaxBreakdown;
  late bool _showTaxId;
  late bool _showBusinessLicense;
  late bool _showBankDetails;
  late bool _showStripeLink;
  late bool _showDetailedBreakdown;
  late bool _showPaymentTerms;
  late bool _showLateFeeClause;

  bool _saving = false;
  int _previewKey = 0;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _nameCtrl = TextEditingController(text: t.name);
    _descriptionCtrl = TextEditingController(text: t.description ?? '');
    _footerCtrl = TextEditingController(text: t.footerText ?? '');
    _templateKey = t.templateKey;
    _primaryColor = Color(t.primaryColor);
    _accentColor = Color(t.accentColor);
    _fontFamily = t.fontFamily;
    _lineItemDisplayMode = t.lineItemDisplayMode;
    _showDateColumn =
        _lineItemDisplayMode == 'full' || _lineItemDisplayMode == 'date_issue';
    _showIssueColumn = _lineItemDisplayMode == 'issue_desc' ||
        _lineItemDisplayMode == 'date_issue';
    _showLogo = t.showLogo;
    _showPaymentInfo = t.showPaymentInfo;
    _showTaxBreakdown = t.showTaxBreakdown;
    _showTaxId = t.showTaxId;
    _showBusinessLicense = t.showBusinessLicense;
    _showBankDetails = t.showBankDetails;
    _showStripeLink = t.showStripeLink;
    _showDetailedBreakdown = t.showDetailedBreakdown;
    _showPaymentTerms = t.showPaymentTerms;
    _showLateFeeClause = t.showLateFeeClause;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  /// Build an InvoiceTemplate from current local state.
  InvoiceTemplate _currentTemplate() {
    // Resolve the base key for built-in templates
    final baseKey = _resolveBaseKey(_templateKey);
    return InvoiceTemplate(
      id: widget.template.id,
      name: _nameCtrl.text.trim(),
      templateKey: baseKey,
      description: _descriptionCtrl.text.trim().isEmpty
          ? null
          : _descriptionCtrl.text.trim(),
      isDefault: widget.template.isDefault,
      primaryColor: _primaryColor.toARGB32(),
      accentColor: _accentColor.toARGB32(),
      fontFamily: _fontFamily,
      lineItemDisplayMode: _lineItemDisplayMode,
      showLogo: _showLogo,
      showPaymentInfo: _showPaymentInfo,
      showTaxBreakdown: _showTaxBreakdown,
      showTaxId: _showTaxId,
      showBusinessLicense: _showBusinessLicense,
      showBankDetails: _showBankDetails,
      showStripeLink: _showStripeLink,
      showDetailedBreakdown: _showDetailedBreakdown,
      showPaymentTerms: _showPaymentTerms,
      showLateFeeClause: _showLateFeeClause,
      footerText: _footerCtrl.text.trim().isEmpty
          ? null
          : _footerCtrl.text.trim(),
      isBuiltIn: widget.template.isBuiltIn,
      createdAt: widget.template.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  /// For custom templates, the key includes a timestamp suffix.
  /// We need the base key (minimal/detailed/modern_developer) for rendering.
  String _resolveBaseKey(String key) {
    for (final base in ['minimal', 'detailed', 'modern_developer']) {
      if (key == base || key.startsWith('${base}_copy')) return base;
    }
    return key;
  }

  void _refreshPreview() {
    setState(() => _previewKey++);
  }

  void _updateLineItemMode() {
    _lineItemDisplayMode = _showDateColumn && _showIssueColumn
        ? 'date_issue'
        : _showDateColumn
            ? 'full'
            : _showIssueColumn
                ? 'issue_desc'
                : 'desc_only';
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Template name is required')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(templateNotifierProvider.notifier)
          .updateTemplate(
            widget.template.id,
            InvoiceTemplatesCompanion(
              name: Value(name),
              lineItemDisplayMode: Value(_lineItemDisplayMode),
              primaryColor: Value(_primaryColor.toARGB32()),
              accentColor: Value(_accentColor.toARGB32()),
              fontFamily: Value(_fontFamily),
              showLogo: Value(_showLogo),
              showPaymentInfo: Value(_showPaymentInfo),
              showTaxBreakdown: Value(_showTaxBreakdown),
              showTaxId: Value(_showTaxId),
              showBusinessLicense: Value(_showBusinessLicense),
              showBankDetails: Value(_showBankDetails),
              showStripeLink: Value(_showStripeLink),
              showDetailedBreakdown: Value(_showDetailedBreakdown),
              showPaymentTerms: Value(_showPaymentTerms),
              showLateFeeClause: Value(_showLateFeeClause),
              footerText: Value(_footerCtrl.text.trim().isEmpty
                  ? null
                  : _footerCtrl.text.trim()),
              updatedAt: Value(DateTime.now()),
            ),
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _pickColor(Color current, ValueChanged<Color> onChanged) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pick a color'),
        content: SingleChildScrollView(
          child: BlockPicker(
            pickerColor: current,
            onColorChanged: (color) {
              onChanged(color);
              Navigator.pop(ctx);
            },
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generatePreviewPdf() async {
    final profileAsync = ref.read(profileProvider);
    final profile = profileAsync.value;

    final now = DateTime.now();
    final sampleProfile = profile ??
        UserProfile(
          id: 1,
          businessName: 'Your Business',
          ownerName: 'Your Name',
          showTaxId: true,
          showWaLicense: false,
          bankAccountType: 'checking',
          showBankDetails: true,
          showStripeLink: false,
          defaultCurrency: 'USD',
          defaultHourlyRate: 75.0,
          defaultTaxLabel: 'Tax',
          defaultTaxRate: 0.0,
          defaultPaymentTerms: 'net_30',
          defaultPaymentTermsDays: 30,
          defaultEmailSubjectFormat: 'Invoice #{number}',
          nextInvoiceNumber: 1,
          invoiceNumberPrefix: 'INV-',
          createdAt: now,
          updatedAt: now,
        );

    final sampleClient = Client(
      id: 1,
      name: 'Sample Client Co.',
      contactName: 'Jane Smith',
      email: 'jane@example.com',
      addressLine1: '456 Client Avenue',
      city: 'Portland',
      stateProvince: 'OR',
      postalCode: '97201',
      country: 'US',
      currency: 'USD',
      isArchived: false,
      createdAt: now,
      updatedAt: now,
    );

    final sampleInvoice = Invoice(
      id: 0,
      clientId: 1,
      invoiceNumber: 'INV-001',
      status: 'draft',
      issueDate: now,
      dueDate: now.add(const Duration(days: 30)),
      periodStart: now.subtract(const Duration(days: 7)),
      periodEnd: now,
      subtotal: 2400.0,
      taxRate: sampleProfile.defaultTaxRate,
      taxLabel: sampleProfile.defaultTaxLabel,
      taxAmount: 2400.0 * sampleProfile.defaultTaxRate / 100,
      lateFeeAmount: 0,
      total: 2400.0 + (2400.0 * sampleProfile.defaultTaxRate / 100),
      amountPaid: 0,
      currency: 'USD',
      templateType: 'detailed',
      createdAt: now,
      updatedAt: now,
    );

    final sampleLineItems = [
      InvoiceLineItem(
        id: 1,
        invoiceId: 0,
        sortOrder: 0,
        description: 'Feb 10, 2024 | Frontend development, UI review',
        issueReference: '#42, #43',
        quantity: 8.0,
        unitPrice: 75.0,
        total: 600.0,
        createdAt: now,
      ),
      InvoiceLineItem(
        id: 2,
        invoiceId: 0,
        sortOrder: 1,
        description: 'Feb 11, 2024 | API integration, testing',
        issueReference: '#44',
        quantity: 6.5,
        unitPrice: 75.0,
        total: 487.5,
        createdAt: now,
      ),
      InvoiceLineItem(
        id: 3,
        invoiceId: 0,
        sortOrder: 2,
        description: 'Feb 12, 2024 | Bug fixes, code review',
        issueReference: '#45',
        quantity: 7.0,
        unitPrice: 75.0,
        total: 525.0,
        createdAt: now,
      ),
      InvoiceLineItem(
        id: 4,
        invoiceId: 0,
        sortOrder: 3,
        description: 'Project setup & consulting',
        quantity: 10.5,
        unitPrice: 75.0,
        total: 787.5,
        createdAt: now,
      ),
    ];

    final template = _currentTemplate();
    final data = PdfInvoiceData(
      invoice: sampleInvoice,
      client: sampleClient,
      profile: sampleProfile,
      template: template,
      lineItems: sampleLineItems,
      projectNames: {1: 'Website Redesign'},
    );

    final doc = await PdfGenerator.generateInvoice(data);
    return doc.save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBuiltIn = widget.template.isBuiltIn;

    return Scaffold(
      appBar: AppBar(
        title: Text(isBuiltIn ? 'Edit Template' : 'Custom Template'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'duplicate') {
                final id = await ref
                    .read(templateNotifierProvider.notifier)
                    .duplicateTemplate(
                        _currentTemplate(), '${_nameCtrl.text} (Copy)');
                if (mounted) {
                  final dao = ref.read(invoiceTemplateDaoProvider);
                  final newTemplate = await dao.getById(id);
                  if (newTemplate != null && mounted) {
                    Navigator.pop(context);
                    context.mounted;
                    // Navigate to the new template's designer
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            TemplateDesignerPage(template: newTemplate),
                      ),
                    );
                  }
                }
              } else if (value == 'default') {
                await ref
                    .read(templateNotifierProvider.notifier)
                    .setDefault(widget.template.id);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Set as default template')),
                  );
                }
              } else if (value == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Template'),
                    content: const Text(
                        'Are you sure you want to delete this template?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete')),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await ref
                      .read(templateNotifierProvider.notifier)
                      .deleteTemplate(widget.template.id);
                  if (mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'duplicate',
                child: ListTile(
                  leading: Icon(Icons.copy),
                  title: Text('Duplicate'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const PopupMenuItem(
                value: 'default',
                child: ListTile(
                  leading: Icon(Icons.star_outline),
                  title: Text('Set as Default'),
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              if (!isBuiltIn)
                const PopupMenuItem(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Delete'),
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(Spacing.md),
        children: [
          // Preview
          Card(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              height: 300,
              child: PdfPreview(
                key: ValueKey(_previewKey),
                build: (_) => _generatePreviewPdf(),
                canChangeOrientation: false,
                canChangePageFormat: false,
                canDebug: false,
                allowPrinting: false,
                allowSharing: false,
                pdfFileName: 'preview.pdf',
              ),
            ),
          ),
          const SizedBox(height: Spacing.lg),

          // Template name & description
          if (!isBuiltIn) ...[
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Template Name',
              ),
            ),
            const SizedBox(height: Spacing.sm),
            TextFormField(
              controller: _descriptionCtrl,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'e.g. Clean minimal layout with tax breakdown',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: Spacing.md),
          ],

          // Base Layout (only for custom templates)
          if (!isBuiltIn) ...[
            _SectionLabel(label: 'Base Layout'),
            const SizedBox(height: Spacing.sm),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'minimal', label: Text('Minimal')),
                ButtonSegment(
                    value: 'detailed', label: Text('Detailed')),
                ButtonSegment(
                    value: 'modern_developer', label: Text('Modern')),
              ],
              selected: {_resolveBaseKey(_templateKey)},
              onSelectionChanged: (selection) {
                setState(() => _templateKey = selection.first);
                _refreshPreview();
              },
              showSelectedIcon: false,
            ),
            const SizedBox(height: Spacing.md),
          ],

          // Colors & Font
          _SectionLabel(label: 'Colors & Font'),
          const SizedBox(height: Spacing.sm),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Primary Color'),
            trailing: GestureDetector(
              onTap: () => _pickColor(_primaryColor, (color) {
                setState(() => _primaryColor = color);
                _refreshPreview();
              }),
              child: CircleAvatar(
                  backgroundColor: _primaryColor, radius: 18),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Accent Color'),
            trailing: GestureDetector(
              onTap: () => _pickColor(_accentColor, (color) {
                setState(() => _accentColor = color);
                _refreshPreview();
              }),
              child: CircleAvatar(
                  backgroundColor: _accentColor, radius: 18),
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _fontFamily,
            decoration: const InputDecoration(
              labelText: 'Font Family',
            ),
            items: const [
              DropdownMenuItem(
                  value: 'Helvetica', child: Text('Helvetica')),
              DropdownMenuItem(
                  value: 'Courier', child: Text('Courier')),
              DropdownMenuItem(
                  value: 'Times', child: Text('Times')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _fontFamily = value);
                _refreshPreview();
              }
            },
          ),
          const SizedBox(height: Spacing.md),

          // Sections
          _SectionLabel(label: 'Sections'),
          const SizedBox(height: Spacing.sm),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Line Item Columns'),
            subtitle: Text(
                'Choose which extra columns appear before the description'),
          ),
          _ToggleTile(
            title: 'Show Date Column',
            value: _showDateColumn,
            onChanged: (v) {
              setState(() {
                _showDateColumn = v;
                _updateLineItemMode();
              });
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Issue # Column',
            value: _showIssueColumn,
            onChanged: (v) {
              setState(() {
                _showIssueColumn = v;
                _updateLineItemMode();
              });
              _refreshPreview();
            },
          ),
          const SizedBox(height: Spacing.sm),
          _ToggleTile(
            title: 'Show Logo',
            value: _showLogo,
            onChanged: (v) {
              setState(() => _showLogo = v);
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Detailed Breakdown',
            value: _showDetailedBreakdown,
            onChanged: (v) {
              setState(() => _showDetailedBreakdown = v);
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Tax Breakdown',
            value: _showTaxBreakdown,
            onChanged: (v) {
              setState(() => _showTaxBreakdown = v);
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Tax ID',
            value: _showTaxId,
            onChanged: (v) {
              setState(() => _showTaxId = v);
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Business License',
            value: _showBusinessLicense,
            onChanged: (v) {
              setState(() => _showBusinessLicense = v);
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Bank Details',
            value: _showBankDetails,
            onChanged: (v) {
              setState(() => _showBankDetails = v);
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Stripe Link',
            value: _showStripeLink,
            onChanged: (v) {
              setState(() => _showStripeLink = v);
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Payment Terms',
            value: _showPaymentTerms,
            onChanged: (v) {
              setState(() => _showPaymentTerms = v);
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Payment Info',
            value: _showPaymentInfo,
            onChanged: (v) {
              setState(() => _showPaymentInfo = v);
              _refreshPreview();
            },
          ),
          _ToggleTile(
            title: 'Show Late Fee Clause',
            value: _showLateFeeClause,
            onChanged: (v) {
              setState(() => _showLateFeeClause = v);
              _refreshPreview();
            },
          ),
          const SizedBox(height: Spacing.md),

          // Footer
          _SectionLabel(label: 'Footer'),
          const SizedBox(height: Spacing.sm),
          TextFormField(
            controller: _footerCtrl,
            decoration: const InputDecoration(
              labelText: 'Footer Text',
              hintText: 'e.g. Thank you for your business!',
            ),
            maxLines: 3,
            onChanged: (_) => _refreshPreview(),
          ),
          const SizedBox(height: Spacing.lg),

          // Set as Default
          OutlinedButton.icon(
            onPressed: () async {
              await ref
                  .read(templateNotifierProvider.notifier)
                  .setDefault(widget.template.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Set as default template')),
                );
              }
            },
            icon: Icon(
              widget.template.isDefault
                  ? Icons.star
                  : Icons.star_outline,
              color: theme.colorScheme.primary,
            ),
            label: Text(widget.template.isDefault
                ? 'Default Template'
                : 'Set as Default'),
          ),
          const SizedBox(height: Spacing.xl),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: Text(title),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }
}
