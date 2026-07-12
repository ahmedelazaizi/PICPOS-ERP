import 'dart:io';
import 'package:flutter/foundation.dart';

/// Touch Keyboard Service for Windows touch devices
/// Opens the on-screen keyboard automatically when a text field is focused
class TouchKeyboardService {
  static final TouchKeyboardService _instance =
      TouchKeyboardService._internal();
  static TouchKeyboardService get instance => _instance;
  TouchKeyboardService._internal();

  /// Whether auto-open is enabled
  bool autoOpenEnabled = true;

  /// Track if keyboard is already open to avoid multiple calls
  bool _isKeyboardOpen = false;

  /// Opens the on-screen keyboard for touch devices
  /// Call this when a TextField receives focus
  void openKeyboard() {
    if (!autoOpenEnabled) return;
    if (_isKeyboardOpen) return;
    if (!Platform.isWindows) return;

    _isKeyboardOpen = true;

    try {
      // Try TabTip first (better for touch screens)
      Process.run('cmd', [
        '/c',
        'start',
        '',
        r'C:\Program Files\Common Files\microsoft shared\ink\TabTip.exe',
      ]);
    } catch (e) {
      // Fallback to osk.exe
      try {
        Process.run('cmd', ['/c', 'start', 'osk.exe']);
      } catch (_) {
        debugPrint('Failed to open on-screen keyboard');
      }
    }

    // Reset flag after a delay to allow reopening
    Future.delayed(const Duration(milliseconds: 500), () {
      _isKeyboardOpen = false;
    });
  }

  /// Closes the on-screen keyboard (optional)
  void closeKeyboard() {
    if (!Platform.isWindows) return;
    _isKeyboardOpen = false;
    // Windows manages closing automatically when focus is lost
  }
}
