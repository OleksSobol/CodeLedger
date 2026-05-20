import '../../database/app_database.dart';
import '../../database/daos/user_profile_dao.dart';
import '../user_profile_repository.dart';

class DriftUserProfileRepository implements UserProfileRepository {
  final UserProfileDao _dao;
  DriftUserProfileRepository(this._dao);

  @override Stream<UserProfile> watchProfile() => _dao.watchProfile();
  @override Future<UserProfile> getProfile() => _dao.getProfile();
  @override Future<bool> updateProfile(UserProfilesCompanion c) => _dao.updateProfile(c);
  @override Future<String> getNextInvoiceNumber() => _dao.getNextInvoiceNumber();
}
