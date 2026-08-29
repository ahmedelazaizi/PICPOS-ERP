import 'dart:async';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../services/scale_service.dart';
import '../../picpos_shell/picpos_surface.dart';

/// Scale input widget that displays real-time weight from connected scale
/// Shows green when stable, red when unstable
class PosScaleInput extends StatefulWidget {
  final Function(double weight)? onWeightChanged;

  const PosScaleInput({super.key, this.onWeightChanged});

  @override
  State<PosScaleInput> createState() => _PosScaleInputState();
}

class _PosScaleInputState extends State<PosScaleInput> {
  double _currentWeight = 0.0;
  bool _isConnected = false;
  bool _isStable = false;
  StreamSubscription<double>? _weightSubscription;
  StreamSubscription<bool>? _stabilitySubscription;
  Timer? _connectionCheckTimer;

  @override
  void initState() {
    super.initState();
    _checkConnectionAndSubscribe();
    // Periodically check if scale connection state changed
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final connected = ScaleService.instance.isConnected;
      if (connected != _isConnected) {
        setState(() => _isConnected = connected);
        if (connected) {
          _subscribeToWeight();
          _subscribeToStability();
        } else {
          _weightSubscription?.cancel();
          _weightSubscription = null;
          _stabilitySubscription?.cancel();
          _stabilitySubscription = null;
        }
      }
    });
  }

  void _checkConnectionAndSubscribe() {
    _isConnected = ScaleService.instance.isConnected;
    _isStable = ScaleService.instance.isStable;
    if (_isConnected) {
      _subscribeToWeight();
      _subscribeToStability();
    }
  }

  void _subscribeToWeight() {
    _weightSubscription?.cancel();
    final stream = ScaleService.instance.weightStream;
    if (stream != null) {
      _weightSubscription = stream.listen((weight) {
        if (!mounted) return;
        if (weight != _currentWeight) {
          setState(() => _currentWeight = weight);
          widget.onWeightChanged?.call(weight);
        }
      });
    }
  }

  void _subscribeToStability() {
    _stabilitySubscription?.cancel();
    final stream = ScaleService.instance.stabilityStream;
    if (stream != null) {
      _stabilitySubscription = stream.listen((stable) {
        if (!mounted) return;
        if (stable != _isStable) {
          setState(() => _isStable = stable);
        }
      });
    }
  }

  @override
  void dispose() {
    _weightSubscription?.cancel();
    _stabilitySubscription?.cancel();
    _connectionCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only show if scale is connected
    if (!_isConnected) {
      return const SizedBox.shrink();
    }

    final statusColor = _isStable ? AppColors.success : AppColors.error;
    final statusText = _isStable ? 'ثابت' : 'غير ثابت';
    final statusIcon = _isStable
        ? PhosphorIconsBold.checkCircle
        : PhosphorIconsBold.warning;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: statusColor.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Scale icon
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Icon(
              PhosphorIconsBold.scales,
              key: ValueKey(_isStable),
              color: statusColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),

          // Label
          const Text(
            'الوزن:',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
          const SizedBox(width: 8),

          // Weight display
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: context.picposCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: statusColor, width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                      fontFamily: 'monospace',
                    ),
                    child: Text(_currentWeight.toStringAsFixed(3)),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'كجم',
                    style: TextStyle(fontSize: 14, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          // Status indicator
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    statusIcon,
                    key: ValueKey(_isStable),
                    size: 14,
                    color: statusColor,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    fontSize: 12,
                    color: statusColor,
                    fontWeight: FontWeight.w500,
                  ),
                  child: Text(statusText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
