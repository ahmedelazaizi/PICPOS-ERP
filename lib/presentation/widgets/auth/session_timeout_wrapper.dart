import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/config/business_profile_provider.dart';
import '../../../data/providers/providers.dart';

/// Wraps a widget (usually the POS screen) and detects inactivity.
/// If inactive for [timeoutMinutes], it displays a lock screen overlay
/// requiring the current user's password/PIN or an admin's to unlock.
class SessionTimeoutWrapper extends ConsumerStatefulWidget {
  final Widget child;

  const SessionTimeoutWrapper({
    super.key,
    required this.child,
  });

  @override
  ConsumerState<SessionTimeoutWrapper> createState() => _SessionTimeoutWrapperState();
}

class _SessionTimeoutWrapperState extends ConsumerState<SessionTimeoutWrapper> {
  Timer? _authTimer;
  bool _isLocked = false;
  
  // Unlock logic
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;
  
  // Card swipe detection
  final _cardBuffer = StringBuffer();
  DateTime _lastKeyTime = DateTime.now();
  static const _msrMaxKeyInterval = Duration(milliseconds: 50);

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  bool _getIsEnabled() {
    return ref.read(posSessionTimeoutEnabledProvider).value ?? true;
  }

  int _getTimeoutMinutes() {
    return ref.read(posSessionTimeoutMinutesProvider).value ?? 5;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Re-evaluate on rebuilds if providers change (using listen in build is better, but here we can just restart timer if needed).
  }

  @override
  void dispose() {
    _authTimer?.cancel();
    _passwordController.dispose();
    super.dispose();
  }

  void _userInteracted() {
    if (!_getIsEnabled() || _isLocked) return;
    _startTimer();
  }

  void _startTimer() {
    _authTimer?.cancel();
    if (!_getIsEnabled()) return;
    
    _authTimer = Timer(Duration(minutes: _getTimeoutMinutes()), () {
      if (mounted && !_isLocked) {
        setState(() {
          _isLocked = true;
          _passwordController.clear();
          _errorMessage = null;
        });
      }
    });
  }

  Future<void> _unlock() async {
    final input = _passwordController.text.trim();
    if (input.isEmpty) {
      setState(() => _errorMessage = 'يرجى إدخال كلمة المرور');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUserInfo = ref.read(authProvider).user;
      final authRepo = ref.read(authRepositoryProvider);
      
      // Check if it's the master admin password first
      if (await ref.read(adminPasswordServiceProvider).verify(input)) {
        _completeUnlock();
        return;
      }

      // Try authenticating by password or card
      final user = await authRepo.authenticateByPasswordOrCard(input);
      if (user != null) {
        // Can be either the same user, or an admin/manager overriding the lock
        final isSameUser = user.user.id == currentUserInfo?.id;
        final roleName = user.role?.name.toLowerCase() ?? '';
        final isSystemRole = user.role?.isSystemRole ?? false;
        final isAdminOrManager = isSystemRole || 
                                roleName.contains('admin') || 
                                roleName.contains('مدير') || 
                                roleName.contains('manager');

        if (isSameUser || isAdminOrManager) {
          _completeUnlock();
        } else {
          setState(() => _errorMessage = 'كلمة المرور غير صحيحة أو لا تملك الصلاحية');
        }
      } else {
        setState(() => _errorMessage = 'كلمة المرور غير صحيحة');
      }
    } catch (e) {
      setState(() => _errorMessage = 'حدث خطأ: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _onCardSwipe(String cardCode) async {
    if (cardCode.isEmpty || _isLoading) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final currentUserInfo = ref.read(authProvider).user;
      final authRepo = ref.read(authRepositoryProvider);
      final user = await authRepo.authenticateByCardCode(cardCode);
      
      if (user != null) {
        final isSameUser = user.user.id == currentUserInfo?.id;
        final roleName = user.role?.name.toLowerCase() ?? '';
        final isSystemRole = user.role?.isSystemRole ?? false;
        final isAdminOrManager = isSystemRole || 
                                roleName.contains('admin') || 
                                roleName.contains('مدير') || 
                                roleName.contains('manager');

        if (isSameUser || isAdminOrManager) {
          _completeUnlock();
        } else {
          setState(() => _errorMessage = 'البطاقة لا تملك صلاحية فك القفل');
        }
      } else {
        setState(() => _errorMessage = 'بطاقة غير معرّفة في النظام');
      }
    } catch (e) {
      setState(() => _errorMessage = 'حدث خطأ: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _completeUnlock() {
    setState(() {
      _isLocked = false;
      _passwordController.clear();
      _errorMessage = null;
    });
    _startTimer();
  }

  void _logout() {
    _authTimer?.cancel();
    ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    // Watch settings to react to changes
    final isEnabled = ref.watch(posSessionTimeoutEnabledProvider).value ?? true;
  // ignore: unused_local_variable
    final timeoutMinutes = ref.watch(posSessionTimeoutMinutesProvider).value ?? 5;

    // If disabled, remove lock if active
    if (!isEnabled && _isLocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _isLocked = false);
          _authTimer?.cancel();
        }
      });
    }

    return Stack(
      children: [
        // Main content wrapper
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _userInteracted(),
          onPointerMove: (_) => _userInteracted(),
          onPointerUp: (_) => _userInteracted(),
          child: widget.child,
        ),
        
        // Lock screen overlay
        if (_isLocked) _buildLockOverlay(),
      ],
    );
  }

  Widget _buildLockOverlay() {
    final currentUser = ref.read(authProvider).user?.displayName ?? 'مستخدم';
    
    return Positioned.fill(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: KeyboardListener(
          focusNode: FocusNode(),
          autofocus: true,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            final now = DateTime.now();
            final char = event.character;
            if (event.logicalKey == LogicalKeyboardKey.enter) {
              final code = _cardBuffer.toString().trim();
              _cardBuffer.clear();
              if (code.length >= 4) {
                _onCardSwipe(code);
              }
              return;
            }
            if (char != null && char.isNotEmpty) {
              if (now.difference(_lastKeyTime) > _msrMaxKeyInterval) {
                _cardBuffer.clear();
              }
              _cardBuffer.write(char);
              _lastKeyTime = now;
            }
          },
          child: Container(
            color: Colors.black.withValues(alpha: 0.85),
            child: Center(
              child: SingleChildScrollView(
                child: Container(
                  width: 420,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Lock Icon
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          PhosphorIconsLight.lockKey,
                          size: 40,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      const Text(
                        'جلسة مقفلة',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'الجلسة مقفلة تلقائياً لعدم النشاط.\nيرجى إدخال كلمة مرور $currentUser\nأو رمز مدير النظام لفك القفل.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textMuted,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Error message
                      if (_errorMessage != null)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                PhosphorIconsBold.warning,
                                color: AppColors.error,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: AppColors.error,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Password field
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(PhosphorIconsBold.lock),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword
                                  ? PhosphorIconsBold.eye
                                  : PhosphorIconsBold.eyeSlash,
                            ),
                            onPressed: () => setState(
                              () => _obscurePassword = !_obscurePassword,
                            ),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: AppColors.surface,
                        ),
                        onSubmitted: (_) => _unlock(),
                      ),
                      const SizedBox(height: 24),

                      // Unlock button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _unlock,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(PhosphorIconsBold.lockOpen),
                                    SizedBox(width: 8),
                                    Text(
                                      'فك القفل',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Logout Button
                      TextButton.icon(
                        onPressed: _logout,
                        icon: const Icon(
                          PhosphorIconsBold.signOut,
                          size: 18,
                          color: AppColors.error,
                        ),
                        label: const Text(
                          'تسجيل الخروج تماماً',
                          style: TextStyle(color: AppColors.error),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
