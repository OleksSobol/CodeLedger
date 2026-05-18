import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/database/daos/client_dao.dart';
import '../../../../core/providers/database_provider.dart';
import '../../../projects/presentation/providers/project_providers.dart';

final clientDaoProvider = Provider<ClientDao>((ref) {
  return ClientDao(ref.watch(databaseProvider));
});

final activeClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(clientDaoProvider).watchActiveClients();
});

final allClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(clientDaoProvider).watchAllClients();
});

/// Fetches a single client by ID.
final clientByIdProvider =
    FutureProvider.family<Client, int>((ref, clientId) async {
  return ref.watch(clientDaoProvider).getClient(clientId);
});

/// Provides summary data for a single client.
class ClientSummary {
  final Client client;
  final double uninvoicedHours;
  final double totalBilled;
  final double totalPaid;

  const ClientSummary({
    required this.client,
    required this.uninvoicedHours,
    required this.totalBilled,
    required this.totalPaid,
  });
}

final clientSummaryProvider =
    FutureProvider.family<ClientSummary, int>((ref, clientId) async {
  final dao = ref.watch(clientDaoProvider);
  final client = await dao.getClient(clientId);
  final uninvoiced = await dao.getUninvoicedHours(clientId);
  final billed = await dao.getTotalBilled(clientId);
  final paid = await dao.getTotalPaid(clientId);
  return ClientSummary(
    client: client,
    uninvoicedHours: uninvoiced,
    totalBilled: billed,
    totalPaid: paid,
  );
});

final clientNotifierProvider =
    AsyncNotifierProvider<ClientNotifier, List<Client>>(ClientNotifier.new);

class ClientNotifier extends AsyncNotifier<List<Client>> {
  late ClientDao _dao;

  @override
  Future<List<Client>> build() async {
    _dao = ref.watch(clientDaoProvider);
    return _dao.getActiveClients();
  }

  Future<int> addClient({
    required String name,
    String? contactName,
    String? email,
    String? phone,
    String? addressLine1,
    String? addressLine2,
    String? city,
    String? stateProvince,
    String? postalCode,
    String? country,
    double? hourlyRate,
    String currency = 'USD',
    double? taxRate,
    String? paymentTermsOverride,
    int? paymentTermsDaysOverride,
    String? notes,
  }) async {
    final id = await _dao.insertClient(ClientsCompanion.insert(
      name: name,
      contactName: Value(contactName),
      email: Value(email),
      phone: Value(phone),
      addressLine1: Value(addressLine1),
      addressLine2: Value(addressLine2),
      city: Value(city),
      stateProvince: Value(stateProvince),
      postalCode: Value(postalCode),
      country: Value(country),
      hourlyRate: Value(hourlyRate),
      currency: Value(currency),
      taxRate: Value(taxRate),
      paymentTermsOverride: Value(paymentTermsOverride),
      paymentTermsDaysOverride: Value(paymentTermsDaysOverride),
      notes: Value(notes),
    ));
    ref.invalidateSelf();
    return id;
  }

  Future<bool> updateClient(int id, ClientsCompanion companion) async {
    final result = await _dao.updateClient(id, companion);
    if (result) {
      ref.invalidateSelf();
      ref.invalidate(clientSummaryProvider(id));
      ref.invalidate(clientByIdProvider(id));
    }
    return result;
  }

  Future<bool> archiveClient(int id) async {
    final result = await _dao.archiveClient(id);
    if (result) {
      ref.invalidateSelf();
      ref.invalidate(clientSummaryProvider(id));
      ref.invalidate(clientByIdProvider(id));
    }
    return result;
  }

  /// Check if client has time entries, invoices, or projects.
  Future<bool> hasLinkedRecords(int id) async {
    if (await _dao.hasLinkedRecords(id)) return true;
    return ref.read(projectDaoProvider).hasProjectsForClient(id);
  }

  /// Permanently delete a client (only if no linked records).
  Future<void> deleteClient(int id) async {
    await _dao.deleteClient(id);
    ref.invalidateSelf();
  }
}
