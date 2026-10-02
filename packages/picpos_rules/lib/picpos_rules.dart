/// PicPos shared business rules — one implementation used by the cloud API
/// (`server/`) and the cash-van app (`mobile/`), so parity is by construction.
/// Pure Dart: no Flutter, no I/O. Fixture: docs/mobile/fixtures/pricing_parity.json.
library;

export 'src/barcode.dart';
export 'src/company_identity.dart';
export 'src/integrity.dart';
export 'src/pricing.dart';
export 'src/receipt_qr.dart';
export 'src/sale_math.dart';
export 'src/tax.dart';
