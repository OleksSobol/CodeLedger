import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/database/daos/app_settings_dao.dart';
import '../../../../core/providers/theme_provider.dart';

const _settingsKey = 'dashboard_quick_actions';

/// A persisted quick action button on the home screen.
class QuickAction {
  final int clientId;
  final int? projectId;
  final String label;
  final String? description;

  const QuickAction({
    required this.clientId,
    this.projectId,
    required this.label,
    this.description,
  });

  Map<String, dynamic> toJson() => {
        'clientId': clientId,
        if (projectId != null) 'projectId': projectId,
        'label': label,
        if (description != null) 'description': description,
      };

  factory QuickAction.fromJson(Map<String, dynamic> json) => QuickAction(
        clientId: json['clientId'] as int,
        projectId: json['projectId'] as int?,
        label: json['label'] as String,
        description: json['description'] as String?,
      );
}

/// Loads/saves quick actions from app_settings.
final quickActionsProvider =
    AsyncNotifierProvider<QuickActionsNotifier, List<QuickAction>>(
  QuickActionsNotifier.new,
);

class QuickActionsNotifier extends AsyncNotifier<List<QuickAction>> {
  late AppSettingsDao _dao;

  @override
  Future<List<QuickAction>> build() async {
    _dao = ref.watch(appSettingsDaoProvider);
    final raw = await _dao.getValue(_settingsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => QuickAction.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> save(List<QuickAction> actions) async {
    final json = jsonEncode(actions.map((a) => a.toJson()).toList());
    await _dao.setValue(_settingsKey, json);
    state = AsyncData(actions);
  }

  Future<void> addAction(QuickAction action) async {
    final current = state.value ?? [];
    await save([...current, action]);
  }

  Future<void> removeAt(int index) async {
    final current = List<QuickAction>.from(state.value ?? []);
    if (index < current.length) {
      current.removeAt(index);
      await save(current);
    }
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    final current = List<QuickAction>.from(state.value ?? []);
    if (newIndex > oldIndex) newIndex--;
    final item = current.removeAt(oldIndex);
    current.insert(newIndex, item);
    await save(current);
  }
}
