import '../database/app_database.dart';

abstract class ClientRepository {
  Stream<List<Client>> watchAllClients();
  Stream<List<Client>> watchActiveClients();
  Future<List<Client>> getActiveClients();
  Future<Client> getClient(String id);
  Future<String> insertClient(ClientsCompanion companion);
  Future<bool> updateClient(String id, ClientsCompanion companion);
  Future<bool> archiveClient(String id);
  Future<bool> hasLinkedRecords(String clientId);
  Future<int> deleteClient(String id);
  Future<double> getUninvoicedHours(String clientId);
  Future<double> getTotalBilled(String clientId);
  Future<double> getTotalPaid(String clientId);
}
