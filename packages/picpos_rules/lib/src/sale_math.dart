/// Sale-level rules applied by the device (offline) and the cloud gate.
library;

/// Desktop `SalesMutationsDao.createSalesInvoice` parity: a credit limit of 0
/// means no limit; only a remaining amount > 0.01 counts.
bool exceedsCreditLimit({required double balance, required double creditLimit, required double remaining}) =>
    remaining > 0.01 && creditLimit > 0 && balance + remaining > creditLimit;

/// J3 — the system cash customer, and a customer created in the field that
/// management has not given a credit limit yet, sell cash only: nothing may
/// be left on account (same 0.01 tolerance as the credit limit).
bool violatesCashOnly({required bool cashOnly, required double remaining}) => cashOnly && remaining > 0.01;

/// Payment method stored on (and signed into) a field invoice:
/// nothing left to pay → `cash`; partly paid → `mixed`; nothing paid → `credit`.
String salesPaymentMethod({required double paid, required double remaining}) =>
    remaining <= 0.01 ? 'cash' : (paid > 0 ? 'mixed' : 'credit');
