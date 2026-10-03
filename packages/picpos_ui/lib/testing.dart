/// Test helpers: load the bundled fonts so widget/golden tests render real
/// Arabic glyphs instead of the test font's boxes.
library;

import 'package:flutter/services.dart';

const _fonts = <String, List<String>>{
  'packages/picpos_ui/Cairo': [
    'Cairo-Regular.ttf',
    'Cairo-SemiBold.ttf',
    'Cairo-Bold.ttf',
    'Cairo-ExtraBold.ttf',
  ],
  'packages/picpos_ui/NotoNaskhArabic': ['NotoNaskhArabic-Regular.ttf', 'NotoNaskhArabic-Bold.ttf'],
};

bool _loaded = false;

/// Registers Cairo and Noto Naskh Arabic from this package's assets. Call
/// from `setUpAll` after `TestWidgetsFlutterBinding.ensureInitialized()`.
Future<void> loadPicPosFonts() async {
  if (_loaded) return;
  for (final e in _fonts.entries) {
    final loader = FontLoader(e.key);
    for (final f in e.value) {
      loader.addFont(rootBundle.load('packages/picpos_ui/fonts/$f'));
    }
    await loader.load();
  }
  _loaded = true;
}
