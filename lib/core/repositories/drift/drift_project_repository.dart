import '../../database/app_database.dart';
import '../../database/daos/project_dao.dart';
import '../project_repository.dart';

class DriftProjectRepository implements ProjectRepository {
  final ProjectDao _dao;
  DriftProjectRepository(this._dao);

  @override Stream<List<Project>> watchProjectsForClient(String clientId) => _dao.watchProjectsForClient(clientId);
  @override Future<List<Project>> getProjectsForClient(String clientId) => _dao.getProjectsForClient(clientId);
  @override Future<bool> hasProjectsForClient(String clientId) => _dao.hasProjectsForClient(clientId);
  @override Stream<List<Project>> watchAllActiveProjects() => _dao.watchAllActiveProjects();
  @override Future<Project> getProject(String id) => _dao.getProject(id);
  @override Future<String> insertProject(ProjectsCompanion c) => _dao.insertProject(c);
  @override Future<bool> updateProject(String id, ProjectsCompanion c) => _dao.updateProject(id, c);
  @override Future<bool> archiveProject(String id) => _dao.archiveProject(id);
}
