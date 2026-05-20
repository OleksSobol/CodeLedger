import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app.dart';
import 'core/constants/supabase_constants.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    // Catch Flutter framework errors (layout, rendering, etc.)
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      if (kDebugMode) {
        debugPrint('FlutterError: ${details.exceptionAsString()}');
      }
    };

    // Catch errors in platform channels and other async gaps
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) {
        debugPrint('PlatformDispatcher error: $error\n$stack');
      }
      return true;
    };

    runApp(
      const ProviderScope(
        child: CodeLedgerApp(),
      ),
    );
  }, (error, stack) async {
    if (kDebugMode) {
      debugPrint('Uncaught error: $error\n$stack');
    }
  });
}
