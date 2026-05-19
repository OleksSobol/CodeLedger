import 'dart:io';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/google_sign_in_utils.dart';

/// Google Drive backup integration.
///
/// Uploads encrypted backup files to `/CodeLedger/` folder on Drive.
class DriveBackupService {
  static const _scopes = [drive.DriveApi.driveFileScope];

  GoogleSignInAccount? _currentUser;
  drive.DriveApi? _driveApi;

  /// Signs in to Google and initializes the Drive API client.
  Future<String?> signIn() async {
    final signIn = GoogleSignIn.instance;
    await ensureGoogleSignInInitialized();
    final user = await _authenticateAndWait(signIn);
    if (user == null) return null;

    await _initDriveApi(user);
    return user.email;
  }

  /// Attempts lightweight (silent) sign-in for returning users.
  Future<String?> trySilentSignIn() async {
    final signIn = GoogleSignIn.instance;
    await ensureGoogleSignInInitialized();

    final result = signIn.attemptLightweightAuthentication();
    if (result == null) return null;

    final user = await result;
    if (user == null) return null;

    await _initDriveApi(user);
    return user.email;
  }

  /// Signs out of Google and clears Drive API client.
  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Ignore errors during sign out
    }
    _currentUser = null;
    _driveApi = null;
  }

  /// Whether the user is currently signed in.
  bool get isSignedIn => _driveApi != null;

  /// The signed-in user's email, if any.
  String? get userEmail => _currentUser?.email;

  /// Uploads an encrypted backup file to Google Drive.
  Future<void> uploadBackup(File backupFile) async {
    final api = _requireApi();
    final folderId = await _getOrCreateFolder(api);
    final filename = p.basename(backupFile.path);

    final media =
        drive.Media(backupFile.openRead(), await backupFile.length());
    final driveFile = drive.File()
      ..name = filename
      ..parents = [folderId];

    await api.files.create(driveFile, uploadMedia: media);
  }

  /// Lists backup files on Google Drive, newest first.
  Future<List<DriveBackupEntry>> listBackups() async {
    final api = _requireApi();
    final folderId = await _getOrCreateFolder(api);

    final result = await api.files.list(
      q: "'$folderId' in parents and name contains "
          "'${AppConstants.backupFilePrefix}' and trashed = false",
      orderBy: 'createdTime desc',
      $fields: 'files(id, name, size, createdTime)',
    );

    return (result.files ?? []).map((f) {
      return DriveBackupEntry(
        id: f.id!,
        name: f.name!,
        size: int.tryParse(f.size ?? '0') ?? 0,
        createdAt: f.createdTime,
      );
    }).toList();
  }

  /// Downloads a backup file from Google Drive to a temp file.
  Future<File> downloadBackup(String fileId, String filename) async {
    final api = _requireApi();

    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final dir = await Directory.systemTemp.createTemp('codledger_restore');
    final file = File(p.join(dir.path, filename));
    final sink = file.openWrite();

    await for (final chunk in media.stream) {
      sink.add(chunk);
    }
    await sink.close();

    return file;
  }

  /// Deletes a backup file from Google Drive.
  Future<void> deleteBackup(String fileId) async {
    final api = _requireApi();
    await api.files.delete(fileId);
  }

  // -- Private helpers --

  Future<GoogleSignInAccount?> _authenticateAndWait(
      GoogleSignIn signIn) async {
    // Try lightweight first
    final silentResult = signIn.attemptLightweightAuthentication();
    if (silentResult != null) {
      final silentUser = await silentResult;
      if (silentUser != null) return silentUser;
    }

    // Full interactive sign-in
    try {
      return await signIn.authenticate(scopeHint: _scopes);
    } on GoogleSignInException {
      return null;
    }
  }

  Future<void> _initDriveApi(GoogleSignInAccount user) async {
    _currentUser = user;

    // Get authorization headers for Drive scope
    final headers = await user.authorizationClient.authorizationHeaders(
      _scopes,
      promptIfNecessary: true,
    );

    if (headers == null) {
      throw StateError('Failed to obtain Drive authorization');
    }

    final client = _GoogleAuthClient(headers);
    _driveApi = drive.DriveApi(client);
  }

  /// Finds or creates the `/CodeLedger/` folder on Drive.
  Future<String> _getOrCreateFolder(drive.DriveApi api) async {
    final result = await api.files.list(
      q: "name = '${AppConstants.driveFolder}' and "
          "mimeType = 'application/vnd.google-apps.folder' and "
          "trashed = false",
      $fields: 'files(id)',
    );

    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }

    final folder = drive.File()
      ..name = AppConstants.driveFolder
      ..mimeType = 'application/vnd.google-apps.folder';

    final created = await api.files.create(folder);
    return created.id!;
  }

  drive.DriveApi _requireApi() {
    if (_driveApi == null) {
      throw StateError('Not signed in to Google Drive');
    }
    return _driveApi!;
  }
}

/// Metadata for a backup file stored on Google Drive.
class DriveBackupEntry {
  final String id;
  final String name;
  final int size;
  final DateTime? createdAt;

  const DriveBackupEntry({
    required this.id,
    required this.name,
    required this.size,
    this.createdAt,
  });

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Simple HTTP client that injects Google auth headers.
class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
