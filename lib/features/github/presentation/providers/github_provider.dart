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
  final String? branchName;
  final String? ticketTitle;
  final String? matchReason;
  final bool isClosedBranch;

  SyncMatch({
    required this.repo,
    required this.projectName,
    required this.clientName,
    required this.issueRef,
    required this.entry,
    this.existingRef,
    this.branchName,
    this.ticketTitle,
    this.matchReason,
    this.isClosedBranch = false,
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
    DateTime start,
    DateTime end, {
    void Function(SyncLog)? onLog,
  }) async {
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
    emit('PAT ok ($username). Loading projects…');

    final service = GitHubService(pat: pat, username: username, onLog: onLog);
    try {
      final allProjects = await ref
          .read(projectRepositoryProvider)
          .watchAllActiveProjects()
          .first;
      final linkedProjects = allProjects
          .where((p) => p.githubRepo != null && p.githubRepo!.isNotEmpty)
          .toList();

      if (linkedProjects.isEmpty) {
        emitError(
          'No projects have a GitHub repo linked. Edit a project to add one.',
        );
        return const GitHubSyncPreview(
          error:
              'No projects have a GitHub repo linked. Edit a project to add one.',
        );
      }
      emit('Loading clients…');

      final allClients = await ref
          .read(clientRepositoryProvider)
          .watchAllClients()
          .first;
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

      // Verify repo access and collect work units across all linked repos
      final accessOk = <String, bool>{};
      final repoWorkMap = <String, List<UserBranchWork>>{};

      for (final p in linkedProjects) {
        final repo = GitHubService.normalizeRepo(p.githubRepo!);
        if (!accessOk.containsKey(repo)) {
          accessOk[repo] = await service.verifyRepoAccess(repo);
        }
        if (accessOk[repo] == true && !repoWorkMap.containsKey(repo)) {
          emit('Scanning tickets, branches & commits for $repo…');
          final workUnits = await service.getUserWorkUnits(
            repo,
            since: scanStart.subtract(const Duration(days: 1)),
            until: scanEnd.add(const Duration(days: 1)),
          );
          repoWorkMap[repo] = workUnits;
        }
      }

      // Fetch all entries in range in one DB call.
      emit('Loading time entries…');
      final timeEntryRepo = ref.read(timeEntryRepositoryProvider);
      final allEntries = await timeEntryRepo.getAllEntries(
        from: scanStart,
        to: scanEnd,
      );

      if (allEntries.isEmpty) {
        emit('No time entries in range.');
        return GitHubSyncPreview(logs: List.from(service.logs));
      }

      emit('Matching ${allEntries.length} time entries with GitHub work…');

      final matches = <SyncMatch>[];

      for (final entry in allEntries) {
        final localDay = DateTime(
          entry.startTime.year,
          entry.startTime.month,
          entry.startTime.day,
        );
        final entryStart = entry.startTime;
        final entryEnd = entry.endTime ?? entry.startTime.add(const Duration(hours: 1));

        final applicableProjects = linkedProjects
            .where(
              (p) =>
                  p.id == entry.projectId ||
                  (entry.projectId == null && p.clientId == entry.clientId),
            )
            .toList();

        for (final project in applicableProjects) {
          final repo = GitHubService.normalizeRepo(project.githubRepo!);
          if (accessOk[repo] != true) continue;

          final repoWork = repoWorkMap[repo] ?? [];
          if (repoWork.isEmpty) continue;

          // Track candidate matches for this entry
          SyncMatch? bestMatch;
          int bestScore = -1;

          for (final work in repoWork) {
            final ticketRef = work.ticketRef ?? GitHubService.extractIssueRef(work.branchName);
            if (ticketRef == null || ticketRef.isEmpty) continue;
            if (_hasRef(entry.issueReference, ticketRef)) continue;

            // 1. Exact commit in entry window (Score 100)
            final inWindowCommits = work.commitTimestamps.where((ts) {
              final localTs = ts.toLocal();
              return !localTs.isBefore(entryStart.subtract(const Duration(minutes: 5))) &&
                     !localTs.isAfter(entryEnd.add(const Duration(minutes: 5)));
            }).toList();

            if (inWindowCommits.isNotEmpty) {
              final match = SyncMatch(
                repo: repo,
                projectName: project.name,
                clientName: clientById[project.clientId] ?? '',
                issueRef: ticketRef,
                entry: entry,
                existingRef: entry.issueReference,
                branchName: work.branchName,
                ticketTitle: work.ticketTitle,
                matchReason: 'Commit at ${_fmtTime(inWindowCommits.first.toLocal())}',
                isClosedBranch: work.isClosed,
              );
              // Add high confidence match directly
              if (!matches.any((m) => m.issueRef == match.issueRef && m.entry.id == entry.id)) {
                matches.add(match);
              }
              bestScore = 100;
              continue;
            }

            if (bestScore >= 100) continue; // Already found an exact match for this entry

            // 2. Commit close to entry window on same day (within 2.5 hours) (Score 80)
            final nearCommits = work.commitTimestamps.where((ts) {
              final localTs = ts.toLocal();
              if (localTs.year != localDay.year || localTs.month != localDay.month || localTs.day != localDay.day) {
                return false;
              }
              final distStart = (localTs.difference(entryStart).inMinutes).abs();
              final distEnd = (localTs.difference(entryEnd).inMinutes).abs();
              return distStart <= 150 || distEnd <= 150;
            }).toList();

            if (nearCommits.isNotEmpty && bestScore < 80) {
              bestScore = 80;
              bestMatch = SyncMatch(
                repo: repo,
                projectName: project.name,
                clientName: clientById[project.clientId] ?? '',
                issueRef: ticketRef,
                entry: entry,
                existingRef: entry.issueReference,
                branchName: work.branchName,
                ticketTitle: work.ticketTitle,
                matchReason: 'Commit near time slot on ${work.branchName}',
                isClosedBranch: work.isClosed,
              );
              continue;
            }

            // 3. Entry description matches ticket key or title (Score 70)
            final desc = (entry.description ?? '').toLowerCase();
            final key = ticketRef.toLowerCase();
            final numOnly = RegExp(r'\d+').firstMatch(ticketRef)?.group(0) ?? '';
            final hasDescMatch = desc.isNotEmpty && (
              desc.contains(key) ||
              (numOnly.isNotEmpty && desc.contains(numOnly)) ||
              (work.ticketTitle != null && _wordsOverlap(desc, work.ticketTitle!.toLowerCase()))
            );

            final hasActivityOnDay = work.commitTimestamps.any((ts) {
              final l = ts.toLocal();
              return l.year == localDay.year && l.month == localDay.month && l.day == localDay.day;
            });

            if (hasDescMatch && hasActivityOnDay && bestScore < 70) {
              bestScore = 70;
              bestMatch = SyncMatch(
                repo: repo,
                projectName: project.name,
                clientName: clientById[project.clientId] ?? '',
                issueRef: ticketRef,
                entry: entry,
                existingRef: entry.issueReference,
                branchName: work.branchName,
                ticketTitle: work.ticketTitle,
                matchReason: 'Description matches $ticketRef',
                isClosedBranch: work.isClosed,
              );
              continue;
            }

            // 4. Same-day commit on branch (Score 50)
            if (hasActivityOnDay && bestScore < 50) {
              bestScore = 50;
              bestMatch = SyncMatch(
                repo: repo,
                projectName: project.name,
                clientName: clientById[project.clientId] ?? '',
                issueRef: ticketRef,
                entry: entry,
                existingRef: entry.issueReference,
                branchName: work.branchName,
                ticketTitle: work.ticketTitle,
                matchReason: 'Worked on ${work.branchName} on this day',
                isClosedBranch: work.isClosed,
              );
              continue;
            }
          }

          // If no exact match (score 100), add the best match found (proximity, desc, same-day)
          if (bestScore > 0 && bestScore < 100 && bestMatch != null) {
            final alreadyQueued = matches.any(
              (m) => m.issueRef == bestMatch!.issueRef && m.entry.id == entry.id,
            );
            if (!alreadyQueued) {
              matches.add(bestMatch);
            }
          }
        }
      }

      emit('Scan complete — ${matches.length} match(es) found.');

      return GitHubSyncPreview(matches: matches, logs: List.from(service.logs));
    } finally {
      service.dispose();
    }
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
      final existing =
          accumulatedRefs[entryId] ?? (match.entry.issueReference ?? '');

      if (_hasRef(existing, match.issueRef)) continue;

      final newRef = existing.isEmpty
          ? match.issueRef
          : '$existing, ${match.issueRef}';
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
    String pat,
    String username,
  ) async {
    if (pat.isEmpty) {
      return GitHubConnectionTest(
        patError: 'No PAT entered. Enter a token and try again.',
      );
    }

    final service = GitHubService(pat: pat, username: username);
    try {
      String? authedAs;
      String? patError;
      try {
        authedAs = await service.verifyPat();
      } catch (e) {
        patError = e.toString();
      }

      final repoResults = <String, bool>{};
      if (patError == null) {
        final allProjects = await ref
            .read(projectRepositoryProvider)
            .watchAllActiveProjects()
            .first;
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
    } finally {
      service.dispose();
    }
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _fmtTime(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  static bool _wordsOverlap(String a, String b) {
    const stopwords = {
      'the', 'and', 'for', 'with', 'from', 'into', 'this', 'that', 'page', 'screen',
      'fix', 'feat', 'update', 'work', 'code', 'task',
    };
    final wordsA = a
        .split(RegExp(r'[\s\-_,.:;]+'))
        .where((w) => w.length > 3 && !stopwords.contains(w))
        .toSet();
    final wordsB = b
        .split(RegExp(r'[\s\-_,.:;]+'))
        .where((w) => w.length > 3 && !stopwords.contains(w))
        .toSet();
    return wordsA.intersection(wordsB).isNotEmpty;
  }

  /// Exact-match check: is [ref] already in the comma-separated [existing] list?
  static bool _hasRef(String? existing, String ref) {
    if (existing == null || existing.isEmpty) return false;
    final normRef = ref.trim().toLowerCase();
    final cleanRef = normRef.replaceAll(RegExp(r'^#'), '');
    return existing.split(',').map((s) => s.trim().toLowerCase()).any((s) {
      final cleanS = s.replaceAll(RegExp(r'^#'), '');
      return s == normRef || cleanS == cleanRef;
    });
  }
}
