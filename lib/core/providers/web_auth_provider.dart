import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../utils/google_sign_in_utils.dart';

final webAuthProvider =
    AsyncNotifierProvider<WebAuthNotifier, GoogleSignInAccount?>(
  WebAuthNotifier.new,
);

class WebAuthNotifier extends AsyncNotifier<GoogleSignInAccount?> {
  @override
  Future<GoogleSignInAccount?> build() async {
    if (!kIsWeb) return null;
    await ensureGoogleSignInInitialized();

    // Subscribe to sign-in events fired by renderButton.
    final sub = GoogleSignIn.instance.authenticationEvents.listen((event) {
      switch (event) {
        case GoogleSignInAuthenticationEventSignIn(:final user):
          state = AsyncData(user);
        case GoogleSignInAuthenticationEventSignOut():
          state = const AsyncData(null);
      }
    });
    ref.onDispose(sub.cancel);

    // Try silent sign-in for returning users.
    final result = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (result != null) return await result;
    return null;
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    state = const AsyncData(null);
  }
}
