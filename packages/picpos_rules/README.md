# picpos_rules — shared business rules (pure Dart)

One implementation of the rules the cloud gate (`server/`, `picpos_cloud`) and the cash-van app (`mobile/`, `picpos_van`) must agree on. Both depend on it by path (`../packages/picpos_rules`), so parity is by construction. No Flutter, no I/O; the only dependency is `crypto`.

| File | Rules | Desktop source |
|---|---|---|
| `lib/src/tax.dart` | `effectiveItemTaxRate`, `roundDp`/`round2`, `computeTotals` (tax-exclusive and tax-inclusive) | `lib/core/tax/effective_item_tax_rate.dart`, `FinancialUtils.calculateInvoiceTotals` |
| `lib/src/pricing.dart` | `resolveUnitPrice` (wholesale level, price-list tiers, sale price), `returnLineAmounts`, `returnSettlement` | `resolveProductPrice`, `calculateReturnRefundTotal`, `SalesReturnRefundSplit` |
| `lib/src/sale_math.dart` | `exceedsCreditLimit`, `salesPaymentMethod` | `SalesMutationsDao.createSalesInvoice` |
| `lib/src/integrity.dart` | `salesIntegrityPayload`, `signV2` (HMAC-SHA256, `v2:`), `integrityShortHash` | `InvoiceIntegrityService._salesPayload` |
| `lib/src/barcode.dart` | `normalizeBarcode` (wedge suffixes, control chars, AIM prefixes) | — (scanner input; cloud stores pushed barcodes normalized) |
| `lib/src/company_identity.dart` | `companyHeaderLines`, `companyMainName`, `companySecondaryName`, `companyCrLine` («س.ت»), `companyTaxLine`, `ltrIsolate` | `lib/domain/printing/company_identity.dart`, `ThermalReceiptGenerator._buildHeader` |
| `lib/src/receipt_qr.dart` | `resolveReceiptQr` (fiscal / none / non-fiscal + disclaimer), `nonFiscalQrPayload`, `jofotaraTlvQr` | `receipt_qr_decision.dart`, `JofotaraService.generateQrCode` |

## Test

```powershell
cd D:\PICPOS-ERP\packages\picpos_rules
D:\Cash\develop\flutter\bin\cache\dart-sdk\bin\dart.exe test
```

`test/pricing_parity_test.dart` runs the shared fixture `docs/mobile/fixtures/pricing_parity.json`; `test/rules_test.dart` covers tax, rounding, sale math, integrity (format + HMAC vector), barcode, identity and QR.

## Follow-up: desktop

The desktop app (`picpos_erp`, root `lib/`) still has its own copies of these rules. Making it depend on this package (replacing `effective_item_tax_rate.dart`, the integrity payload, `company_identity.dart` and the QR decision with re-exports) is out of scope for I-4 and is the next step, so the desktop is also "parity by construction".
