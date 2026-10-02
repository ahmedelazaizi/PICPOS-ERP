/// Sale-level rules applied by the device (offline) and the cloud gate.
library;

/// Desktop `SalesMutationsDao.createSalesInvoice` parity: a credit limit of 0
/// means no limit; only a remaining amount > 0.01 counts.
bool exceedsCreditLimit({required double balance, required double creditLimit, required double remaining}) =>
    remaining > 0.01 && creditLimit > 0 && balance + remaining > creditLimit;

/// Payment method stored on (and signed into) a field invoice:
/// nothing left to pay → `cash`; partly paid → `mixed`; nothing paid → `credit`.
String salesPaymentMethod({required double paid, required double remaining}) =>
    remaining <= 0.01 ? 'cash' : (paid > 0 ? 'mixed' : 'credit');
