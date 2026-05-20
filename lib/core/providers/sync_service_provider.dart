import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/sync_service.dart';
import 'auth_provider.dart';
import 'database_provider.dart';
import 'supabase_provider.dart';

/// Provides a [SyncService] on Android/native.
/// Returns `null` on web (web uses Supabase directly — no local sync needed).
final syncServiceProvider = FutureProvider<SyncService?>((ref) async {
  if (kIsWeb) return null;

  final session = ref.watch(authProvider).value;
  if (session == null) return null;

  final db = ref.watch(databaseProvider);
  final supabase = ref.watch(supabaseProvider);

  final service = SyncService(db, supabase);
  await service.init();

  ref.onDispose(service.dispose);
  return service;
});

/// Fires an automatic sync when the auth session first becomes available.
///
/// Watch this provider from a root widget to keep auto-sync alive.
final autoSyncProvider = Provider<void>((ref) {
  if (kIsWeb) return;

  ref.listen(syncServiceProvider, (_, next) {
    next.whenData((service) {
      if (service != null) {
        service.sync().ignore();
      }
    });
  }, fireImmediately: true);
});

/// Current sync status stream. Yields `null` on web or before the service initialises.
final syncStatusProvider = StreamProvider<SyncStatus?>((ref) {
  if (kIsWeb) return Stream.value(null);

  final serviceAsync = ref.watch(syncServiceProvider);
  final service = serviceAsync.value;
  if (service == null) return Stream.value(null);

  return service.statusStream.cast<SyncStatus?>();
});

/// Convenience: exposes [SyncService.sync()] as a callable action.
/// Returns `null` on web or when not authenticated.
final syncNowProvider = Provider<Future<void> Function()?>((ref) {
  if (kIsWeb) return null;

  final serviceAsync = ref.watch(syncServiceProvider);
  final service = serviceAsync.value;
  if (service == null) return null;

  return service.sync;
});
