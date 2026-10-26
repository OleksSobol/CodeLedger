import 'package:collection/collection.dart';

/// US States & Territories helper for consistent state selection and WA / out-of-state tax checks.
class UsStates {
  UsStates._();

  static const Map<String, String> stateMap = {
    'AL': 'Alabama',
    'AK': 'Alaska',
    'AZ': 'Arizona',
    'AR': 'Arkansas',
    'CA': 'California',
    'CO': 'Colorado',
    'CT': 'Connecticut',
    'DE': 'Delaware',
    'DC': 'District of Columbia',
    'FL': 'Florida',
    'GA': 'Georgia',
    'HI': 'Hawaii',
    'ID': 'Idaho',
    'IL': 'Illinois',
    'IN': 'Indiana',
    'IA': 'Iowa',
    'KS': 'Kansas',
    'KY': 'Kentucky',
    'LA': 'Louisiana',
    'ME': 'Maine',
    'MD': 'Maryland',
    'MA': 'Massachusetts',
    'MI': 'Michigan',
    'MN': 'Minnesota',
    'MS': 'Mississippi',
    'MO': 'Missouri',
    'MT': 'Montana',
    'NE': 'Nebraska',
    'NV': 'Nevada',
    'NH': 'New Hampshire',
    'NJ': 'New Jersey',
    'NM': 'New Mexico',
    'NY': 'New York',
    'NC': 'North Carolina',
    'ND': 'North Dakota',
    'OH': 'Ohio',
    'OK': 'Oklahoma',
    'OR': 'Oregon',
    'PA': 'Pennsylvania',
    'RI': 'Rhode Island',
    'SC': 'South Carolina',
    'SD': 'South Dakota',
    'TN': 'Tennessee',
    'TX': 'Texas',
    'UT': 'Utah',
    'VT': 'Vermont',
    'VA': 'Virginia',
    'WA': 'Washington',
    'WV': 'West Virginia',
    'WI': 'Wisconsin',
    'WY': 'Wyoming',
    'INTL': 'Outside US / Foreign',
  };

  /// Normalizes a raw state string (e.g. 'wa', 'Washington', 'WA - Washington', 'California')
  /// to its standard 2-letter code (or 'INTL' / trimmed uppercase fallback).
  static String? normalizeCode(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final upper = trimmed.toUpperCase();
    if (stateMap.containsKey(upper)) return upper;

    // Check if it matches "WA - Washington" format
    if (upper.contains(' - ')) {
      final prefix = upper.split(' - ').first.trim();
      if (stateMap.containsKey(prefix)) return prefix;
    }

    // Match by full state name
    final byName = stateMap.entries.firstWhereOrNull(
      (e) => e.value.toUpperCase() == upper,
    );
    if (byName != null) return byName.key;

    return upper;
  }

  /// Display label for a state code (e.g. 'WA - Washington').
  static String displayLabel(String code) {
    final name = stateMap[code];
    if (name == null) return code;
    if (code == 'INTL') return 'Outside US / Foreign (INTL)';
    return '$code - $name';
  }

  /// Checks whether two state strings refer to the same state (defaults to comparing against 'WA').
  static bool isSameState(String? clientState, {String? businessState = 'WA'}) {
    final normClient = normalizeCode(clientState);
    final normBiz = normalizeCode(businessState) ?? 'WA';
    if (normClient == null) return true; // Default to in-state if not specified
    return normClient == normBiz;
  }

  /// Returns true if the client has an explicit state set that is outside [businessState] (default 'WA').
  static bool isOutOfState(String? clientState, {String? businessState = 'WA'}) {
    final normClient = normalizeCode(clientState);
    if (normClient == null) return false;
    final normBiz = normalizeCode(businessState) ?? 'WA';
    return normClient != normBiz;
  }
}

