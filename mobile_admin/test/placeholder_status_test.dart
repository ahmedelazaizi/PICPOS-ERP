import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_admin/app.dart';
import 'package:picpos_ui/picpos_ui.dart';

import 'support.dart';

void main() {
  setUpAll(loadTestFonts);

  for (final language in ['ar', 'en']) {
    for (final (destination, name) in [
      (2, 'reports'),
      (3, 'operations'),
      (4, 'notifications'),
    ]) {
      testWidgets(
        '$language $name placeholder shows planned state, not offline',
        (tester) async {
          setSurface(tester, kPhone);
          await tester.pumpWidget(
            PicPosAdminApp(
              settings: PicPosAppSettings(locale: Locale(language)),
              startInShell: true,
              initialDestination: destination,
            ),
          );
          await tester.pumpAndSettle();

          expect(
            find.text(language == 'ar' ? 'قيد الإنشاء' : 'Coming soon'),
            findsOneWidget,
          );
          expect(
            find.text(language == 'ar' ? 'غير متصل' : 'Offline'),
            findsNothing,
          );
        },
      );
    }
  }
}
