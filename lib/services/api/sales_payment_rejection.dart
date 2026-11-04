import 'package:shelf/shelf.dart';

import 'api_errors.dart';

Response salesPaymentRejection(String code) {
  final message = code == 'PAYMENT_NOT_POSITIVE'
      ? 'يجب أن يكون مبلغ التحصيل أكبر من صفر.'
      : 'مبلغ التحصيل يتجاوز المتبقي على الفاتورة.';
  return ApiErrors.fail(
    StateError(message),
    '',
    statusCode: 422,
    code: code,
  );
}

Response? salesPaymentRejectionFor(Object error) {
  final text = error.toString();
  if (text.contains('PAYMENT_EXCEEDS_REMAINING')) {
    return salesPaymentRejection('PAYMENT_EXCEEDS_REMAINING');
  }
  if (text.contains('PAYMENT_NOT_POSITIVE')) {
    return salesPaymentRejection('PAYMENT_NOT_POSITIVE');
  }
  return null;
}
