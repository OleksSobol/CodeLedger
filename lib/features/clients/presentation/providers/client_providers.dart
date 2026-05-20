import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/client_repository.dart';

final activeClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(clientRepositoryProvider).watchActiveClients();
});

final allClientsProvider = StreamProvider<List<Client>>((ref) {
  return ref.watch(clientRepositoryProvider).watchAllClients();
});

final clientByIdProvider =
    FutureProvider.family<Client, String>((ref, clientId) async {
  return ref.watch(clientRepositoryProvider).getClient(clientId);
});

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
    FutureProvider.family<ClientSummary, String>((ref, clientId) async {
  final repo = ref.watch(clientRepositoryProvider);
  final client = await repo.getClient(clientId);
  final uninvoiced = await repo.getUninvoicedHours(clientId);
  final billed = await repo.getTotalBilled(clientId);
  final paid = await repo.getTotalPaid(clientId);
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
  late ClientRepository _dao;

  @override
  Future<List<Client>> build() async {
    _dao = ref.watch(clientRepositoryProvider);
    return _dao.getActiveClients();
  }

  Future<String> addClient({
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
    final id = await _dao.insertClient(ClientsCompanion(
      name: Value(name),
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

  Future<bool> updateClient(String id, ClientsCompanion companion) async {
    final result = await _dao.updateClient(id, companion);
    if (result) {
      ref.invalidateSelf();
      ref.invalidate(clientSummaryProvider(id));
      ref.invalidate(clientByIdProvider(id));
    }
    return result;
  }

  Future<bool> archiveClient(String id) async {
    final result = await _dao.archiveClient(id);
    if (result) {
      ref.invalidateSelf();
      ref.invalidate(clientSummaryProvider(id));
      ref.invalidate(clientByIdProvider(id));
    }
    return result;
  }

  Future<bool> hasLinkedRecords(String id) => _dao.hasLinkedRecords(id);

  Future<void> deleteClient(String id) async {
    await _dao.deleteClient(id);
    ref.invalidateSelf();
  }
}
