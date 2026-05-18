import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/projects_table.dart';

part 'project_dao.g.dart';

@DriftAccessor(tables: [Projects])
class ProjectDao extends DatabaseAccessor<AppDatabase>
    with _$ProjectDaoMixin {
  ProjectDao(super.db);

  /// Watch all active projects for a client.
  Stream<List<Project>> watchProjectsForClient(int clientId) {
    return (select(projects)
          ..where((t) =>
              t.clientId.equals(clientId) & t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// Get all active projects for a client.
  Future<List<Project>> getProjectsForClient(int clientId) {
    return (select(projects)
          ..where((t) =>
              t.clientId.equals(clientId) & t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  /// Get all active projects across all clients.
  Stream<List<Project>> watchAllActiveProjects() {
    return (select(projects)
          ..where((t) => t.isActive.equals(true) & t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<Project> getProject(int id) {
    return (select(projects)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<int> insertProject(ProjectsCompanion companion) {
    return into(projects).insert(companion);
  }

  Future<bool> updateProject(int id, ProjectsCompanion companion) {
    return (update(projects)..where((t) => t.id.equals(id)))
        .write(companion.copyWith(updatedAt: Value(DateTime.now())))
        .then((rows) => rows > 0);
  }

  Future<bool> archiveProject(int id) {
    return updateProject(
      id,
      const ProjectsCompanion(isArchived: Value(true)),
    );
  }

  /// Returns true if any projects (including archived) exist for this client.
  Future<bool> hasProjectsForClient(int clientId) async {
    final result = await (select(projects)
          ..where((t) => t.clientId.equals(clientId))
          ..limit(1))
        .get();
    return result.isNotEmpty;
  }
}
