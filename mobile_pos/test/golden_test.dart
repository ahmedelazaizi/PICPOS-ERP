// Golden screenshots of the main screen: AR/EN × light/dark × phone/tablet
// (ARCHITECTURE-M §4.1). Real fonts are loaded so Arabic renders. Goldens
// are platform-sensitive: they were generated on the Windows dev machine;
// regenerate deliberately with `flutter test --update-goldens test/golden_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_pos/app.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'support.dart';

void main() {
  setUpAll(loadTestFonts);

  for (final lang in ['ar', 'en']) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final MapEntry(key: sizeName, value: size) in kSizes.entries) {
        testWidgets('golden sale $lang ${mode.name} $sizeName', (tester) async {
          setSurface(tester, size);
          await tester.pumpWidget(PicPosPosApp(
            settings: PicPosAppSettings(locale: Locale(lang), themeMode: mode),
            startInShell: true,
          ));
          await tester.pumpAndSettle();
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile('goldens/sale_${lang}_${mode.name}_$sizeName.png'),
          );
        });
      }
    }
  }
}
