import '../database/app_database.dart';

abstract class UserProfileRepository {
  Stream<UserProfile> watchProfile();
  Future<UserProfile> getProfile();
  Future<bool> updateProfile(UserProfilesCompanion companion);
  Future<String> getNextInvoiceNumber();
}
