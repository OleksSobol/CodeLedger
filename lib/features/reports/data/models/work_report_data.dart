import '../../../../core/database/app_database.dart';

class WorkReportData {
  final UserProfile profile;
  final DateTime startDate;
  final DateTime endDate;
  final List<TimeEntry> entries;
  final Client? client;
  final Project? project;
  final Map<String, String> projectNames;

  const WorkReportData({
    required this.profile,
    required this.startDate,
    required this.endDate,
    required this.entries,
    this.client,
    this.project,
    this.projectNames = const <String, String>{},
  });

  String get dateRangeText {
    // Basic formatting, could use DateFormat
    final start = '${startDate.year}-${startDate.month}-${startDate.day}';
    final end = '${endDate.year}-${endDate.month}-${endDate.day}';
    return '$start to $end';
  }

  double get totalHours {
    return entries.fold(0, (sum, e) => sum + (e.durationMinutes ?? 0) / 60.0);
  }
}
