import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/daos/client_dao.dart';
import '../database/daos/project_dao.dart';
import '../database/daos/time_entry_dao.dart';
import '../database/daos/invoice_dao.dart';
import '../database/daos/invoice_template_dao.dart';
import '../database/daos/user_profile_dao.dart';
import 'database_provider.dart';

final clientDaoProvider = Provider<ClientDao>((ref) {
  return ClientDao(ref.watch(databaseProvider));
});

final projectDaoProvider = Provider<ProjectDao>((ref) {
  return ProjectDao(ref.watch(databaseProvider));
});

final timeEntryDaoProvider = Provider<TimeEntryDao>((ref) {
  return TimeEntryDao(ref.watch(databaseProvider));
});

final invoiceDaoProvider = Provider<InvoiceDao>((ref) {
  return InvoiceDao(ref.watch(databaseProvider));
});

final invoiceTemplateDaoProvider = Provider<InvoiceTemplateDao>((ref) {
  return InvoiceTemplateDao(ref.watch(databaseProvider));
});

final userProfileDaoProvider = Provider<UserProfileDao>((ref) {
  return UserProfileDao(ref.watch(databaseProvider));
});
