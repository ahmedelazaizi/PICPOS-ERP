import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_osk.dart';
import '../../../data/database/database.dart';
import '../providers/pos_controller.dart';

/// Barcode input for POS — handles USB/Bluetooth barcode scanners.
///
/// USB barcode scanners behave like fast keyboards: they type the barcode
/// characters one-by-one and finish with an Enter key. This widget:
/// 1. Buffers all input until Enter (onSubmitted) is pressed
/// 2. Only triggers the search callback on Enter — never on partial input
/// 3. Clears the field after submit so it's ready for the next scan
class PosBarcodeInput extends ConsumerStatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Function(String) onSubmitted;

  const PosBarcodeInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
  });

  @override
  ConsumerState<PosBarcodeInput> createState() => _PosBarcodeInputState();
}

class _PosBarcodeInputState extends ConsumerState<PosBarcodeInput> {
  // Processing lock to prevent double-fires. Guarded by a timestamp (below)
  // so it can never wedge `true` forever and silently swallow every scan.
  bool _isProcessing = false;
  int _lastSubmitMs = 0;

  // Some scanners emit their "end of scan" terminator as a CHARACTER (CR/LF/
  // Tab) that lands in the field instead of triggering onSubmitted. Detect it
  // in onChanged and submit (Spec 136 ISS-6).
  static final RegExp _terminator = RegExp(r'[\r\n\t]');

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    // Only rebuild if it affects the clear icon visibility
    if (mounted) setState(() {});
  }

  /// Sanitize and normalize the barcode input
  String _sanitizeBarcode(String input) {
    if (input.isEmpty) return input;

    // 1. Clean invisible/control characters, scanner-specific chars, and whitespace
    String cleaned = input
        .replaceAll('\r', '')
        .replaceAll('\n', '')
        .replaceAll('\x00', '')
        .replaceAll('\x1D', '')   // GS (Group Separator) — common in barcode scanners
        .replaceAll('\x1E', '')   // RS (Record Separator)
        .replaceAll('\x1F', '')   // US (Unit Separator)
        .replaceAll('\uFEFF', '') // BOM (Byte Order Mark)
        .replaceAll('\u200E', '') // LRM (Left-to-Right Mark)
        .replaceAll('\u200F', '') // RLM (Right-to-Left Mark)
        .replaceAll('\u200B', '') // ZWSP (Zero-Width Space)
        .replaceAll('\u200C', '') // ZWNJ
        .replaceAll('\u200D', '') // ZWJ
        .replaceAll(RegExp(r'\s+'), '') // All whitespace
        .trim();

    // 2. Normalize Arabic Indic numbers to English numbers
    const arabicNumbers = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    for (int i = 0; i < 10; i++) {
      cleaned = cleaned.replaceAll(arabicNumbers[i], i.toString());
    }

    // 3. Normalize Persian numbers to English numbers
    const persianNumbers = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
    for (int i = 0; i < 10; i++) {
      cleaned = cleaned.replaceAll(persianNumbers[i], i.toString());
    }

    return cleaned;
  }

  /// onChanged — submits when a terminator character (CR/LF/Tab) is embedded
  /// in the text, for scanners that send their end-of-scan terminator as a
  /// character that lands in the field instead of triggering onSubmitted.
  ///
  /// NOTE (Spec 136 review): an earlier draft also auto-submitted after an
  /// idle gap in supermarket mode (for scanners with no terminator at all).
  /// That was removed — the review found it could (a) fire mid manual typing
  /// and submit a partial code, and (b) open a double-submit timing seam with
  /// the processing lock. The confirmed field bug (field not clearing after a
  /// successful add) is fixed by `_clearField`, independent of any onChanged
  /// auto-submit. Manual typing and normal scans submit on Enter as before.
  void _onChanged(String val) {
    if (_terminator.hasMatch(val)) {
      _submitBarcode(val);
    }
  }

  /// Bulletproof clear: empties the field NOW and again after the frame.
  ///
  /// Spec 136 ISS-6 — a synchronous `controller.clear()` inside `onSubmitted`
  /// is overwritten by TextField's input pipeline reasserting the submitted
  /// value in the SAME frame, so the scanned barcode stays "stuck" in the
  /// field even though the product was already added to the cart. Clearing
  /// again in a post-frame callback runs AFTER that restoration, guaranteeing
  /// the field is empty (and the scanner still focused) for the next scan.
  void _clearField() {
    widget.controller.value = TextEditingValue.empty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.controller.text.isNotEmpty) {
        widget.controller.value = TextEditingValue.empty;
      }
      if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
    });
  }

  /// Submit the barcode — on Enter or an embedded terminator character.
  void _submitBarcode(String barcode) {
    final text = _sanitizeBarcode(barcode);

    // Clear the UI field (now + post-frame) so it's ready for the next scan
    // even if this input was bad/empty.
    _clearField();

    if (text.isEmpty) return;

    // Time-based debounce. Pre-fix the lock was a bare boolean reset only when
    // `mounted` — if the widget rebuilt mid-delay the lock leaked `true` and
    // every later scan was swallowed. Letting a submit through once 150ms has
    // elapsed since the last one makes the lock self-healing.
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (_isProcessing && (nowMs - _lastSubmitMs) < 150) return;
    _isProcessing = true;
    _lastSubmitMs = nowMs;

    unawaited(DiagnosticLogger.log(
      'BARCODE-INPUT',
      'submit len=${text.length}',
    ).catchError((_) {}));
    debugPrint('[BarcodeInput] Submit: "$text" (${text.length} chars)');

    // Fire the search callback
    widget.onSubmitted(text);

    // Release lock after short delay to prevent double-scans from fast hardware.
    Future.delayed(const Duration(milliseconds: 150), () {
      _isProcessing = false;
    });
  }

  /// Show the custom on-screen keyboard
  void _showTouchKeyboard(BuildContext context) {
    AppOSK.show(
      context,
      controller: widget.controller,
      isNumeric: false,
      onSubmitted: () => _submitBarcode(widget.controller.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final posState = ref.watch(posControllerProvider);
    final isSupermarket = posState.industryMode == IndustryMode.supermarket;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: AppColors.border.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                decoration: InputDecoration(
                  hintText: isSupermarket
                      ? 'امسح الباركود الآن...'
                      : 'امسح الباركود أو اكتب الرقم واضغط Enter...',
                  prefixIcon: const Icon(
                    PhosphorIconsBold.barcode,
                    color: AppColors.primary,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.controller.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(PhosphorIconsBold.xCircle),
                          onPressed: () {
                            widget.controller.clear();
                            // Force clear the internal text as well
                            _isProcessing = false;
                            setState(() {});
                          },
                        ),
                      // Keyboard icon for touch manual trigger
                      IconButton(
                        icon: const Icon(PhosphorIconsBold.keyboard),
                        onPressed: () => _showTouchKeyboard(context),
                      ),
                      if (widget.controller.text.isEmpty)
                        _buildScannerPulse(),
                    ],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
                // Primary path: fire on Enter — when the scanner finishes
                // sending the barcode, or the user types and presses Enter.
                onSubmitted: (val) {
                  _submitBarcode(val);
                },
                // Fallback path (Spec 136 ISS-6): catch scanners that embed a
                // terminator char or send no Enter suffix at all.
                onChanged: _onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerPulse() {
    return const Padding(
      padding: EdgeInsets.all(12.0),
      child: Tooltip(
        message: 'الماسح الضوئي نشط — امسح الباركود أو اكتب واضغط Enter',
        child: Icon(PhosphorIconsBold.scan, color: AppColors.success, size: 20),
      ),
    );
  }
}
