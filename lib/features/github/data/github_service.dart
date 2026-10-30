import 'dart:convert';
import 'package:http/http.dart' as http;

enum SyncLogLevel { info, warning, error }

class SyncLog {
  final String message;
  final SyncLogLevel level;
  SyncLog(this.message, this.level);
}

class GitHubTicket {
  final int number;
  final String title;
  final String? body;
  final String state; // 'open' or 'closed'
  final DateTime? createdAt;
  final DateTime? closedAt;
  final DateTime? updatedAt;
  final String? ticketKey; // e.g. "SOL-56", "DEV-79"
  final String? associatedBranch;

  GitHubTicket({
    required this.number,
    required this.title,
    this.body,
    required this.state,
    this.createdAt,
    this.closedAt,
    this.updatedAt,
    this.ticketKey,
    this.associatedBranch,
  });

  /// Best display reference: "SOL-56" if key present, else "Issue-56"
  String get preferredRef => ticketKey ?? 'Issue-$number';
}

class UserBranchWork {
  final String branchName;
  final String? ticketRef; // e.g. "SOL-56", "DEV-79", "Issue-4095"
  final String? ticketTitle;
  final bool isClosed;
  final List<DateTime> commitTimestamps;
  final String? source; // 'pr', 'branch', 'ticket', 'commit', 'push'

  UserBranchWork({
    required this.branchName,
    this.ticketRef,
    this.ticketTitle,
    this.isClosed = false,
    this.commitTimestamps = const [],
    this.source,
  });
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
  final Map<String, List<GitHubTicket>> _cachedTickets = {};
  final Map<String, List<String>> _cachedCommitPulls = {};
  final Map<String, List<String>> _cachedUserBranches = {};
  final Map<String, List<UserBranchWork>> _cachedWorkUnits = {};

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

  /// Extracts ticket keys like "SOL-56", "DEV-79", "GH-39", "PVM-4095".
  static String? extractTicketKey(String text) {
    if (text.isEmpty) return null;
    const ignoredPrefixes = {
      'HTTP', 'UTF', 'PAGE', 'FEAT', 'FIX', 'BUG', 'TEST', 'TASK',
      'CHORE', 'DOCS', 'DOC', 'PATCH', 'UPDATE', 'REFACTOR', 'BUILD', 'CI',
      'BATCH', 'STEP', 'PART', 'REV', 'VER', 'RELEASE',
    };
    final pattern = RegExp(r'\b([A-Za-z]{2,6})[-_](\d{1,6})\b');
    for (final m in pattern.allMatches(text)) {
      final prefix = m.group(1)!.toUpperCase();
      final num = m.group(2)!;
      if (ignoredPrefixes.contains(prefix)) continue;
      if (prefix == 'ISSUE') return 'Issue-$num';
      return '$prefix-$num';
    }
    return null;
  }

  /// Extracts a normalized issue reference (e.g. "SOL-56", "DEV-79", "Issue-4095")
  /// from text (branch name, PR title, commit message, etc.).
  static String? extractIssueRef(String text) {
    if (text.isEmpty) return null;

    // 1. Explicit ticket key like SOL-56, DEV-79, PVM-4095, GH-39
    final key = extractTicketKey(text);
    if (key != null) return key;

    // 2. Issue-123, issue_123, Issue#123
    final issueMatch = RegExp(r'(?:[Ii]ssue)[-_ ]?#?(\d+)', caseSensitive: false).firstMatch(text);
    if (issueMatch != null) return 'Issue-${issueMatch.group(1)}';

    // 3. Fixes #123, Closes #123
    final fixMatch = RegExp(r'(?:fix(?:es|ed)?|close[sd]?|resolve[sd]?)\s+#?(\d+)', caseSensitive: false).firstMatch(text);
    if (fixMatch != null) return 'Issue-${fixMatch.group(1)}';

    // 4. #123
    final hashMatch = RegExp(r'#(\d{1,6})\b').firstMatch(text);
    if (hashMatch != null) return 'Issue-${hashMatch.group(1)}';

    // 5. Standalone number in branch or path: e.g. 4095-tax-calc, feat/4095, fix/39
    final numMatch = RegExp(r'(?:^|/|[_\-])(\d{2,6})(?:[_\-]|$|\b)').firstMatch(text);
    if (numMatch != null) return 'Issue-${numMatch.group(1)}';

    return null;
  }

  /// Extracts all issue references from a text block (e.g. commit messages).
  static List<String> extractAllIssueRefs(String text) {
    if (text.isEmpty) return [];
    final results = <String>{};
    const ignoredPrefixes = {
      'HTTP', 'UTF', 'PAGE', 'FEAT', 'FIX', 'BUG', 'TEST', 'TASK',
      'CHORE', 'DOCS', 'DOC', 'PATCH', 'UPDATE', 'REFACTOR', 'BUILD', 'CI',
      'BATCH', 'STEP', 'PART', 'REV', 'VER', 'RELEASE',
    };

    // 1. All ticket keys: SOL-56, DEV-79, etc.
    final keyPattern = RegExp(r'\b([A-Za-z]{2,6})[-_](\d{1,6})\b');
    for (final m in keyPattern.allMatches(text)) {
      final prefix = m.group(1)!.toUpperCase();
      final num = m.group(2)!;
      if (ignoredPrefixes.contains(prefix)) continue;
      if (prefix == 'ISSUE') {
        results.add('Issue-$num');
      } else {
        results.add('$prefix-$num');
      }
    }

    // 2. Issue-123
    final issuePattern = RegExp(r'(?:[Ii]ssue)[-_ ]?#?(\d+)', caseSensitive: false);
    for (final m in issuePattern.allMatches(text)) {
      results.add('Issue-${m.group(1)}');
    }

    // 3. Fixes #123
    final fixPattern = RegExp(r'(?:fix(?:es|ed)?|close[sd]?|resolve[sd]?)\s+#?(\d+)', caseSensitive: false);
    for (final m in fixPattern.allMatches(text)) {
      results.add('Issue-${m.group(1)}');
    }

    // 4. #123
    final hashPattern = RegExp(r'#(\d{1,6})\b');
    for (final m in hashPattern.allMatches(text)) {
      results.add('Issue-${m.group(1)}');
    }

    // 5. Standalone number in branch or path
    final numPattern = RegExp(r'(?:^|/|[_\-])(\d{2,6})(?:[_\-]|$|\b)');
    for (final m in numPattern.allMatches(text)) {
      results.add('Issue-${m.group(1)}');
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

  /// Fetches tickets (issues) assigned to or created by the user (both open and closed).
  Future<List<GitHubTicket>> getAssignedTickets(String repo) async {
    repo = normalizeRepo(repo);
    if (_cachedTickets.containsKey(repo)) return _cachedTickets[repo]!;

    final ticketsMap = <int, GitHubTicket>{};
    _log('  Fetching tickets assigned to $username in $repo (open & closed)…');

    Future<void> fetchIssues(Uri uri) async {
      final resp = await _getWithRetry(uri);
      if (resp != null && resp.statusCode == 200) {
        try {
          final List<dynamic> data = jsonDecode(resp.body);
          for (final item in data) {
            final num = item['number'] as int;
            final title = item['title'] as String? ?? '';
            final body = item['body'] as String?;
            final state = item['state'] as String? ?? 'open';
            final createdAt = item['created_at'] != null ? DateTime.parse(item['created_at']) : null;
            final closedAt = item['closed_at'] != null ? DateTime.parse(item['closed_at']) : null;
            final updatedAt = item['updated_at'] != null ? DateTime.parse(item['updated_at']) : null;

            final ticketKey = extractTicketKey(title) ?? extractTicketKey(body ?? '');

            ticketsMap[num] = GitHubTicket(
              number: num,
              title: title,
              body: body,
              state: state,
              createdAt: createdAt,
              closedAt: closedAt,
              updatedAt: updatedAt,
              ticketKey: ticketKey,
            );
          }
        } catch (e) {
          _log('  ⚠ Error parsing issues: $e', SyncLogLevel.warning);
        }
      }
    }

    // 1. Issues assigned to user
    await fetchIssues(Uri.parse(
      'https://api.github.com/repos/$repo/issues'
      '?state=all&assignee=${Uri.encodeComponent(username)}'
      '&sort=updated&direction=desc&per_page=100',
    ));

    // 2. Issues created by user
    await fetchIssues(Uri.parse(
      'https://api.github.com/repos/$repo/issues'
      '?state=all&creator=${Uri.encodeComponent(username)}'
      '&sort=updated&direction=desc&per_page=100',
    ));

    final result = ticketsMap.values.toList();
    _cachedTickets[repo] = result;
    final closedCount = result.where((t) => t.state == 'closed').length;
    _log('  ✓ Found ${result.length} ticket(s) for $username ($closedCount closed)');
    return result;
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
      'https://api.github.com/repos/$repo/pulls?state=all&sort=updated&direction=desc&per_page=100',
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
    _log('  ✓ Found ${prList.length} user PR branch(es) (including merged & closed)');
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

  /// Fetches candidate branches that the user worked on or committed to.
  Future<List<String>> listUserBranches(
    String repo, {
    List<GitHubTicket>? assignedTickets,
    DateTime? since,
    DateTime? until,
  }) async {
    repo = normalizeRepo(repo);
    if (_cachedUserBranches.containsKey(repo)) {
      return _cachedUserBranches[repo]!;
    }

    final userBranches = <String>{};

    // 1. Branches from user's PRs (including closed and merged!)
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

    // 3. Active repository branches
    final uri = Uri.parse('https://api.github.com/repos/$repo/branches?per_page=100');
    final response = await _getWithRetry(uri);
    if (response != null && response.statusCode == 200) {
      try {
        final List<dynamic> data = jsonDecode(response.body);
        final target = username.toLowerCase();

        final ticketNumbers = (assignedTickets ?? []).map((t) => t.number.toString()).toSet();
        final ticketKeys = (assignedTickets ?? [])
            .where((t) => t.ticketKey != null)
            .map((t) => t.ticketKey!.toLowerCase())
            .toSet();

        for (final b in data) {
          final name = b['name'] as String? ?? '';
          if (name.isEmpty) continue;
          final lower = name.toLowerCase();

          // Check if name contains username prefix
          final isUserNamed = lower.startsWith('$target/') ||
              lower.contains(target) ||
              lower.startsWith('osobol/');

          // Check if matches an assigned ticket
          bool matchesTicket = false;
          for (final key in ticketKeys) {
            if (lower.contains(key)) {
              matchesTicket = true;
              break;
            }
          }
          if (!matchesTicket) {
            for (final num in ticketNumbers) {
              final reg = RegExp('(?:^|/|[_-])$num(?:[_-]|\$)', caseSensitive: false);
              if (reg.hasMatch(name)) {
                matchesTicket = true;
                break;
              }
            }
          }

          // Check if has an identifiable ticket ref (e.g. feat/taxes-page-sol-56)
          final hasTicketRef = extractIssueRef(name) != null;

          if (isUserNamed || matchesTicket || hasTicketRef) {
            userBranches.add(name);
          }
        }
      } catch (e) {
        _log('  ⚠ Error parsing branches: $e', SyncLogLevel.warning);
      }
    }

    final result = userBranches.toList();
    _cachedUserBranches[repo] = result;
    return result;
  }

  /// Legacy alias so existing callers remain compatible.
  Future<List<String>> listIssueBranches(String repo) => listUserBranches(repo);

  /// Comprehensive collector of all user work (tickets, branches, commits) on [repo].
  /// Gathers active branches, closed/merged PR branches, assigned tickets, and commits.
  Future<List<UserBranchWork>> getUserWorkUnits(
    String repo, {
    DateTime? since,
    DateTime? until,
  }) async {
    repo = normalizeRepo(repo);
    final cacheKey = '$repo::${since?.toIso8601String()}::${until?.toIso8601String()}';
    if (_cachedWorkUnits.containsKey(cacheKey)) {
      return _cachedWorkUnits[cacheKey]!;
    }

    _log('Gathering your GitHub work history for $repo…');

    // 1. Assigned tickets (open & closed)
    final tickets = await getAssignedTickets(repo);

    // 2. User Pull Requests (active, merged, closed)
    final prs = await getUserPullRequests(repo);

    // 3. User candidate branches (active and closed)
    final branches = await listUserBranches(
      repo,
      assignedTickets: tickets,
      since: since,
      until: until,
    );

    // 4. Default branch commits by author
    final defaultCommits = <Map<String, dynamic>>[];
    final sinceParam = since != null ? '&since=${since.toIso8601String()}' : '';
    final untilParam = until != null ? '&until=${until.toIso8601String()}' : '';
    final commitsUri = Uri.parse(
      'https://api.github.com/repos/$repo/commits'
      '?author=${Uri.encodeComponent(username)}'
      '$sinceParam$untilParam&per_page=100',
    );
    final commitsResp = await _getWithRetry(commitsUri);
    if (commitsResp != null && commitsResp.statusCode == 200) {
      try {
        final List<dynamic> data = jsonDecode(commitsResp.body);
        for (final c in data) {
          if (_isUserAuthor(c)) defaultCommits.add(c);
        }
      } catch (_) {}
    }

    // 5. User Push Events
    final pushEvents = await getUserPushEvents();

    // Map: branchName -> UserBranchWork
    final workMap = <String, UserBranchWork>{};

    void addWork(
      String branchName, {
      String? ticketRef,
      String? ticketTitle,
      bool isClosed = false,
      List<DateTime>? timestamps,
      String? source,
    }) {
      final existing = workMap[branchName];
      final combinedTimestamps = <DateTime>{
        ...?existing?.commitTimestamps,
        ...?timestamps,
      }.toList()..sort();

      final resolvedRef = ticketRef ??
          existing?.ticketRef ??
          extractIssueRef(branchName);

      final resolvedTitle = ticketTitle ?? existing?.ticketTitle;
      final resolvedClosed = (existing?.isClosed ?? false) || isClosed;

      workMap[branchName] = UserBranchWork(
        branchName: branchName,
        ticketRef: resolvedRef,
        ticketTitle: resolvedTitle,
        isClosed: resolvedClosed,
        commitTimestamps: combinedTimestamps,
        source: source ?? existing?.source,
      );
    }

    // A. Add PR branches (covers closed and merged branches!)
    for (final pr in prs) {
      final prRef = extractIssueRef(pr.branch) ??
          extractIssueRef(pr.title) ??
          'Issue-${pr.number}';

      final timestamps = <DateTime>[...pr.commitTimestamps];
      if (pr.mergedAt != null) timestamps.add(pr.mergedAt!);
      if (pr.createdAt != null) timestamps.add(pr.createdAt!);

      addWork(
        pr.branch,
        ticketRef: prRef,
        ticketTitle: pr.title,
        isClosed: true,
        timestamps: timestamps,
        source: 'pr',
      );
    }

    // B. Add commits on active candidate branches
    for (final branch in branches) {
      if (branch == 'main' || branch == 'master') continue;
      final timestamps = await _getCommitTimestampsOnBranch(
        repo,
        branch,
        since ?? DateTime.now().subtract(const Duration(days: 30)),
        until ?? DateTime.now().add(const Duration(days: 1)),
      );
      if (timestamps.isNotEmpty || !workMap.containsKey(branch)) {
        addWork(
          branch,
          timestamps: timestamps,
          source: 'branch',
        );
      }
    }

    // C. Add commits from default branch
    for (final commit in defaultCommits) {
      final dateStr = commit['commit']?['author']?['date'] as String?;
      if (dateStr == null) continue;
      final ts = DateTime.parse(dateStr);
      final msg = commit['commit']?['message'] as String? ?? '';
      final sha = commit['sha'] as String? ?? '';

      final msgRefs = extractAllIssueRefs(msg);
      String? matchedRef;
      if (msgRefs.isNotEmpty) {
        matchedRef = msgRefs.first;
      } else if (sha.isNotEmpty) {
        final prRefs = await _getIssueRefsFromCommitPulls(repo, sha);
        if (prRefs.isNotEmpty) matchedRef = prRefs.first;
      }

      if (matchedRef != null) {
        final branchMatch = workMap.keys.firstWhere(
          (b) => extractIssueRef(b) == matchedRef,
          orElse: () => 'main',
        );
        addWork(
          branchMatch,
          ticketRef: matchedRef,
          timestamps: [ts],
          source: 'commit',
        );
      }
    }

    // D. Add Push Events for this repo
    for (final ev in pushEvents) {
      if (ev.repo == repo && ev.ref.isNotEmpty) {
        final cleanRef = ev.ref.replaceFirst(RegExp(r'^refs/heads/'), '');
        addWork(
          cleanRef,
          ticketRef: ev.issueRef,
          timestamps: [ev.timestamp],
          source: 'push',
        );
      }
    }

    // E. Link Assigned Tickets to Branches (or create work unit for assigned tickets)
    for (final ticket in tickets) {
      final ticketRef = ticket.preferredRef;
      final ticketNumStr = ticket.number.toString();
      final key = ticket.ticketKey?.toLowerCase();

      // Find matching branch among workMap
      String? matchedBranch;
      for (final branchName in workMap.keys) {
        final bLower = branchName.toLowerCase();
        if (key != null && bLower.contains(key)) {
          matchedBranch = branchName;
          break;
        }
        final reg = RegExp('(?:^|/|[_-])$ticketNumStr(?:[_-]|\$)', caseSensitive: false);
        if (reg.hasMatch(branchName)) {
          matchedBranch = branchName;
          break;
        }
      }

      final ticketTimestamps = <DateTime>[
        if (ticket.closedAt != null) ticket.closedAt!,
        if (ticket.updatedAt != null) ticket.updatedAt!,
        if (ticket.createdAt != null) ticket.createdAt!,
      ];

      if (matchedBranch != null) {
        addWork(
          matchedBranch,
          ticketRef: ticketRef,
          ticketTitle: ticket.title,
          isClosed: ticket.state == 'closed' || (workMap[matchedBranch]?.isClosed ?? false),
          timestamps: ticketTimestamps,
          source: 'ticket',
        );
      } else {
        // Assigned ticket without an identified git branch
        addWork(
          'ticket-${ticket.number}',
          ticketRef: ticketRef,
          ticketTitle: ticket.title,
          isClosed: ticket.state == 'closed',
          timestamps: ticketTimestamps,
          source: 'ticket',
        );
      }
    }

    final result = workMap.values.toList();
    _cachedWorkUnits[cacheKey] = result;

    _log('  ✓ Loaded ${result.length} work units across branches & tickets for $repo');
    return result;
  }

  /// Legacy method: builds a map of { issueRef → [commit UTC timestamps] } for a single day.
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

    // 1. Commits on default branch
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

    // 2. User's Pull Requests
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

    // 4. User's active branches
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
    // 1. Try with author filter
    final uri = Uri.parse(
      'https://api.github.com/repos/$repo/commits'
      '?sha=${Uri.encodeComponent(branch)}'
      '&author=${Uri.encodeComponent(username)}'
      '&since=${since.toIso8601String()}'
      '&until=${until.toIso8601String()}'
      '&per_page=100',
    );
    final response = await _getWithRetry(uri);
    final timestamps = <DateTime>[];

    if (response != null && response.statusCode == 200) {
      try {
        final List<dynamic> data = jsonDecode(response.body);
        for (final commit in data) {
          if (!_isUserAuthor(commit)) continue;
          final dateStr = commit['commit']?['author']?['date'] as String?;
          if (dateStr != null) timestamps.add(DateTime.parse(dateStr));
        }
      } catch (e) {
        _log('  ⚠ Error decoding commits for $branch: $e', SyncLogLevel.warning);
      }
    }

    // 2. If author query returned empty, try without author filter in case git email differs
    if (timestamps.isEmpty) {
      final fallbackUri = Uri.parse(
        'https://api.github.com/repos/$repo/commits'
        '?sha=${Uri.encodeComponent(branch)}'
        '&since=${since.toIso8601String()}'
        '&until=${until.toIso8601String()}'
        '&per_page=50',
      );
      final fallbackResp = await _getWithRetry(fallbackUri);
      if (fallbackResp != null && fallbackResp.statusCode == 200) {
        try {
          final List<dynamic> data = jsonDecode(fallbackResp.body);
          for (final commit in data) {
            if (!_isUserAuthor(commit)) continue;
            final dateStr = commit['commit']?['author']?['date'] as String?;
            if (dateStr != null) timestamps.add(DateTime.parse(dateStr));
          }
        } catch (_) {}
      }
    }

    return timestamps;
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
