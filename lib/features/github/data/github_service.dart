import 'dart:convert';
import 'package:http/http.dart' as http;

enum SyncLogLevel { info, warning, error }

class SyncLog {
  final String message;
  final SyncLogLevel level;
  SyncLog(this.message, this.level);
}

class GitHubService {
  final String pat;
  final String username;
  final List<SyncLog> logs = [];
  final void Function(SyncLog)? onLog;

  GitHubService({required this.pat, required this.username, this.onLog});

  Map<String, String> get _headers => {
        'Authorization': 'token $pat',
        'Accept': 'application/vnd.github.v3+json',
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

  /// Verifies the PAT by calling /user.
  Future<String> verifyPat() async {
    final uri = Uri.parse('https://api.github.com/user');
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['login'] as String? ?? 'unknown';
    } else if (response.statusCode == 401) {
      throw 'Invalid PAT — authentication failed (401)';
    } else {
      throw 'Unexpected response: HTTP ${response.statusCode}';
    }
  }

  /// Checks if the repo is accessible. Returns true on success.
  Future<bool> verifyRepoAccess(String repo) async {
    repo = normalizeRepo(repo);
    _log('Checking access to $repo…');
    final uri = Uri.parse('https://api.github.com/repos/$repo');
    try {
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final name = data['full_name'] ?? repo;
        final isPrivate = data['private'] as bool? ?? false;
        _log('✓ Connected to $name (${isPrivate ? 'private' : 'public'})');
        return true;
      } else if (response.statusCode == 401) {
        _log('✗ Authentication failed — check your GitHub PAT', SyncLogLevel.error);
      } else if (response.statusCode == 404) {
        _log('✗ $repo not found or PAT lacks access (404)', SyncLogLevel.error);
      } else {
        _log('✗ $repo returned HTTP ${response.statusCode}', SyncLogLevel.error);
      }
    } catch (e) {
      _log('✗ Network error for $repo: $e', SyncLogLevel.error);
    }
    return false;
  }

  /// Fetches all branch names matching the Issue-* pattern for [repo].
  Future<List<String>> listIssueBranches(String repo) async {
    final branches = <String>[];
    var page = 1;
    final issuePattern = RegExp(r'^[Ii]ssue[-_]\d+');

    while (true) {
      final uri = Uri.parse(
        'https://api.github.com/repos/$repo/branches?per_page=100&page=$page',
      );
      final response = await http.get(uri, headers: _headers);
      if (response.statusCode != 200) {
        _log('  Branch list failed: HTTP ${response.statusCode}',
            SyncLogLevel.warning);
        break;
      }

      final List<dynamic> data = jsonDecode(response.body);
      if (data.isEmpty) break;

      for (final branch in data) {
        final name = branch['name'] as String;
        if (issuePattern.hasMatch(name)) branches.add(name);
      }

      if (data.length < 100) break;
      page++;
    }
    return branches;
  }

  /// Builds a map of { issueRef → [commit UTC timestamps] } for a single day.
  ///
  /// Call once per (repo, day) and cache the result. Each entry then filters
  /// the timestamps to its own start–end window — no redundant API calls.
  Future<Map<String, List<DateTime>>> getRefsWithTimestampsForDay(
    String repo,
    DateTime dayStart,
    DateTime dayEnd,
    List<String> issueBranches,
  ) async {
    final result = <String, List<DateTime>>{};

    // Check issue branches in parallel batches of 10.
    const batchSize = 10;
    for (var i = 0; i < issueBranches.length; i += batchSize) {
      final batch = issueBranches.skip(i).take(batchSize).toList();
      final batchResults = await Future.wait(
        batch.map((branch) =>
            _getCommitTimestampsOnBranch(repo, branch, dayStart, dayEnd)
                .then((ts) => (branch, ts))),
      );
      for (final (branch, timestamps) in batchResults) {
        if (timestamps.isNotEmpty) {
          result[branch] = timestamps;
          _log('  ✓ $branch — ${timestamps.length} commit(s) on ${_fmtDate(dayStart)}');
        }
      }
    }

    // Commit message refs for the day.
    final msgEntries =
        await _getCommitMessageRefsWithTimestamps(repo, dayStart, dayEnd);
    for (final (ref, timestamp) in msgEntries) {
      result.putIfAbsent(ref, () => []).add(timestamp);
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
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) return [];
    final List<dynamic> data = jsonDecode(response.body);
    final timestamps = <DateTime>[];
    for (final commit in data) {
      final dateStr = commit['commit']?['author']?['date'] as String?;
      if (dateStr != null) timestamps.add(DateTime.parse(dateStr));
    }
    return timestamps;
  }

  Future<List<(String, DateTime)>> _getCommitMessageRefsWithTimestamps(
    String repo,
    DateTime since,
    DateTime until,
  ) async {
    final uri = Uri.parse(
      'https://api.github.com/repos/$repo/commits'
      '?author=${Uri.encodeComponent(username)}'
      '&since=${since.toIso8601String()}'
      '&until=${until.toIso8601String()}'
      '&per_page=100',
    );
    final response = await http.get(uri, headers: _headers);
    if (response.statusCode != 200) return [];

    final List<dynamic> data = jsonDecode(response.body);
    final results = <(String, DateTime)>[];
    final pattern = RegExp(
      r'[Ii]ssue[-_ ]?#?(\d+)|(?:fix(?:es|ed)?|close[sd]?|resolve[sd]?)\s+#(\d+)',
      caseSensitive: false,
    );

    for (final commit in data) {
      final msg = commit['commit']?['message'] as String? ?? '';
      final dateStr = commit['commit']?['author']?['date'] as String?;
      if (dateStr == null) continue;
      final timestamp = DateTime.parse(dateStr);
      for (final match in pattern.allMatches(msg)) {
        final num = match.group(1) ?? match.group(2);
        if (num != null) results.add(('Issue-$num', timestamp));
      }
    }
    return results;
  }
}
