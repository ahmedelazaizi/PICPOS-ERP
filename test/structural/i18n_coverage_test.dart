import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../tool/i18n/extract_catalog.dart';

void main() {
  test('every tr key in lib exists in en.json', () {
    final sources = <String, String>{};
    final lib = Directory('lib');
    for (final entity in lib.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        sources[entity.path.replaceAll('\\', '/')] = entity.readAsStringSync();
      }
    }

    final usedKeys = extractCatalogFromSources(sources).keys.toSet();
    final catalog = jsonDecode(
      File('assets/i18n/en.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final missing = usedKeys.where((key) => !catalog.containsKey(key)).toList()
      ..sort();

    expect(missing, isEmpty, reason: 'Missing i18n keys: ${missing.join(', ')}');
  });
}
