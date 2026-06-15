import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import '../app_database.dart';
import '../tables/projects_table.dart';

part 'project_dao.g.dart';

@DriftAccessor(tables: [Projects])
class ProjectDao extends DatabaseAccessor<AppDatabase>
    with _$ProjectDaoMixin {
  ProjectDao(super.db);

  Stream<List<Project>> watchProjectsForClient(String clientId) {
    return (select(projects)
          ..where((t) =>
              t.clientId.equals(clientId) & t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<List<Project>> getProjectsForClient(String clientId) {
    return (select(projects)
          ..where((t) =>
              t.clientId.equals(clientId) & t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  Future<bool> hasProjectsForClient(String clientId) async {
    final rows = await (select(projects)
          ..where((t) => t.clientId.equals(clientId))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  Stream<List<Project>> watchAllActiveProjects() {
    return (select(projects)
          ..where((t) => t.isActive.equals(true) & t.isArchived.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  Future<Project> getProject(String id) {
    return (select(projects)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<String> insertProject(ProjectsCompanion companion) async {
    const uuid = Uuid();
    final id = uuid.v4();
    await into(projects).insert(companion.copyWith(id: Value(id)));
    return id;
  }

  Future<bool> updateProject(String id, ProjectsCompanion companion) {
    return (update(projects)..where((t) => t.id.equals(id)))
        .write(companion.copyWith(updatedAt: Value(DateTime.now())))
        .then((rows) => rows > 0);
  }

  Future<bool> archiveProject(String id) {
    return updateProject(
      id,
      const ProjectsCompanion(isArchived: Value(true)),
    );
  }
}
