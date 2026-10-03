import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_ui/testing.dart';

/// The two review form factors of ARCHITECTURE-M §4.1.
const kPhone = Size(411, 891);
const kTablet = Size(1280, 800);
const kSizes = {'phone': kPhone, 'tablet': kTablet};

/// Cairo, Noto Naskh and Material Icons, so text and icons render for real.
Future<void> loadTestFonts() async {
  await loadPicPosFonts();
  final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

void setSurface(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}
