import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import 'dart:ui' as ui;

class SecurityScreenGate extends ConsumerStatefulWidget {
  final String settingKey;
  final String title;
  final Widget child;

  const SecurityScreenGate({
    super.key,
    required this.settingKey,
    required this.title,
    required this.child,
  });

  @override
  ConsumerState<SecurityScreenGate> createState() => _SecurityScreenGateState();
}

class _SecurityScreenGateState extends ConsumerState<SecurityScreenGate> {
  bool _isUnlocked = false;
  bool _isLoading = true;
  String? _gatePassword;

  @override
  void initState() {
    super.initState();
    _checkGate();
  }

  Future<void> _checkGate() async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final pw = await settingsRepo.getSetting(widget.settingKey);
    
    if (mounted) {
      if (pw == null || pw.isEmpty) {
        setState(() {
          _isUnlocked = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _gatePassword = pw;
          _isLoading = false;
        });
      }
    }
  }

  void _showPasswordDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.lockKey, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('🔒 حماية ${widget.title}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'هذا القسم محمي بكلمة مرور. يرجى إدخالها للمتابعة.',
                style: TextStyle(fontSize: 14, color: AppColors.textMuted),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(PhosphorIconsBold.key),
                ),
                onSubmitted: (val) {
                  if (val == _gatePassword) {
                    Navigator.pop(ctx);
                    setState(() => _isUnlocked = true);
                  } else {
                    AppToast.show(ctx, 'كلمة المرور غير صحيحة', type: ToastType.error);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                if (controller.text == _gatePassword) {
                  Navigator.pop(ctx);
                  setState(() => _isUnlocked = true);
                } else {
                  AppToast.show(ctx, 'كلمة المرور غير صحيحة', type: ToastType.error);
                }
              },
              child: const Text('دخول'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_isUnlocked) {
      return widget.child;
    }

    // Lock screen UI
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  PhosphorIconsBold.lockKey,
                  size: 64,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'قسم ${widget.title} محمي',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'يرجى إدخال كلمة المرور الخاصة بهذا القسم للوصول إليه.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _showPasswordDialog,
                  icon: const Icon(PhosphorIconsBold.key),
                  label: const Text('إدخال كلمة المرور'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
