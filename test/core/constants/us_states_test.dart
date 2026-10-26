import 'package:flutter_test/flutter_test.dart';
import 'package:code_ledger/core/constants/us_states.dart';

void main() {
  group('UsStates', () {
    test('normalizeCode handles 2-letter codes, case-insensitively', () {
      expect(UsStates.normalizeCode('wa'), 'WA');
      expect(UsStates.normalizeCode('WA'), 'WA');
      expect(UsStates.normalizeCode('ca'), 'CA');
      expect(UsStates.normalizeCode('CA'), 'CA');
      expect(UsStates.normalizeCode('intl'), 'INTL');
      expect(UsStates.normalizeCode('INTL'), 'INTL');
    });

    test('normalizeCode matches full state names and prefixes', () {
      expect(UsStates.normalizeCode('Washington'), 'WA');
      expect(UsStates.normalizeCode('WASHINGTON'), 'WA');
      expect(UsStates.normalizeCode('california'), 'CA');
      expect(UsStates.normalizeCode('WA - Washington'), 'WA');
      expect(UsStates.normalizeCode('CA - California'), 'CA');
      expect(UsStates.normalizeCode('Foreign / Outside US'), 'INTL');
    });

    test('normalizeCode returns null for empty or null', () {
      expect(UsStates.normalizeCode(null), isNull);
      expect(UsStates.normalizeCode(''), isNull);
      expect(UsStates.normalizeCode('   '), isNull);
    });

    test('displayLabel formats state name or falls back', () {
      expect(UsStates.displayLabel('WA'), 'WA - Washington');
      expect(UsStates.displayLabel('CA'), 'CA - California');
      expect(UsStates.displayLabel('INTL'), 'INTL - Outside US / Foreign');
      expect(UsStates.displayLabel('XYZ'), 'XYZ');
    });

    test('isSameState compares states correctly against business state', () {
      expect(UsStates.isSameState('WA', businessState: 'WA'), isTrue);
      expect(UsStates.isSameState('wa', businessState: 'WA'), isTrue);
      expect(UsStates.isSameState('Washington', businessState: 'WA'), isTrue);
      expect(UsStates.isSameState('CA', businessState: 'WA'), isFalse);
      expect(UsStates.isSameState(null, businessState: 'WA'), isFalse);
    });

    test('isOutOfState identifies out-of-state and foreign clients', () {
      expect(UsStates.isOutOfState('CA', businessState: 'WA'), isTrue);
      expect(UsStates.isOutOfState('California', businessState: 'WA'), isTrue);
      expect(UsStates.isOutOfState('INTL', businessState: 'WA'), isTrue);
      expect(UsStates.isOutOfState('WA', businessState: 'WA'), isFalse);
      expect(UsStates.isOutOfState('Washington', businessState: 'WA'), isFalse);
      expect(UsStates.isOutOfState(null, businessState: 'WA'), isFalse);
    });
  });
}

