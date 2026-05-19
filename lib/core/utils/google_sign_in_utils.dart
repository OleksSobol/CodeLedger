import 'package:google_sign_in/google_sign_in.dart';
import '../constants/google_credentials.dart';

bool _initialized = false;

/// Calls [GoogleSignIn.instance.initialize] exactly once across the app lifetime.
Future<void> ensureGoogleSignInInitialized() async {
  if (_initialized) return;
  _initialized = true;
  await GoogleSignIn.instance.initialize(
    serverClientId: googleServerClientId.isNotEmpty ? googleServerClientId : null,
  );
}
