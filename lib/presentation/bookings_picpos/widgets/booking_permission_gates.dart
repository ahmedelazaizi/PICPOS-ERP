import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/permission_codes.dart';
import '../../../domain/models/picpos_booking_view.dart';
import '../../widgets/permission_guard.dart';

// بوّاباتُ الأفعال داخل شاشة الحجوزات (P2 — قرار المالك F.2).
//
// فتحُ الشاشة بأيّ كودٍ من مجموعتها (`screen_access_resolver`)؛ وكلُّ فعلٍ
// داخلَها يُفحَص بكوده هو. هذا الملفُّ موضعٌ واحدٌ للأكواد حتى لا يتناثر
// الفحصُ بين الأزرار، ولا يستورد شيئاً من `data/database`.

/// الكودُ الذي يلزم لرؤية وجهةٍ بعينها، أو `null` لوجهةٍ يكفي لها دخولُ
/// الشاشة (`bookings_view` أو أيُّ كودٍ من مجموعتها).
String? bookingDestinationPermission(BookingsDestination d) => switch (d) {
      BookingsDestination.reports => PermissionCodes.bookingsReports,
      BookingsDestination.settings => PermissionCodes.bookingsSettings,
      _ => null,
    };

/// هل تظهر الوجهةُ [d] لمن يملك [permissions]؟ (مديرُ النظام يتجاوز.)
bool bookingDestinationAllowed(
  List<String> permissions,
  BookingsDestination d,
) {
  final code = bookingDestinationPermission(d);
  return code == null || hasPermissionWithAdminBypass(permissions, code);
}

/// كودُ تغيير الحالة إلى [next]: الإلغاءُ له كودُه، وما عداه `bookings_status`.
String bookingStatusPermission(String next) => next == 'cancelled'
    ? PermissionCodes.bookingsCancel
    : PermissionCodes.bookingsStatus;

/// ينفّذ [action] بعد التأكّد من [code] (مع مسار الموافقة للمشروطة).
Future<void> runBookingAction(
  WidgetRef ref,
  BuildContext context,
  String code,
  String actionName,
  FutureOr<void> Function() action,
) async {
  if (!await ensurePermission(ref, context, code, actionName: actionName)) {
    return;
  }
  if (!context.mounted) return;
  await action();
}
