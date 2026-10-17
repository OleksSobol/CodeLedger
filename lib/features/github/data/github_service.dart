import 'dart:convert';
import 'package:http/http.dart' as http;

enum SyncLogLevel { info, warning, error }

class SyncLog {
  final String message;
  final SyncLogLevel level;
  SyncLog(this.message, this.level);
}

class UserPR {
  final int number;
  final String title;
  final String branch;
  final DateTime? createdAt;
  final DateTime? mergedAt;
  final List<DateTime> commitTimestamps;

  UserPR({
    required this.number,
    required this.title,
    required this.branch,
    this.createdAt,
    this.mergedAt,
    this.commitTimestamps = const [],
  });
}

class UserPushEvent {
  final String repo;
  final String ref;
  final String? issueRef;
  final DateTime timestamp;

  UserPushEvent({
    required this.repo,
    required this.ref,
    this.issueRef,
    required this.timestamp,
  });
}

class GitHubService {
  final String pat;
  final String username;
  final List<SyncLog> logs = [];
  final void Function(SyncLog)? onLog;
  final http.Client _client;

  // In-memory caches to avoid duplicate network calls
  List<UserPushEvent>? _cachedPushEvents;
  final Map<String, List<UserPR>> _cachedPRs = {};
  final Map<String, List<String>> _cachedCommitPulls = {};
  final Map<String, List<String>> _cachedUserBranches = {};

  GitHubService({
    required this.pat,
    required this.username,
    this.onLog,
    http.Client? client,
  }) : _client = client ?? http.Client();

  void dispose() {
    _client.close();
  }

  Map<String, String> get _headers => {
    'Authorization': 'token $pat',
    'Accept': 'application/vnd.github.v3+json',
    'User-Agent': 'CodeLedger-App/$username',
  };

  void _log(String msg, [SyncLogLevel level = SyncLogLevel.info]) {
    final entry = SyncLog(msg, level);
    logs.add(entry);
    onLog?.call(entry);
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Normalizes any GitHub repo string to "owner/repo" format.
  static String normalizeRepo(String raw) {
    var s = raw.trim();
    s = s.replaceFirst(RegExp(r'^https?://github\.com/'), '');
    if (s.endsWith('.git')) s = s.substring(0, s.length - 4);
    s = s.replaceAll(RegExp(r'^/+|/+$'), '');
    return s;
  }

  static const _timeout = Duration(seconds: 15);

  /// Extracts a normalized issue reference (e.g. "Issue-4095") from text
  /// (branch name, PR title, commit message, etc.).
  static String? extractIssueRef(String text) {
    if (text.isEmpty) return null;
    final pattern = RegExp(
      r'(?:[Ii]ssue|[Pp][Vv][Mm]|[Aa]ccounting|[Hh]earha)[-_ ]?#?(\d+)|'
      r'(?:fix(?:es|ed)?|close[sd]?|resolve[sd]?)\s+#(\d+)|'
      r'#(\d{2,6})\b|'
      r'\b[A-Za-z]+-(\d{2,6})\b',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(text);
    if (match != null) {
      final num = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4);
      if (num != null) return 'Issue-$num';
    }
    return null;
  }

  /// Extracts all issue references from a text block (e.g. commit messages).
  static List<String> extractAllIssueRefs(String text) {
    if (text.isEmpty) return [];
    final results = <String>{};
    final pattern = RegExp(
      r'(?:[Ii]ssue|[Pp][Vv][Mm]|[Aa]ccounting|[Hh]earha)[-_ ]?#?(\d+)|'
      r'(?:fix(?:es|ed)?|close[sd]?|resolve[sd]?)\s+#(\d+)|'
      r'#(\d{2,6})\b|'
      r'\b[A-Za-z]+-(\d{2,6})\b',
      caseSensitive: false,
    );
    for (final match in pattern.allMatches(text)) {
      final num = match.group(1) ?? match.group(2) ?? match.group(3) ?? match.group(4);
      if (num != null) results.add('Issue-$num');
    }
    return results.toList();
  }

  /// Performs an HTTP GET request with retries and exponential backoff.
  Future<http.Response?> _getWithRetry(
    Uri uri, {
    int maxRetries = 2,
    Duration? timeout,
  }) async {
    final effectiveTimeout = timeout ?? _timeout;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: _headers)
            .timeout(effectiveTimeout);
        return response;
      } catch (e) {
        if (attempt == maxRetries) {
          _log('  ✗ Network error on $uri: $e', SyncLogLevel.warning);
          return null;
        }
        await Future.delayed(Duration(milliseconds: 300 * (attempt + 1)));
      }
    }
    return null;
  }

  /// Verifies the PAT by calling /user.
  Future<String> verifyPat() async {
    final uri = Uri.parse('https://api.github.com/user');
    final response = await _getWithRetry(uri);
    if (response == null) {
      throw 'Network connection failed. Please check your internet connection.';
    }
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['login'] as String? ?? 'unknown';
    } else if (response.statusCode == 401) {
      throw 'Invalid PAT - authentication failed (401)';
    } else {
      throw 'Unexpected response: HTTP ${response.statusCode}';
    }
  }

  /// Checks if the repo is accessible. Returns true on success.
  Future<bool> verifyRepoAccess(String repo) async {
    repo = normalizeRepo(repo);
    _log('Checking access to $repo…');
    final uri = Uri.parse('https://api.github.com/repos/$repo');
    final response = await _getWithRetry(uri);
    if (response == null) {
      _log('✗ Network error connecting to $repo', SyncLogLevel.error);
      return false;
    }
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final name = data['full_name'] ?? repo;
      final isPrivate = data['private'] as bool? ?? false;
      _log('✓ Connected to $name (${isPrivate ? 'private' : 'public'})');
      return true;
    } else if (response.statusCode == 401) {
      _log(
        '✗ Authentication failed - check your GitHub PAT',
        SyncLogLevel.error,
      );
    } else if (response.statusCode == 404) {
      _log('✗ $repo not found or PAT lacks access (404)', SyncLogLevel.error);
    } else {
      _log(
        '✗ $repo returned HTTP ${response.statusCode}',
        SyncLogLevel.error,
      );
    }
    return false;
  }

  /// Fetches the user's recent push/PR events across GitHub.
  Future<List<UserPushEvent>> getUserPushEvents() async {
    if (_cachedPushEvents != null) return _cachedPushEvents!;

    final events = <UserPushEvent>[];
    final uri = Uri.parse('https://api.github.com/users/$username/events?per_page=100');
    final response = await _getWithRetry(uri);
    if (response != null && response.statusCode == 200) {
      try {
        final List<dynamic> data = jsonDecode(response.body);
        for (final item in data) {
          final type = item['type'] as String?;
          if (type == 'PushEvent') {
            final repoName = normalizeRepo(item['repo']?['name'] as String? ?? '');
            final ref = item['payload']?['ref'] as String? ?? '';
            final createdAtStr = item['created_at'] as String?;
            final createdAt = createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now();
            final issueRef = extractIssueRef(ref);

            final commits = item['payload']?['commits'] as List<dynamic>? ?? [];
            if (commits.isEmpty) {
              events.add(UserPushEvent(repo: repoName, ref: ref, issueRef: issueRef, timestamp: createdAt));
            } else {
              for (final c in commits) {
                final msg = c['message'] as String? ?? '';
                final cRef = extractIssueRef(msg) ?? issueRef;
                events.add(UserPushEvent(repo: repoName, ref: ref, issueRef: cRef, timestamp: createdAt));
              }
            }
          } else if (type == 'PullRequestEvent') {
            final repoName = normalizeRepo(item['repo']?['name'] as String? ?? '');
            final pr = item['payload']?['pull_request'];
            if (pr != null) {
              final headRef = pr['head']?['ref'] as String? ?? '';
              final title = pr['title'] as String? ?? '';
              final createdAtStr = pr['created_at'] as String?;
              final createdAt = createdAtStr != null ? DateTime.parse(createdAtStr) : DateTime.now();
              final issueRef = extractIssueRef(headRef) ?? extractIssueRef(title);
              events.add(UserPushEvent(repo: repoName, ref: headRef, issueRef: issueRef, timestamp: createdAt));
            }
          }
        }
      } catch (e) {
        _log('  ⚠ Error parsing GitHub events: $e', SyncLogLevel.warning);
      }
    }
    _cachedPushEvents = events;
    return events;
  }

  /// Fetches Pull Requests authored by or assigned to the user for [repo].
  /// Preserves the original branch name and commit dates even after PR is merged and branch deleted.
  Future<List<UserPR>> getUserPullRequests(String repo) async {
    repo = normalizeRepo(repo);
    if (_cachedPRs.containsKey(repo)) return _cachedPRs[repo]!;

    final prList = <UserPR>[];
    final uri = Uri.parse(
      'https://api.github.com/repos/$repo/pulls?state=all&sort=updated&direction=desc&per_page=60',
    );
    final response = await _getWithRetry(uri);
    if (response != null && response.statusCode == 200) {
      try {
        final List<dynamic> data = jsonDecode(response.body);
        final target = username.toLowerCase();

        for (final item in data) {
          final authorLogin = (item['user']?['login'] as String?)?.toLowerCase();
          final isUser = authorLogin == target ||
              ((item['assignees'] as List<dynamic>?)?.any(
                    (a) => (a['login'] as String?)?.toLowerCase() == target,
                  ) ??
                  false);
          if (!isUser) continue;

          final number = item['number'] as int;
          final title = item['title'] as String? ?? '';
          final branch = item['head']?['ref'] as String? ?? '';
          final createdAt = item['created_at'] != null ? DateTime.parse(item['created_at']) : null;
          final mergedAt = item['merged_at'] != null ? DateTime.parse(item['merged_at']) : null;

          final commitTimestamps = await _getPRCommitTimestamps(repo, number);

          prList.add(UserPR(
            number: number,
            title: title,
            branch: branch,
            createdAt: createdAt,
            mergedAt: mergedAt,
            commitTimestamps: commitTimestamps,
          ));
        }
      } catch (e) {
        _log('  ⚠ Error parsing PRs for $repo: $e', SyncLogLevel.warning);
      }
    }

    _cachedPRs[repo] = prList;
    return prList;
  }

  Future<List<DateTime>> _getPRCommitTimestamps(String repo, int prNumber) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$repo/pulls/$prNumber/commits?per_page=100',
    );
    final response = await _getWithRetry(uri);
    if (response == null || response.statusCode != 200) return [];

    try {
      final List<dynamic> data = jsonDecode(response.body);
      final timestamps = <DateTime>[];
      for (final c in data) {
        if (!_isUserAuthor(c)) continue;
        final dateStr = c['commit']?['author']?['date'] as String?;
        if (dateStr != null) timestamps.add(DateTime.parse(dateStr));
      }
      return timestamps;
    } catch (_) {
      return [];
    }
  }

  /// Retrieves issue references associated with a commit SHA via the Pull Requests API.
  Future<List<String>> _getIssueRefsFromCommitPulls(String repo, String sha) async {
    final cacheKey = '$repo::$sha';
    if (_cachedCommitPulls.containsKey(cacheKey)) {
      return _cachedCommitPulls[cacheKey]!;
    }

    final refs = <String>{};
    final uri = Uri.parse('https://api.github.com/repos/$repo/commits/$sha/pulls');
    final response = await _getWithRetry(uri);
    if (response != null && response.statusCode == 200) {
      try {
        final List<dynamic> data = jsonDecode(response.body);
        for (final pr in data) {
          final branch = pr['head']?['ref'] as String? ?? '';
          final title = pr['title'] as String? ?? '';
          final num = pr['number'] as int?;

          final bRef = extractIssueRef(branch);
          if (bRef != null) refs.add(bRef);

          final tRef = extractIssueRef(title);
          if (tRef != null) refs.add(tRef);

          if (num != null) refs.add('Issue-$num');
        }
      } catch (_) {}
    }

    final list = refs.toList();
    _cachedCommitPulls[cacheKey] = list;
    return list;
  }

  /// Fetches active branches that belong specifically to the user (not other team members).
  Future<List<String>> listUserBranches(String repo) async {
    repo = normalizeRepo(repo);
    if (_cachedUserBranches.containsKey(repo)) {
      return _cachedUserBranches[repo]!;
    }

    final userBranches = <String>{};

    // 1. Branches from user's PRs
    final prs = await getUserPullRequests(repo);
    for (final pr in prs) {
      if (pr.branch.isNotEmpty) userBranches.add(pr.branch);
    }

    // 2. Branches from user's push events for this repo
    final events = await getUserPushEvents();
    for (final ev in events) {
      if (ev.repo == repo && ev.ref.isNotEmpty) {
        final cleanRef = ev.ref.replaceFirst(RegExp(r'^refs/heads/'), '');
        userBranches.add(cleanRef);
      }
    }

    // 3. Branches with user's name or prefix
    final uri = Uri.parse('https://api.github.com/repos/$repo/branches?per_page=100');
    final response = await _getWithRetry(uri);
    if (response != null && response.statusCode == 200) {
      try {
        final List<dynamic> data = jsonDecode(response.body);
        final target = username.toLowerCase();
        for (final b in data) {
          final name = b['name'] as String? ?? '';
          final lower = name.toLowerCase();
          if (lower.startsWith('$target/') ||
              lower.contains(target) ||
              lower.startsWith('osobol/')) {
            userBranches.add(name);
          }
        }
      } catch (_) {}
    }

    final result = userBranches.toList();
    _cachedUserBranches[repo] = result;
    return result;
  }

  /// Legacy alias so existing callers remain compatible.
  Future<List<String>> listIssueBranches(String repo) => listUserBranches(repo);

  /// Builds a map of { issueRef → [commit UTC timestamps] } for a single day.
  ///
  /// Gathers the user's actual history from:
  /// 1. Commits authored by the user on the repository (default branch, merged work).
  /// 2. User's Pull Requests (preserves branch names & commit dates for merged/deleted branches).
  /// 3. User's push events.
  /// 4. User's active branches (unmerged work).
  Future<Map<String, List<DateTime>>> getRefsWithTimestampsForDay(
    String repo,
    DateTime dayStart,
    DateTime dayEnd,
    List<String> userBranches,
  ) async {
    repo = normalizeRepo(repo);
    final result = <String, List<DateTime>>{};

    void addRef(String rawRef, DateTime ts) {
      final norm = extractIssueRef(rawRef);
      if (norm != null) {
        result.putIfAbsent(norm, () => []).add(ts);
      }
    }

    // 1. Commits on default branch authored by user for this day (covers merged PRs)
    final commitsUri = Uri.parse(
      'https://api.github.com/repos/$repo/commits'
      '?author=${Uri.encodeComponent(username)}'
      '&since=${dayStart.toIso8601String()}'
      '&until=${dayEnd.toIso8601String()}'
      '&per_page=100',
    );
    final commitsResp = await _getWithRetry(commitsUri);
    if (commitsResp != null && commitsResp.statusCode == 200) {
      try {
        final List<dynamic> data = jsonDecode(commitsResp.body);
        for (final commit in data) {
          if (!_isUserAuthor(commit)) continue;

          final dateStr = commit['commit']?['author']?['date'] as String?;
          if (dateStr == null) continue;
          final ts = DateTime.parse(dateStr);
          final msg = commit['commit']?['message'] as String? ?? '';
          final sha = commit['sha'] as String? ?? '';

          final msgRefs = extractAllIssueRefs(msg);
          if (msgRefs.isNotEmpty) {
            for (final r in msgRefs) {
              addRef(r, ts);
            }
          } else if (sha.isNotEmpty) {
            final prRefs = await _getIssueRefsFromCommitPulls(repo, sha);
            for (final r in prRefs) {
              addRef(r, ts);
            }
          }
        }
      } catch (e) {
        _log(
          '  ⚠ Error parsing commits for $repo on ${_fmtDate(dayStart)}: $e',
          SyncLogLevel.warning,
        );
      }
    }

    // 2. User's Pull Requests (covers merged/deleted branches)
    final prs = await getUserPullRequests(repo);
    for (final pr in prs) {
      final prRef = extractIssueRef(pr.branch) ??
          extractIssueRef(pr.title) ??
          'Issue-${pr.number}';

      for (final ts in pr.commitTimestamps) {
        if (!ts.isBefore(dayStart) && ts.isBefore(dayEnd)) {
          addRef(prRef, ts);
        }
      }
      if (pr.mergedAt != null &&
          !pr.mergedAt!.isBefore(dayStart) &&
          pr.mergedAt!.isBefore(dayEnd)) {
        addRef(prRef, pr.mergedAt!);
      }
    }

    // 3. User's Push Events
    final events = await getUserPushEvents();
    for (final ev in events) {
      if (ev.repo == repo &&
          !ev.timestamp.isBefore(dayStart) &&
          ev.timestamp.isBefore(dayEnd)) {
        if (ev.issueRef != null) {
          addRef(ev.issueRef!, ev.timestamp);
        }
      }
    }

    // 4. User's active branches (unmerged feature work)
    for (final branch in userBranches) {
      final timestamps = await _getCommitTimestampsOnBranch(
        repo,
        branch,
        dayStart,
        dayEnd,
      );
      if (timestamps.isNotEmpty) {
        final ref = extractIssueRef(branch) ?? branch;
        for (final ts in timestamps) {
          addRef(ref, ts);
        }
      }
    }

    for (final entry in result.entries) {
      _log(
        '  ✓ ${entry.key} — ${entry.value.length} commit(s) on ${_fmtDate(dayStart)}',
      );
    }

    return result;
  }

  Future<List<DateTime>> _getCommitTimestampsOnBranch(
    String repo,
    String branch,
    DateTime since,
    DateTime until,
  ) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$repo/commits'
      '?sha=${Uri.encodeComponent(branch)}'
      '&author=${Uri.encodeComponent(username)}'
      '&since=${since.toIso8601String()}'
      '&until=${until.toIso8601String()}'
      '&per_page=100',
    );
    final response = await _getWithRetry(uri);
    if (response == null || response.statusCode != 200) return [];

    try {
      final List<dynamic> data = jsonDecode(response.body);
      final timestamps = <DateTime>[];
      for (final commit in data) {
        if (!_isUserAuthor(commit)) continue;

        final dateStr = commit['commit']?['author']?['date'] as String?;
        if (dateStr != null) timestamps.add(DateTime.parse(dateStr));
      }
      return timestamps;
    } catch (e) {
      _log('  ⚠ Error decoding commits for $branch: $e', SyncLogLevel.warning);
      return [];
    }
  }

  /// Checks if the commit was authored or committed by the user.
  /// Supports GitHub login as well as Git committer/author names & emails.
  bool _isUserAuthor(Map<String, dynamic> commit) {
    final target = username.toLowerCase();
    final authorLogin = (commit['author']?['login'] as String?)?.toLowerCase();
    final committerLogin = (commit['committer']?['login'] as String?)?.toLowerCase();

    if (authorLogin == target || committerLogin == target) return true;

    // Check git author/committer names and emails
    final gitAuthorName = (commit['commit']?['author']?['name'] as String?)?.toLowerCase();
    final gitAuthorEmail = (commit['commit']?['author']?['email'] as String?)?.toLowerCase();
    final gitCommitterName = (commit['commit']?['committer']?['name'] as String?)?.toLowerCase();
    final gitCommitterEmail = (commit['commit']?['committer']?['email'] as String?)?.toLowerCase();

    bool matchesTarget(String? s) {
      if (s == null || s.isEmpty) return false;
      final clean = s.replaceAll(RegExp(r'[\s._\-]'), '');
      final cleanTarget = target.replaceAll(RegExp(r'[\s._\-]'), '');
      return clean == cleanTarget ||
          clean.contains(cleanTarget) ||
          cleanTarget.contains(clean) ||
          s.contains('sobol') ||
          s.contains('oleks');
    }

    if (matchesTarget(gitAuthorName) ||
        matchesTarget(gitAuthorEmail) ||
        matchesTarget(gitCommitterName) ||
        matchesTarget(gitCommitterEmail)) {
      return true;
    }

    return false;
  }
}
