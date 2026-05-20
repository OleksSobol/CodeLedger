import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/providers/repository_providers.dart';
import '../../../../core/database/app_database.dart';
import '../../../../features/time_tracking/presentation/providers/time_entry_providers.dart';
import '../../data/github_service.dart';

export '../../data/github_service.dart' show SyncLog, SyncLogLevel;

final githubPatProvider = FutureProvider<String?>((ref) {
  return ref.watch(appSettingsDaoProvider).getValue('github_pat');
});

final githubUsernameProvider = FutureProvider<String?>((ref) {
  return ref.watch(appSettingsDaoProvider).getValue('github_username');
});

final githubSyncNotifierProvider =
    AsyncNotifierProvider<GitHubSyncNotifier, void>(GitHubSyncNotifier.new);

/// One potential issue-ref → time-entry assignment found during a scan.
class SyncMatch {
  final String repo;
  final String projectName;
  final String clientName;
  final String issueRef;
  final TimeEntry entry;
  final String? existingRef;

  SyncMatch({
    required this.repo,
    required this.projectName,
    required this.clientName,
    required this.issueRef,
    required this.entry,
    this.existingRef,
  });

  /// What the issueReference field will become after applying.
  String get newRef {
    final existing = existingRef ?? '';
    return existing.isEmpty ? issueRef : '$existing, $issueRef';
  }
}

class GitHubConnectionTest {
  final String? authedAs;
  final String? patError;
  final Map<String, bool> repoResults;

  GitHubConnectionTest({
    this.authedAs,
    this.patError,
    this.repoResults = const {},
  });

  bool get patOk => patError == null && authedAs != null;
}

class GitHubSyncPreview {
  final List<SyncMatch> matches;
  final List<SyncLog> logs;
  final String? error;

  const GitHubSyncPreview({
    this.matches = const [],
    this.logs = const [],
    this.error,
  });

  bool get hasError => error != null;
}

class GitHubSyncNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Scans all linked repos for the date range and returns potential matches
  /// WITHOUT applying any changes. [onLog] is called live as each step runs.
  ///
  /// Uses a day-level commit cache: API calls = repos × days × (branches/10 + 1),
  /// not repos × entries × (branches/10 + 1), so a month scan stays fast.
  Future<GitHubSyncPreview> previewSync(
      DateTime start, DateTime end, {void Function(SyncLog)? onLog}) async {
    void emit(String msg, [SyncLogLevel level = SyncLogLevel.info]) =>
        onLog?.call(SyncLog(msg, level));
    void emitError(String msg) => emit(msg, SyncLogLevel.error);

    emit('Reading settings…');
    final dao = ref.read(appSettingsDaoProvider);
    final pat = await dao.getValue('github_pat');
    final username = await dao.getValue('github_username');

    if (pat == null || pat.isEmpty) {
      emitError('GitHub PAT not configured. Go to Settings → Accounts.');
      return const GitHubSyncPreview(
        error: 'GitHub PAT not configured. Go to Settings → Accounts.',
      );
    }
    if (username == null || username.isEmpty) {
      emitError('GitHub username not configured. Go to Settings → Accounts.');
      return const GitHubSyncPreview(
        error: 'GitHub username not configured. Go to Settings → Accounts.',
      );
    }
    emit('PAT ok. Loading projects…');

    final service = GitHubService(pat: pat, username: username, onLog: onLog);

    final allProjects =
        await ref.read(projectRepositoryProvider).watchAllActiveProjects().first;
    final linkedProjects = allProjects
        .where((p) => p.githubRepo != null && p.githubRepo!.isNotEmpty)
        .toList();

    if (linkedProjects.isEmpty) {
      emitError('No projects have a GitHub repo linked. Edit a project to add one.');
      return const GitHubSyncPreview(
        error: 'No projects have a GitHub repo linked. Edit a project to add one.',
      );
    }
    emit('Loading clients…');

    final allClients = await ref.read(clientRepositoryProvider).watchAllClients().first;
    final clientById = {for (final c in allClients) c.id: c.name};

    // Cap end at today — never scan future dates.
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    final scanStart = DateTime(start.year, start.month, start.day);
    final scanEnd = end.isBefore(tomorrow) ? end : tomorrow;

    emit(
      'Scanning ${linkedProjects.length} linked project(s) for '
      '${_fmtDate(scanStart)} – ${_fmtDate(scanEnd.subtract(const Duration(days: 1)))}',
    );

    // Verify repo access and pre-fetch branch lists — once per repo.
    final accessOk = <String, bool>{};
    final branchCache = <String, List<String>>{};
    for (final p in linkedProjects) {
      final repo = GitHubService.normalizeRepo(p.githubRepo!);
      if (!accessOk.containsKey(repo)) {
        accessOk[repo] = await service.verifyRepoAccess(repo);
      }
      if (accessOk[repo] == true && !branchCache.containsKey(repo)) {
        emit('  Fetching Issue-* branches for $repo…');
        branchCache[repo] = await service.listIssueBranches(repo);
        emit('  $repo: ${branchCache[repo]!.length} Issue-* branch(es)');
      }
    }

    // Fetch all entries in range in one DB call.
    emit('Loading time entries…');
    final timeEntryRepo = ref.read(timeEntryRepositoryProvider);
    final allEntries =
        await timeEntryRepo.getAllEntries(from: scanStart, to: scanEnd);

    if (allEntries.isEmpty) {
      emit('No time entries in range.');
      return GitHubSyncPreview(logs: List.from(service.logs));
    }

    // Build a day-level commit cache: "$repo::$dateKey" → {issueRef: [timestamps]}.
    // One set of API calls per (repo, day) regardless of how many entries that day has.
    final commitCache = <String, Map<String, List<DateTime>>>{};

    for (final entry in allEntries) {
      final applicableProjects = linkedProjects
          .where((p) =>
              p.id == entry.projectId ||
              (entry.projectId == null && p.clientId == entry.clientId))
          .toList();

      for (final project in applicableProjects) {
        final repo = GitHubService.normalizeRepo(project.githubRepo!);
        if (accessOk[repo] != true) continue;

        final localDay = DateTime(entry.startTime.year, entry.startTime.month,
            entry.startTime.day);
        final cacheKey = '$repo::${_fmtDate(localDay)}';

        if (!commitCache.containsKey(cacheKey)) {
          emit('  Scanning commits for $repo on ${_fmtDate(localDay)}…');
          final dayStart = localDay.toUtc();
          final dayEnd = localDay.add(const Duration(days: 1)).toUtc();
          commitCache[cacheKey] = await service.getRefsWithTimestampsForDay(
            repo, dayStart, dayEnd, branchCache[repo] ?? [],
          );
        }
      }
    }

    // Match entries to issue refs by filtering timestamps to the entry's window.
    final matches = <SyncMatch>[];

    for (final entry in allEntries) {
      final since = entry.startTime.toUtc();
      final localDay = DateTime(
          entry.startTime.year, entry.startTime.month, entry.startTime.day);
      final dayEnd = localDay.add(const Duration(days: 1)).toUtc();
      final until = (entry.endTime?.toUtc()) ?? dayEnd;

      final applicableProjects = linkedProjects
          .where((p) =>
              p.id == entry.projectId ||
              (entry.projectId == null && p.clientId == entry.clientId))
          .toList();

      for (final project in applicableProjects) {
        final repo = GitHubService.normalizeRepo(project.githubRepo!);
        if (accessOk[repo] != true) continue;

        final cacheKey = '$repo::${_fmtDate(localDay)}';
        final dayRefs = commitCache[cacheKey] ?? {};

        for (final issueRef in dayRefs.keys) {
          final timestamps = dayRefs[issueRef]!;
          // At least one commit must fall within the entry's exact time window.
          final hasInWindow =
              timestamps.any((ts) => !ts.isBefore(since) && ts.isBefore(until));
          if (!hasInWindow) continue;
          if (_hasRef(entry.issueReference, issueRef)) continue;

          final alreadyQueued =
              matches.any((m) => m.issueRef == issueRef && m.entry.id == entry.id);
          if (alreadyQueued) continue;

          matches.add(SyncMatch(
            repo: repo,
            projectName: project.name,
            clientName: clientById[project.clientId] ?? '',
            issueRef: issueRef,
            entry: entry,
            existingRef: entry.issueReference,
          ));
        }
      }
    }

    emit('Scan complete — ${matches.length} match(es) found.');

    return GitHubSyncPreview(
      matches: matches,
      logs: List.from(service.logs),
    );
  }

  /// Applies the selected matches, writing issue refs to time entries.
  /// Returns the number of entries updated.
  Future<int> applyMatches(List<SyncMatch> selected) async {
    final timeEntryDao = ref.read(timeEntryRepositoryProvider);
    // Track accumulated refs per entry so multiple matches on the same entry stack correctly.
    final accumulatedRefs = <String, String>{};
    int count = 0;

    for (final match in selected) {
      final entryId = match.entry.id;
      final existing = accumulatedRefs[entryId] ??
          (match.entry.issueReference ?? '');

      if (_hasRef(existing, match.issueRef)) continue;

      final newRef =
          existing.isEmpty ? match.issueRef : '$existing, ${match.issueRef}';
      accumulatedRefs[entryId] = newRef;

      await timeEntryDao.updateWithOverlapCheck(
        entryId,
        TimeEntriesCompanion(issueReference: Value(newRef)),
      );
      count++;
    }

    ref.invalidate(filteredEntriesProvider);
    return count;
  }

  /// Tests the PAT and checks access to all linked repos.
  Future<GitHubConnectionTest> testConnection(
      String pat, String username) async {
    if (pat.isEmpty) {
      return GitHubConnectionTest(
          patError: 'No PAT entered. Enter a token and try again.');
    }

    final service = GitHubService(pat: pat, username: username);

    String? authedAs;
    String? patError;
    try {
      authedAs = await service.verifyPat();
    } catch (e) {
      patError = e.toString();
    }

    final repoResults = <String, bool>{};
    if (patError == null) {
      final allProjects =
          await ref.read(projectRepositoryProvider).watchAllActiveProjects().first;
      final linkedRepos = allProjects
          .where((p) => p.githubRepo != null && p.githubRepo!.isNotEmpty)
          .map((p) => GitHubService.normalizeRepo(p.githubRepo!))
          .toSet();

      for (final repo in linkedRepos) {
        repoResults[repo] = await service.verifyRepoAccess(repo);
      }
    }

    return GitHubConnectionTest(
      authedAs: authedAs,
      patError: patError,
      repoResults: repoResults,
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Exact-match check: is [ref] already in the comma-separated [existing] list?
  /// Uses split instead of contains() to avoid "Issue-3" matching inside "Issue-30".
  static bool _hasRef(String? existing, String ref) {
    if (existing == null || existing.isEmpty) return false;
    return existing.split(',').map((s) => s.trim()).contains(ref);
  }
}
