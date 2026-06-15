import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../database/app_database.dart';
import '../project_repository.dart';

class SupabaseProjectRepository implements ProjectRepository {
  final SupabaseClient _client;
  SupabaseProjectRepository(this._client);

  String get _uid => _client.auth.currentUser!.id;

  Project _fromRow(Map<String, dynamic> r) => Project(
        id: r['id'] as String,
        clientId: r['client_id'] as String,
        name: r['name'] as String,
        description: r['description'] as String?,
        hourlyRateOverride: (r['hourly_rate_override'] as num?)?.toDouble(),
        color: r['color'] as int? ?? 0xFF2196F3,
        githubRepo: r['github_repo'] as String?,
        isActive: r['is_active'] as bool? ?? true,
        isArchived: r['is_archived'] as bool? ?? false,
        createdAt: DateTime.parse(r['created_at'] as String),
        updatedAt: DateTime.parse(r['updated_at'] as String),
      );

  @override
  Stream<List<Project>> watchProjectsForClient(String clientId) =>
      Stream.fromFuture(getProjectsForClient(clientId));

  @override
  Future<List<Project>> getProjectsForClient(String clientId) async {
    final rows = await _client
        .from('projects')
        .select()
        .eq('client_id', clientId)
        .order('name');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<bool> hasProjectsForClient(String clientId) async {
    final rows = await _client
        .from('projects')
        .select('id')
        .eq('client_id', clientId)
        .limit(1);
    return rows.isNotEmpty;
  }

  @override
  Stream<List<Project>> watchAllActiveProjects() =>
      Stream.fromFuture(_fetchAllActive());

  Future<List<Project>> _fetchAllActive() async {
    final rows = await _client
        .from('projects')
        .select()
        .eq('is_active', true)
        .eq('is_archived', false)
        .order('name');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Project> getProject(String id) async {
    final row =
        await _client.from('projects').select().eq('id', id).single();
    return _fromRow(row);
  }

  @override
  Future<String> insertProject(ProjectsCompanion companion) async {
    const uuid = Uuid();
    final id = uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('projects').insert({
      'id': id,
      'user_id': _uid,
      'client_id': companion.clientId.value,
      'name': companion.name.value,
      if (companion.description.present) 'description': companion.description.value,
      if (companion.hourlyRateOverride.present) 'hourly_rate_override': companion.hourlyRateOverride.value,
      'color': companion.color.present ? companion.color.value : 0xFF2196F3,
      if (companion.githubRepo.present) 'github_repo': companion.githubRepo.value,
      'is_active': companion.isActive.present ? companion.isActive.value : true,
      'is_archived': false,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  @override
  Future<bool> updateProject(String id, ProjectsCompanion companion) async {
    final map = <String, dynamic>{
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
    if (companion.clientId.present) map['client_id'] = companion.clientId.value;
    if (companion.name.present) map['name'] = companion.name.value;
    if (companion.description.present) map['description'] = companion.description.value;
    if (companion.hourlyRateOverride.present) map['hourly_rate_override'] = companion.hourlyRateOverride.value;
    if (companion.color.present) map['color'] = companion.color.value;
    if (companion.githubRepo.present) map['github_repo'] = companion.githubRepo.value;
    if (companion.isActive.present) map['is_active'] = companion.isActive.value;
    if (companion.isArchived.present) map['is_archived'] = companion.isArchived.value;
    final result =
        await _client.from('projects').update(map).eq('id', id).select();
    return result.isNotEmpty;
  }

  @override
  Future<bool> archiveProject(String id) async {
    final result = await _client.from('projects').update({
      'is_archived': true,
      'is_active': false,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id).select();
    return result.isNotEmpty;
  }
}
