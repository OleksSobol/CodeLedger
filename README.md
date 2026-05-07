# CodeLedger

Offline-first time tracking and invoicing app for freelance developers. Built with Flutter, backed by local SQLite via Drift, with encrypted Google Drive backups.

> **Latest release:** [v1.1.0](https://github.com/OleksSobol/-CodeLedger-/releases/tag/v1.1.0)

## Features

### Time Tracking
- Clock in/out timer with overlap detection and running duration display
- Manual entry and editing — date, times, rate, description, project, issue reference, repository, tags
- Project selection on time entries (filterable by client)
- Configurable tile layout — show/hide and reorder fields (time, client, description, issue, repo, tags, badges)
- Tag filtering and date-range filter (today / this week / this month / custom)
- CSV export for any date range

### GitHub Integration
- Link a GitHub repo (`owner/repo`) to any project
- Connect via Personal Access Token (Settings → Accounts → GitHub)
- **Connection test** — verifies PAT and checks access to all linked repos with live feedback
- **Sync GitHub Issues** — scans linked repos for `Issue-XXXX` branches and commit messages within the selected date range (capped at today); previews matches with live log before applying; matches use the entry's exact time window for commit-level precision

### Client & Project Management
- Archive/restore clients and projects
- Per-client hourly rate, tax rate, and currency
- Per-project hourly rate override and GitHub repo link

### Invoicing
- Invoice wizard — select uninvoiced time entries, add manual line items, apply tax
- Draft editing, mark paid/archived, late fee clause
- PDF templates — 3 built-in: Minimal, Detailed Breakdown, Modern Developer
- Template designer — colors, font, footer, description, independent Date, Issue #, and Description column toggles, logo, payment info, tax breakdown, bank details, Stripe link, and more
- Custom templates (duplicate and customize any built-in)

### Reports
- **Timesheet** — PDF with configurable columns (start/end, description, project)
- **Work Report** — detailed PDF grouped by day with issue references
- **Tax / Income Report** — net income and tax collected from paid invoices (PDF + CSV)
- **WA Excise Tax (B&O)** — quarterly WA DOR data upload CSV (ACCOUNT + TAX line 6 for Service B&O); History tab tracks submitted quarters with re-export

### Settings & Data
- **Accounts** — GitHub PAT and username for issue sync
- **Entry Layout** — drag-to-reorder and toggle visibility of time entry tile fields
- **Invoice Templates** — manage and set default template
- **Encrypted backups** — AES-256-GCM to local storage or Google Drive
- **Erase all data** — double-confirmation reset (passphrase preserved)
- **Dark mode** — System / Light / Dark theme switcher

## Tech Stack
- **Flutter** (Android, iOS, Web, Windows)
- **Drift** — SQLite ORM with reactive streams
- **Riverpod** — State management
- **GoRouter** — Navigation
- **pdf** / **printing** — Invoice PDF generation

## Setup

### Prerequisites
- Flutter SDK ≥ 3.9.2
- Android Studio or VS Code with Flutter extension
- For Android: Android SDK, USB debugging enabled on device

### Install & Run
```bash
cd code_ledger

# Install dependencies
flutter pub get

# Generate Drift/Riverpod/Freezed code
dart run build_runner build --delete-conflicting-outputs

# Run on connected device or emulator
flutter run
```

### Build APK for Android Phone
```bash
# Debug APK (fast, larger size, includes dev tools)
flutter build apk --debug

# Release APK (optimized, smaller, no dev tools)
flutter build apk --release

# The APK will be at:
# build/app/outputs/flutter-apk/app-debug.apk
# build/app/outputs/flutter-apk/app-release.apk
```

### Install APK on Phone
```bash
# With USB connected and USB debugging enabled:
flutter install

# Or manually transfer the APK file and open it on the phone
# (enable "Install from unknown sources" in Android settings)

# Or use adb directly:
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Run on Phone via USB (Development)
```bash
# 1. Enable Developer Options on your Android phone:
#    Settings → About Phone → tap "Build Number" 7 times
#
# 2. Enable USB Debugging:
#    Settings → Developer Options → USB Debugging → ON
#
# 3. Connect phone via USB, accept the debugging prompt
#
# 4. Verify device is detected:
flutter devices

# 5. Run the app on your phone:
flutter run
```

## Project Structure
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full architecture details.

```
lib/
├── main.dart / app.dart          # Entry points
├── core/                         # Database, theme, routing, utils
└── features/                     # Feature modules (clean architecture)
    ├── dashboard/
    ├── profile/
    ├── clients/
    ├── projects/
    ├── time_tracking/
    ├── invoices/
    ├── pdf_generation/
    ├── github/                   # GitHub issue sync
    ├── reports/
    ├── backup/
    └── ...
```

## Documentation
- [Architecture](docs/ARCHITECTURE.md)
- [Database Schema](docs/DATABASE_SCHEMA.md)
- [DAO Reference](docs/DAO_REFERENCE.md)
- [Business Logic](docs/BUSINESS_LOGIC.md)
- [Implementation Phases](docs/IMPLEMENTATION_PHASES.md)
- [Packages](docs/PACKAGES.md)
