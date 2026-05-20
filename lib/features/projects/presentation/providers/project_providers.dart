import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/project_repository.dart';

final allActiveProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(projectRepositoryProvider).watchAllActiveProjects();
});

final projectsForClientProvider =
    StreamProvider.family<List<Project>, String>((ref, clientId) {
  return ref.watch(projectRepositoryProvider).watchProjectsForClient(clientId);
});

final projectNotifierProvider =
    AsyncNotifierProvider<ProjectNotifier, void>(ProjectNotifier.new);

class ProjectNotifier extends AsyncNotifier<void> {
  late ProjectRepository _dao;

  @override
  Future<void> build() async {
    _dao = ref.watch(projectRepositoryProvider);
  }

  Future<String> addProject({
    required String clientId,
    required String name,
    String? description,
    double? hourlyRateOverride,
    String? githubRepo,
    int color = 0xFF2196F3,
  }) async {
    final id = await _dao.insertProject(ProjectsCompanion(
      clientId: Value(clientId),
      name: Value(name),
      description: Value(description),
      hourlyRateOverride: Value(hourlyRateOverride),
      githubRepo: Value(githubRepo),
      color: Value(color),
    ));
    ref.invalidate(projectsForClientProvider(clientId));
    return id;
  }

  Future<bool> updateProject(
      String id, String clientId, ProjectsCompanion companion) async {
    final result = await _dao.updateProject(id, companion);
    if (result) {
      ref.invalidate(projectsForClientProvider(clientId));
    }
    return result;
  }

  Future<bool> archiveProject(String id, String clientId) async {
    final result = await _dao.archiveProject(id);
    if (result) {
      ref.invalidate(projectsForClientProvider(clientId));
    }
    return result;
  }
}
