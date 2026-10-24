/// Unified scan events (plan 2026-10-23, ADR-W8): camera, keyboard-wedge,
/// hardware intent and manual entry all become a [ScanEvent]; [ScanDeduper]
/// drops the echo a scanner can produce (camera frame + wedge, double trigger).
library;

import 'scanner_input.dart';

enum ScanSource { camera, wedge, intent, manual }

class ScanEvent {
  const ScanEvent({required this.value, required this.source, required this.at, this.symbology});

  /// Already normalised (CR/LF/TAB, AIM prefix, spaces removed).
  final String value;
  final ScanSource source;
  final DateTime at;
  final String? symbology;

  /// Normalises [raw]; returns null for an empty read.
  static ScanEvent? from(String raw, ScanSource source, {DateTime? at, String? symbology}) {
    final v = normalizeScan(raw);
    return v.isEmpty ? null : ScanEvent(value: v, source: source, at: at ?? DateTime.now(), symbology: symbology);
  }
}

/// Accepts a value once per [window]; the same value after the window, or a
/// different value, is accepted.
class ScanDeduper {
  ScanDeduper({this.window = const Duration(milliseconds: 800)});
  final Duration window;
  String? _lastValue;
  DateTime? _lastAt;

  bool accept(ScanEvent e) {
    final sameRecent = _lastValue == e.value && _lastAt != null && e.at.difference(_lastAt!) < window;
    if (sameRecent) return false;
    _lastValue = e.value;
    _lastAt = e.at;
    return true;
  }
}
