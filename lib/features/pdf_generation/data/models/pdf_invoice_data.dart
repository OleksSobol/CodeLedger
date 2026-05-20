import '../../../../core/database/app_database.dart';

/// All data needed to render an invoice PDF, pre-fetched and resolved.
class PdfInvoiceData {
  final Invoice invoice;
  final Client client;
  final UserProfile profile;
  final InvoiceTemplate template;
  final List<InvoiceLineItem> lineItems;
  final Map<String, String> projectNames; // projectId -> name

  const PdfInvoiceData({
    required this.invoice,
    required this.client,
    required this.profile,
    required this.template,
    required this.lineItems,
    this.projectNames = const <String, String>{},
  });

  String get formattedAddress {
    final parts = <String>[];
    if (profile.addressLine1 != null) parts.add(profile.addressLine1!);
    if (profile.addressLine2 != null) parts.add(profile.addressLine2!);
    final cityState = [
      profile.city,
      profile.stateProvince,
      profile.postalCode,
    ].whereType<String>().join(', ');
    if (cityState.isNotEmpty) parts.add(cityState);
    if (profile.country != null) parts.add(profile.country!);
    return parts.join('\n');
  }

  static final _datePattern = RegExp(r'^[A-Za-z]+ \d+, \d{4}$');

  double get totalHours {
    double total = 0;
    for (final item in lineItems) {
      final parts = item.description.split(' | ');
      final isTimeBased = item.timeEntryId != null ||
          (parts.length > 1 && _datePattern.hasMatch(parts.first.trim()));
      if (isTimeBased) total += item.quantity;
    }
    return total;
  }

  String get clientAddress {
    final parts = <String>[];
    if (client.addressLine1 != null) parts.add(client.addressLine1!);
    if (client.addressLine2 != null) parts.add(client.addressLine2!);
    final cityState = [
      client.city,
      client.stateProvince,
      client.postalCode,
    ].whereType<String>().join(', ');
    if (cityState.isNotEmpty) parts.add(cityState);
    if (client.country != null) parts.add(client.country!);
    return parts.join('\n');
  }
}
