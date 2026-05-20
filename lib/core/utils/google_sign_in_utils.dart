import 'package:google_sign_in/google_sign_in.dart';

bool _initialized = false;

Future<void> ensureGoogleSignInInitialized() async {
  if (_initialized) return;
  _initialized = true;
  await GoogleSignIn.instance.initialize();
}
