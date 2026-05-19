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
    final result = GoogleSignIn.instance.attemptLightweightAuthentication();
    if (result != null) return await result;
    return null;
  }

  Future<void> signIn() async {
    state = const AsyncLoading();
    try {
      await ensureGoogleSignInInitialized();
      final user = await GoogleSignIn.instance.authenticate();
      state = AsyncData(user);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> signOut() async {
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    state = const AsyncData(null);
  }
}
