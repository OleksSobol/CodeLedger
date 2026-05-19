import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../constants/google_credentials.dart';

bool _initialized = false;

/// Calls [GoogleSignIn.instance.initialize] exactly once across the app lifetime.
///
/// Web: pass [clientId] only (serverClientId is unsupported on web).
/// Native: pass [serverClientId] only.
Future<void> ensureGoogleSignInInitialized() async {
  if (_initialized) return;
  _initialized = true;
  if (kIsWeb) {
    await GoogleSignIn.instance.initialize(
      clientId: googleWebClientId.isNotEmpty ? googleWebClientId : null,
    );
  } else {
    await GoogleSignIn.instance.initialize(
      serverClientId: googleServerClientId.isNotEmpty ? googleServerClientId : null,
    );
  }
}
