import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../database/app_database.dart';
import '../client_repository.dart';

class SupabaseClientRepository implements ClientRepository {
  final SupabaseClient _client;
  SupabaseClientRepository(this._client);

  String get _uid => _client.auth.currentUser!.id;

  Client _fromRow(Map<String, dynamic> r) => Client(
        id: r['id'] as String,
        name: r['name'] as String,
        contactName: r['contact_name'] as String?,
        email: r['email'] as String?,
        phone: r['phone'] as String?,
        addressLine1: r['address_line1'] as String?,
        addressLine2: r['address_line2'] as String?,
        city: r['city'] as String?,
        stateProvince: r['state_province'] as String?,
        postalCode: r['postal_code'] as String?,
        country: r['country'] as String?,
        hourlyRate: (r['hourly_rate'] as num?)?.toDouble(),
        currency: r['currency'] as String? ?? 'USD',
        taxRate: (r['tax_rate'] as num?)?.toDouble(),
        defaultTemplateId: r['default_template_id'] as String?,
        paymentTermsOverride: r['payment_terms_override'] as String?,
        paymentTermsDaysOverride: r['payment_terms_days_override'] as int?,
        notes: r['notes'] as String?,
        isArchived: r['is_archived'] as bool? ?? false,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  @override
  Stream<List<Client>> watchAllClients() => Stream.fromFuture(_fetchAll());

  Future<List<Client>> _fetchAll() async {
    final rows = await _client
        .from('clients')
        .select()
        .order('is_archived')
        .order('name');
    return rows.map(_fromRow).toList();
  }

  @override
  Stream<List<Client>> watchActiveClients() =>
      Stream.fromFuture(getActiveClients());

  @override
  Future<List<Client>> getActiveClients() async {
    final rows = await _client
        .from('clients')
        .select()
        .eq('is_archived', false)
        .order('name');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Client> getClient(String id) async {
    final row =
        await _client.from('clients').select().eq('id', id).single();
    return _fromRow(row);
  }

  @override
  Future<String> insertClient(ClientsCompanion companion) async {
    const uuid = Uuid();
    final id = uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('clients').insert({
      'id': id,
      'user_id': _uid,
      'name': companion.name.value,
      if (companion.contactName.present) 'contact_name': companion.contactName.value,
      if (companion.email.present) 'email': companion.email.value,
      if (companion.phone.present) 'phone': companion.phone.value,
      if (companion.addressLine1.present) 'address_line1': companion.addressLine1.value,
      if (companion.addressLine2.present) 'address_line2': companion.addressLine2.value,
      if (companion.city.present) 'city': companion.city.value,
      if (companion.stateProvince.present) 'state_province': companion.stateProvince.value,
      if (companion.postalCode.present) 'postal_code': companion.postalCode.value,
      if (companion.country.present) 'country': companion.country.value,
      if (companion.hourlyRate.present) 'hourly_rate': companion.hourlyRate.value,
      'currency': companion.currency.present ? companion.currency.value : 'USD',
      if (companion.taxRate.present) 'tax_rate': companion.taxRate.value,
      if (companion.defaultTemplateId.present) 'default_template_id': companion.defaultTemplateId.value,
      if (companion.paymentTermsOverride.present) 'payment_terms_override': companion.paymentTermsOverride.value,
      if (companion.paymentTermsDaysOverride.present) 'payment_terms_days_override': companion.paymentTermsDaysOverride.value,
      if (companion.notes.present) 'notes': companion.notes.value,
      'is_archived': false,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  @override
  Future<bool> updateClient(String id, ClientsCompanion companion) async {
    final map = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (companion.name.present) map['name'] = companion.name.value;
    if (companion.contactName.present) map['contact_name'] = companion.contactName.value;
    if (companion.email.present) map['email'] = companion.email.value;
    if (companion.phone.present) map['phone'] = companion.phone.value;
    if (companion.addressLine1.present) map['address_line1'] = companion.addressLine1.value;
    if (companion.addressLine2.present) map['address_line2'] = companion.addressLine2.value;
    if (companion.city.present) map['city'] = companion.city.value;
    if (companion.stateProvince.present) map['state_province'] = companion.stateProvince.value;
    if (companion.postalCode.present) map['postal_code'] = companion.postalCode.value;
    if (companion.country.present) map['country'] = companion.country.value;
    if (companion.hourlyRate.present) map['hourly_rate'] = companion.hourlyRate.value;
    if (companion.currency.present) map['currency'] = companion.currency.value;
    if (companion.taxRate.present) map['tax_rate'] = companion.taxRate.value;
    if (companion.defaultTemplateId.present) map['default_template_id'] = companion.defaultTemplateId.value;
    if (companion.paymentTermsOverride.present) map['payment_terms_override'] = companion.paymentTermsOverride.value;
    if (companion.paymentTermsDaysOverride.present) map['payment_terms_days_override'] = companion.paymentTermsDaysOverride.value;
    if (companion.notes.present) map['notes'] = companion.notes.value;
    if (companion.isArchived.present) map['is_archived'] = companion.isArchived.value;
    final result = await _client.from('clients').update(map).eq('id', id).select();
    return result.isNotEmpty;
  }

  @override
  Future<bool> archiveClient(String id) async {
    final result = await _client.from('clients').update({
      'is_archived': true,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).select();
    return result.isNotEmpty;
  }

  @override
  Future<bool> hasLinkedRecords(String clientId) async {
    final entries = await _client
        .from('time_entries')
        .select('id')
        .eq('client_id', clientId)
        .limit(1);
    if (entries.isNotEmpty) return true;
    final invoices = await _client
        .from('invoices')
        .select('id')
        .eq('client_id', clientId)
        .limit(1);
    return invoices.isNotEmpty;
  }

  @override
  Future<int> deleteClient(String id) async {
    await _client.from('clients').delete().eq('id', id);
    return 1;
  }

  @override
  Future<double> getUninvoicedHours(String clientId) async {
    final rows = await _client
        .from('time_entries')
        .select('duration_minutes')
        .eq('client_id', clientId)
        .eq('is_invoiced', false)
        .not('end_time', 'is', null);
    return rows.fold<double>(
      0,
      (sum, r) => sum + ((r['duration_minutes'] as int?) ?? 0) / 60.0,
    );
  }

  @override
  Future<double> getTotalBilled(String clientId) async {
    final rows = await _client
        .from('invoices')
        .select('total')
        .eq('client_id', clientId);
    return rows.fold<double>(
        0, (sum, r) => sum + ((r['total'] as num?) ?? 0).toDouble());
  }

  @override
  Future<double> getTotalPaid(String clientId) async {
    final rows = await _client
        .from('invoices')
        .select('amount_paid')
        .eq('client_id', clientId)
        .eq('status', 'paid');
    return rows.fold<double>(
        0, (sum, r) => sum + ((r['amount_paid'] as num?) ?? 0).toDouble());
  }
}
