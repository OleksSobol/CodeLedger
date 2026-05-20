import '../../database/app_database.dart';
import '../../database/daos/client_dao.dart';
import '../client_repository.dart';

class DriftClientRepository implements ClientRepository {
  final ClientDao _dao;
  DriftClientRepository(this._dao);

  @override Stream<List<Client>> watchAllClients() => _dao.watchAllClients();
  @override Stream<List<Client>> watchActiveClients() => _dao.watchActiveClients();
  @override Future<List<Client>> getActiveClients() => _dao.getActiveClients();
  @override Future<Client> getClient(String id) => _dao.getClient(id);
  @override Future<String> insertClient(ClientsCompanion c) => _dao.insertClient(c);
  @override Future<bool> updateClient(String id, ClientsCompanion c) => _dao.updateClient(id, c);
  @override Future<bool> archiveClient(String id) => _dao.archiveClient(id);
  @override Future<bool> hasLinkedRecords(String id) => _dao.hasLinkedRecords(id);
  @override Future<int> deleteClient(String id) => _dao.deleteClient(id);
  @override Future<double> getUninvoicedHours(String id) => _dao.getUninvoicedHours(id);
  @override Future<double> getTotalBilled(String id) => _dao.getTotalBilled(id);
  @override Future<double> getTotalPaid(String id) => _dao.getTotalPaid(id);
}
