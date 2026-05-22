import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../../database/app_database.dart';
import '../expense_repository.dart';

class SupabaseExpenseRepository implements ExpenseRepository {
  final SupabaseClient _client;
  SupabaseExpenseRepository(this._client);

  String get _uid => _client.auth.currentUser!.id;

  Expense _fromRow(Map<String, dynamic> r) => Expense(
        id: r['id'] as String,
        name: r['name'] as String,
        category: r['category'] as String? ?? 'other',
        amount: (r['amount'] as num).toDouble(),
        frequency: r['frequency'] as String? ?? 'monthly',
        deductionMethod: r['deduction_method'] as String? ?? 'manual',
        manualPercentage: (r['manual_percentage'] as num?)?.toDouble(),
        workHoursPerDay: (r['work_hours_per_day'] as num?)?.toDouble(),
        totalHoursPerDay: (r['total_hours_per_day'] as num?)?.toDouble(),
        workSpaceSqft: (r['work_space_sqft'] as num?)?.toDouble(),
        totalSpaceSqft: (r['total_space_sqft'] as num?)?.toDouble(),
        startDate: DateTime.parse(r['start_date'] as String),
        endDate: r['end_date'] != null
            ? DateTime.parse(r['end_date'] as String)
            : null,
        notes: r['notes'] as String?,
        createdAt: DateTime.parse(r['created_at'] as String),
      );

  @override
  Stream<List<Expense>> watchAll() => Stream.fromFuture(getAll());

  @override
  Future<List<Expense>> getAll() async {
    final rows = await _client
        .from('expenses')
        .select()
        .eq('user_id', _uid)
        .order('name');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Expense?> getById(String id) async {
    final rows = await _client
        .from('expenses')
        .select()
        .eq('id', id)
        .eq('user_id', _uid)
        .limit(1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<void> insertExpense(ExpensesCompanion companion) async {
    const uuid = Uuid();
    final id = companion.id.present ? companion.id.value : uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    await _client.from('expenses').insert({
      'id': id,
      'user_id': _uid,
      'name': companion.name.value,
      'category': companion.category.present
          ? companion.category.value
          : 'other',
      'amount': companion.amount.value,
      'frequency': companion.frequency.present
          ? companion.frequency.value
          : 'monthly',
      'deduction_method': companion.deductionMethod.present
          ? companion.deductionMethod.value
          : 'manual',
      if (companion.manualPercentage.present)
        'manual_percentage': companion.manualPercentage.value,
      if (companion.workHoursPerDay.present)
        'work_hours_per_day': companion.workHoursPerDay.value,
      if (companion.totalHoursPerDay.present)
        'total_hours_per_day': companion.totalHoursPerDay.value,
      if (companion.workSpaceSqft.present)
        'work_space_sqft': companion.workSpaceSqft.value,
      if (companion.totalSpaceSqft.present)
        'total_space_sqft': companion.totalSpaceSqft.value,
      'start_date':
          companion.startDate.value.toUtc().toIso8601String(),
      if (companion.endDate.present && companion.endDate.value != null)
        'end_date': companion.endDate.value!.toUtc().toIso8601String(),
      if (companion.notes.present) 'notes': companion.notes.value,
      'created_at': companion.createdAt.present
          ? companion.createdAt.value.toUtc().toIso8601String()
          : now,
    });
  }

  @override
  Future<bool> updateExpense(ExpensesCompanion companion) async {
    final map = <String, dynamic>{};
    if (companion.name.present) map['name'] = companion.name.value;
    if (companion.category.present) map['category'] = companion.category.value;
    if (companion.amount.present) map['amount'] = companion.amount.value;
    if (companion.frequency.present) map['frequency'] = companion.frequency.value;
    if (companion.deductionMethod.present) {
      map['deduction_method'] = companion.deductionMethod.value;
    }
    if (companion.manualPercentage.present) {
      map['manual_percentage'] = companion.manualPercentage.value;
    }
    if (companion.workHoursPerDay.present) {
      map['work_hours_per_day'] = companion.workHoursPerDay.value;
    }
    if (companion.totalHoursPerDay.present) {
      map['total_hours_per_day'] = companion.totalHoursPerDay.value;
    }
    if (companion.workSpaceSqft.present) {
      map['work_space_sqft'] = companion.workSpaceSqft.value;
    }
    if (companion.totalSpaceSqft.present) {
      map['total_space_sqft'] = companion.totalSpaceSqft.value;
    }
    if (companion.startDate.present) {
      map['start_date'] = companion.startDate.value.toUtc().toIso8601String();
    }
    if (companion.endDate.present) {
      map['end_date'] = companion.endDate.value?.toUtc().toIso8601String();
    }
    if (companion.notes.present) map['notes'] = companion.notes.value;
    final result = await _client
        .from('expenses')
        .update(map)
        .eq('id', companion.id.value)
        .eq('user_id', _uid)
        .select();
    return result.isNotEmpty;
  }

  @override
  Future<int> deleteExpense(String id) async {
    await _client
        .from('expenses')
        .delete()
        .eq('id', id)
        .eq('user_id', _uid);
    return 1;
  }
}
