import 'dart:async';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/app_database.dart';
import '../database/daos/app_settings_dao.dart';

// ── Status ──────────────────────────────────────────────────────────────────

enum SyncState { idle, syncing, error }

class SyncStatus {
  final SyncState state;
  final DateTime? lastSyncedAt;
  final String? error;

  const SyncStatus._({required this.state, this.lastSyncedAt, this.error});

  factory SyncStatus.idle(DateTime? lastSyncedAt) =>
      SyncStatus._(state: SyncState.idle, lastSyncedAt: lastSyncedAt);
  factory SyncStatus.syncing(DateTime? lastSyncedAt) =>
      SyncStatus._(state: SyncState.syncing, lastSyncedAt: lastSyncedAt);
  factory SyncStatus.error(String msg, DateTime? lastSyncedAt) =>
      SyncStatus._(state: SyncState.error, error: msg, lastSyncedAt: lastSyncedAt);
}

// ── Service ─────────────────────────────────────────────────────────────────

/// Bidirectional sync between the local Drift database and Supabase.
///
/// Strategy: upload-first, then download.
///   1. Push all local rows to Supabase (upsert — Supabase keeps newest by
///      updated_at if RLS allows, otherwise last-write-wins).
///   2. Pull all rows for this user from Supabase and upsert into Drift.
///
/// Deletions are NOT propagated (rows survive on both sides until explicitly
/// removed on each platform). Archive instead of delete for clients/projects.
class SyncService {
  final AppDatabase _db;
  final SupabaseClient _supabase;
  final AppSettingsDao _settings;

  static const _lastSyncKey = 'sync_last_at';

  final _statusController = StreamController<SyncStatus>.broadcast();
  DateTime? _lastSyncedAt;

  SyncService(this._db, this._supabase)
      : _settings = AppSettingsDao(_db);

  Stream<SyncStatus> get statusStream => _statusController.stream;
  SyncStatus get currentStatus => SyncStatus.idle(_lastSyncedAt);

  String get _uid => _supabase.auth.currentUser!.id;

  Future<void> init() async {
    final stored = await _settings.getValue(_lastSyncKey);
    if (stored != null) _lastSyncedAt = DateTime.tryParse(stored);
    _emit(SyncStatus.idle(_lastSyncedAt));
  }

  void _emit(SyncStatus status) => _statusController.add(status);

  Future<void> dispose() => _statusController.close();

  // ── Public API ─────────────────────────────────────────────────────────────

  Future<void> sync() async {
    if (_statusController.isClosed) return;
    _emit(SyncStatus.syncing(_lastSyncedAt));
    try {
      await _upload();
      await _download();
      _lastSyncedAt = DateTime.now();
      await _settings.setValue(_lastSyncKey, _lastSyncedAt!.toIso8601String());
      _emit(SyncStatus.idle(_lastSyncedAt));
    } catch (e) {
      _emit(SyncStatus.error(e.toString(), _lastSyncedAt));
      rethrow;
    }
  }

  // ── Upload (Drift → Supabase) ───────────────────────────────────────────

  Future<void> _upload() async {
    await _upsertBatch('user_profiles', await _profileRows());
    await _upsertBatch('clients', await _clientRows());
    await _upsertBatch('projects', await _projectRows());
    await _upsertBatch('time_entries', await _timeEntryRows());
    await _upsertBatch('invoice_templates', await _templateRows());
    await _upsertBatch('invoices', await _invoiceRows());
    await _upsertBatch('invoice_line_items', await _lineItemRows());
    await _upsertBatch('expenses', await _expenseRows());
  }

  Future<void> _upsertBatch(String table, List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    for (var i = 0; i < rows.length; i += 100) {
      final chunk = rows.sublist(i, (i + 100).clamp(0, rows.length));
      await _supabase.from(table).upsert(chunk);
    }
  }

  Future<List<Map<String, dynamic>>> _profileRows() async {
    final rows = await _db.select(_db.userProfiles).get();
    return rows.map((p) => {
      'id': p.id,
      'user_id': _uid,
      'business_name': p.businessName,
      'owner_name': p.ownerName,
      'email': p.email,
      'phone': p.phone,
      'address_line1': p.addressLine1,
      'address_line2': p.addressLine2,
      'city': p.city,
      'state_province': p.stateProvince,
      'postal_code': p.postalCode,
      'country': p.country,
      'tax_id': p.taxId,
      'show_tax_id': p.showTaxId,
      'wa_business_license': p.waBusinessLicense,
      'show_wa_license': p.showWaLicense,
      'logo_path': p.logoPath,
      'bank_name': p.bankName,
      'bank_account_name': p.bankAccountName,
      'bank_account_number': p.bankAccountNumber,
      'bank_routing_number': p.bankRoutingNumber,
      'bank_account_type': p.bankAccountType,
      'bank_swift': p.bankSwift,
      'bank_iban': p.bankIban,
      'show_bank_details': p.showBankDetails,
      'stripe_payment_link': p.stripePaymentLink,
      'show_stripe_link': p.showStripeLink,
      'payment_instructions': p.paymentInstructions,
      'default_currency': p.defaultCurrency,
      'default_hourly_rate': p.defaultHourlyRate,
      'default_tax_label': p.defaultTaxLabel,
      'default_tax_rate': p.defaultTaxRate,
      'default_payment_terms': p.defaultPaymentTerms,
      'default_payment_terms_days': p.defaultPaymentTermsDays,
      'late_fee_percentage': p.lateFeePercentage,
      'default_template_id': p.defaultTemplateId,
      'default_email_subject_format': p.defaultEmailSubjectFormat,
      'next_invoice_number': p.nextInvoiceNumber,
      'invoice_number_prefix': p.invoiceNumberPrefix,
      'created_at': p.createdAt.toUtc().toIso8601String(),
      'updated_at': p.updatedAt.toUtc().toIso8601String(),
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _clientRows() async {
    final rows = await _db.select(_db.clients).get();
    return rows.map((c) => {
      'id': c.id,
      'user_id': _uid,
      'name': c.name,
      'contact_name': c.contactName,
      'email': c.email,
      'phone': c.phone,
      'address_line1': c.addressLine1,
      'address_line2': c.addressLine2,
      'city': c.city,
      'state_province': c.stateProvince,
      'postal_code': c.postalCode,
      'country': c.country,
      'hourly_rate': c.hourlyRate,
      'currency': c.currency,
      'tax_rate': c.taxRate,
      'default_template_id': c.defaultTemplateId,
      'payment_terms_override': c.paymentTermsOverride,
      'payment_terms_days_override': c.paymentTermsDaysOverride,
      'notes': c.notes,
      'is_archived': c.isArchived,
      'created_at': c.createdAt.toUtc().toIso8601String(),
      'updated_at': c.updatedAt.toUtc().toIso8601String(),
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _projectRows() async {
    final rows = await _db.select(_db.projects).get();
    return rows.map((p) => {
      'id': p.id,
      'user_id': _uid,
      'client_id': p.clientId,
      'name': p.name,
      'description': p.description,
      'hourly_rate_override': p.hourlyRateOverride,
      'color': p.color,
      'github_repo': p.githubRepo,
      'is_active': p.isActive,
      'is_archived': p.isArchived,
      'created_at': p.createdAt.toUtc().toIso8601String(),
      'updated_at': p.updatedAt.toUtc().toIso8601String(),
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _timeEntryRows() async {
    final rows = await _db.select(_db.timeEntries).get();
    return rows.map((e) => {
      'id': e.id,
      'user_id': _uid,
      'client_id': e.clientId,
      'project_id': e.projectId,
      'start_time': e.startTime.toUtc().toIso8601String(),
      'end_time': e.endTime?.toUtc().toIso8601String(),
      'duration_minutes': e.durationMinutes,
      'description': e.description,
      'issue_reference': e.issueReference,
      'repository': e.repository,
      'tags': e.tags,
      'is_manual': e.isManual,
      'hourly_rate_snapshot': e.hourlyRateSnapshot,
      'is_invoiced': e.isInvoiced,
      'invoice_id': e.invoiceId,
      'created_at': e.createdAt.toUtc().toIso8601String(),
      'updated_at': e.updatedAt.toUtc().toIso8601String(),
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _templateRows() async {
    final rows = await _db.select(_db.invoiceTemplates).get();
    return rows.map((t) => {
      'id': t.id,
      'user_id': _uid,
      'name': t.name,
      'template_key': t.templateKey,
      'description': t.description,
      'is_default': t.isDefault,
      'primary_color': t.primaryColor,
      'accent_color': t.accentColor,
      'font_family': t.fontFamily,
      'show_logo': t.showLogo,
      'show_payment_info': t.showPaymentInfo,
      'show_tax_breakdown': t.showTaxBreakdown,
      'show_tax_id': t.showTaxId,
      'show_business_license': t.showBusinessLicense,
      'show_bank_details': t.showBankDetails,
      'show_stripe_link': t.showStripeLink,
      'show_detailed_breakdown': t.showDetailedBreakdown,
      'show_payment_terms': t.showPaymentTerms,
      'show_late_fee_clause': t.showLateFeeClause,
      'show_description': t.showDescription,
      'footer_text': t.footerText,
      'is_built_in': t.isBuiltIn,
      'line_item_display_mode': t.lineItemDisplayMode,
      'created_at': t.createdAt.toUtc().toIso8601String(),
      'updated_at': t.updatedAt.toUtc().toIso8601String(),
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _invoiceRows() async {
    final rows = await _db.select(_db.invoices).get();
    return rows.map((inv) => {
      'id': inv.id,
      'user_id': _uid,
      'client_id': inv.clientId,
      'invoice_number': inv.invoiceNumber,
      'status': inv.status,
      'issue_date': inv.issueDate.toUtc().toIso8601String(),
      'due_date': inv.dueDate.toUtc().toIso8601String(),
      'period_start': inv.periodStart?.toUtc().toIso8601String(),
      'period_end': inv.periodEnd?.toUtc().toIso8601String(),
      'subtotal': inv.subtotal,
      'tax_rate': inv.taxRate,
      'tax_label': inv.taxLabel,
      'tax_amount': inv.taxAmount,
      'late_fee_amount': inv.lateFeeAmount,
      'total': inv.total,
      'amount_paid': inv.amountPaid,
      'currency': inv.currency,
      'notes': inv.notes,
      'template_id': inv.templateId,
      'template_type': inv.templateType,
      'pdf_path': inv.pdfPath,
      'payment_method': inv.paymentMethod,
      'paid_date': inv.paidDate?.toUtc().toIso8601String(),
      'sent_date': inv.sentDate?.toUtc().toIso8601String(),
      'created_at': inv.createdAt.toUtc().toIso8601String(),
      'updated_at': inv.updatedAt.toUtc().toIso8601String(),
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _lineItemRows() async {
    final rows = await _db.select(_db.invoiceLineItems).get();
    return rows.map((li) => {
      'id': li.id,
      'user_id': _uid,
      'invoice_id': li.invoiceId,
      'sort_order': li.sortOrder,
      'description': li.description,
      'quantity': li.quantity,
      'unit_price': li.unitPrice,
      'total': li.total,
      'time_entry_id': li.timeEntryId,
      'project_id': li.projectId,
      'issue_reference': li.issueReference,
      'created_at': li.createdAt.toUtc().toIso8601String(),
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _expenseRows() async {
    final rows = await _db.select(_db.expenses).get();
    return rows.map((e) => {
      'id': e.id,
      'user_id': _uid,
      'name': e.name,
      'category': e.category,
      'amount': e.amount,
      'frequency': e.frequency,
      'deduction_method': e.deductionMethod,
      'manual_percentage': e.manualPercentage,
      'work_hours_per_day': e.workHoursPerDay,
      'total_hours_per_day': e.totalHoursPerDay,
      'work_space_sqft': e.workSpaceSqft,
      'total_space_sqft': e.totalSpaceSqft,
      'start_date': e.startDate.toUtc().toIso8601String(),
      'end_date': e.endDate?.toUtc().toIso8601String(),
      'notes': e.notes,
      'created_at': e.createdAt.toUtc().toIso8601String(),
    }).toList();
  }

  // ── Download (Supabase → Drift) ─────────────────────────────────────────

  Future<void> _download() async {
    await _downloadProfiles();
    await _downloadClients();
    await _downloadProjects();
    await _downloadTemplates();
    // Invoices before line items (FK dependency)
    await _downloadInvoices();
    // Time entries before line items (FK dependency)
    await _downloadTimeEntries();
    await _downloadLineItems();
    await _downloadExpenses();
  }

  Future<void> _downloadProfiles() async {
    final rows = await _supabase
        .from('user_profiles')
        .select()
        .eq('user_id', _uid);
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.userProfiles).insertOnConflictUpdate(
          UserProfilesCompanion(
            id: Value(r['id'] as String),
            businessName: Value(r['business_name'] as String? ?? ''),
            ownerName: Value(r['owner_name'] as String? ?? ''),
            email: Value(r['email'] as String?),
            phone: Value(r['phone'] as String?),
            addressLine1: Value(r['address_line1'] as String?),
            addressLine2: Value(r['address_line2'] as String?),
            city: Value(r['city'] as String?),
            stateProvince: Value(r['state_province'] as String?),
            postalCode: Value(r['postal_code'] as String?),
            country: Value(r['country'] as String?),
            taxId: Value(r['tax_id'] as String?),
            showTaxId: Value(r['show_tax_id'] as bool? ?? true),
            waBusinessLicense: Value(r['wa_business_license'] as String?),
            showWaLicense: Value(r['show_wa_license'] as bool? ?? false),
            logoPath: Value(r['logo_path'] as String?),
            bankName: Value(r['bank_name'] as String?),
            bankAccountName: Value(r['bank_account_name'] as String?),
            bankAccountNumber: Value(r['bank_account_number'] as String?),
            bankRoutingNumber: Value(r['bank_routing_number'] as String?),
            bankAccountType: Value(r['bank_account_type'] as String? ?? 'checking'),
            bankSwift: Value(r['bank_swift'] as String?),
            bankIban: Value(r['bank_iban'] as String?),
            showBankDetails: Value(r['show_bank_details'] as bool? ?? true),
            stripePaymentLink: Value(r['stripe_payment_link'] as String?),
            showStripeLink: Value(r['show_stripe_link'] as bool? ?? false),
            paymentInstructions: Value(r['payment_instructions'] as String?),
            defaultCurrency: Value(r['default_currency'] as String? ?? 'USD'),
            defaultHourlyRate: Value((r['default_hourly_rate'] as num?)?.toDouble() ?? 0.0),
            defaultTaxLabel: Value(r['default_tax_label'] as String? ?? 'Tax'),
            defaultTaxRate: Value((r['default_tax_rate'] as num?)?.toDouble() ?? 0.0),
            defaultPaymentTerms: Value(r['default_payment_terms'] as String? ?? 'net_30'),
            defaultPaymentTermsDays: Value(r['default_payment_terms_days'] as int? ?? 30),
            lateFeePercentage: Value((r['late_fee_percentage'] as num?)?.toDouble()),
            defaultTemplateId: Value(r['default_template_id'] as String?),
            defaultEmailSubjectFormat: Value(r['default_email_subject_format'] as String? ?? 'Invoice #{number} - {period}'),
            nextInvoiceNumber: Value(r['next_invoice_number'] as int? ?? 1),
            invoiceNumberPrefix: Value(r['invoice_number_prefix'] as String? ?? 'INV-'),
            createdAt: Value(DateTime.parse(r['created_at'] as String)),
            updatedAt: Value(DateTime.parse(r['updated_at'] as String)),
          ),
        );
      }
    });
  }

  Future<void> _downloadClients() async {
    final rows = await _supabase.from('clients').select().eq('user_id', _uid);
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.clients).insertOnConflictUpdate(
          ClientsCompanion(
            id: Value(r['id'] as String),
            name: Value(r['name'] as String),
            contactName: Value(r['contact_name'] as String?),
            email: Value(r['email'] as String?),
            phone: Value(r['phone'] as String?),
            addressLine1: Value(r['address_line1'] as String?),
            addressLine2: Value(r['address_line2'] as String?),
            city: Value(r['city'] as String?),
            stateProvince: Value(r['state_province'] as String?),
            postalCode: Value(r['postal_code'] as String?),
            country: Value(r['country'] as String?),
            hourlyRate: Value((r['hourly_rate'] as num?)?.toDouble()),
            currency: Value(r['currency'] as String? ?? 'USD'),
            taxRate: Value((r['tax_rate'] as num?)?.toDouble()),
            defaultTemplateId: Value(r['default_template_id'] as String?),
            paymentTermsOverride: Value(r['payment_terms_override'] as String?),
            paymentTermsDaysOverride: Value(r['payment_terms_days_override'] as int?),
            notes: Value(r['notes'] as String?),
            isArchived: Value(r['is_archived'] as bool? ?? false),
            createdAt: Value(DateTime.parse(r['created_at'] as String)),
            updatedAt: Value(DateTime.parse(r['updated_at'] as String)),
          ),
        );
      }
    });
  }

  Future<void> _downloadProjects() async {
    final rows = await _supabase.from('projects').select().eq('user_id', _uid);
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.projects).insertOnConflictUpdate(
          ProjectsCompanion(
            id: Value(r['id'] as String),
            clientId: Value(r['client_id'] as String),
            name: Value(r['name'] as String),
            description: Value(r['description'] as String?),
            hourlyRateOverride: Value((r['hourly_rate_override'] as num?)?.toDouble()),
            color: Value(r['color'] as int? ?? 0xFF2196F3),
            githubRepo: Value(r['github_repo'] as String?),
            isActive: Value(r['is_active'] as bool? ?? true),
            isArchived: Value(r['is_archived'] as bool? ?? false),
            createdAt: Value(DateTime.parse(r['created_at'] as String)),
            updatedAt: Value(DateTime.parse(r['updated_at'] as String)),
          ),
        );
      }
    });
  }

  Future<void> _downloadTemplates() async {
    final rows = await _supabase.from('invoice_templates').select().eq('user_id', _uid);
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.invoiceTemplates).insertOnConflictUpdate(
          InvoiceTemplatesCompanion(
            id: Value(r['id'] as String),
            name: Value(r['name'] as String),
            templateKey: Value(r['template_key'] as String),
            description: Value(r['description'] as String?),
            isDefault: Value(r['is_default'] as bool? ?? false),
            primaryColor: Value(r['primary_color'] as int? ?? 0xFF2196F3),
            accentColor: Value(r['accent_color'] as int? ?? 0xFF1565C0),
            fontFamily: Value(r['font_family'] as String? ?? 'Helvetica'),
            showLogo: Value(r['show_logo'] as bool? ?? true),
            showPaymentInfo: Value(r['show_payment_info'] as bool? ?? true),
            showTaxBreakdown: Value(r['show_tax_breakdown'] as bool? ?? true),
            showTaxId: Value(r['show_tax_id'] as bool? ?? true),
            showBusinessLicense: Value(r['show_business_license'] as bool? ?? false),
            showBankDetails: Value(r['show_bank_details'] as bool? ?? true),
            showStripeLink: Value(r['show_stripe_link'] as bool? ?? false),
            showDetailedBreakdown: Value(r['show_detailed_breakdown'] as bool? ?? true),
            showPaymentTerms: Value(r['show_payment_terms'] as bool? ?? true),
            showLateFeeClause: Value(r['show_late_fee_clause'] as bool? ?? false),
            showDescription: Value(r['show_description'] as bool? ?? true),
            footerText: Value(r['footer_text'] as String?),
            isBuiltIn: Value(r['is_built_in'] as bool? ?? true),
            lineItemDisplayMode: Value(r['line_item_display_mode'] as String? ?? 'full'),
            createdAt: Value(DateTime.parse(r['created_at'] as String)),
            updatedAt: Value(DateTime.parse(r['updated_at'] as String)),
          ),
        );
      }
    });
  }

  Future<void> _downloadInvoices() async {
    final rows = await _supabase.from('invoices').select().eq('user_id', _uid);
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.invoices).insertOnConflictUpdate(
          InvoicesCompanion(
            id: Value(r['id'] as String),
            clientId: Value(r['client_id'] as String),
            invoiceNumber: Value(r['invoice_number'] as String),
            status: Value(r['status'] as String? ?? 'draft'),
            issueDate: Value(DateTime.parse(r['issue_date'] as String)),
            dueDate: Value(DateTime.parse(r['due_date'] as String)),
            periodStart: Value(r['period_start'] != null ? DateTime.parse(r['period_start'] as String) : null),
            periodEnd: Value(r['period_end'] != null ? DateTime.parse(r['period_end'] as String) : null),
            subtotal: Value((r['subtotal'] as num?)?.toDouble() ?? 0.0),
            taxRate: Value((r['tax_rate'] as num?)?.toDouble() ?? 0.0),
            taxLabel: Value(r['tax_label'] as String? ?? 'Tax'),
            taxAmount: Value((r['tax_amount'] as num?)?.toDouble() ?? 0.0),
            lateFeeAmount: Value((r['late_fee_amount'] as num?)?.toDouble() ?? 0.0),
            total: Value((r['total'] as num?)?.toDouble() ?? 0.0),
            amountPaid: Value((r['amount_paid'] as num?)?.toDouble() ?? 0.0),
            currency: Value(r['currency'] as String? ?? 'USD'),
            notes: Value(r['notes'] as String?),
            templateId: Value(r['template_id'] as String?),
            templateType: Value(r['template_type'] as String? ?? 'detailed'),
            pdfPath: Value(r['pdf_path'] as String?),
            paymentMethod: Value(r['payment_method'] as String?),
            paidDate: Value(r['paid_date'] != null ? DateTime.parse(r['paid_date'] as String) : null),
            sentDate: Value(r['sent_date'] != null ? DateTime.parse(r['sent_date'] as String) : null),
            createdAt: Value(DateTime.parse(r['created_at'] as String)),
            updatedAt: Value(DateTime.parse(r['updated_at'] as String)),
          ),
        );
      }
    });
  }

  Future<void> _downloadTimeEntries() async {
    final rows = await _supabase.from('time_entries').select().eq('user_id', _uid);
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.timeEntries).insertOnConflictUpdate(
          TimeEntriesCompanion(
            id: Value(r['id'] as String),
            clientId: Value(r['client_id'] as String),
            projectId: Value(r['project_id'] as String?),
            startTime: Value(DateTime.parse(r['start_time'] as String)),
            endTime: Value(r['end_time'] != null ? DateTime.parse(r['end_time'] as String) : null),
            durationMinutes: Value(r['duration_minutes'] as int?),
            description: Value(r['description'] as String?),
            issueReference: Value(r['issue_reference'] as String?),
            repository: Value(r['repository'] as String?),
            tags: Value(r['tags'] as String?),
            isManual: Value(r['is_manual'] as bool? ?? false),
            hourlyRateSnapshot: Value((r['hourly_rate_snapshot'] as num).toDouble()),
            isInvoiced: Value(r['is_invoiced'] as bool? ?? false),
            invoiceId: Value(r['invoice_id'] as String?),
            createdAt: Value(DateTime.parse(r['created_at'] as String)),
            updatedAt: Value(DateTime.parse(r['updated_at'] as String)),
          ),
        );
      }
    });
  }

  Future<void> _downloadLineItems() async {
    final rows = await _supabase.from('invoice_line_items').select().eq('user_id', _uid);
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.invoiceLineItems).insertOnConflictUpdate(
          InvoiceLineItemsCompanion(
            id: Value(r['id'] as String),
            invoiceId: Value(r['invoice_id'] as String),
            sortOrder: Value(r['sort_order'] as int? ?? 0),
            description: Value(r['description'] as String),
            quantity: Value((r['quantity'] as num).toDouble()),
            unitPrice: Value((r['unit_price'] as num).toDouble()),
            total: Value((r['total'] as num).toDouble()),
            timeEntryId: Value(r['time_entry_id'] as String?),
            projectId: Value(r['project_id'] as String?),
            issueReference: Value(r['issue_reference'] as String?),
            createdAt: Value(DateTime.parse(r['created_at'] as String)),
          ),
        );
      }
    });
  }

  Future<void> _downloadExpenses() async {
    final rows = await _supabase.from('expenses').select().eq('user_id', _uid);
    await _db.transaction(() async {
      for (final r in rows) {
        await _db.into(_db.expenses).insertOnConflictUpdate(
          ExpensesCompanion(
            id: Value(r['id'] as String),
            name: Value(r['name'] as String),
            category: Value(r['category'] as String? ?? 'other'),
            amount: Value((r['amount'] as num).toDouble()),
            frequency: Value(r['frequency'] as String? ?? 'monthly'),
            deductionMethod: Value(r['deduction_method'] as String? ?? 'manual'),
            manualPercentage: Value((r['manual_percentage'] as num?)?.toDouble()),
            workHoursPerDay: Value((r['work_hours_per_day'] as num?)?.toDouble()),
            totalHoursPerDay: Value((r['total_hours_per_day'] as num?)?.toDouble()),
            workSpaceSqft: Value((r['work_space_sqft'] as num?)?.toDouble()),
            totalSpaceSqft: Value((r['total_space_sqft'] as num?)?.toDouble()),
            startDate: Value(DateTime.parse(r['start_date'] as String)),
            endDate: Value(r['end_date'] != null ? DateTime.parse(r['end_date'] as String) : null),
            notes: Value(r['notes'] as String?),
            createdAt: Value(DateTime.parse(r['created_at'] as String)),
          ),
        );
      }
    });
  }
}
