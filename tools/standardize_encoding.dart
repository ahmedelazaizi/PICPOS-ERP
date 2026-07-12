// ignore_for_file: avoid_print

import 'dart:io';

void main() async {
  final libDir = Directory('lib');
  if (!await libDir.exists()) {
    print('lib directory not found');
    return;
  }

  print('Starting standardization to UTF-8 with BOM...');
  int count = 0;
  int fixed = 0;

  await for (final entity in libDir.list(recursive: true, followLinks: false)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      count++;
      final bytes = await entity.readAsBytes();
      
      // Check for UTF-8 BOM: 0xEF, 0xBB, 0xBF
      final hasBom = bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;

      if (!hasBom) {
        final newBytes = [0xEF, 0xBB, 0xBF, ...bytes];
        await entity.writeAsBytes(newBytes);
        fixed++;
        print('Fixed: ${entity.path}');
      }
    }
  }

  print('Finished.');
  print('Total .dart files: $count');
  print('Files updated with BOM: $fixed');
}
