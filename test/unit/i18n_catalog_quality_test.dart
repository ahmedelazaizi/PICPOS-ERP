import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _arabicLetters = RegExp(
  r'[\u0621-\u063A\u0641-\u064A\u066E-\u06D3\u06FA-\u06FF'
  r'\u0750-\u077F\u08A0-\u08FF\uFB50-\uFDFF\uFE70-\uFEFF]',
);
final _placeholder = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

/// Key/value pairs that must remain Arabic in the English catalog.
/// Keep this synchronized with docs/i18n/catalog_arabic_allowlist.md.
const _documentedArabicValueAllowlist = <String, String>{
  '[أإآ]': '[أإآ]',
  'ء': 'ء',
  'ؤ': 'ؤ',
  'ئ': 'ئ',
  'ا': 'ا',
  'ب': 'ب',
  'ة': 'ة',
  'ت': 'ت',
  'ث': 'ث',
  'ج': 'ج',
  'ح': 'ح',
  'خ': 'خ',
  'د': 'د',
  'ذ': 'ذ',
  'ر': 'ر',
  'ز': 'ز',
  'س': 'س',
  'ش': 'ش',
  'ص': 'ص',
  'ض': 'ض',
};

Map<String, int> _placeholders(String value) {
  final counts = <String, int>{};
  for (final match in _placeholder.allMatches(value)) {
    final name = match.group(1)!;
    counts[name] = (counts[name] ?? 0) + 1;
  }
  return counts;
}

bool _sameCounts(Map<String, int> left, Map<String, int> right) =>
    left.length == right.length &&
    left.entries.every((entry) => right[entry.key] == entry.value);

void main() {
  test('English catalog values are complete and preserve placeholders', () {
    final decoded = jsonDecode(
      File('assets/i18n/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final defects = <String>[];

    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is! String) {
        defects.add('${entry.key}: value is not a string');
        continue;
      }
      if (value.trim().isEmpty) {
        defects.add('${entry.key}: English value is empty');
      }
      if (_arabicLetters.hasMatch(value) &&
          _documentedArabicValueAllowlist[entry.key] != value) {
        defects.add('${entry.key}: English value contains Arabic letters: $value');
      }
      final keyPlaceholders = _placeholders(entry.key);
      final valuePlaceholders = _placeholders(value);
      if (!_sameCounts(keyPlaceholders, valuePlaceholders)) {
        defects.add(
          '${entry.key}: placeholders $keyPlaceholders != $valuePlaceholders',
        );
      }
    }

    for (final exception in _documentedArabicValueAllowlist.entries) {
      if (decoded[exception.key] != exception.value) {
        defects.add('${exception.key}: documented exception is missing or changed');
      }
    }

    expect(defects, isEmpty, reason: defects.join('\n'));
  });
}
