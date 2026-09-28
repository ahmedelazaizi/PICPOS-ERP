import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Cairo font asset is declared and mapped to its weight', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final files = Directory('assets/fonts')
        .listSync()
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .where((name) => name.startsWith('Cairo-') && name.endsWith('.ttf'))
        .toList()
      ..sort();

    expect(files, isNotEmpty);
    for (final file in files) {
      expect(pubspec, contains('- assets/fonts/$file'));
      if (file == 'Cairo-Regular.ttf') continue;
      final weight = switch (file) {
        'Cairo-Light.ttf' => 300,
        'Cairo-Medium.ttf' => 500,
        'Cairo-SemiBold.ttf' => 600,
        'Cairo-Bold.ttf' => 700,
        'Cairo-ExtraBold.ttf' => 800,
        'Cairo-Black.ttf' => 900,
        _ => null,
      };
      if (weight != null) {
        expect(pubspec, contains('weight: $weight'));
      }
    }
  });
}
