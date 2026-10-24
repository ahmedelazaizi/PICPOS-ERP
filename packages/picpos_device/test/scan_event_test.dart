import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_device/picpos_device.dart';

void main() {
  final t0 = DateTime(2026, 1, 1, 8);

  test('from() normalises and drops empty reads', () {
    final e = ScanEvent.from('  6221234567890\r\n', ScanSource.wedge, at: t0)!;
    expect(e.value, '6221234567890');
    expect(e.source, ScanSource.wedge);
    expect(ScanEvent.from('\r\n', ScanSource.camera), isNull);
  });

  test('the same value inside the window is an echo; after it, or a different value, is a scan', () {
    final d = ScanDeduper();
    ScanEvent ev(String v, int ms) => ScanEvent(value: v, source: ScanSource.camera, at: t0.add(Duration(milliseconds: ms)));
    expect(d.accept(ev('A', 0)), isTrue);
    expect(d.accept(ev('A', 300)), isFalse);
    expect(d.accept(ev('B', 350)), isTrue);
    expect(d.accept(ev('B', 1300)), isTrue, reason: 'outside the 800 ms window');
    expect(d.accept(ev('A', 1400)), isTrue);
  });
}
