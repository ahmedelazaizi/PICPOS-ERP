import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/presentation/screens/settings/work_holidays_screen.dart';

import '_support/screen_smoke.dart';

void main() {
  testWidgets('الشاشةُ تُرسَم بلا استثناءٍ ولا فيضان',
      timeout: const Timeout(Duration(seconds: 45)), (tester) async {
    final error =
        await pumpScreen(tester, () => const WorkHolidaysScreen());
    expect(error, isNull);
  });
}
