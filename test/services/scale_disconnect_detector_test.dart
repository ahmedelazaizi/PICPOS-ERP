import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/scale_disconnect_detector.dart';

/// Regression cover for the scale "cable disconnected" verdict.
///
/// The read loop in `scale_service_io.dart` is event-driven: it calls
/// `readBytes(..., timeout: 30ms)` in a tight loop, so a read that returns no
/// bytes is the NORMAL state for any scale that transmits slower than 33 Hz.
/// The old policy counted those empty reads and declared the cable
/// disconnected after 10 of them — i.e. after as little as 300 ms of silence,
/// and the verdict was permanent for the session. Scales that idle between
/// frames, USB-serial latency, or a Windows scheduling stall all tripped it.
///
/// The rule these tests pin down: sustained SILENCE (measured in time) means
/// the link is gone; an empty read on its own means nothing. A genuine I/O
/// exception is separate evidence and keeps its own counter.
void main() {
  final t0 = DateTime(2026, 7, 26, 12, 0, 0);

  group('ScaleDisconnectDetector — empty reads are not disconnections', () {
    test('a scale transmitting every 200ms never trips the detector', () {
      final d = ScaleDisconnectDetector(
        silenceThreshold: const Duration(seconds: 3),
      );
      var now = t0;
      d.onData(now);

      // 30 seconds of a 5 Hz scale: ~6 empty 30ms reads between every frame.
      // The old count-based policy died on the 10th empty read.
      for (var frame = 0; frame < 150; frame++) {
        for (var empty = 0; empty < 6; empty++) {
          now = now.add(const Duration(milliseconds: 30));
          d.onEmptyRead(now);
          expect(d.shouldDisconnect(now), isFalse,
              reason: 'empty read $empty of frame $frame must not disconnect');
        }
        now = now.add(const Duration(milliseconds: 20));
        d.onData(now);
      }
    });

    test('a burst of empty reads inside the threshold does not disconnect', () {
      final d = ScaleDisconnectDetector(
        silenceThreshold: const Duration(seconds: 3),
      );
      var now = t0;
      d.onData(now);

      // 300 empty reads crammed into 100ms — what a non-blocking readBytes
      // produces. Count-based logic disconnects on #10; elapsed time is the
      // only honest signal here.
      for (var i = 0; i < 300; i++) {
        now = now.add(const Duration(microseconds: 333));
        d.onEmptyRead(now);
      }
      expect(d.shouldDisconnect(now), isFalse);
    });
  });

  group('ScaleDisconnectDetector — sustained silence is a disconnection', () {
    test('silence past the threshold disconnects', () {
      final d = ScaleDisconnectDetector(
        silenceThreshold: const Duration(seconds: 3),
      );
      d.onData(t0);

      final justUnder = t0.add(const Duration(milliseconds: 2999));
      d.onEmptyRead(justUnder);
      expect(d.shouldDisconnect(justUnder), isFalse);

      final atThreshold = t0.add(const Duration(seconds: 3));
      d.onEmptyRead(atThreshold);
      expect(d.shouldDisconnect(atThreshold), isTrue);
    });

    test('data arriving resets the silence clock', () {
      final d = ScaleDisconnectDetector(
        silenceThreshold: const Duration(seconds: 3),
      );
      d.onData(t0);

      final almost = t0.add(const Duration(milliseconds: 2900));
      d.onEmptyRead(almost);
      expect(d.shouldDisconnect(almost), isFalse);

      d.onData(almost);
      final laterButFresh = almost.add(const Duration(milliseconds: 2900));
      d.onEmptyRead(laterButFresh);
      expect(d.shouldDisconnect(laterButFresh), isFalse,
          reason: 'the clock restarts from the last byte, not from connect');
    });

    test('silence is measured from the first empty read when no data ever came',
        () {
      final d = ScaleDisconnectDetector(
        silenceThreshold: const Duration(seconds: 3),
      );
      d.onEmptyRead(t0);
      expect(d.shouldDisconnect(t0), isFalse);

      final later = t0.add(const Duration(seconds: 4));
      d.onEmptyRead(later);
      expect(d.shouldDisconnect(later), isTrue);
    });
  });

  group('ScaleDisconnectDetector — I/O errors keep their own counter', () {
    test('consecutive I/O errors disconnect without waiting for the silence '
        'threshold', () {
      final d = ScaleDisconnectDetector(
        silenceThreshold: const Duration(seconds: 3),
        ioErrorThreshold: 10,
      );
      var now = t0;
      d.onData(now);

      for (var i = 0; i < 9; i++) {
        now = now.add(const Duration(milliseconds: 5));
        d.onIoError(now);
        expect(d.shouldDisconnect(now), isFalse, reason: 'error ${i + 1} of 10');
      }
      now = now.add(const Duration(milliseconds: 5));
      d.onIoError(now);
      expect(d.shouldDisconnect(now), isTrue);
    });

    test('a successful read clears the I/O error streak', () {
      final d = ScaleDisconnectDetector(
        silenceThreshold: const Duration(seconds: 3),
        ioErrorThreshold: 10,
      );
      var now = t0;
      d.onData(now);

      for (var i = 0; i < 9; i++) {
        now = now.add(const Duration(milliseconds: 5));
        d.onIoError(now);
      }
      now = now.add(const Duration(milliseconds: 5));
      d.onData(now);

      for (var i = 0; i < 9; i++) {
        now = now.add(const Duration(milliseconds: 5));
        d.onIoError(now);
        expect(d.shouldDisconnect(now), isFalse,
            reason: 'streak restarted after the good read');
      }
    });

    test('empty reads do not feed the I/O error counter', () {
      final d = ScaleDisconnectDetector(
        silenceThreshold: const Duration(seconds: 30),
        ioErrorThreshold: 3,
      );
      var now = t0;
      d.onData(now);

      for (var i = 0; i < 100; i++) {
        now = now.add(const Duration(milliseconds: 1));
        d.onEmptyRead(now);
      }
      expect(d.shouldDisconnect(now), isFalse);
    });
  });

  group('ScaleDisconnectDetector — defaults', () {
    test('the default silence window survives a scale that idles for seconds',
        () {
      // Some scales stop transmitting while the weight is unchanged. The old
      // policy killed the link after ~300ms of that; the default must leave
      // real headroom, because a genuinely pulled cable is caught by the I/O
      // error counter instead.
      final d = ScaleDisconnectDetector();
      d.onData(t0);
      final quiet = t0.add(const Duration(seconds: 5));
      d.onEmptyRead(quiet);
      expect(d.shouldDisconnect(quiet), isFalse);
    });

    test('the default silence window still ends', () {
      final d = ScaleDisconnectDetector();
      d.onData(t0);
      final gone = t0.add(const Duration(seconds: 11));
      d.onEmptyRead(gone);
      expect(d.shouldDisconnect(gone), isTrue);
    });
  });

  group('ScaleDisconnectDetector — reset', () {
    test('reset clears both silence and error state', () {
      final d = ScaleDisconnectDetector(
        silenceThreshold: const Duration(seconds: 3),
        ioErrorThreshold: 2,
      );
      var now = t0;
      d.onIoError(now);
      d.onIoError(now);
      expect(d.shouldDisconnect(now), isTrue);

      d.reset(now);
      expect(d.shouldDisconnect(now), isFalse);

      now = now.add(const Duration(seconds: 4));
      d.onEmptyRead(now);
      expect(d.shouldDisconnect(now), isTrue,
          reason: 'the silence clock restarts at reset time');
    });
  });
}
