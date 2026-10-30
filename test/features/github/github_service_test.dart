import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:code_ledger/features/github/data/github_service.dart';

void main() {
  group('GitHubService Issue & Ticket Ref Extraction', () {
    test('extractTicketKey extracts standard keys like SOL-56 and DEV-79', () {
      expect(GitHubService.extractTicketKey('feat/taxes-page-sol-56'), 'SOL-56');
      expect(GitHubService.extractTicketKey('olekssobol/sol-44-fix-line-item-description'), 'SOL-44');
      expect(GitHubService.extractTicketKey('olekssobol/sol-50-pdf-selection'), 'SOL-50');
      expect(GitHubService.extractTicketKey('olekssobol/sol-58-on-time-tracking-screen-add-show-by-company'), 'SOL-58');
      expect(GitHubService.extractTicketKey('feat: DEV-79 overhaul invoice screen'), 'DEV-79');
      expect(GitHubService.extractTicketKey('fix: DEV-100 fix tax dates'), 'DEV-100');
      expect(GitHubService.extractTicketKey('PVM-4095'), 'PVM-4095');
      expect(GitHubService.extractTicketKey('GH-39'), 'GH-39');
      // Should ignore git action words like feat, fix, page
      expect(GitHubService.extractTicketKey('fix/scan-bugs-batch-1'), isNull);
      expect(GitHubService.extractTicketKey('fix/quarterly-tax-deductions-39'), isNull);
    });

    test('extractIssueRef extracts ticket keys and falls back to issue numbers', () {
      expect(GitHubService.extractIssueRef('feat/taxes-page-sol-56'), 'SOL-56');
      expect(GitHubService.extractIssueRef('olekssobol/sol-44-fix-line-item-description'), 'SOL-44');
      expect(GitHubService.extractIssueRef('fix/quarterly-tax-deductions-39'), 'Issue-39');
      expect(GitHubService.extractIssueRef('fix/quarterly-tax-deductions-gh-39'), 'GH-39');
      expect(GitHubService.extractIssueRef('feat: DEV-79 overhaul invoice'), 'DEV-79');
      expect(GitHubService.extractIssueRef('Fixes #4095'), 'Issue-4095');
      expect(GitHubService.extractIssueRef('closes #56'), 'Issue-56');
      expect(GitHubService.extractIssueRef('#142'), 'Issue-142');
      expect(GitHubService.extractIssueRef('feat/4095-tax-calc'), 'Issue-4095');
      expect(GitHubService.extractIssueRef('4095-tax-calc'), 'Issue-4095');
      expect(GitHubService.extractIssueRef('random-branch-name'), isNull);
    });

    test('extractAllIssueRefs finds all refs in commit messages', () {
      final refs = GitHubService.extractAllIssueRefs(
        'feat: DEV-79 and SOL-56 overhaul invoice screen, closes #100',
      );
      expect(refs, contains('DEV-79'));
      expect(refs, contains('SOL-56'));
      expect(refs, contains('Issue-100'));
    });
  });

  group('GitHubService Work Units & Ticket Association', () {
    test('getUserWorkUnits fetches assigned tickets, closed PRs, and associates them', () async {
      final client = MockClient((request) async {
        final uri = request.url.toString();

        // 1. Verify repo access
        if (uri.contains('/repos/owner/repo') && !uri.contains('/issues') && !uri.contains('/pulls') && !uri.contains('/branches') && !uri.contains('/commits')) {
          return http.Response(jsonEncode({
            'full_name': 'owner/repo',
            'private': true,
          }), 200);
        }

        // 2. Assigned issues (open & closed)
        if (uri.contains('/issues') && uri.contains('assignee=')) {
          return http.Response(jsonEncode([
            {
              'number': 56,
              'title': '[SOL-56] Taxes page overhaul',
              'body': 'Implements WA excise and deduction breakdown',
              'state': 'closed',
              'created_at': '2026-10-20T10:00:00Z',
              'closed_at': '2026-10-25T22:30:00Z',
              'updated_at': '2026-10-25T22:30:00Z',
            },
            {
              'number': 79,
              'title': 'Overhaul invoice screen with metrics [DEV-79]',
              'state': 'open',
              'created_at': '2026-10-15T08:00:00Z',
              'updated_at': '2026-10-16T18:00:00Z',
            },
          ]), 200);
        }

        // Issues created by user
        if (uri.contains('/issues') && uri.contains('creator=')) {
          return http.Response(jsonEncode([]), 200);
        }

        // 3. User PRs (including closed/merged)
        if (uri.contains('/pulls') && !uri.contains('/commits')) {
          return http.Response(jsonEncode([
            {
              'number': 12,
              'title': 'feat: taxes page SOL-56',
              'head': {'ref': 'feat/taxes-page-sol-56'},
              'user': {'login': 'OleksSobol'},
              'state': 'closed',
              'created_at': '2026-10-25T20:00:00Z',
              'merged_at': '2026-10-25T22:30:00Z',
            },
          ]), 200);
        }

        // PR commits
        if (uri.contains('/pulls/12/commits')) {
          return http.Response(jsonEncode([
            {
              'commit': {
                'author': {
                  'name': 'OleksSobol',
                  'email': '20010526+OleksSobol@users.noreply.github.com',
                  'date': '2026-10-25T22:00:00Z',
                },
              },
            },
          ]), 200);
        }

        // 4. Branches
        if (uri.contains('/branches')) {
          return http.Response(jsonEncode([
            {'name': 'main'},
            {'name': 'feat/taxes-page-sol-56'},
            {'name': 'olekssobol/sol-44-fix-line-item-description'},
          ]), 200);
        }

        // 5. Default branch commits
        if (uri.contains('/commits') && uri.contains('author=')) {
          return http.Response(jsonEncode([
            {
              'sha': 'bad220a',
              'commit': {
                'author': {
                  'name': 'OleksSobol',
                  'date': '2026-10-16T18:00:00Z',
                },
                'message': 'feat: DEV-79 overhaul invoice screen',
              },
            },
          ]), 200);
        }

        // Push events
        if (uri.contains('/users/OleksSobol/events')) {
          return http.Response(jsonEncode([]), 200);
        }

        // Branch commits
        if (uri.contains('/commits') && uri.contains('sha=olekssobol')) {
          return http.Response(jsonEncode([
            {
              'commit': {
                'author': {
                  'name': 'OleksSobol',
                  'date': '2026-10-28T14:00:00Z',
                },
              },
            },
          ]), 200);
        }

        return http.Response('[]', 200);
      });

      final service = GitHubService(
        pat: 'fake_pat',
        username: 'OleksSobol',
        client: client,
      );

      final workUnits = await service.getUserWorkUnits('owner/repo');

      expect(workUnits.isNotEmpty, isTrue);

      // Verify SOL-56 was associated to its branch feat/taxes-page-sol-56
      final sol56Work = workUnits.firstWhere(
        (w) => w.branchName == 'feat/taxes-page-sol-56',
      );
      expect(sol56Work.ticketRef, 'SOL-56');
      expect(sol56Work.isClosed, isTrue);
      expect(sol56Work.commitTimestamps, contains(DateTime.parse('2026-10-25T22:00:00Z')));

      // Verify DEV-79 from default branch commits
      final dev79Work = workUnits.firstWhere(
        (w) => w.ticketRef == 'DEV-79',
      );
      expect(dev79Work.ticketRef, 'DEV-79');
      expect(dev79Work.commitTimestamps, contains(DateTime.parse('2026-10-16T18:00:00Z')));

      // Verify sol-44 branch
      final sol44Work = workUnits.firstWhere(
        (w) => w.branchName == 'olekssobol/sol-44-fix-line-item-description',
      );
      expect(sol44Work.ticketRef, 'SOL-44');
    });
  });
}
