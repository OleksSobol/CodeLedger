import '../database/app_database.dart';

abstract class ProjectRepository {
  Stream<List<Project>> watchProjectsForClient(String clientId);
  Future<List<Project>> getProjectsForClient(String clientId);
  Future<bool> hasProjectsForClient(String clientId);
  Stream<List<Project>> watchAllActiveProjects();
  Future<Project> getProject(String id);
  Future<String> insertProject(ProjectsCompanion companion);
  Future<bool> updateProject(String id, ProjectsCompanion companion);
  Future<bool> archiveProject(String id);
}
