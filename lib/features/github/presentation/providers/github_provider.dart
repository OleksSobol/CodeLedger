import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import '../../../../core/providers/theme_provider.dart';
import '../../../../core/database/app_database.dart';
import '../../../../features/clients/presentation/providers/client_providers.dart';
import '../../../../features/projects/presentation/providers/project_providers.dart';
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
  Future<GitHubSyncPreview> previewSync(
      DateTime start, DateTime end, {void Function(SyncLog)? onLog}) async {
    final dao = ref.read(appSettingsDaoProvider);
    final pat = await dao.getValue('github_pat');
    final username = await dao.getValue('github_username');

    void emitError(String msg) =>
        onLog?.call(SyncLog(msg, SyncLogLevel.error));

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

    final service = GitHubService(pat: pat, username: username, onLog: onLog);

    final allProjects = await ref.read(allActiveProjectsProvider.future);
    final linkedProjects = allProjects
        .where((p) => p.githubRepo != null && p.githubRepo!.isNotEmpty)
        .toList();

    if (linkedProjects.isEmpty) {
      emitError('No projects have a GitHub repo linked. Edit a project to add one.');
      return const GitHubSyncPreview(
        error:
            'No projects have a GitHub repo linked. Edit a project to add one.',
      );
    }

    final allClients = await ref.read(allClientsProvider.future);
    final clientById = {for (final c in allClients) c.id: c.name};

    // Cap end at today — never scan future dates.
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    var day = DateTime(start.year, start.month, start.day);
    final endDay = () {
      final raw = DateTime(end.year, end.month, end.day + 1);
      return raw.isBefore(tomorrow) ? raw : tomorrow;
    }();

    service.logs.add(SyncLog(
      'Scanning ${linkedProjects.length} linked project(s) for '
      '${_fmtDate(day)} - ${_fmtDate(endDay.subtract(const Duration(days: 1)))}',
      SyncLogLevel.info,
    ));

    // Verify repo access first.
    final accessOk = <String, bool>{};
    for (final p in linkedProjects) {
      final normalized = GitHubService.normalizeRepo(p.githubRepo!);
      accessOk[normalized] = await service.verifyRepoAccess(normalized);
    }

    // Pre-fetch Issue-* branch lists once per repo to avoid redundant API calls.
    final branchCache = <String, List<String>>{};
    for (final p in linkedProjects) {
      final repo = GitHubService.normalizeRepo(p.githubRepo!);
      if (accessOk[repo] != true) continue;
      if (!branchCache.containsKey(repo)) {
        branchCache[repo] = await service.listIssueBranches(repo);
        service.logs.add(SyncLog(
          '  $repo: ${branchCache[repo]!.length} Issue-* branch(es)',
          SyncLogLevel.info,
        ));
      }
    }

    final timeEntryDao = ref.read(timeEntryDaoProvider);
    final matches = <SyncMatch>[];

    while (day.isBefore(endDay)) {
      final dayEnd = day.add(const Duration(days: 1));
      final entries = await timeEntryDao.getAllEntries(from: day, to: dayEnd);

      for (final entry in entries) {
        // Use the entry's exact time window — commits outside it are ignored.
        final since = entry.startTime.toUtc();
        final until = (entry.endTime ?? dayEnd).toUtc();

        // Match only projects whose repo could apply to this entry.
        final applicableProjects = linkedProjects.where((p) =>
            p.id == entry.projectId ||
            (entry.projectId == null && p.clientId == entry.clientId)).toList();

        for (final project in applicableProjects) {
          final repo = GitHubService.normalizeRepo(project.githubRepo!);
          if (accessOk[repo] != true) continue;
          final branches = branchCache[repo] ?? [];

          final issueRefs = await service.getIssueRefsForTimeRange(
            repo, since, until, branches,
          );

          for (final issueRef in issueRefs) {
            if (_hasRef(entry.issueReference, issueRef)) continue;

            // Deduplicate: don't add the same (issueRef, entryId) twice.
            final alreadyQueued = matches.any(
              (m) => m.issueRef == issueRef && m.entry.id == entry.id,
            );
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

      day = dayEnd;
    }

    service.logs.add(SyncLog(
      'Scan complete - ${matches.length} match(es) found.',
      SyncLogLevel.info,
    ));

    return GitHubSyncPreview(
      matches: matches,
      logs: List.from(service.logs),
    );
  }

  /// Applies the selected matches, writing issue refs to time entries.
  /// Returns the number of entries updated.
  Future<int> applyMatches(List<SyncMatch> selected) async {
    final timeEntryDao = ref.read(timeEntryDaoProvider);
    // Track accumulated refs per entry so multiple matches on the same entry stack correctly.
    final accumulatedRefs = <int, String>{};
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
      final allProjects = await ref.read(allActiveProjectsProvider.future);
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
