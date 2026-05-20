import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/client_repository.dart';
import '../repositories/project_repository.dart';
import '../repositories/time_entry_repository.dart';
import '../repositories/invoice_repository.dart';
import '../repositories/invoice_template_repository.dart';
import '../repositories/user_profile_repository.dart';
import '../repositories/drift/drift_client_repository.dart';
import '../repositories/drift/drift_project_repository.dart';
import '../repositories/drift/drift_time_entry_repository.dart';
import '../repositories/drift/drift_invoice_repository.dart';
import '../repositories/drift/drift_invoice_template_repository.dart';
import '../repositories/drift/drift_user_profile_repository.dart';
import '../repositories/supabase/supabase_client_repository.dart';
import '../repositories/supabase/supabase_project_repository.dart';
import '../repositories/supabase/supabase_time_entry_repository.dart';
import '../repositories/supabase/supabase_invoice_repository.dart';
import '../repositories/supabase/supabase_invoice_template_repository.dart';
import '../repositories/supabase/supabase_user_profile_repository.dart';
import 'dao_providers.dart';
import 'database_provider.dart';
import 'supabase_provider.dart';

final clientRepositoryProvider = Provider<ClientRepository>((ref) {
  if (kIsWeb) {
    return SupabaseClientRepository(ref.watch(supabaseProvider));
  }
  return DriftClientRepository(ref.watch(clientDaoProvider));
});

final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  if (kIsWeb) {
    return SupabaseProjectRepository(ref.watch(supabaseProvider));
  }
  return DriftProjectRepository(ref.watch(projectDaoProvider));
});

final timeEntryRepositoryProvider = Provider<TimeEntryRepository>((ref) {
  if (kIsWeb) {
    return SupabaseTimeEntryRepository(ref.watch(supabaseProvider));
  }
  final db = ref.watch(databaseProvider);
  return DriftTimeEntryRepository(ref.watch(timeEntryDaoProvider), db);
});

final invoiceRepositoryProvider = Provider<InvoiceRepository>((ref) {
  if (kIsWeb) {
    return SupabaseInvoiceRepository(ref.watch(supabaseProvider));
  }
  return DriftInvoiceRepository(ref.watch(invoiceDaoProvider));
});

final invoiceTemplateRepositoryProvider =
    Provider<InvoiceTemplateRepository>((ref) {
  if (kIsWeb) {
    return SupabaseInvoiceTemplateRepository(ref.watch(supabaseProvider));
  }
  return DriftInvoiceTemplateRepository(ref.watch(invoiceTemplateDaoProvider));
});

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  if (kIsWeb) {
    return SupabaseUserProfileRepository(ref.watch(supabaseProvider));
  }
  return DriftUserProfileRepository(ref.watch(userProfileDaoProvider));
});
