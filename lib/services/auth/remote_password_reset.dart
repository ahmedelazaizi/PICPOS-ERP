import 'dart:async';
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http show ClientException;
import 'package:picpos_erp/core/i18n/tr.dart';

/// Sends the new password to the host (`POST /api/users/<id>/password`).
typedef PasswordSender = Future<void> Function(int userId, String password);

/// The main system could not be reached: an admin password reset from a
/// client/mirror device is refused instead of being parked in the outbox
/// (RESET-001 — the outbox would keep the plaintext password on disk).
class RemotePasswordResetException implements Exception {
  RemotePasswordResetException(this.cause);
  final Object cause;

  @override
  String toString() => tr('تغيير كلمة المرور يتطلب اتصالًا بالنظام الرئيسي');
}

/// Online-only password reset on the host. Network failures become
/// [RemotePasswordResetException]; a host rejection (4xx/5xx) is rethrown
/// unchanged so the operator sees the real reason. Nothing is queued and
/// nothing is written locally.
Future<void> resetPasswordOnMain({
  required int userId,
  required String password,
  required PasswordSender send,
}) async {
  try {
    await send(userId, password);
  } on SocketException catch (e) {
    throw RemotePasswordResetException(e);
  } on TimeoutException catch (e) {
    throw RemotePasswordResetException(e);
  } on http.ClientException catch (e) {
    throw RemotePasswordResetException(e);
  }
}
