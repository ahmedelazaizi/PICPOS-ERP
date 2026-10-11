import 'dart:io';

/// Step files carved out of lib/data/database/migrations/epoch_3.dart (pure
/// move, no behaviour change). Source-grep tests that used to read epoch_3.dart
/// alone read the merged text through [readEpoch3Source], so every assertion
/// keeps searching the same code.
const String kEpoch3MainPath = 'lib/data/database/migrations/epoch_3.dart';

const List<String> kEpoch3SplitParts = <String>[
  'lib/data/database/migrations/epoch_3_v081_v093.dart',
  'lib/data/database/migrations/epoch_3_v094_v118.dart',
  'lib/data/database/migrations/epoch_3_v119_v133.dart',
  'lib/data/database/migrations/epoch_3_v134_v147.dart',
  'lib/data/database/migrations/epoch_3_v148_v156.dart',
  'lib/data/database/migrations/epoch_3_v157_v166.dart',
  'lib/data/database/migrations/epoch_3_v167_v173.dart',
  'lib/data/database/migrations/epoch_3_v174_v195.dart',
];

/// epoch_3.dart plus the parts split out of it, joined by newlines.
String readEpoch3Source() => [
      for (final p in <String>[kEpoch3MainPath, ...kEpoch3SplitParts])
        File(p).readAsStringSync(),
    ].join('\n');