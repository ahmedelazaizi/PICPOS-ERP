import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/screen_id.dart';
import '../../core/permissions/financial_figures_access.dart';
import 'auth_providers.dart';

/// Current user's screen-level access to monetary figures.
final screenFiguresVisibilityProvider =
    FutureProvider.family<bool, ScreenId>((ref, screen) async {
  final auth = ref.watch(authProvider);
  final permissions = await ref.watch(currentUserPermissionsProvider.future);
  return canSeeScreenFigures(
    permissions,
    screen,
    bypass: auth.hasSystemAdminBypass,
  );
});
